# Ghost Text — parity status

Measured against `cotypist_pro_feature_spec.md`. Marked conservatively: `[x]` means
there is code doing it, `[~]` means partial with the gap named, `[ ]` means not
started. A wrong tick makes the whole list useless, so when in doubt it is `[~]`.

## Summary

| Spec section | State | Note |
|---|---|---|
| 2. Core autocomplete engine | `[x]` mostly | Inline suggestions, next-word and phrase accept, dynamic re-prediction all work |
| 3. Acceptance / dismissal | `[~]` | Tab / `~` / Escape and a global toggle work; no rebinding, no force-activate, no per-app toggle |
| 4. Autocorrect | `[ ]` | Not started. Password fields are handled (§30) |
| 5. Emoji | `[ ]` | Not started |
| 6. Multilingual | `[~]` | Key decoding is layout-correct via UCKeyTranslate and handles IME/dead keys; the model is English-weighted |
| 7. Context acquisition | `[~]` | Text before *and after* the caret, 600/200 char window, both fed to the model. No screen or clipboard context |
| 8-9. Personalization | `[ ]` | Nothing is learned or stored. Deliberate for now — see non-goals |
| 10. Custom AI instructions | `[~]` | Global instructions via a text file, hot-reloaded. No per-app or per-domain |
| 11. Completion length | `[~]` | Boundary-stop at sentence/newline/~8 words; not user-configurable |
| 12. Local model layer | `[~]` | Nine models mirroring Cotypist's lineup, switchable from the menu without restart, download progress in the menu title. No catalog management |
| 13. Low-latency inference | `[x]` | Debounce, cancellation, streaming, boundary-stop, prefix KV cache, type-through, instant fallback. 70-110ms, 0ms when typing through |
| 14. Ranking / filtering | `[x]` | Empty, echo, repetition, markdown and whitespace all handled in `CompletionSanitizer` |
| 15. Inline rendering | `[x]` | Click-through overlay, real font from AX, baseline-aligned, screen-edge clamped |
| 16. Field-level UI | `[ ]` | No per-field affordance |
| 17. Menu-bar app | `[~]` | Menu bar with toggle and log access; no settings window |
| 18. App compatibility | `[~]` | Verified in 5 of 6 probed apps; Electron falls back |
| 19-21. Docs / Arc / AI-assistant integrations | `[ ]` | Not started |
| 22. Terminal behavior | `[x]` | Works in Terminal.app; caret geometry confirmed |
| 23-24. App-specific / troubleshooting | `[ ]` | No per-app rules, no diagnostics mode |
| 25. Permissions | `[x]` | Accessibility and Input Monitoring requested and verified at launch |
| 26. Privacy architecture | `[x]` | Fully local, no telemetry, no network at inference time |
| 27. Personalization controls | `[ ]` | Nothing to control yet |
| 28. Statistics | `[ ]` | Not started |
| 29. Diagnostics | `[~]` | Two structured log files; no in-app viewer |
| 30. Secure-input handling | `[x]` | Checked per keydown; buffering and overlay both suppressed |
| 31. Model download manager | `[~]` | HuggingFace download on first launch; no UI, no progress, no management |
| 32. Settings architecture | `[ ]` | On/off only |
| 33. Labs | `[ ]` | No mid-line completion, no word alternatives |
| 34-35. UI states / error handling | `[~]` | Failures log and degrade safely; nothing surfaced in the UI |
| 36. Performance | `[x]` | Measured and recorded in `BENCH.md` |
| 37. AX architecture | `[x]` | Geometry, text window and font, all with timeouts and a fallback ladder |
| 38. Browser/domain detection | `[ ]` | Bundle ID only, no domain awareness |
| 39. Security boundaries | `[x]` | No network, no persistence of typed text |
| 40-41. Open-source architecture | `[x]` | MIT, modular targets, 172 tests |

## Detail on what exists

### Core engine (§2, §13, §14)
- [x] System-wide inline suggestions via a global `CGEventTap`
- [x] Next-word acceptance (`Tab`) and phrase acceptance (`~`)
- [x] Dynamic re-prediction as typing continues, with stale requests cancelled
- [x] Suggestion lifecycle: appear, update in place, dismiss on Escape / commit / caret move / focus change / 30s idle
- [x] Streaming — the overlay paints on the first token, not the last
- [x] Boundary-stop at sentence end, newline, or ~8 words
- [x] Model stays loaded and warm; ~1s cold start, then no reinitialisation
- [x] Inference off the main thread; the tap callback never blocks on it
- [x] Rejects empty, echoed, repeating, and malformed completions
- [~] Measures keystroke-to-suggestion, first-token, prefill/decode split — but no acceptance-rate or cancellation-rate metrics

### Input and output (§37, §30)
- [x] Keystroke buffering rather than AX text reading, so Electron is covered
- [x] Synthetic keystroke insertion rather than AX writes, for the same reason
- [x] Self-event filtering so accepted text is not re-buffered
- [x] Tap re-enabled after `tapDisabledByTimeout`
- [x] Secure input suppresses buffering and the overlay
- [x] Toggle-off tears the tap down rather than hiding the UI

### Rendering (§15)
- [x] Borderless, click-through, non-activating overlay that never takes focus
- [x] Real font read from `AXAttributedStringForRange`, baseline-aligned
- [x] Screen-edge clamping
- [ ] No multi-monitor-specific handling beyond clamping to the containing screen

### Context (§7)
- [x] Text before the caret (600 chars) and after (200 chars)
- [x] Merged with the keystroke buffer, reconciling AX lag
- [x] Falls back to the buffer alone where AX text is unavailable
- [x] Text after the caret is passed to the model as trailing context, capped at 160 chars
- [ ] Screen-aware context (needs Screen Recording)
- [ ] Clipboard context

## What's next

Everything below is measured or diagnosed, not speculative. Numbers live in
`BENCH.md`.

**1. Re-test suggestion quality first, before building anything.**
Concurrent generations were corrupting the KV cache, which made the model emit
the same hallucinated digits for unrelated prompts and probably caused the
near-miss words too ("createt" for "create", "sinces" for "since"). That is
fixed but the quality result has not been judged by a person yet. If word
completions are now sound, the quality complaint is largely answered and the
remaining work is speed polish. If they are still wrong, it is a real model
weakness and needs a different attack. **Do not start optimising until this is
known** - it decides whether items 2 and 3 are worth doing at all.

**2. Prompt Lookup Decoding (P0-ish, speed).**
Model-agnostic speculative decoding that drafts by matching n-grams already
present in the prompt. No draft model, nothing to download, reported 2-2.65x on
Apple Silicon. Our prompts carry 600 characters of the user's own document,
which is close to the ideal case for it. `mlx-swift-lm` ships
`SpeculativeDecodingConfig`, though it is wired for `ChatSession` rather than
the `TokenIterator` path this project uses.

**3. Parked generation (speed).**
Start generating during the 45ms debounce instead of after it, and discard if
the user keeps typing. Cheap now that superseded requests are dropped before
they touch the model.

**4. Shortcut customisation and per-app disable (§3, P0).**
`Tab` suits prose and not every app. `AcceptPolicy.deniedBundleIDs` already
exists and is empty, so the mechanism is there.

**5. A settings window (§32, P0).**
Model choice, instructions and shortcuts all currently live in a menu or a text
file. Once there are three of them it wants a real home.

**6. Personalization (§8-9, P1).**
The largest remaining Cotypist differentiator and the most privacy-sensitive.
Design the encrypted local store before collecting anything.

### Known open issues

- **Mid-word completion quality** is the weakest area and the thing to judge
  first. See item 1.
- **Gemma models are ~8x slower than their parameter count suggests** because
  decode cost tracks vocabulary size: Gemma's 262k against Qwen's 151k. Gemma 3
  1B costs 550-850ms against Qwen3 1.7B's 70-110ms despite being smaller. Worth
  remembering before adding any Gemma to the recommended list.
- **No download progress bar**, only a percentage in the menu title. The 6GB
  models will look frozen for minutes.
- **Two browser tabs** were left open by an early AX probe run
  (`caret-probe.html` in Safari and Brave). Harmless, just clutter.

## Deliberate non-goals

Not gaps. These are decisions recorded in `DESIGN.md` and `README.md`, and should
not resurface as missing features.

- **No telemetry or usage tracking**, ever. Not even local analytics by default.
- **No cloud inference path.** Local-only is the point of the project.
- **No multi-Mac sync**, no accounts, no licensing (§1.2). This is a personal tool.
- **No AX text writing.** Completions are inserted as synthetic keystrokes. The
  spec assumes AX read/write; Ghost Text deliberately inverts that for Electron
  coverage, and this is a difference in approach rather than a missing feature.
- **No per-app caret perfection for every Electron edge case.** The fallback ladder
  handles them; being a few pixels off is cosmetic.
- **No general-purpose chatbot, no IDE code-completion replacement** (§46).
