import Foundation
import GhostTextInference

// MARK: - CLI args

private let defaultModels = [
    "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
    "mlx-community/Qwen2.5-0.5B-4bit",
]

struct Args {
    var models: [String] = defaultModels
    var samples = 20
    var maxTokens = 12
    var quality = false
    var help = false
    /// Override the per-model framing heuristic. Not in the original spec's
    /// flag list — added to let quality mode directly A/B `.raw` vs
    /// `.chatPrefill` on the same model, which is exactly the comparison the
    /// task asks for ("try both and see what actually behaves").
    var framing: PromptFraming?
}

func parseArgs(_ argv: [String]) -> Args {
    var args = Args()
    var i = 0
    while i < argv.count {
        switch argv[i] {
        case "--model":
            i += 1
            if i < argv.count {
                args.models = argv[i].split(separator: ",").map { String($0) }
            }
        case "--samples":
            i += 1
            if i < argv.count, let n = Int(argv[i]) {
                args.samples = n
            }
        case "--max-tokens":
            i += 1
            if i < argv.count, let n = Int(argv[i]) {
                args.maxTokens = n
            }
        case "--quality":
            args.quality = true
        case "--framing":
            i += 1
            if i < argv.count {
                switch argv[i] {
                case "raw": args.framing = .raw
                case "chatPrefill": args.framing = .chatPrefill
                default:
                    FileHandle.standardError.write("ghost-bench: unknown --framing value '\(argv[i])' (expected raw or chatPrefill)\n".data(using: .utf8)!)
                }
            }
        case "--help", "-h":
            args.help = true
        default:
            FileHandle.standardError.write("ghost-bench: ignoring unrecognized argument '\(argv[i])'\n".data(using: .utf8)!)
        }
        i += 1
    }
    return args
}

let helpText = """
ghost-bench — no-GUI latency/quality harness for GhostTextInference.CompletionEngine.

Runs entirely in-process: no menu bar app, no Accessibility/Input Monitoring
permissions, no event tap.

USAGE:
  ghost-bench [--model <id>[,<id>...]] [--samples <n>] [--max-tokens <n>] [--quality] [--help]

FLAGS:
  --model <id>       HuggingFace model id(s), comma-separated.
                      Default: \(defaultModels.joined(separator: ", "))
  --samples <n>      Samples per buffer length in latency mode. Default: 20.
  --max-tokens <n>   Max tokens to generate per completion. Default: 12.
  --quality          Run quality mode (canned prose prefixes, prints
                      buffer -> completion) instead of the default latency mode.
  --framing <raw|chatPrefill>
                      Override the per-model prompt-framing heuristic (see
                      GhostTextInference.PromptFraming). Mainly useful in
                      --quality mode to A/B both framings on the same model.
  --help             Show this help and exit.

Both modes append their results to BENCH.md at the repo root, replacing the
matching <!-- LATENCY:... --> or <!-- QUALITY:... --> marker block so hand-written
sections (verdicts, commentary) are left untouched.
"""

let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
if args.help {
    print(helpText)
    exit(0)
}

// MARK: - Stats

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = max(0, min(sorted.count - 1, Int((p * Double(sorted.count)).rounded(.up)) - 1))
    return sorted[rank]
}

struct Stats {
    let p50: Double
    let p95: Double
    let max: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        p50 = percentile(sorted, 0.50)
        p95 = percentile(sorted, 0.95)
        max = sorted.last ?? 0
    }
}

func ms(_ seconds: Double) -> String {
    String(format: "%.0f", seconds * 1000)
}

// MARK: - Corpus

// A single piece of ordinary English prose, sliced to the requested character
// count. Not meant to be "quality" content (that's qualityPrefixes below) —
// just realistic buffer material at controlled lengths for latency sampling.
private let longProse = """
The kitchen smelled of coffee and burnt toast, and outside the window the \
rain kept falling in that slow, insistent way that made the whole street \
look like it was underwater. She had been meaning to call her sister back \
for three days now, ever since the voicemail about their mother's test \
results, but every time she picked up the phone she found some other task \
to do instead, some dish to wash or some email to answer, anything that let \
her put off the conversation for another hour. The dog scratched at the \
back door, wanting out, and she let him into the yard without really \
looking up from the counter where her tea had gone cold an hour ago. \
Outside, the neighbor's kids were building something out of cardboard \
boxes on the porch, and their laughter carried faintly through the rain.
"""

func bufferOfLength(_ n: Int) -> String {
    String(longProse.prefix(n))
}

private let latencyLengths = [20, 50, 100, 200, 400]

// MARK: - Quality prefixes

// ~20 canned English prose prefixes: mid-sentence, mid-word, after a
// trailing space, after a comma, and start of a fresh sentence.
private let qualityPrefixes: [String] = [
    // mid-sentence
    "I was thinking that maybe we could",
    "The report shows a significant",
    "She opened the door and",
    "He walked into the room and immediately",
    "According to the latest data, the company",
    // mid-word (deliberately truncated)
    "The weather this weekend is supposed to be absolutely gorg",
    "Can you send me the quarterly rep",
    "I really appreciate you taking the time to expl",
    "We should probably reconsi",
    "The recipe calls for two cups of all-purp",
    // after a trailing space
    "Thanks so much for your help. ",
    "Let me know what you think. ",
    "That sounds like a great plan. ",
    // after a comma
    "Once the meeting wraps up,",
    "If the weather holds,",
    "After a long day at the office,",
    // start of a fresh sentence
    "The stock market fell sharply after the announcement.",
    "Once upon a time, in a village near the coast, there lived",
    "In conclusion, the evidence strongly suggests",
    "My favorite thing about the new apartment is",
]

// MARK: - Bench runs

func runLatencyMode(modelID: String) async -> String {
    var out = "### `\(modelID)`\n\n"
    let engine = CompletionEngine(modelID: modelID, framing: args.framing)

    print("[\(modelID)] loading...")
    let loadStart = Date()
    do {
        try await engine.warmup()
    } catch {
        out += "Warmup failed: \(error)\n\n"
        return out
    }
    let loadTime = Date().timeIntervalSince(loadStart)
    print("[\(modelID)] cold load: \(String(format: "%.2f", loadTime))s")
    out += "Cold load (download-if-needed + weight load + first-token Metal kernel compile): **\(String(format: "%.2f", loadTime))s**\n\n"
    out += "\(args.samples) samples per buffer length, maxTokens=\(args.maxTokens). "
    out += "\"total\" is end-to-end `complete()` wall time; prefill/decode are the engine's own breakdown.\n\n"
    out += "| Buffer length | p50 total | p95 total | max total | p50 prefill | p95 prefill | p50 decode | p95 decode |\n"
    out += "|---|---|---|---|---|---|---|---|\n"

    for length in latencyLengths {
        let buffer = bufferOfLength(length)
        var totals: [Double] = []
        var prefills: [Double] = []
        var decodes: [Double] = []
        for sampleIndex in 0..<args.samples {
            let start = Date()
            do {
                let result = try await engine.completeWithTiming(buffer: buffer, maxTokens: args.maxTokens)
                let elapsed = Date().timeIntervalSince(start)
                totals.append(elapsed)
                prefills.append(result.promptTime)
                decodes.append(result.generateTime)
            } catch {
                print("[\(modelID)] sample \(sampleIndex) at \(length) chars failed: \(error)")
            }
        }
        let totalStats = Stats(totals)
        let prefillStats = Stats(prefills)
        let decodeStats = Stats(decodes)
        print("[\(modelID)] \(length) chars: p50=\(ms(totalStats.p50))ms p95=\(ms(totalStats.p95))ms max=\(ms(totalStats.max))ms")
        out += "| \(length) chars | \(ms(totalStats.p50))ms | \(ms(totalStats.p95))ms | \(ms(totalStats.max))ms | \(ms(prefillStats.p50))ms | \(ms(prefillStats.p95))ms | \(ms(decodeStats.p50))ms | \(ms(decodeStats.p95))ms |\n"
    }
    out += "\n"
    return out
}

func mdEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "|", with: "\\|")
        .replacingOccurrences(of: "\n", with: "⏎")
        .replacingOccurrences(of: "\r", with: "")
}

func runQualityMode(modelID: String) async -> String {
    var out = "### `\(modelID)`\n\n"
    let engine = CompletionEngine(modelID: modelID, framing: args.framing)

    print("[\(modelID)] loading...")
    do {
        try await engine.warmup()
    } catch {
        out += "Warmup failed: \(error)\n\n"
        return out
    }

    out += "maxTokens=\(args.maxTokens). Framing: `\(await engine.debugFraming)`.\n\n"
    out += "| Buffer | Completion |\n|---|---|\n"
    for prefix in qualityPrefixes {
        do {
            let completion = try await engine.complete(buffer: prefix, maxTokens: args.maxTokens)
            print("[\(modelID)] \(prefix.debugDescription) -> \(completion.debugDescription)")
            out += "| `\(mdEscape(prefix))` | `\(mdEscape(completion))` |\n"
        } catch {
            out += "| `\(mdEscape(prefix))` | ERROR: \(error) |\n"
        }
    }
    out += "\n"
    return out
}

// MARK: - BENCH.md marker-scoped write

/// Replace the content between `<!-- NAME:BEGIN -->` / `<!-- NAME:END -->`
/// markers in `path` with `content`, preserving everything else in the file
/// (hand-written verdicts, headings, other mode's results). If the markers
/// aren't found, the block is appended at the end of the file.
func writeMarkedSection(path: String, marker: String, content: String) throws {
    let beginMarker = "<!-- \(marker):BEGIN -->"
    let endMarker = "<!-- \(marker):END -->"
    let block = "\(beginMarker)\n\(content)\(endMarker)"

    let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

    guard let beginRange = existing.range(of: beginMarker),
        let endRange = existing.range(of: endMarker),
        beginRange.lowerBound < endRange.lowerBound
    else {
        let separator = existing.isEmpty ? "" : "\n\n"
        try (existing + separator + block + "\n").write(
            toFile: path, atomically: true, encoding: .utf8)
        return
    }

    var updated = existing
    updated.replaceSubrange(beginRange.lowerBound..<endRange.upperBound, with: block)
    try updated.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - main

func main() async {
    let mode = args.quality ? "quality" : "latency"
    print("ghost-bench: \(mode) mode, models: \(args.models.joined(separator: ", "))")

    var sections: [String] = []
    for modelID in args.models {
        let section = args.quality
            ? await runQualityMode(modelID: modelID)
            : await runLatencyMode(modelID: modelID)
        sections.append(section)
    }

    let combined = sections.joined(separator: "\n") + "\n"
    let marker = args.quality ? "QUALITY" : "LATENCY"
    let benchPath = "BENCH.md"
    do {
        try writeMarkedSection(path: benchPath, marker: marker, content: combined)
        print("ghost-bench: wrote \(marker) section to \(benchPath)")
    } catch {
        print("ghost-bench: failed to write \(benchPath): \(error)")
    }
}

await main()
