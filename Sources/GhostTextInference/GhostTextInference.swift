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

// MARK: - Completion boundary

/// Decides whether a completion has reached a useful stopping point, so
/// generation can stop before `maxTokens` instead of always running to the
/// cap. This is next-word/phrase completion (Tab takes one word, `~` takes a
/// short phrase) — most useful completions end well short of the token
/// budget, and stopping early is most of the latency win: decode dominates
/// end-to-end time (see BENCH.md), so fewer tokens decoded is fewer
/// milliseconds on screen.
///
/// A pure function over the generated text alone (never touches MLX, the
/// engine, or wall-clock time) so it is trivially unit-testable in isolation.
public enum CompletionBoundary {
    /// Default "roughly 8 words" cap referenced in DESIGN.md-adjacent bench
    /// notes: `~` accepts a 2-3 word phrase and Tab accepts one word, so 8
    /// words is already generous headroom above anything the UI shows in one
    /// accept, while still bounding runaway completions that never hit a
    /// terminator or newline.
    public static let defaultWordLimit = 8

    private static let terminators: Set<Character> = [".", "!", "?"]

    /// `text` is the completion generated *so far* — never the original
    /// buffer, which is not re-examined. Checked after every streamed token
    /// (see `CompletionEngine`'s internal generation loop), so this needs to
    /// be cheap: no regex, single pass over `text` at worst.
    ///
    /// Three triggers:
    /// 1. A sentence terminator (`.`, `!`, `?`) that is either the last
    ///    character produced so far, or immediately followed by whitespace.
    ///    Checking "last character so far" (not waiting to confirm a
    ///    trailing space arrives) trades a small amount of false-stop risk
    ///    on things like mid-typing decimals (`3.14`) for not paying for an
    ///    extra decode step just to confirm — acceptable here because a
    ///    next-word completion stopping one token early is a non-event, and
    ///    the model rarely emits a bare `.` mid-number as its own token
    ///    against these prompts (verified empirically in `--quality` runs).
    /// 2. Any newline. Completions are single-line by design; the model
    ///    occasionally free-associates into a fresh paragraph, a bullet
    ///    list, or a recipe ingredients block (see BENCH.md's quality
    ///    table), none of which are useful as inline ghost text.
    /// 3. `wordLimit` whitespace-separated words have been produced.
    public static func isAtBoundary(_ text: String, wordLimit: Int = defaultWordLimit) -> Bool {
        guard !text.isEmpty else { return false }

        if text.contains(where: { $0.isNewline }) {
            return true
        }

        var previous: Character?
        for character in text {
            if let previous, terminators.contains(previous), character.isWhitespace {
                return true
            }
            previous = character
        }
        if let last = text.last, terminators.contains(last) {
            return true
        }

        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount >= wordLimit {
            return true
        }

        return false
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
    public func complete(buffer: String, maxTokens: Int = defaultMaxTokens) async throws -> String {
        try await completeWithTiming(buffer: buffer, maxTokens: maxTokens).text
    }

    /// Like `complete`, but also returns the engine's own timing breakdown
    /// (prefill vs decode, first-token latency, and whether the boundary or
    /// `maxTokens` ended generation). Used by `ghost-bench`; not part of the
    /// app's hot path, which only needs the text.
    public func completeWithTiming(
        buffer: String, maxTokens: Int = defaultMaxTokens
    ) async throws -> CompletionTiming {
        try await runGeneration(buffer: buffer, maxTokens: maxTokens, onPartial: nil)
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
        maxTokens: Int = defaultMaxTokens,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await runGeneration(buffer: buffer, maxTokens: maxTokens, onPartial: onPartial).text
    }

    /// Like `completeStreaming`, but also returns the timing breakdown.
    /// `ghost-bench` uses this to measure first-token latency through the
    /// real streaming API path rather than reconstructing it from
    /// `completeWithTiming`'s internals.
    public func completeStreamingWithTiming(
        buffer: String,
        maxTokens: Int = defaultMaxTokens,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> CompletionTiming {
        try await runGeneration(buffer: buffer, maxTokens: maxTokens, onPartial: onPartial)
    }

    /// Shared generation core for all four public entry points above.
    /// `onPartial == nil` is the non-streaming path (no per-token callback
    /// overhead beyond the boundary check, which runs either way since it's
    /// cheap and always wanted).
    private func runGeneration(
        buffer: String,
        maxTokens: Int,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> CompletionTiming {
        guard let container else { throw CompletionEngineError.notReady }
        guard !buffer.isEmpty else {
            return CompletionTiming(
                text: "", promptTime: 0, generateTime: 0, promptTokenCount: 0,
                generationTokenCount: 0, firstTokenTime: nil, stoppedAtBoundary: false)
        }

        let promptText = framedPrompt(for: buffer)
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
