# Open-Source Mac Autocomplete — Cotypist Pro Feature Specification

> **Purpose:** Implementation backlog and parity specification for an open-source Mac application targeting feature parity with Cotypist Pro for a single Mac user.
>
> **Research basis:** Current Cotypist official pricing, knowledge-base, privacy, shortcuts, personalization, compatibility, tips, and troubleshooting documentation reviewed August 12, 2026.
>
> **Important:** This is a **behavioral/product parity specification**, not a recommendation to copy proprietary source code, assets, branding, or implementation details. Implement independently using documented behavior and compatible open-source components.

---

## 0. Product definition

### Product goal

Build a native macOS application that:

- Runs primarily/system-wide on Apple Silicon Macs.
- Provides low-latency inline next-word / phrase autocomplete in supported text fields.
- Runs language-model inference locally on the Mac.
- Can use surrounding screen context, clipboard context, and optional local writing history to improve suggestions.
- Supports configurable keyboard-driven acceptance.
- Supports global, per-app, and per-domain behavior.
- Provides configurable personalization and custom AI instructions.
- Provides a model-selection layer suitable for multiple local LLMs.
- Provides experimental features such as mid-line completion and word alternatives.
- Provides transparent privacy controls and local data deletion.
- Provides statistics and diagnostics.
- Handles macOS Accessibility / Screen Recording / clipboard permissions cleanly.

---

# 1. Platform and account scope

## 1.1 Target platform

- [ ] macOS
- [ ] Apple Silicon required for first release
- [ ] macOS 14+ target
- [ ] Intel Mac behavior explicitly rejected or documented as unsupported
- [ ] Native menu-bar application
- [ ] Application launches without requiring a visible main window
- [ ] Application can run continuously in the background

## 1.2 Licensing model

For the first implementation target:

- [ ] Single user
- [ ] Single Mac
- [ ] No team-sharing requirement
- [ ] No multi-user account requirement
- [ ] No subscription/payment requirement for the open-source implementation unless the project chooses to add one later

Optional future parity:

- [ ] Multi-Mac identity/account support
- [ ] One-person / multiple-device entitlement
- [ ] Subscription management

---

# 2. Core autocomplete engine

## 2.1 System-wide inline suggestions

- [ ] Detect supported text fields across macOS.
- [ ] Read the text immediately surrounding the insertion point.
- [ ] Determine cursor position.
- [ ] Build a completion prompt/context.
- [ ] Run a local language model.
- [ ] Render the completion inline at/near the cursor.
- [ ] Update the suggestion while the user continues typing.
- [ ] Remove stale suggestions when context changes.
- [ ] Never require a separate chat window for normal autocomplete.
- [ ] Avoid inserting text unless the user explicitly accepts it.

## 2.2 Next-word completion

Primary interaction:

- [ ] Suggest a multi-word continuation.
- [ ] `Tab` accepts only the next word.
- [ ] Repeated `Tab` presses walk through the existing suggestion word-by-word.
- [ ] User can stop accepting at any point.
- [ ] After each accepted word, maintain normal cursor/typing behavior.
- [ ] Allow a trailing-space option after single-word acceptance.

## 2.3 Full-completion acceptance

- [ ] Separate shortcut accepts the entire current suggestion.
- [ ] Default shortcut is the key above Tab on supported keyboard layouts.
- [ ] Support keyboard-layout-dependent availability.
- [ ] Allow complete shortcut reassignment.

## 2.4 Dynamic prediction

- [ ] Re-run/update completion as the user types.
- [ ] Avoid forcing the user to dismiss an almost-correct suggestion.
- [ ] Recompute prediction after relevant keystrokes.
- [ ] Preserve already accepted user text.
- [ ] Keep latency low enough that suggestions do not visibly lag behind normal typing.

## 2.5 Suggestion lifecycle

States:

- [ ] No suggestion
- [ ] Generating
- [ ] Displaying suggestion
- [ ] Partially accepted
- [ ] Fully accepted
- [ ] Dismissed
- [ ] Temporarily paused
- [ ] Disabled for current field
- [ ] Disabled for current application
- [ ] Globally disabled

---

# 3. Acceptance / dismissal controls

## 3.1 Default shortcuts

Implement configurable actions:

| Action | Default |
|---|---|
| Complete next word | `Tab` |
| Accept full completion | key above Tab (``, `§`, or `^` depending on layout) |
| Dismiss suggestion | `Esc` |
| Force-activate completion | `Ctrl` + key above Tab |
| Temporarily toggle current app | `Ctrl` + `Option` + `Cmd` + key above Tab |
| Global toggle | Unassigned by default |

- [ ] All shortcuts configurable.
- [ ] Detect conflicts where possible.
- [ ] Handle keyboard layouts where the default key is unavailable.
- [ ] Allow shortcuts to be unassigned.

## 3.2 Escape behavior

Configurable `Esc` behavior:

- [ ] Dismiss current suggestion.
- [ ] Briefly pause completion in current field.
- [ ] Pass through to underlying application.
- [ ] Persist chosen behavior in settings.

## 3.3 Force activation

- [ ] Provide a shortcut to force a completion when automatic activation is idle.
- [ ] Useful in terminals.
- [ ] Useful in unusual/partially supported text fields.
- [ ] Useful in Google Sheets and AI-chat panels.
- [ ] Do not require force activation in normally supported fields.

## 3.4 Global toggle

- [ ] User-configurable global enable/disable shortcut.
- [ ] Global disabled state survives until toggled back on.
- [ ] Show current state in menu-bar UI.

## 3.5 Per-app temporary toggle

- [ ] Temporarily disable completions for current application.
- [ ] Allow them to automatically return after a short period if desired.
- [ ] Provide visual indication of temporary state.

---

# 4. Autocorrect

## 4.1 Full autocorrect

Pro-equivalent behavior:

- [ ] Detect likely spelling/typing errors.
- [ ] Offer an inline correction.
- [ ] Allow user to accept the correction using the normal completion interaction.
- [ ] Do not silently replace user text without explicit acceptance.

## 4.2 Typo-suspected behavior

When a typo is suspected:

- [ ] Option to suppress the next predictive completion so the model does not build on an obvious typo.
- [ ] Option to show a suggested fix.
- [ ] Make these behaviors independently configurable.

## 4.3 Password fields

- [ ] Never generate suggestions in password fields.
- [ ] Respect macOS protected/password-field semantics.
- [ ] Do not attempt to bypass secure input.

---

# 5. Emoji

- [ ] Predict emoji where context warrants it.
- [ ] Render emoji as normal completion candidates.
- [ ] Allow emoji completion through the normal acceptance flow.
- [ ] Do not interfere with native emoji picker behavior.

---

# 6. Multilingual support

- [ ] Support writing in multiple languages.
- [ ] Do not require a hard language switch for ordinary code-switching.
- [ ] Permit language-specific custom instructions.
- [ ] Detect language/context from recent text where practical.
- [ ] Allow app/domain instructions to specify a preferred language.

Example:

```text
Global: general writing preferences
Mail: German
Slack: English
Client website: French
```

---

# 7. Context acquisition

## 7.1 Immediate text-field context

- [ ] Read text before cursor.
- [ ] Read text after cursor when available.
- [ ] Read current field contents where supported.
- [ ] Track selection/cursor changes.
- [ ] Rebuild context after edits.

## 7.2 Screen-aware context

Optional feature requiring macOS Screen Recording permission:

- [ ] Capture relevant visible screen content.
- [ ] Extract/read surrounding text.
- [ ] Use visible context when generating suggestions.
- [ ] Use surrounding email/document/chat text to infer context.
- [ ] Use visible names and terminology.
- [ ] Avoid repeating information already visible.
- [ ] Never persist screen captures unless explicitly designed and disclosed.
- [ ] Never transmit screen content to a remote inference service in the default local-only architecture.

Examples:

- Replying to an email.
- Responding to a message.
- Writing beneath a visible document heading.
- Writing in a visible form with surrounding explanatory text.

## 7.3 Clipboard context

Pro-equivalent optional feature:

- [ ] Optional clipboard-aware context.
- [ ] Feature off by default.
- [ ] Read clipboard contents in memory.
- [ ] Use recently copied text as generation context.
- [ ] Do not persist clipboard contents.
- [ ] Do not transmit clipboard contents.
- [ ] Restore the original clipboard if temporary clipboard manipulation is required for insertion.

---

# 8. Personalization

## 8.1 Input collection

Feature:

`Collect inputs for personalization`

- [ ] Off by default.
- [ ] Explicit opt-in.
- [ ] Record text from monitored fields when enabled.
- [ ] Use collected text to improve vocabulary/style prediction.
- [ ] Do not send collected inputs to a server.
- [ ] Store locally in encrypted storage.

## 8.2 Accepted-completion-only mode

Default collection mode:

- [ ] Save a writing session only when the user actually accepted a completion during that session.
- [ ] Use accepted text as a higher-confidence personalization signal.

## 8.3 Store-all-inputs mode

Optional setting:

`Store inputs without accepted completions`

- [ ] When enabled, store all eligible monitored input sessions.
- [ ] When disabled, retain accepted-completion-only behavior.

## 8.4 Short-input filtering

- [ ] Do not store short inputs.
- [ ] Skip search queries.
- [ ] Skip quick form entries.
- [ ] Apply minimum useful-content threshold.
- [ ] Ensure password fields are excluded.

## 8.5 Per-app / per-domain collection controls

- [ ] Enable/disable personalization collection globally.
- [ ] Enable/disable collection for individual apps.
- [ ] Enable/disable collection for individual browser domains.
- [ ] Current app/domain setting accessible from field-level Cotypist-style UI.
- [ ] Current app/domain setting accessible from menu-bar/settings UI.

## 8.6 Local encrypted storage

- [ ] Store personalization input history locally.
- [ ] Encrypt the database at rest.
- [ ] Store encryption key in macOS Keychain.
- [ ] Never upload personalization input history.
- [ ] Never expose raw personalization data through telemetry.

## 8.7 Derived personalization profile

- [ ] Derive a compact profile from collected writing.
- [ ] Capture vocabulary preferences.
- [ ] Capture frequently used names.
- [ ] Capture specialist terminology.
- [ ] Capture common phrases.
- [ ] Capture stylistic tendencies.
- [ ] Use profile during generation.
- [ ] Delete derived profile when all source personalization data is deleted.

---

# 9. Personalization strength

Implement a six-stop control:

```text
1. Off
2. Low
3. ...
4. Medium / balanced
5. ...
6. Strong / Max
```

- [ ] Six discrete positions.
- [ ] Off disables influence from personalization.
- [ ] Low/medium provide increasingly subtle vocabulary bias.
- [ ] Strong provides maximum influence.
- [ ] Changing slider changes generation behavior without requiring deletion of the underlying history.
- [ ] Deleting collected data resets the derived personalization profile.

Cotypist's current tier limits:

- Free: through position 2.
- Plus: through position 4.
- Pro: through position 6.

For this open-source project:

- [ ] Expose all six positions.

---

# 10. Custom AI instructions

## 10.1 Global instructions

- [ ] Free-text global instruction field.
- [ ] Include instructions in every suggestion generation request.
- [ ] Example use cases:
  - occupation
  - audience
  - preferred language
  - tone
  - terminology
  - writing style
- [ ] Keep prompt concise.
- [ ] Provide an editable default based on system language/region if desired.
- [ ] Provide `Reset to Default`.

## 10.2 Per-app instructions

- [ ] Attach custom instructions to a native macOS app.
- [ ] Apply app instructions whenever typing in that app.
- [ ] Append app instructions after global instructions.
- [ ] Allow editing/removal.
- [ ] Allow adding an app not currently listed.
- [ ] Support drag-and-drop app addition.

## 10.3 Per-domain instructions

- [ ] Attach custom instructions to a website/domain.
- [ ] Apply domain instructions when typing on that domain.
- [ ] Allow manually entering a domain.
- [ ] Allow editing/removal.
- [ ] Browser-specific configuration overrides or supplements global instructions.

Example:

```text
Global:
Write concise technical prose.

Slack:
Be informal and short.

Mail:
Use professional language.

github.com:
Use engineering terminology.
```

---

# 11. Completion length

- [ ] Provide configurable maximum completion length.
- [ ] At minimum expose:
  - Short
  - Medium/default
  - Long
- [ ] Longer completions must not be forced on users who prefer word-by-word interaction.
- [ ] Completion length must influence generation constraints.
- [ ] Setting must persist across launches.

Cotypist tier behavior:

- Free: default/locked length.
- Plus: configurable.
- Pro: configurable.

Open-source implementation:

- [ ] Make all length options available.

---

# 12. Local model layer

## 12.1 Model abstraction

Build a model-provider abstraction independent of the UI:

```text
ModelProvider
├── load()
├── unload()
├── generate(context)
├── cancel()
├── stream_tokens()
├── estimate_latency()
├── memory_requirement()
└── health_check()
```

## 12.2 Required initial model catalog for Cotypist parity

Current Cotypist catalog:

### Light models

- [ ] Gemma 4 E2B
- [ ] Qwen 3 1.7B
- [ ] Gemma 3 1B

### Mid-size models

- [ ] Gemma 4 E4B
- [ ] Qwen 3 4B
- [ ] Gemma 3 4B

### Pro / large models

- [ ] Gemma 4 26B A4B
- [ ] Qwen 3 30B-A3B
- [ ] Qwen 3 8B

## 12.3 Model selection

- [ ] User-selectable model.
- [ ] Model metadata:
  - parameter count
  - quantization
  - memory requirement
  - expected latency
  - supported context length
- [ ] Automatically recommend a model based on Mac hardware.
- [ ] Warn when a model is likely too slow for real-time autocomplete.
- [ ] Allow manual override.
- [ ] Download models on demand.
- [ ] Show model download progress.
- [ ] Verify model integrity.
- [ ] Allow model deletion.
- [ ] Avoid downloading every model by default.

## 12.4 Local inference

- [ ] No cloud inference required.
- [ ] Run models locally.
- [ ] Support Apple Silicon acceleration.
- [ ] Support an efficient local inference runtime such as llama.cpp or an equivalent open-source runtime.
- [ ] Stream output where useful.
- [ ] Cancel stale generation immediately when the user types new content.
- [ ] Prioritize time-to-first-useful-word over maximum generation throughput.

---

# 13. Low-latency inference requirements

Autocomplete is latency-sensitive.

Implement:

- [ ] Debounce generation triggers.
- [ ] Cancel stale requests.
- [ ] Maintain model loaded state.
- [ ] Avoid repeated model initialization.
- [ ] Cache reusable prompt/context components where safe.
- [ ] Limit context to relevant text.
- [ ] Prioritize short completions.
- [ ] Stream model output.
- [ ] Stop generation once a useful completion boundary is reached.
- [ ] Prevent UI blocking.
- [ ] Run inference off the main UI thread.
- [ ] Measure:
  - keystroke-to-suggestion latency
  - model load latency
  - first-token latency
  - tokens/sec
  - acceptance rate
  - stale-generation cancellation rate

Suggested product target:

```text
P50 suggestion latency: as low as practical
P95 suggestion latency: low enough that normal typing is not interrupted
```

Do not define a hard latency target until real hardware benchmarks exist.

---

# 14. Suggestion ranking / filtering

- [ ] Reject empty completions.
- [ ] Reject completions that merely repeat existing text.
- [ ] Remove malformed outputs.
- [ ] Normalize whitespace.
- [ ] Handle punctuation correctly.
- [ ] Avoid duplicating a word already immediately before cursor.
- [ ] Detect sentence/paragraph boundaries.
- [ ] Stop at useful boundaries where appropriate.
- [ ] Prefer the next useful word for word-by-word acceptance.
- [ ] Respect custom instructions.
- [ ] Respect personalization.
- [ ] Respect app/domain context.
- [ ] Respect language context.
- [ ] Respect clipboard/screen context if enabled.

---

# 15. Inline rendering UI

- [ ] Render suggestion in a visually distinct but unobtrusive style.
- [ ] Align suggestion with current text baseline.
- [ ] Show suggestion only when confidence/quality is sufficient.
- [ ] Avoid obscuring existing application UI.
- [ ] Update display without visible flicker.
- [ ] Support light/dark macOS appearance.
- [ ] Respect text-field geometry.
- [ ] Handle scrolling text fields.
- [ ] Handle cursor movement.
- [ ] Handle selection changes.
- [ ] Handle window movement.
- [ ] Handle display changes.
- [ ] Handle Retina scaling.

---

# 16. Field-level Cotypist UI

Provide a small contextual UI near supported fields.

Functions:

- [ ] Open current app settings.
- [ ] Toggle completions for current app.
- [ ] Toggle personalization collection for current app.
- [ ] Toggle relevant contextual features.
- [ ] Show troubleshooting/status information.
- [ ] Indicate current active/disabled state.

---

# 17. Menu-bar application

- [ ] Menu-bar icon.
- [ ] Current enabled/disabled state.
- [ ] Open Settings.
- [ ] Global enable/disable.
- [ ] Current app controls.
- [ ] Personalization controls.
- [ ] Statistics access.
- [ ] Privacy status/access.
- [ ] Troubleshooting entry.
- [ ] Quit/restart application.

---

# 18. Application compatibility layer

## 18.1 General strategy

Use macOS Accessibility APIs to:

- [ ] Discover focused text fields.
- [ ] Read text.
- [ ] Read selection/cursor.
- [ ] Insert accepted completion.
- [ ] Detect application/domain.
- [ ] Determine field type where possible.

## 18.2 Supported applications to target

### Browsers

- [ ] Safari — works
- [ ] Chrome — works
- [ ] Brave — works
- [ ] Edge — works
- [ ] Firefox — works
- [ ] Zen Browser — works
- [ ] Arc — setup required
- [ ] Dia — setup required

### Email

- [ ] Apple Mail — works
- [ ] Gmail — works
- [ ] Outlook — works
- [ ] Mimestream — works
- [ ] Thunderbird — currently unsupported by Cotypist

### Documents

- [ ] Microsoft Word — works
- [ ] Google Docs — setup required
- [ ] Google Sheets — works
- [ ] Google Slides — unsupported by Cotypist
- [ ] TextEdit — works
- [ ] Pages — works
- [ ] Scrivener — works

### Notes

- [ ] Apple Notes — works
- [ ] Notion — works
- [ ] Obsidian — works
- [ ] OneNote — unsupported
- [ ] Anki — unsupported

### Messaging

- [ ] Messages — works
- [ ] Teams — works
- [ ] Slack — partial
- [ ] WhatsApp — works

### Code editors

- [ ] VS Code — AI/sidebar chat fields
- [ ] Cursor — AI/sidebar chat fields
- [ ] Windsurf — AI/sidebar chat fields
- [ ] Zed — unsupported
- [ ] BBEdit — works
- [ ] Sublime Text — unsupported

### Terminals

- [ ] Terminal.app — works
- [ ] iTerm — works
- [ ] Ghostty — unsupported
- [ ] cmux — unsupported
- [ ] Warp — unsupported
- [ ] Kitty — unsupported

### Creative

- [ ] Final Cut Pro — unsupported

> Compatibility changes over time. Treat this list as the parity target observed in the current Cotypist documentation, not a permanent compatibility promise.

---

# 19. Google Docs integration

- [ ] Detect Google Docs.
- [ ] Detect whether accessibility support is enabled.
- [ ] Provide setup guidance.
- [ ] Support Google Docs Screen Reader support.
- [ ] Support Google Docs Braille support where required.
- [ ] Recommend disabling Google Docs Smart Compose to avoid competing autocomplete systems.
- [ ] Provide troubleshooting instructions.

---

# 20. Arc / Dia integration

- [ ] Detect Arc/Dia.
- [ ] Detect whether accessibility/text metrics support is enabled.
- [ ] Provide one-time setup instructions.
- [ ] Support Chrome accessibility Text Metrics where applicable.
- [ ] Document alternate launch configuration using complete renderer accessibility where necessary.
- [ ] Provide troubleshooting state.

---

# 21. AI coding assistant integration

Target:

- [ ] VS Code AI/sidebar chats
- [ ] Cursor AI/sidebar chats
- [ ] Windsurf AI/sidebar chats

Behavior:

- [ ] Enable autocomplete in natural-language AI prompts.
- [ ] Avoid interfering with native code completion in the main code editor.
- [ ] Allow force activation in supported fields.
- [ ] Detect AI-chat text fields where possible.

Do not automatically compete with:

- IntelliSense
- native code completion
- Copilot code completion
- editor-specific completion systems

---

# 22. Terminal behavior

## 22.1 Terminal.app

- [ ] Support text interaction.
- [ ] Detect AI-agent prompts where possible.
- [ ] Provide autocomplete in AI-agent prompts.
- [ ] Keep ordinary shell command completion behavior undisturbed by default.
- [ ] Allow force activation for normal terminal text.

## 22.2 iTerm

Same target behavior as Terminal.app.

## 22.3 Unsupported terminals

Document that some terminal applications may not expose sufficient Accessibility support.

Examples currently listed as unsupported:

- Ghostty
- cmux
- Warp
- Kitty

---

# 23. App-specific behavior

Each app/domain configuration should be able to store:

```text
enabled
input_collection_enabled
custom_instructions
language/preferences
compatibility_mode
tab_behavior
```

Optional:

```text
screen_context_enabled
clipboard_context_enabled
model_override
completion_length_override
```

---

# 24. Compatibility troubleshooting mode

Implement:

- [ ] `Improve Compatibility With This App`
- [ ] Toggle accessibility workarounds.
- [ ] Adjust text-field detection strategy.
- [ ] Try alternate insertion strategy.
- [ ] Provide force-activate shortcut.
- [ ] Provide diagnostic logging.
- [ ] Display current application bundle ID.
- [ ] Display current focused accessibility element.
- [ ] Display detected text-field capabilities.

Electron apps:

- [ ] Provide compatibility mode.
- [ ] Provide force activation.
- [ ] Document that accessibility support varies.

---

# 25. Permissions

## 25.1 Accessibility — required

Use for:

- [ ] Reading active text fields.
- [ ] Reading cursor/selection.
- [ ] Inserting completions.
- [ ] Detecting focused application context.

If missing:

- [ ] Explain why permission is required.
- [ ] Provide direct path to System Settings.
- [ ] Detect permission state.
- [ ] Re-check after user changes settings.

## 25.2 Screen Recording — optional

Use for:

- [ ] Screen-aware contextual suggestions.

If missing:

- [ ] Core autocomplete continues working.
- [ ] Screen-context feature reports unavailable.
- [ ] Settings explain why the permission is useful.

## 25.3 Clipboard — optional

Use for:

- [ ] Clipboard context.

If disabled:

- [ ] Core autocomplete continues working.
- [ ] No clipboard reads.

---

# 26. Privacy architecture

## 26.1 Core principle

Default architecture:

```text
User typing
    ↓
macOS Accessibility
    ↓
Local context builder
    ↓
Local model
    ↓
Local suggestion renderer
    ↓
User
```

No text needs to leave the Mac.

## 26.2 Data that must remain local

- [ ] Active text-field content.
- [ ] Completion context.
- [ ] Generated completion.
- [ ] Screen-derived text.
- [ ] Clipboard-derived text.
- [ ] Personalization history.
- [ ] Personalization profile.

## 26.3 Telemetry

If telemetry is implemented:

- [ ] Anonymous only.
- [ ] Never transmit typed text.
- [ ] Never transmit completions.
- [ ] Never transmit clipboard contents.
- [ ] Never transmit screen-recognized text.
- [ ] Never transmit personalization history.
- [ ] Make telemetry opt-out.
- [ ] Explain exactly what is sent.
- [ ] Provide a settings switch.
- [ ] Prefer no telemetry in the initial open-source release unless needed.

---

# 27. Personalization data controls

Settings must support:

- [ ] Enable collection.
- [ ] Disable collection.
- [ ] Per-app exclusion.
- [ ] Per-domain exclusion.
- [ ] Show amount of collected data by app/domain.
- [ ] Delete all data.
- [ ] Delete data by app.
- [ ] Delete data by domain.
- [ ] Clear derived personalization profile.
- [ ] Explain that disabling collection does not delete previously collected data.

---

# 28. Statistics

Provide:

- [ ] Total accepted completion words.
- [ ] Completion count by day.
- [ ] Active writing days.
- [ ] Per-app usage where privacy allows.
- [ ] Acceptance rate.
- [ ] Potentially saved-word count.
- [ ] Model performance metrics.
- [ ] Latency statistics.

Minimum parity requirement:

- [ ] Statistics screen showing completed words broken down by active day.

---

# 29. Diagnostics

Implement a diagnostics page containing:

- [ ] Accessibility permission status.
- [ ] Screen Recording permission status.
- [ ] Clipboard feature status.
- [ ] Current model.
- [ ] Model loaded/not loaded.
- [ ] Model memory usage where available.
- [ ] Model latency.
- [ ] Current focused app.
- [ ] Current domain.
- [ ] Current field support status.
- [ ] Compatibility mode state.
- [ ] Recent errors.
- [ ] Copy diagnostic information button.

---

# 30. Secure-input handling

macOS Secure Input can interfere with global keyboard shortcuts.

Implement:

- [ ] Detect secure-input state where possible.
- [ ] Do not attempt to bypass secure input.
- [ ] Explain when shortcuts are blocked by another application.
- [ ] Continue allowing `Tab` where macOS permits it.
- [ ] Identify likely troubleshooting steps without falsely claiming which application owns secure input.
- [ ] Document common causes:
  - password managers
  - browser extensions
  - screen-sharing software
  - Terminal/iTerm Secure Keyboard Entry

---

# 31. Model download manager

- [ ] Browse available models.
- [ ] Show installed models.
- [ ] Download model.
- [ ] Pause/cancel download.
- [ ] Verify download.
- [ ] Delete model.
- [ ] Show disk size.
- [ ] Show approximate RAM requirement.
- [ ] Show recommended hardware.
- [ ] Prevent use of incomplete/corrupt models.
- [ ] Automatically select a usable default.

---

# 32. Settings architecture

Suggested settings structure:

```text
Settings
├── General
│   ├── Enable Cotypist
│   ├── Model
│   ├── Completion Length
│   ├── Autocorrect
│   ├── Privacy / Telemetry
│   └── Diagnostics
│
├── Shortcuts
│   ├── Complete Next Word
│   ├── Accept Full Completion
│   ├── Dismiss
│   ├── Force Activate
│   ├── Temporary App Toggle
│   └── Global Toggle
│
├── Personalization
│   ├── Collect Inputs
│   ├── Store All Inputs
│   ├── Personalization Strength
│   ├── Custom AI Instructions
│   └── Existing Data
│
├── Context
│   ├── Screen-Aware Context
│   └── Clipboard Context
│
├── App Settings
│   ├── App List
│   ├── Domain List
│   ├── Enable/Disable
│   ├── Input Collection
│   ├── Custom Instructions
│   └── Compatibility
│
├── Labs
│   ├── Mid-Line Completion
│   └── Word Alternatives
│
├── Statistics
│   ├── Completed Words
│   ├── Daily History
│   └── Performance
│
└── About
    ├── Version
    ├── Model Runtime
    ├── Open Source Licenses
    └── Diagnostics
```

---

# 33. Labs

## 33.1 Mid-line completion

- [ ] Experimental feature.
- [ ] Disabled by default.
- [ ] Pro-equivalent feature.
- [ ] Detect cursor inside existing text.
- [ ] Read both left and right context.
- [ ] Generate text that bridges the cursor location.
- [ ] Insert only after explicit acceptance.
- [ ] Handle punctuation and spacing.
- [ ] Avoid overwriting surrounding text.

Example:

```text
The meeting is scheduled for | at 3pm.
                       cursor
```

Possible suggestion:

```text
Thursday
```

## 33.2 Word Alternatives

- [ ] Experimental feature.
- [ ] Generate alternative word candidates for current suggestion.
- [ ] Display numbered choices.
- [ ] Select by number.
- [ ] Allow automatic display after a short pause.
- [ ] Allow shortcut-triggered display only.
- [ ] Make feature optional.
- [ ] Preserve normal autocomplete when disabled.

Example:

```text
1. significant
2. substantial
3. considerable
4. notable
```

---

# 34. UI states

Implement UI states for:

- [ ] Loading model
- [ ] Model ready
- [ ] Model unavailable
- [ ] Downloading model
- [ ] Accessibility permission missing
- [ ] Screen Recording permission missing
- [ ] Clipboard context disabled
- [ ] Global disabled
- [ ] App disabled
- [ ] Field unsupported
- [ ] Generating
- [ ] Suggestion ready
- [ ] Suggestion dismissed
- [ ] Labs feature enabled
- [ ] Labs feature disabled
- [ ] Compatibility mode enabled
- [ ] Secure Input interference

---

# 35. Error handling

Must gracefully handle:

- [ ] Accessibility permission revoked.
- [ ] Screen Recording permission revoked.
- [ ] Model missing.
- [ ] Model download failure.
- [ ] Model corruption.
- [ ] Out-of-memory conditions.
- [ ] Unsupported field.
- [ ] Unsupported application.
- [ ] Application crash/restart.
- [ ] Cursor moved during generation.
- [ ] Text changed during generation.
- [ ] User switches apps during generation.
- [ ] Display changes.
- [ ] Clipboard changes during generation.
- [ ] Secure Input enabled.
- [ ] App loses accessibility element.
- [ ] Model runtime crash.

---

# 36. Performance requirements

Measure and optimize:

- [ ] Cold startup.
- [ ] Warm startup.
- [ ] Model loading.
- [ ] First-token latency.
- [ ] Suggestion display latency.
- [ ] Full-completion generation time.
- [ ] CPU usage while idle.
- [ ] CPU usage while generating.
- [ ] GPU/ANE utilization where available.
- [ ] RAM usage.
- [ ] Battery impact.
- [ ] Disk usage.
- [ ] Accessibility polling overhead.
- [ ] Screen capture overhead.
- [ ] Clipboard polling overhead.

Important:

- [ ] Never continuously poll the entire screen.
- [ ] Avoid unnecessary accessibility-tree traversal.
- [ ] Avoid inference when the field is inactive.
- [ ] Cancel stale generations.
- [ ] Avoid keeping unnecessarily large context windows.

---

# 37. Accessibility API architecture

Suggested components:

```text
Mac Accessibility Layer
├── FocusObserver
├── TextFieldReader
├── CursorReader
├── SelectionReader
├── TextInserter
├── AppDetector
├── WindowDetector
├── SecureInputDetector
└── CapabilityDetector
```

Requirements:

- [ ] Event-driven observation where possible.
- [ ] Avoid aggressive polling.
- [ ] Handle apps with partial AX support.
- [ ] Provide compatibility fallbacks.
- [ ] Keep Accessibility operations off the UI thread.

---

# 38. Browser/domain detection

- [ ] Detect browser application.
- [ ] Detect active tab/domain where technically possible.
- [ ] Map domain → configuration.
- [ ] Handle subdomains.
- [ ] Normalize domains.
- [ ] Avoid storing full URLs unless necessary.
- [ ] Never transmit visited URLs through telemetry by default.

---

# 39. Security boundaries

- [ ] Never bypass macOS permission mechanisms.
- [ ] Never read password fields.
- [ ] Never scrape arbitrary applications outside the focused/contextually required scope.
- [ ] Never transmit user text by default.
- [ ] Encrypt local personalization data.
- [ ] Protect encryption keys using Keychain.
- [ ] Provide explicit data deletion.
- [ ] Ensure logs do not contain user text by default.
- [ ] Redact sensitive text from diagnostics.

---

# 40. Open-source architecture

Recommended high-level architecture:

```text
┌──────────────────────────────────────────────┐
│                 macOS App                    │
│                                              │
│  Menu Bar ─── Settings ─── Diagnostics       │
│                    │                         │
│                    ▼                         │
│              Configuration                   │
│                    │                         │
│       ┌────────────┴────────────┐            │
│       ▼                         ▼            │
│ Accessibility Layer       Context Layer      │
│       │                  ┌──────┼──────┐     │
│       │                  │      │      │     │
│       │                Field  Screen Clipboard│
│       │                  │      │      │     │
│       └──────────────────┴──────┴──────┘     │
│                         │                    │
│                         ▼                    │
│                 Prompt Builder              │
│                         │                    │
│                         ▼                    │
│                Personalization              │
│                         │                    │
│                         ▼                    │
│                   Model Router              │
│                         │                    │
│                         ▼                    │
│                 Local Inference             │
│                         │                    │
│                         ▼                    │
│                 Suggestion Engine            │
│                         │                    │
│                         ▼                    │
│                 Inline Renderer              │
└──────────────────────────────────────────────┘
```

---

# 41. Suggested repository structure

```text
/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── SECURITY.md
├── docs/
│   ├── architecture.md
│   ├── privacy.md
│   ├── compatibility.md
│   ├── model-support.md
│   └── troubleshooting.md
│
├── app/
│   ├── UI/
│   ├── Settings/
│   ├── MenuBar/
│   └── Diagnostics/
│
├── accessibility/
│   ├── FocusObserver
│   ├── TextReader
│   ├── TextInserter
│   ├── CursorTracker
│   └── AppDetector
│
├── context/
│   ├── FieldContext
│   ├── ScreenContext
│   ├── ClipboardContext
│   └── ContextAssembler
│
├── inference/
│   ├── ModelProvider
│   ├── ModelRegistry
│   ├── ModelDownloader
│   ├── ModelRouter
│   └── Runtime
│
├── personalization/
│   ├── InputCollector
│   ├── ProfileBuilder
│   ├── InstructionManager
│   └── EncryptedStore
│
├── completion/
│   ├── CompletionEngine
│   ├── CandidateFilter
│   ├── WordTokenizer
│   ├── AcceptanceManager
│   └── MidLineCompletion
│
├── shortcuts/
│   └── ShortcutManager
│
├── privacy/
│   ├── PermissionManager
│   ├── SecureInput
│   └── Telemetry
│
└── tests/
    ├── Accessibility
    ├── Completion
    ├── Personalization
    ├── Inference
    ├── Privacy
    └── Integration
```

---

# 42. Implementation phases

## Phase 0 — Architecture

- [ ] Repository setup.
- [ ] Native macOS app.
- [ ] Accessibility permission flow.
- [ ] Menu-bar shell.
- [ ] Settings shell.
- [ ] Logging/diagnostics framework.
- [ ] Model abstraction.
- [ ] Test harness.

## Phase 1 — MVP autocomplete

- [ ] Focus detection.
- [ ] Read active field.
- [ ] Cursor tracking.
- [ ] Local model integration.
- [ ] Basic prompt builder.
- [ ] Inline rendering.
- [ ] Tab next-word acceptance.
- [ ] Full completion acceptance.
- [ ] Escape dismissal.
- [ ] Dynamic prediction.
- [ ] App switching.

## Phase 2 — Production input layer

- [ ] Robust text insertion.
- [ ] Selection handling.
- [ ] Secure-input handling.
- [ ] Compatibility fallbacks.
- [ ] App/domain detection.
- [ ] Force activation.
- [ ] Per-app enable/disable.
- [ ] Global toggle.
- [ ] Shortcut customization.

## Phase 3 — Context

- [ ] Screen-aware context.
- [ ] Clipboard context.
- [ ] Context settings.
- [ ] Context privacy boundaries.

## Phase 4 — Personalization

- [ ] Local encrypted input store.
- [ ] Opt-in collection.
- [ ] Accepted-completion-only mode.
- [ ] Store-all mode.
- [ ] Per-app/domain exclusions.
- [ ] Derived profile.
- [ ] Six-position personalization slider.
- [ ] Global instructions.
- [ ] Per-app instructions.
- [ ] Per-domain instructions.

## Phase 5 — Model platform

- [ ] Model downloader.
- [ ] Model registry.
- [ ] Hardware detection.
- [ ] Model recommendation.
- [ ] User model selection.
- [ ] Model deletion.
- [ ] Model integrity verification.
- [ ] Initial model catalog.
- [ ] Performance benchmarking.

## Phase 6 — Autocorrect / quality

- [ ] Typo detection.
- [ ] Suggested corrections.
- [ ] Correction acceptance.
- [ ] Duplicate suppression.
- [ ] Punctuation handling.
- [ ] Better sentence-boundary handling.
- [ ] Emoji suggestions.
- [ ] Multilingual/code-switching support.

## Phase 7 — Compatibility

- [ ] Safari.
- [ ] Chrome.
- [ ] Firefox.
- [ ] Edge.
- [ ] Brave.
- [ ] Gmail.
- [ ] Apple Mail.
- [ ] Outlook.
- [ ] Word.
- [ ] Pages.
- [ ] Notes.
- [ ] Notion.
- [ ] Obsidian.
- [ ] Slack.
- [ ] Teams.
- [ ] Messages.
- [ ] WhatsApp.
- [ ] Terminal.
- [ ] iTerm.
- [ ] Google Docs.
- [ ] VS Code AI panels.
- [ ] Cursor AI panels.
- [ ] Windsurf AI panels.

## Phase 8 — Labs

- [ ] Mid-line completion.
- [ ] Word Alternatives.
- [ ] Numbered candidate UI.
- [ ] Labs settings.
- [ ] Experimental feature telemetry, if telemetry is retained.

## Phase 9 — Production hardening

- [ ] Performance profiling.
- [ ] Memory profiling.
- [ ] Battery testing.
- [ ] Crash handling.
- [ ] Permission recovery.
- [ ] Accessibility regression suite.
- [ ] Multi-monitor testing.
- [ ] Dark/light mode.
- [ ] Keyboard-layout testing.
- [ ] Secure-input testing.
- [ ] Model corruption/recovery testing.
- [ ] Data deletion verification.
- [ ] Privacy audit.

---

# 43. Acceptance-test matrix

Every feature should have a test.

## Core

- [ ] Type sentence → suggestion appears.
- [ ] Press Tab → exactly next word accepted.
- [ ] Press Tab repeatedly → words accepted sequentially.
- [ ] Accept full completion → full suggestion inserted.
- [ ] Press Esc → suggestion disappears.
- [ ] Continue typing → suggestion updates.

## Context

- [ ] Screen context OFF → no screen capture.
- [ ] Screen context ON → visible surrounding text influences suggestion.
- [ ] Clipboard context OFF → clipboard not accessed.
- [ ] Clipboard context ON → copied text can influence suggestion.
- [ ] Clipboard unchanged after completion insertion.

## Personalization

- [ ] Collection OFF → no input history stored.
- [ ] Collection ON → eligible text stored locally.
- [ ] Accepted-only mode → unaccepted session excluded.
- [ ] Store-all mode → eligible session stored.
- [ ] Short input → excluded.
- [ ] App exclusion → no collection in excluded app.
- [ ] Domain exclusion → no collection on excluded domain.
- [ ] Delete all → source data removed.
- [ ] Delete all → derived profile removed.

## Instructions

- [ ] Global instructions influence suggestion.
- [ ] App instructions influence suggestion.
- [ ] Domain instructions influence suggestion.
- [ ] App instructions supplement global instructions.

## Models

- [ ] Model download.
- [ ] Model cancellation.
- [ ] Model integrity check.
- [ ] Model selection.
- [ ] Model unload.
- [ ] Model reload.
- [ ] Low-memory failure handling.
- [ ] Hardware recommendation.

## Privacy

- [ ] Password field → no suggestion.
- [ ] Screen Recording revoked → core autocomplete remains functional.
- [ ] Accessibility revoked → clear failure state.
- [ ] Clipboard disabled → core autocomplete remains functional.
- [ ] Telemetry disabled → no telemetry sent.
- [ ] Personalization database encrypted.
- [ ] Key stored in Keychain.
- [ ] Logs contain no user text.

---

# 44. Definition of Done for Cotypist Pro parity

The project should not be considered Pro-parity complete until all of the following are true:

- [ ] System-wide inline autocomplete works reliably.
- [ ] Word-by-word Tab acceptance works.
- [ ] Full completion acceptance works.
- [ ] Dynamic prediction works.
- [ ] Full autocorrect works.
- [ ] Emoji suggestions work.
- [ ] Multilingual writing works.
- [ ] Screen-aware context works.
- [ ] Clipboard-aware context works.
- [ ] Personalization works.
- [ ] Six-level personalization control works.
- [ ] Global custom instructions work.
- [ ] Per-app instructions work.
- [ ] Per-domain instructions work.
- [ ] Completion length is configurable.
- [ ] Full target model catalog is supported or documented as blocked by licensing/model availability.
- [ ] Model selection/recommendation works.
- [ ] Mid-line completion works.
- [ ] Word Alternatives works.
- [ ] Keyboard shortcuts are configurable.
- [ ] Global toggle works.
- [ ] Per-app toggle works.
- [ ] Force activation works.
- [ ] Local inference works without cloud inference.
- [ ] Personalization data remains local and encrypted.
- [ ] Data deletion is complete and verifiable.
- [ ] Permission management is robust.
- [ ] Password fields are protected.
- [ ] Diagnostics exist.
- [ ] Statistics exist.
- [ ] Compatibility layer handles supported applications.
- [ ] Unsupported applications fail gracefully.
- [ ] Performance is acceptable for real-time typing.

---

# 45. Feature-priority labels

Use these labels in project management:

### P0 — core product

- Accessibility text-field integration
- Local model inference
- Inline suggestion rendering
- Next-word acceptance
- Full completion acceptance
- Dynamic prediction
- Shortcut system
- Model management
- App enable/disable
- Basic settings
- macOS permissions
- Password-field protection

### P1 — Pro parity

- Full autocorrect
- Screen-aware context
- Clipboard context
- Personalization
- Six-level personalization
- Global instructions
- Per-app instructions
- Per-domain instructions
- Completion length
- Model catalog
- Statistics
- Diagnostics

### P2 — advanced parity

- Mid-line completion
- Word Alternatives
- Advanced compatibility modes
- Browser/domain configuration
- Advanced model recommendation
- Extensive app-specific handling

### P3 — polish / scale

- Multi-monitor refinements
- Additional apps
- Advanced model benchmarking
- Rich analytics
- Advanced personalization controls
- Automatic compatibility heuristics
- Plugin/provider architecture

---

# 46. Non-goals

Unless explicitly added later:

- [ ] Do not build a general-purpose chatbot.
- [ ] Do not replace native IDE code completion.
- [ ] Do not require cloud inference.
- [ ] Do not silently rewrite user text.
- [ ] Do not bypass macOS security permissions.
- [ ] Do not collect user writing by default.
- [ ] Do not upload personalization history.
- [ ] Do not store clipboard contents.
- [ ] Do not store screenshots.
- [ ] Do not build a subscription system before the core open-source product is useful.

---

# 47. Source-of-truth references

Primary sources consulted:

1. Cotypist Pricing:
   https://cotypist.app/pricing

2. Cotypist App Compatibility:
   https://cotypist.app/compatibility

3. Cotypist Personalization:
   https://cotypist.app/help/personalization

4. Cotypist Privacy & Security:
   https://cotypist.app/help/privacy

5. Cotypist Shortcuts:
   https://cotypist.app/help/shortcuts

6. Cotypist Productivity Tips:
   https://cotypist.app/help/tips

7. Cotypist Troubleshooting:
   https://cotypist.app/help/troubleshooting

8. Cotypist Knowledge Base:
   https://cotypist.app/help/

---

# 48. Important research notes

- This specification is based primarily on the **current official Cotypist documentation**, not older launch-era descriptions.
- Cotypist's pricing/features can change; re-check the official pricing and knowledge base before declaring parity complete.
- The official current Pro plan advertises:
  - unlimited completions
  - up to 3 Macs for one person
  - full model catalog
  - strong personalization
  - clipboard awareness
  - per-app instructions
  - Cotypist Labs
  - mid-line completion
  - word alternatives
- Cotypist currently describes local/on-device inference as a core privacy property.
- Optional screen context, clipboard context, and personalization have distinct permission/data controls.
- Compatibility is not literally universal: some applications require setup, some are partial, and some cannot currently be supported.
- The open-source implementation should independently implement the documented behaviors rather than copying proprietary code or UI assets.

---

# 49. Recommended team execution format

For every checklist item, create a ticket using:

```text
Title:
Feature:
Priority:
Dependencies:
Platform:
Owner:
Status:
Acceptance Criteria:
Test Cases:
Performance Requirement:
Privacy/Security Requirement:
Documentation:
```

Suggested statuses:

```text
BACKLOG
DESIGN
IMPLEMENTING
CODE REVIEW
TESTING
BLOCKED
DONE
```

Every `DONE` item should include:

- [ ] Unit test
- [ ] Integration test where applicable
- [ ] Manual Mac test
- [ ] Performance measurement where applicable
- [ ] Privacy/security review where applicable
- [ ] Documentation
