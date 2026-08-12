# Ghost Text — design decisions

Local next-word autocomplete for macOS. Menu bar app, on-device model, keystrokes
never leave the machine. Open source because the heavy lifting already happens on
your hardware; metering it behind a subscription is the thing this exists to undo.

## The central flip

The obvious design reads the focused text field through the Accessibility API and
writes the completion back the same way. That breaks on Electron (Slack, VS Code,
Notion, Obsidian) and is inconsistent across browser text fields. So:

- **Input is keystrokes, not AX.** A global `CGEventTap` watches keydown events and
  maintains an in-memory buffer. That buffer is the source of truth for "what has
  the user typed."
- **Output is synthesized keystrokes, not AX writes.** Accepting a completion posts
  key events via `CGEventPost`, exactly as if the user typed fast. Every app accepts
  synthetic keystrokes; no app needs to know Ghost Text exists.
- **AX is used only for geometry** — where to draw the overlay. It is a soft
  dependency with a fallback ladder. Being a few pixels off is cosmetic; it is never
  allowed to break the feature.

## Accept keys

`Tab` accepts the next word. `~` accepts the whole phrase (2–3 words). `Escape`
dismisses.

Tab collides with tab-to-next-field and indent, and tilde collides with `~/` paths.
Both are resolved by one rule:

> **Visible-only gating.** A key is swallowed *only* while ghost text is actually on
> screen. No suggestion showing means Tab and `~` pass through completely untouched.

There is no app denylist — the collision window is narrow enough that gating alone
carries it. `AcceptPolicy` keeps an empty `deniedBundleIDs` set as a one-line escape
valve if a specific app turns out to need it.

To type a literal `~`, or send a real `Tab`, while a suggestion is up: press `Escape`
first. One rule covers both keys. This is the Copilot model and users already know it.

## Hard-won constraints

These are the things that will silently break the app if forgotten.

1. **TCC grants are keyed to the code signature.** Every build must be signed with the
   same identity and bundle ID (`com.suryatej.ghosttext`), or macOS invalidates the
   Accessibility / Input Monitoring grant on every rebuild. `scripts/build.sh` handles
   this. Never ad-hoc sign.
2. **The tap sees its own synthetic events.** Events posted when accepting a completion
   come straight back into our own tap and would re-buffer, potentially looping. All
   synthetic events are stamped with a magic `eventSourceUserData` value and dropped at
   the top of the tap callback.
3. **The tap callback runs inline with system input.** An active (swallowing) tap that
   is slow lags typing machine-wide. The callback does no work beyond reading an atomic
   flag and enqueueing. Never block it on inference.
4. **The system disables taps that overrun.** `.tapDisabledByTimeout` and
   `.tapDisabledByUserInput` must be caught and the tap re-enabled, or the app dies
   quietly after one hiccup.
5. **Secure input mode.** When `IsSecureEventInputEnabled()` is true, stop buffering,
   drop the buffer, hide the overlay. Checked per keydown; it is cheap.
6. **MLX ships Metal shaders in a SwiftPM resource bundle.** A hand-assembled `.app`
   does not pick these up and MLX fails at runtime. `scripts/build.sh` copies every
   `.bundle` into `Contents/Resources/`.
7. **Swift 6 strict concurrency is on.** MLX types are not `Sendable`. Inference lives
   behind an actor. Some Carbon globals (e.g. `kAXTrustedCheckOptionPrompt`) are
   imported as `var` and must be replaced with string literals.

## Targets

| Target | Contents | How it is verified |
|---|---|---|
| `GhostTextCore` | `KeystrokeBuffer`, `KeyDecoder`, `Debouncer`, `CaretResolver`, `CompletionSanitizer`, `AcceptPolicy` | XCTest, seconds, no launch |
| `GhostTextUI` | Click-through overlay `NSPanel` | harness with hardcoded coords |
| `GhostTextInference` | MLX actor, warm model, cancellable generate | `ghost-bench` CLI |
| `GhostTextApp` | Menu bar, event tap, AX geometry | live checkpoints only |

The rule: anything expressible as a pure function over injected inputs belongs in
`GhostTextCore`. The caret fallback ladder in particular is a decision function over
`(axBounds?, elementFrame?, windowFrame?, lastKnownGood?, age)` and is fully tested
without ever touching AX.

## Testing budget

Live runs are expensive. Prefer logs over screenshots, unit tests over live runs, and
one consolidated checkpoint per phase rather than verification after every fix. Budget
for v1 is five live runs plus one batched six-app AX probe.
