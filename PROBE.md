# AX caret probe results

Run 2026-08-12 with the passive probe built into the app. The question this run
exists to answer, from the project spec:

> If caret bounds come back usable in 3 of 5 apps, proceed with the AX-first
> design. If not, the fallback ladder needs to be primary, and that changes the
> build order.

## Results

| App | Bundle ID | Focused role | `AXBoundsForRange` | Caret rect | Usable |
|---|---|---|---|---|---|
| Terminal | `com.apple.Terminal` | `AXTextArea` | yes | `(17,786 7×14)` | yes |
| TextEdit | `com.apple.TextEdit` | `AXTextArea` | yes | `(157,159 0×14)` | yes |
| Safari | `com.apple.Safari` | `AXTextArea` | yes | `(347,235 2×19)` | yes |
| Brave (Chromium) | `com.brave.Browser` | `AXTextArea` | yes | `(342,224 0×20)` | yes |
| Notes | `com.apple.Notes` | `AXTextArea` | yes | `(980,94 0×23)` | yes |
| Claude (Electron) | `com.anthropic.claudefordesktop` | `AXWebArea` | advertised | `(0,982 0×0)` | **no** |

**5 of 6. AX-first geometry is viable.** Build the AX path as primary with the
ladder underneath, as originally planned. No change to build order.

## What the failures look like

Electron is the one miss, exactly where the spec predicted it. Claude's focused
element is an `AXWebArea` rather than a text element, and while it *advertises*
`AXBoundsForRange` in its parameterized attribute list, the call returns
`(0,982 0×0)` — a zero-size rect at a junk origin. Advertising the attribute means
nothing; the returned rect has to be validated.

Brave showed the same shape transiently: the first sample after activation came
back as `AXGroup` with `(0,982 0×0)` before the web content settled and the real
`AXTextArea` appeared half a second later. So a single bad sample is not proof an
app is unusable — it may just be early.

Both cases are caught by the same plausibility check, which is why
`AX.isPlausibleCaretRect` rejects on geometry rather than on whether the attribute
exists: height must be 4–200pt and the origin must be finite. Zero-width rects are
accepted, because a collapsed caret legitimately has zero width — Safari, Brave,
Notes and TextEdit all returned width 0 or 2 for a real, correctly-placed caret.
Keying the check on width would have thrown away four working apps.

## Other things worth keeping

- **Coordinates are top-left origin.** Terminal's caret came back at y=786 inside a
  window at y=33 height 875. AppKit wants bottom-left, so the overlay needs the flip
  (`AXCoordinates.flipToAppKit`).
- **A caret rect is not always a caret.** Notes reported
  `selectedTextRange = loc 0 len 8829` — the whole note selected, not an insertion
  point. Position off the *end* of the selected range, not the start, or the overlay
  lands at the top of the document.
- **`AXTextArea` is the workhorse role.** Five of six. Worth trying
  `AXBoundsForRange` on any focused element rather than gating on role.
- **`AXInsertionPointLineNumber` is widely available** (Terminal, TextEdit, Notes)
  and is a cheaper sanity check than a full bounds query.

## Method note

The probe watches passively rather than driving apps, because automating text entry
would mean creating real notes, drafts and files in someone's data. Activating an
app is enough: TextEdit, Notes and Claude all focus a text element on activation,
and the browsers were probed with a local page carrying an autofocused `textarea`.

Mail and Obsidian were not running and are not covered here. Both are AppKit and
Electron respectively, so Notes and Claude stand in for their behaviour until a
passive pass catches them.
