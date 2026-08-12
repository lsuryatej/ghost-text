# Ghost Text

Local next-word autocomplete for macOS. It predicts the next few words as you type,
in any Mac app, using a model that runs entirely on your machine. No cloud calls, no
account, no subscription. Keystrokes never leave the laptop.

This exists because the heavy lifting already happens on your hardware. Metering that
behind a paywall is the thing this is meant to undo.

> **Status:** early development. Not yet usable.

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
swift test
```

## License

MIT
