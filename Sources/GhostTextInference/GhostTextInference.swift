import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

public enum GhostTextInference {
    public static let version = "0.1.0"
}

// MARK: - Errors

public enum CompletionEngineError: Error, Sendable, CustomStringConvertible {
    /// `complete(buffer:maxTokens:)` was called before `warmup()` finished.
    case notReady

    public var description: String {
        switch self {
        case .notReady:
            return "CompletionEngine.complete called before warmup() finished."
        }
    }
}

// MARK: - Prompt framing

/// How raw keystroke buffers are turned into the token sequence fed to the model.
///
/// This is deliberately *not* `GhostTextCore.CompletionSanitizer`'s job — that
/// component cleans up model *output*. This type controls what goes *in*, which
/// is the difference between a model that continues your sentence and one that
/// answers it as a question.
public enum PromptFraming: Sendable, Equatable {
    /// Feed the buffer straight to the tokenizer with no wrapping. Correct for
    /// base (non-instruct) models, which have no notion of chat turns and will
    /// simply continue whatever token sequence they're given.
    case raw

    /// Wrap the buffer as the (deliberately unterminated) start of an
    /// assistant turn in a ChatML-style template, so an instruct-tuned model
    /// continues its own in-progress utterance instead of replying to the
    /// user turn conversationally. Sometimes called the "assistant prefill"
    /// trick. Built by hand (not via `Tokenizer.applyChatTemplate`, which
    /// this package's `Tokenizer` protocol always terminates with a closed,
    /// generation-ready assistant turn) so the assistant turn is left open
    /// for the model to continue.
    case chatPrefill

    /// Pick `.chatPrefill` for model IDs that look instruct-tuned (contain
    /// "instruct", "chat", or "it" as a path component, case-insensitively),
    /// `.raw` otherwise. This is a heuristic, not a guarantee — verify actual
    /// continuation behavior per model with `ghost-bench --quality`.
    public static func inferred(fromModelID modelID: String) -> PromptFraming {
        let lowered = modelID.lowercased()
        let instructMarkers = ["instruct", "-chat", "_chat", "-it-", "-it"]
        return instructMarkers.contains(where: lowered.contains) ? .chatPrefill : .raw
    }
}

// MARK: - CompletionEngine

/// Owns the MLX model, tokenizer, and generation loop for on-device next-phrase
/// completion. An `actor` because every MLX type it touches (`MLXArray`,
/// `LanguageModel`, `ModelContext`, …) is not `Sendable`; nothing here is ever
/// allowed to leave the actor's isolation domain.
public actor CompletionEngine {
    private let modelID: String
    private let framing: PromptFraming
    private var container: ModelContainer?

    /// - Parameters:
    ///   - modelID: a HuggingFace repo id, e.g. `"mlx-community/Qwen2.5-0.5B-4bit"`.
    ///   - framing: how to turn a keystroke buffer into model input. Defaults
    ///     to a heuristic based on `modelID` — pass an explicit value to
    ///     override it (this is what `ghost-bench` does to compare both).
    public init(modelID: String, framing: PromptFraming? = nil) {
        self.modelID = modelID
        self.framing = framing ?? .inferred(fromModelID: modelID)
    }

    /// `true` once `warmup()` has completed successfully.
    public var isReady: Bool { container != nil }

    /// The prompt framing this engine resolved to for `modelID`. Exposed for
    /// diagnostics (`ghost-bench --quality` prints it); not meant for
    /// runtime branching by callers.
    public var debugFraming: String {
        switch framing {
        case .raw: return "raw"
        case .chatPrefill: return "chatPrefill"
        }
    }

    /// Downloads (if needed), loads, and runs one throwaway generation so
    /// Metal kernels are compiled before the first user-visible request.
    /// Idempotent: calling it again after a successful warmup is a no-op.
    public func warmup() async throws {
        if container != nil { return }

        let configuration = ModelConfiguration(id: modelID)
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration
        )
        self.container = loaded

        // Throwaway generation: compiles every Metal kernel the real request
        // path will hit, so the user's first completion isn't the one that
        // eats the JIT cost.
        _ = try await complete(buffer: "The quick brown fox jumps over the lazy", maxTokens: 4)
    }

    /// Generate a short continuation of `buffer`. Cancellable: if the calling
    /// `Task` is cancelled, generation stops within one decode step instead
    /// of running to `maxTokens`. Emits raw model output — no trimming, no
    /// dedup against `buffer`, no whitespace cleanup. That's
    /// `GhostTextCore.CompletionSanitizer`'s job.
    public func complete(buffer: String, maxTokens: Int = 12) async throws -> String {
        try await completeWithTiming(buffer: buffer, maxTokens: maxTokens).text
    }

    /// Like `complete`, but also returns the engine's own timing breakdown
    /// (prefill vs decode) for the call. Used by `ghost-bench`; not part of
    /// the app's hot path, which only needs the text.
    public func completeWithTiming(
        buffer: String, maxTokens: Int = 12
    ) async throws -> (text: String, promptTime: TimeInterval, generateTime: TimeInterval, promptTokenCount: Int, generationTokenCount: Int) {
        guard let container else { throw CompletionEngineError.notReady }
        guard !buffer.isEmpty else {
            return ("", 0, 0, 0, 0)
        }

        let promptText = framedPrompt(for: buffer)

        return try await container.perform { context in
            let promptTokens = context.tokenizer.encode(text: promptText, addSpecialTokens: true)
            let lmInput = LMInput(tokens: MLXArray(promptTokens))
            // A 0.5B model at low temperature falls into degenerate loops on short
            // prompts — "The quick " produced "mouse mouse mouse mouse mouse mouse".
            // The penalty is what breaks the loop; the context size only needs to
            // span a completion of this length.
            let parameters = GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.2,
                repetitionPenalty: 1.15,
                repetitionContextSize: 20
            )

            let iterator = try TokenIterator(
                input: lmInput,
                model: context.model,
                cache: nil,
                parameters: parameters
            )

            let (stream, task) = generateTask(
                promptTokenCount: promptTokens.count,
                modelConfiguration: context.configuration,
                tokenizer: context.tokenizer,
                iterator: iterator
            )

            var result = ""
            var info: GenerateCompletionInfo?
            for await event in stream {
                if Task.isCancelled {
                    // Signal the detached generation task to unwind; it is
                    // NOT a child task of ours (generateTask launches its own
                    // unstructured Task internally), so our own cancellation
                    // does not reach it unless we cancel it explicitly.
                    task.cancel()
                    break
                }
                switch event {
                case .chunk(let text):
                    result += text
                case .info(let completionInfo):
                    info = completionInfo
                case .toolCall:
                    break
                }
            }

            // Wait for the generation task to fully unwind (releases the MLX
            // command buffer / cache state cleanly) before returning.
            await task.value

            return (
                result,
                info?.promptTime ?? 0,
                info?.generateTime ?? 0,
                promptTokens.count,
                info?.generationTokenCount ?? 0
            )
        }
    }

    private func framedPrompt(for buffer: String) -> String {
        switch framing {
        case .raw:
            return buffer
        case .chatPrefill:
            // Deliberately NOT closed with <|im_end|>: leaving the assistant
            // turn open makes the model continue its own in-progress
            // utterance (the user's buffer) instead of starting a fresh,
            // conversational reply.
            return """
                <|im_start|>user
                Continue writing the following text with the next few words only. No preamble, no explanation, no repeating the instructions.<|im_end|>
                <|im_start|>assistant
                \(buffer)
                """
        }
    }
}
