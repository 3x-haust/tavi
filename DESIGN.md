# Tavi

## Intent

One writing surface, not two language modes. No language badge beside the cursor.
The name is provisional; display names live in bundle metadata and UI copy.

## Research and constraints

- The user approved a native InputMethodKit input source after testing the
  accessibility helper's limits in Ghostty. Preserve existing input sources
  and OS shortcuts; installation and selection are explicit actions.
- Apple-inspired design reference: system typography, neutral surfaces, blue
  reserved for action, and restrained depth. This is a native Mac utility,
  not a marketing website or an imitation of Apple's branding.
- AppKit is the rendering surface. No SwiftUI, Electron or web view runtime.
  Web-only screenshot research,
  React tooling, Lighthouse and generated web concepts do not apply.
- Native host editors own their glyph rendering. Tavi cannot promise iPhone
  text morphing inside arbitrary applications. Never animate or delay the
  actual typing path. No confirmation overlays or learning/correction toasts.

## Tokens

Use system semantic colors and fonts for light/dark appearance.
Window canvas: NSColor.windowBackgroundColor; raised surface:
NSColor.controlBackgroundColor; text: primary/secondary. Accent: blue.
Spacing: 4, 8, 12, 16, 24, 32. Corners: 8 controls, 16 panels.
Title 32 semibold; section 17 semibold; body 14; metadata 12.

## Resource and latency contract

The user explicitly prioritizes an extremely small, low-memory, fast utility.
These are release targets, not measured claims:

- Precomputed statistical model plus vocabulary tables: at most 2 MiB.
- Warm engine decision p95 <= 1 ms; measure p99 and maximum too.
- No idle polling, periodic input-source checks, network inference or runtime
  corpus training. Subscribe to source, focus, selection and input events.
- The only network access is the update check: the GitHub latest-release API, at
  input-method launch and about daily through NSBackgroundActivityScheduler.
  A newer release is applied with no window, banner or prompt; an already added
  Tavi keeps its selection state.
- Load statistical tables once, share them across sessions, bound token length
  and dictionary cache size. Never rebuild a lexicon on each keystroke.
- Create the preferences window only when opened. No resident browser or
  graphics loop. The menu bar item is static while idle.
- Measure process resident memory and CPU separately with settings closed
  and open. Record model bytes, application bytes, cold-start time, warm engine
  latency and end-to-end editor replacement latency; do not substitute one
  for another or call a target a result.
- Use binary tables generated offline from attributed public datasets, not
  handwritten vocabulary as the main classifier.

## Surfaces and primitives

- One 760 x 600 resizable settings window, minimum 640 x 540.
- First run: until Tavi is in the user's input sources the window shows only a
  setup page — three step labels, one button that prepares Tavi and opens
  Keyboard Settings, and the Keyboard Settings recording playing inline.
  Adding Tavi there switches the window to the sidebar layout on the tutorial.
  No separate guide window.
- Sidebar: Overview, My words, Settings. No dashboard statistics invented
  from session contents.
- Overview: a real inline native text editor. First use is a short interactive
  tutorial: type a mixed token, correct with the user's input-source switch key,
  and observe automatic learning. Gate progress on actual input events.
  Include skip and replay; completion persists locally.
- Do not show static explanatory paragraphs, the sidebar tagline, or the
  "내 맥 안에서만" prose panel the user explicitly removed. Keep labels and
  contextual exercise prompts only.
- My words: raw-key sequence, exact preferred spelling, confirmation count,
  add/update/delete controls. Case is deliberate, never guessed.
- Settings: automatic conversion on/off, learning on/off, current input-source
  status, the system keyboard settings link and input-method removal.
  No Accessibility permission flow.
- No floating panels, success banners, learning badges or correction toasts.
  Ordinary typing should feel like the host's own native input.
- In-app editing uses native marked text and preserves standard AppKit
  select-all, copy, cut, paste, undo/redo and navigation. It is available without
  cross-app permission. External editors receive native IMK marked text.

## Interaction

Tavi owns only its active marked composition. The user's own input-source switch
key (whatever macOS is set to) toggles the composing word between Korean and its
keys; there is no separate correction shortcut.
Space confirms with a trailing space; Enter confirms an active composition
without also submitting it. With no composition, Enter passes to the host.
Escape restores literal keys; navigation and focus changes do not teach.
Backspace recomposes raw keys until empty, then passes through. Undo and paste
remain the host editor's behavior; pasted content is not reinterpreted or learned.

Use restrained native transitions only inside the explicitly opened tutorial.
Respect macOS Reduce Motion; use opacity-only or immediate updates.
No bouncing letters, typewriter delays, auto-pulsing or toast.

## Accessibility

Use native focus rings, buttons, lists and text entry. Label icon-only actions.
Support keyboard navigation, Dynamic Type/system text sizes where available,
VoiceOver labels, dark appearance and Reduce Motion. Never require color
alone to distinguish a correction.

## Known limits to report

- Same keys can form two valid words. Local lexical/structural scoring is
  fallible, with explicit correction and learned vocabulary as the escape hatch.
- Host input-method behavior varies; verify actual apps rather than claiming
  every editor supports every composition operation.
- One-time installation and explicit selection of the Tavi input source are needed.
- The app does not change or hide the system's own input-source indicator.
- No event tap or cross-application accessibility observer is installed.
