# Ghost Text

Local next-word autocomplete for macOS. It predicts the next few words as you type,
in any Mac app, using a model that runs entirely on your machine. No cloud calls, no
account, no subscription. Keystrokes never leave the laptop.

This exists because the heavy lifting already happens on your hardware. Metering that
behind a paywall is the thing this is meant to undo.

> **Status:** early development. The input path, the overlay and the accept keys all
> work end to end against real apps. On-device inference is the remaining piece, so
> what it currently suggests is a placeholder string rather than a prediction.

| Piece | State |
|---|---|
| Menu bar app, signed bundle, permission handling | working |
| Global keystroke tap, buffer, debounce, secure-input handling | working |
| Caret geometry via Accessibility, with fallback ladder | working in 5 of 6 apps ([PROBE.md](PROBE.md)) |
| Click-through ghost overlay, screen-edge clamping | working |
| `Tab` / `~` accept, `Escape` dismiss | working |
| On-device model | in progress |

## How it works

Ghost Text does not read the text field you are typing into. It watches keystrokes
through a global event tap and keeps its own buffer of what you have typed. Completions
are drawn as grey ghost text in a floating click-through panel near the caret, and
accepting one synthesizes keystrokes as if you had typed them quickly.

That flip is what makes it work everywhere. Reading and writing text fields through the
Accessibility API breaks on Electron apps and browser text fields; synthetic keystrokes
work in every app, and no app needs to know Ghost Text exists.

Accessibility is used for one thing only: finding out where the caret is on screen, so
the overlay lands in the right place. When that fails it falls back through the focused
element, then the focused window, then hides. A few pixels off is a cosmetic bug.

See [DESIGN.md](DESIGN.md) for the full architecture and the constraints behind it.

## Keys

| Key | Action |
|---|---|
| `Tab` | accept the next word |
| `~` | accept the whole phrase |
| `Escape` | dismiss |

`Tab` and `~` are only intercepted while a suggestion is actually on screen, so they
behave normally the rest of the time. To type a literal `~` or send a real `Tab` while
a suggestion is up, press `Escape` first.

## Building

Requires macOS 14+, Xcode 26+, and Apple Silicon.

```sh
./scripts/build.sh
open "build/Ghost Text.app"
```

Grant **Accessibility** and **Input Monitoring** to the app in System Settings →
Privacy & Security on first launch.

Set `GHOST_SIGN_IDENTITY` to your own signing identity. Using a stable identity matters:
macOS ties permission grants to the code signature, so ad-hoc signing makes the system
forget your grant on every rebuild.

## Tests

```sh
swift test                          # 150 unit tests, ~2s, no permissions needed
./.build/debug/ghost-panel-demo --once   # overlay placement and clamping
open "build/Ghost Text.app" --args --selftest   # end-to-end, types into a scratch file
```

Most of the logic is pure and tested without launching anything. The end-to-end
self-test exists because Ghost Text holds the Accessibility grant and a shell does
not, so the app is the only place that can drive real keystrokes through the real
tap. It writes to a scratch file of its own and re-checks the frontmost app before
every key, so it never types into your documents.

Both logs live in `~/Library/Logs/GhostText/`.

## License

MIT
