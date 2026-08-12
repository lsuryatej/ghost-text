import Foundation
import GhostTextCore
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

    /// ChatML with an empty reasoning block already closed. Qwen3 models are
    /// hybrid reasoners and will otherwise open a `<think>` block and spend the
    /// whole token budget deliberating instead of finishing the sentence.
    case qwen3Prefill

    /// Gemma uses `<start_of_turn>` / `<end_of_turn>` rather than ChatML, and
    /// names the assistant role "model". Feeding it ChatML produces the tags as
    /// literal output.
    case gemmaPrefill

    /// Pick `.chatPrefill` for model IDs that look instruct-tuned (contain
    /// "instruct", "chat", or "it" as a path component, case-insensitively),
    /// `.raw` otherwise. This is a heuristic, not a guarantee — verify actual
    /// continuation behavior per model with `ghost-bench --quality`.
    public static func inferred(fromModelID modelID: String) -> PromptFraming {
        let lowered = modelID.lowercased()
        if lowered.contains("gemma") { return .gemmaPrefill }
        if lowered.contains("qwen3") { return .qwen3Prefill }
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
    private var instructions: String?

    /// Writer-supplied guidance folded into every prompt. Changing it does not
    /// require reloading the model.
    public func setInstructions(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        instructions = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Lowered from the original 12 after `ghost-bench` data (see BENCH.md's
    /// "Retuning maxTokens" section) showed boundary-stop ends most
    /// completions well before this cap fires — it only exists now as a
    /// worst-case backstop for buffers with no natural terminator nearby, so
    /// it can be small.
    public static let defaultMaxTokens = 10

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
        case .qwen3Prefill: return "qwen3Prefill"
        case .gemmaPrefill: return "gemmaPrefill"
        }
    }

    /// Downloads (if needed), loads, and runs one throwaway generation so
    /// Metal kernels are compiled before the first user-visible request.
    /// Idempotent: calling it again after a successful warmup is a no-op.
    public func warmup(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if container != nil { return }

        // Without these the chat-template terminators are decoded as literal
        // text and generation runs on past the end of the turn into multilingual
        // garbage - Gemma emitted "<end_of_turn>" mid-completion followed by
        // tokens from three other scripts.
        let configuration = ModelConfiguration(
            id: modelID,
            extraEOSTokens: ["<end_of_turn>", "<|im_end|>", "<start_of_turn>", "<|endoftext|>", "<eos>"]
        )
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            progressHandler: { p in progress?(p.fractionCompleted) }
        )
        self.container = loaded

        // Throwaway generation: compiles every Metal kernel the real request
        // path will hit, so the user's first completion isn't the one that
        // eats the JIT cost. Streamed (not plain `complete`) so warmup also
        // compiles whatever kernel path first-token delivery depends on —
        // there shouldn't be one that differs from `complete`'s, but this
        // keeps the two paths symmetric for free.
        _ = try await completeStreaming(
            buffer: "The quick brown fox jumps over the lazy", maxTokens: 4, onPartial: { _ in })
    }

    /// Generate a short continuation of `buffer`. Cancellable: if the calling
    /// `Task` is cancelled, generation stops within one decode step instead
    /// of running to `maxTokens`. Emits raw model output — no trimming, no
    /// dedup against `buffer`, no whitespace cleanup. That's
    /// `GhostTextCore.CompletionSanitizer`'s job. Stops early at a
    /// `CompletionBoundary` (sentence end, newline, or ~8 words) rather than
    /// always running to `maxTokens`.
    public func complete(buffer: String, suffix: String? = nil, maxTokens: Int = defaultMaxTokens) async throws -> String {
        try await completeWithTiming(buffer: buffer, suffix: suffix, maxTokens: maxTokens).text
    }

    /// Like `complete`, but also returns the engine's own timing breakdown
    /// (prefill vs decode, first-token latency, and whether the boundary or
    /// `maxTokens` ended generation). Used by `ghost-bench`; not part of the
    /// app's hot path, which only needs the text.
    public func completeWithTiming(
        buffer: String, suffix: String? = nil, maxTokens: Int = defaultMaxTokens
    ) async throws -> CompletionTiming {
        try await runGeneration(buffer: buffer, suffix: suffix, maxTokens: maxTokens, onPartial: nil)
    }

    /// Streaming completion: `onPartial` fires with the *cumulative* text so
    /// far on every generated token, starting with the first one, so a
    /// caller can paint ghost text as soon as it exists instead of waiting
    /// for the whole completion. Returns the final full text once generation
    /// stops (boundary, `maxTokens`, or cancellation).
    ///
    /// `AsyncThrowingStream` would be the other reasonable shape here, but a
    /// callback keeps the actor-hop story simple: `onPartial` is invoked
    /// synchronously from inside this actor's isolated `container.perform`
    /// closure (the same context that drives the token loop), so there is no
    /// extra stream-consumer `Task` and no risk of a second reader racing
    /// `complete`'s cancellation path. The tradeoff a caller should know:
    /// `onPartial` runs on whatever queue MLX's `container.perform` uses,
    /// not necessarily the main actor — callers updating UI (as `GhostTextApp`
    /// will) must hop to `MainActor` themselves inside the closure.
    ///
    /// Cancellable exactly like `complete`: cancelling the calling `Task`
    /// stops generation within one decode step. `onPartial` is `@Sendable`
    /// and non-async so it can be called inline without awaiting back into
    /// the caller's isolation domain from inside the actor.
    public func completeStreaming(
        buffer: String,
        suffix: String? = nil,
        maxTokens: Int = defaultMaxTokens,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await runGeneration(buffer: buffer, suffix: suffix, maxTokens: maxTokens, onPartial: onPartial).text
    }

    /// Like `completeStreaming`, but also returns the timing breakdown.
    /// `ghost-bench` uses this to measure first-token latency through the
    /// real streaming API path rather than reconstructing it from
    /// `completeWithTiming`'s internals.
    public func completeStreamingWithTiming(
        buffer: String,
        suffix: String? = nil,
        maxTokens: Int = defaultMaxTokens,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> CompletionTiming {
        try await runGeneration(buffer: buffer, suffix: suffix, maxTokens: maxTokens, onPartial: onPartial)
    }

    /// Shared generation core for all four public entry points above.
    /// `onPartial == nil` is the non-streaming path (no per-token callback
    /// overhead beyond the boundary check, which runs either way since it's
    /// cheap and always wanted).
    private func runGeneration(
        buffer: String,
        suffix: String?,
        maxTokens: Int,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> CompletionTiming {
        guard let container else { throw CompletionEngineError.notReady }
        guard !buffer.isEmpty else {
            return CompletionTiming(
                text: "", promptTime: 0, generateTime: 0, promptTokenCount: 0,
                generationTokenCount: 0, firstTokenTime: nil, stoppedAtBoundary: false)
        }

        let promptText = framedPrompt(for: buffer, suffix: suffix)
        let callStart = Date()

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
            var firstTokenTime: TimeInterval?
            var stoppedAtBoundary = false
            var boundaryCancelled = false

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
                    guard !boundaryCancelled else { break }
                    if firstTokenTime == nil {
                        firstTokenTime = Date().timeIntervalSince(callStart)
                    }
                    result += text
                    onPartial?(result)
                    if CompletionBoundary.isAtBoundary(result) {
                        // Stop the underlying generation task now rather than
                        // waiting for maxTokens — this is the whole point of
                        // boundary-stop. Keep draining the stream (don't
                        // `break` this loop) so the `.info` event below still
                        // arrives and timing stays populated: once
                        // `task.cancel()` lands, `generateTask`'s loop
                        // notices on its next iteration and finishes almost
                        // immediately (no further GPU work), so this costs
                        // no meaningful latency.
                        stoppedAtBoundary = true
                        boundaryCancelled = true
                        task.cancel()
                    }
                case .info(let completionInfo):
                    info = completionInfo
                case .toolCall:
                    break
                }
            }

            // Wait for the generation task to fully unwind (releases the MLX
            // command buffer / cache state cleanly) before returning.
            await task.value

            return CompletionTiming(
                text: result,
                promptTime: info?.promptTime ?? 0,
                generateTime: info?.generateTime ?? 0,
                promptTokenCount: promptTokens.count,
                generationTokenCount: info?.generationTokenCount ?? 0,
                firstTokenTime: firstTokenTime,
                stoppedAtBoundary: stoppedAtBoundary
            )
        }
    }

    /// Text following the caret is included as context but capped: a small model
    /// given a long trailing passage starts summarising it instead of writing the
    /// next few words.
    static let maxSuffixContext = 160

    private func framedPrompt(for buffer: String, suffix: String?) -> String {
        if case .raw = framing { return buffer }

        let task = "Continue writing the following text with the next few words only."
            + " No preamble, no explanation, no repeating the instructions."

        var brief = ""
        if let instructions {
            brief += "About the writer and how they write:\n\(instructions)\n\n"
        }
        brief += task
        if let trailing = Self.usableSuffix(suffix) {
            brief += "\nThe text already continues after the cursor with: \"\(trailing)\""
            brief += "\nYour continuation must lead naturally into that and must not repeat it."
        }

        switch framing {
        case .raw:
            return buffer

        case .chatPrefill:
            // Deliberately NOT closed: leaving the assistant turn open makes the
            // model continue the user's in-progress sentence rather than reply.
            return """
                <|im_start|>user
                \(brief)<|im_end|>
                <|im_start|>assistant
                \(buffer)
                """

        case .qwen3Prefill:
            // The pre-closed empty think block is the documented way to put a
            // hybrid Qwen3 model into non-reasoning mode.
            return """
                <|im_start|>user
                \(brief)<|im_end|>
                <|im_start|>assistant
                <think>

                </think>

                \(buffer)
                """

        case .gemmaPrefill:
            return """
                <start_of_turn>user
                \(brief)<end_of_turn>
                <start_of_turn>model
                \(buffer)
                """
        }
    }

    /// Trim to a sentence-ish boundary so the model is not handed a fragment
    /// ending mid-word, and drop it entirely when there is nothing useful.
    static func usableSuffix(_ suffix: String?) -> String? {
        guard let suffix else { return nil }
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var window = String(trimmed.prefix(maxSuffixContext))
        if trimmed.count > maxSuffixContext, let lastSpace = window.lastIndex(where: { $0.isWhitespace }) {
            window = String(window[window.startIndex..<lastSpace])
        }
        // Newlines inside the quoted context confuse the ChatML framing.
        window = window.replacingOccurrences(of: "\n", with: " ")
        return window.isEmpty ? nil : window
    }
}

/// Timing breakdown for one `complete`/`completeStreaming` call. Returned by
/// the `*WithTiming` variants; `ghost-bench` is the primary consumer.
public struct CompletionTiming: Sendable {
    public let text: String
    /// Engine-reported prefill time (prompt encode + first forward pass).
    public let promptTime: TimeInterval
    /// Engine-reported decode time (all sampled tokens, including any that
    /// were in flight when a boundary-triggered cancel landed).
    public let generateTime: TimeInterval
    public let promptTokenCount: Int
    public let generationTokenCount: Int
    /// Wall-clock time from the call starting to the first token's text
    /// arriving, or `nil` if no token was generated (e.g. empty buffer).
    /// This is the number that determines when ghost text can first appear
    /// on screen.
    public let firstTokenTime: TimeInterval?
    /// `true` if `CompletionBoundary.isAtBoundary` ended generation early;
    /// `false` if it ran to `maxTokens` (or was cancelled by the caller).
    public let stoppedAtBoundary: Bool
}
