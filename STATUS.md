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
| 7. Context acquisition | `[~]` | Text before and after the caret, 600/200 char window. No screen or clipboard context |
| 8-9. Personalization | `[ ]` | Nothing is learned or stored. Deliberate for now — see non-goals |
| 10. Custom AI instructions | `[ ]` | Not started |
| 11. Completion length | `[~]` | Boundary-stop at sentence/newline/~8 words; not user-configurable |
| 12. Local model layer | `[~]` | One model, in-process MLX, warm at launch. No catalog, no switching |
| 13. Low-latency inference | `[x]` | Debounce, cancellation, warm model, streaming, boundary-stop, off-main-thread. 67-94ms end to end |
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
- [ ] Screen-aware context (needs Screen Recording)
- [ ] Clipboard context

## What's next

Ordered by what makes this better to use daily, which given the feedback so far
means quality and control before breadth.

**1. Suggestion quality (P0, unlabelled in the spec but the real gap).**
The plumbing is fast; the predictions are mediocre because a 0.5B model is small.
Worth trying, roughly in cost order: a larger model (1.5B-3B, measure the latency
cost against the 67-94ms baseline), better prompt framing now that real context is
available, and using the text *after* the caret, which is already read but not yet
fed to the model.

**2. Model catalog and switching (§12, P1).** Directly serves item 1 and is the
main lever a user has over the quality/latency trade. Needs a download manager
with progress (§31).

**3. Shortcut customisation and per-app toggle (§3, P0).** `Tab` is right for
prose and wrong in some apps. Users need to rebind it and to disable Ghost Text
per app. The `AcceptPolicy.deniedBundleIDs` hook already exists and is empty.

**4. A settings window (§32, P0).** Everything above needs somewhere to live.

**5. Personalization (§8-9, P1).** The largest remaining Cotypist differentiator,
and the most privacy-sensitive. Needs the encrypted local store designed before
any collection starts.

Then: autocorrect (§4), statistics (§28), mid-line completion (§33.1).

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
