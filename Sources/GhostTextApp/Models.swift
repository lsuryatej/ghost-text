import AppKit
import Foundation

/// The model catalog, mirroring Cotypist's lineup in MLX form.
///
/// Cotypist ships GGUF and runs llama.cpp; Ghost Text runs MLX in-process, so the
/// same models are pulled from `mlx-community` rather than reused from Cotypist's
/// own download directory. Sizes are the 4-bit MLX weights, which differ slightly
/// from the GGUF Q4_K_M figures shown in Cotypist's UI.
struct ModelChoice: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let approximateSizeGB: Double
    let recommended: Bool

    var displayName: String { "\(name) (\(String(format: "%.1f", approximateSizeGB)) GB)" }

    static let catalog: [ModelChoice] = [
        // The default. 70-74ms end to end in the app - as fast as the 0.5B while
        // being three times the size, because decode cost tracks vocabulary as
        // much as parameter count and Qwen's 151k vocab is far cheaper than
        // Gemma's 262k. Measured in BENCH.md.
        ModelChoice(id: "mlx-community/Qwen3-1.7B-4bit", name: "Qwen3 1.7B", approximateSizeGB: 1.0, recommended: true),
        // Smallest footprint, weakest mid-word continuation.
        ModelChoice(id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", name: "Qwen2.5 0.5B", approximateSizeGB: 0.3, recommended: true),
        // Good prose, but 550-850ms in app conditions. Kept for comparison.
        ModelChoice(id: "mlx-community/gemma-3-1b-it-4bit", name: "Gemma 3 1B (slow)", approximateSizeGB: 0.8, recommended: false),
        ModelChoice(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen2.5 1.5B", approximateSizeGB: 0.9, recommended: false),
        // Base (non-instruct) checkpoint. Tried as an experiment and reverted:
        // BENCH.md already has a rigorous A/B (`raw` vs `chatPrefill`, 20
        // prompts each) showing raw/base framing reliably drifts into
        // quiz/exam artifacts ("____（进入）", "A. B. C." multiple choice) -
        // "a symptom of what it was pretrained on, not a framing problem."
        // Live use tonight reproduced exactly that failure mode. Kept in the
        // catalog for comparison, not recommended.
        ModelChoice(id: "mlx-community/Qwen2.5-1.5B-4bit", name: "Qwen2.5 1.5B Base", approximateSizeGB: 0.9, recommended: false),
        ModelChoice(id: "mlx-community/gemma-3-4b-it-qat-4bit", name: "Gemma 3 4B", approximateSizeGB: 2.3, recommended: false),
        // What Cotypist is currently running here.
        ModelChoice(id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 E2B", approximateSizeGB: 3.2, recommended: true),
        ModelChoice(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", name: "Qwen3 4B", approximateSizeGB: 2.3, recommended: false),
        ModelChoice(id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 E4B", approximateSizeGB: 6.2, recommended: false),
        ModelChoice(id: "mlx-community/Qwen3-8B-4bit", name: "Qwen3 8B", approximateSizeGB: 4.7, recommended: false),
    ]

    /// Looked up by id rather than by position, so reordering the catalog cannot
    /// silently change what everyone gets.
    static let fallback = catalog.first { $0.id == "mlx-community/Qwen3-1.7B-4bit" } ?? catalog[0]

    static var current: ModelChoice {
        get {
            guard let saved = UserDefaults.standard.string(forKey: "modelID"),
                  let match = catalog.first(where: { $0.id == saved }) else { return fallback }
            return match
        }
        set { UserDefaults.standard.set(newValue.id, forKey: "modelID") }
    }
}

/// Writer-supplied guidance folded into every prompt — occupation, the kinds of
/// writing they do, spelling conventions, voice rules.
///
/// Backed by a plain text file rather than a settings window, because the app has
/// no settings UI yet and a file the user can open in any editor is more useful
/// than a cramped text box. Re-read when it changes on disk.
@MainActor
final class InstructionsStore {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GhostText", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("instructions.txt")
    }()

    private var cached: String?
    private var cachedModified: Date?
    private var lastChecked: Date = .distantPast

    /// Stat is cheap but this runs on the suggestion path, so throttle it.
    private static let recheckInterval: TimeInterval = 2

    func createTemplateIfMissing() {
        guard !FileManager.default.fileExists(atPath: Self.url.path) else { return }
        try? Self.template.write(to: Self.url, atomically: true, encoding: .utf8)
    }

    func current() -> String? {
        let now = Date()
        if now.timeIntervalSince(lastChecked) < Self.recheckInterval { return cached }
        lastChecked = now

        let attributes = try? FileManager.default.attributesOfItem(atPath: Self.url.path)
        let modified = attributes?[.modificationDate] as? Date
        if modified == cachedModified { return cached }

        cachedModified = modified
        let text = try? String(contentsOf: Self.url, encoding: .utf8)
        // Comment lines let the template explain itself without leaking into
        // the prompt.
        let body = (text ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cached = body.isEmpty ? nil : body
        return cached
    }

    func reveal() {
        createTemplateIfMissing()
        NSWorkspace.shared.open(Self.url)
    }

    private static let template = """
        # Ghost Text custom instructions
        #
        # Everything below that does not start with "#" is included in every
        # prompt. Describe who you are and how you write: occupation, the kinds
        # of writing you do, spelling conventions, voice rules.
        #
        # A few hundred words is a sensible upper bound. Shorter usually works
        # just as well, and every word here costs a little prefill time.
        #
        # Saving this file is enough - Ghost Text picks up changes within a
        # couple of seconds, with no restart.

        """
}
