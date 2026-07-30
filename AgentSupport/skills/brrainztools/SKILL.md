---
name: "brrainztools"
description: "Use when macOS screenshots, desktop app/window/menu capture, UI inspection, Accessibility-driven UX actions, app launch/quit/activation, keyboard/mouse input, clipboard, waiting, or window management are needed and the `brrainztools` command is available. Prefer it as the project-provided tool; consult `brrainztools --help` for exact commands."
---

# BrrainzTools

`brrainztools` is the project-provided CLI for macOS desktop automation, inspection, and capture work. In configured environments it is expected to be on PATH; verify with `command -v brrainztools` if needed.

Prefer it over raw `screencapture`, generic screenshots, System Events AppleScript, or hand-rolled Accessibility scripts when the task fits what BrrainzTools can do:

- discover running apps and displays with `brrainztools apps QUERY` and `brrainztools displays`
- capture rectangles, displays, app windows, visible floating panels, and menu-bar/status-item menus with `brrainztools capture ...` and `brrainztools menu ... capture`
- return compact JSON envelopes, structured JSON errors, and explicit exit codes for agent branching
- add cheap text output to captures with `--with-ocr` or `--with-ascii`, downscale images with `--max-dimension`, and inspect existing images with `brrainztools ascii IMAGE --ocr-only`
- list windows with `brrainztools windows --app APP [--visible|--ax]`
- inspect Accessibility trees and state with `brrainztools ax --app APP tree|get|wait-for-element`, including `value`, `enabled`, `focused`, `selected`, stable `path` selectors, `--interactive`, `--flat`, `--depth`, `--max-children`, and `--roles`
- act on UI with `brrainztools ax --app APP press|set-value|type|key|click|drag|scroll`, including selector-targeted scrolling such as `scroll 0,-800 --path 0.3.1`
- launch, activate, quit (including `quit --wait` for deterministic relaunches), wait for windows/elements, move/resize/raise/close/minimize windows, and read/set clipboard text
- reveal a file or directory as a Finder selection with `brrainztools reveal PATH`
- check permissions without prompting with `brrainztools doctor`, and add `--no-prompt` to Accessibility/menu/waiting commands when unattended behavior matters

It is designed for agent use and may already be authorized for local screen capture and Accessibility workflows.

Start with:

```bash
brrainztools --help
```

Do not copy a command list into context. The top-level help is a short subcommand index; use `brrainztools <subcommand> --help` to choose exact flags for the current task.

When the exact app name is unknown, use BrrainzTools's app discovery before falling back to process searches. If ScreenCaptureKit app/window capture fails or visible pixels are enough, use the visible-window listing/capture modes before raw rectangle capture; visible-window modes include app-owned floating panels. If Screen Recording permission blocks app/window inspection but Accessibility works, use `brrainztools ax --app APP windows` to inspect AX windows and `brrainztools ax --app APP raise --window-index N` to bring a specific AX window forward. Use menu-bar modes for visible UI that is not a normal app window, such as status-item menus or popovers from accessory/background apps. Use `brrainztools menu --app APP press-item TEXT` after selecting a menu-bar item when you need to choose a child item inside a status menu. Use raw coordinate/rectangle capture only when the UI is visible but not exposed through BrrainzTools's app/window/visible-window/menu-bar commands.

For a local app development loop, prefer BrrainzTools's observe-act primitives before ad hoc sleeps: `brrainztools launch PATH|BUNDLE_ID --wait-window`, `brrainztools ax --app APP wait-for-element ...`, `brrainztools ax --app APP set-value ...`, `brrainztools ax --app APP type ...`, `brrainztools ax --app APP key cmd+s`, `brrainztools ax --app APP click X,Y`, and `brrainztools quit --app APP --wait`. Use `quit --wait` before immediately relaunching the same app so the next launch cannot attach to a process that is still terminating.

When scrolling a known panel, prefer `brrainztools ax --app APP scroll DX,DY --path PATH` (or another element selector) so the event is posted inside that element's visible frame instead of at the window center. This is especially useful when buttons or other workflow-changing controls sit outside the scroll area.

Do not silently switch to System Events AppleScript for screenshot/UX work just because BrrainzTools is missing a semantic command. If AppleScript or another ad hoc tool seems necessary, first treat that as a BrrainzTools capability gap: state the use case, explain the missing BrrainzTools operation, and suggest the command/API BrrainzTools should grow. Use the fallback only as an explicit temporary probe or when the user asks for immediate best-effort execution.

BrrainzTools is maintained by this project, not an external fixed constraint. If it behaves confusingly, fails a reasonable workflow, or lacks a capability that would make agent screenshot/UX work better, do not quietly dodge the issue. Report:

- the concrete use case
- the observed limitation or error
- the improvement that would make the tool more capable

Do not present BrrainzTools shortcomings as unavoidable macOS facts unless verified. If you are working in this repository and the improvement is small and well-scoped, propose or implement it.
