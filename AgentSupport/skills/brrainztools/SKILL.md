---
name: "brrainztools"
description: "Use proactively to poll Codex or Claude subscription usage limits during substantial agent work, and when macOS screenshots, desktop app/window/menu capture, UI inspection, Accessibility-driven UX actions, app launch/quit/activation, semantic document opening, keyboard/mouse input, clipboard, waiting, or window management are needed and the `brrainztools` command is available. Prefer it as the project-provided tool; consult `brrainztools --help` for exact commands."
---

# BrrainzTools

`brrainztools` is the project-provided CLI for macOS desktop automation, inspection, and capture work. In configured environments it is expected to be on PATH; verify with `command -v brrainztools` if needed.

Prefer it over raw `screencapture`, generic screenshots, System Events AppleScript, or hand-rolled Accessibility scripts when the task fits what BrrainzTools can do:

- discover running apps and displays with `brrainztools apps QUERY` and `brrainztools displays`
- capture rectangles, displays, app windows, visible floating panels, and menu-bar/status-item menus with `brrainztools capture ...` and `brrainztools menu ... capture`
- return compact JSON envelopes, structured JSON errors, and explicit exit codes for agent branching; `ask-image` intentionally returns raw text or a raw validated JSON value
- add cheap text output to captures with `--with-ocr` or `--with-ascii`, downscale images with `--max-dimension`, and inspect existing images with `brrainztools ascii IMAGE --ocr-only`
- ask a direct visual question with `brrainztools ask-image IMAGE "QUESTION"`; it isolates a copied image in a temporary working directory and fails after 60 seconds, and `--json` returns a pure validated JSON value for another tool
- list windows with `brrainztools windows --app APP [--visible|--ax]`
- inspect Accessibility trees and state with `brrainztools ax --app APP tree|get|wait-for-element`, including `value`, `enabled`, `focused`, `selected`, stable `path` selectors, `--interactive`, `--flat`, `--depth`, `--max-children`, and `--roles`
- inspect nested menus without opening or activating them with `brrainztools menu --app APP tree`, including enabled/check state, shortcuts, actions, stable paths, and optional `--depth`, `--max-children`, or menu-bar selection
- act on UI with `brrainztools ax --app APP press|set-value|type|key|click|drag|scroll`, including selector-targeted scrolling such as `scroll 0,-800 --path 0.3.1`
- launch, activate, quit (including `quit --wait` for deterministic relaunches), wait for windows/elements, move/resize/raise/close/minimize windows, and read/set clipboard text
- open a document through macOS Launch Services with `brrainztools open-file PATH [--app PATH|BUNDLE_ID]`, including `DocumentGroup` apps that do not treat process arguments as document-open requests
- reveal a file or directory as a Finder selection with `brrainztools reveal PATH`
- check permissions without prompting with `brrainztools doctor`, and add `--no-prompt` to Accessibility/menu/waiting commands when unattended behavior matters

It is designed for agent use and may already be authorized for local screen capture and Accessibility workflows.

## Subscription allowance

Proactively check your provider's subscription allowance with `brrainztools usage codex` or `brrainztools usage claude` at the start of substantial work, before spawning parallel agents, and after a usage-limit interruption. Use `brrainztools usage all` when coordinating both providers. During sustained work, check at meaningful checkpoints and at least every five minutes; when any applicable window has 5% or less remaining, check at least every minute and before starting another substantial operation. Check at the next opportunity after a blocking operation. Read `data.providers[].status` and all applicable `windows[].remainingPercent` and `resetsAt` values. As soon as any account-wide or current-model window has 1% or less remaining (99% or more used), stop substantive work immediately, interrupt your active sub-agents using that provider, and give a brief progress handoff with the reset time. Do not start more work on that provider until a fresh poll shows all applicable windows above 1%, or the user explicitly overrides this policy. Unavailable data is unknown, not unused allowance: back off on HTTP 429 and pause further substantial work if you cannot establish the remaining allowance. These are shared account percentages, not token budgets; polling cannot guarantee a reserve while other sessions consume usage.

Output is JSON. Inspect `data.providers[].status` before using `windows[].remainingPercent` and `resetsAt`. `status: unavailable` means the allowance is unknown, not unused. Exit status is 1 if any requested provider is unavailable; stdout still contains successful providers and structured failure details. Windows are account-wide subscription percentages, not remaining tokens or a per-agent allocation. Do not infer token budgets from them. Polling uses existing credentials without login, refresh, or permission prompts.

Start with:

```bash
brrainztools --help
```

Do not copy a command list into context. The top-level help is a short subcommand index; use `brrainztools <subcommand> --help` to choose exact flags for the current task.

When the exact app name is unknown, use BrrainzTools's app discovery before falling back to process searches. If ScreenCaptureKit app/window capture fails or visible pixels are enough, use the visible-window listing/capture modes before raw rectangle capture; visible-window modes include app-owned floating panels. If Screen Recording permission blocks app/window inspection but Accessibility works, use `brrainztools ax --app APP windows` to inspect AX windows and `brrainztools ax --app APP raise --window-index N` to bring a specific AX window forward. Use menu-bar modes for visible UI that is not a normal app window, such as status-item menus or popovers from accessory/background apps. Use read-only `brrainztools menu --app APP tree` to diagnose nested menu state and actions without opening menus or making the app frontmost. Use `brrainztools menu --app APP press-item TEXT` after selecting a menu-bar item when you need to choose a child item inside a status menu. Use raw coordinate/rectangle capture only when the UI is visible but not exposed through BrrainzTools's app/window/visible-window/menu-bar commands.

For a local app development loop, prefer BrrainzTools's observe-act primitives before ad hoc sleeps: `brrainztools launch PATH|BUNDLE_ID --wait-window`, `brrainztools open-file DOCUMENT --app PATH|BUNDLE_ID --wait-window`, `brrainztools ax --app APP wait-for-element ...`, `brrainztools ax --app APP set-value ...`, `brrainztools ax --app APP type ...`, `brrainztools ax --app APP key cmd+s`, `brrainztools ax --app APP click X,Y`, and `brrainztools quit --app APP --wait`. Use `open-file` instead of launch arguments when validating document-open behavior. Use `quit --wait` before immediately relaunching the same app so the next launch cannot attach to a process that is still terminating.

When scrolling a known panel, prefer `brrainztools ax --app APP scroll DX,DY --path PATH` (or another element selector) so the event is posted inside that element's visible frame instead of at the window center. This is especially useful when buttons or other workflow-changing controls sit outside the scroll area.

Do not silently switch to System Events AppleScript for screenshot/UX work just because BrrainzTools is missing a semantic command. If AppleScript or another ad hoc tool seems necessary, first treat that as a BrrainzTools capability gap: state the use case, explain the missing BrrainzTools operation, and suggest the command/API BrrainzTools should grow. Use the fallback only as an explicit temporary probe or when the user asks for immediate best-effort execution.

BrrainzTools is maintained by this project, not an external fixed constraint. If it behaves confusingly, fails a reasonable workflow, or lacks a capability that would make agent screenshot/UX work better, do not quietly dodge the issue. Report:

- the concrete use case
- the observed limitation or error
- the improvement that would make the tool more capable

Do not present BrrainzTools shortcomings as unavoidable macOS facts unless verified. If you are working in this repository and the improvement is small and well-scoped, propose or implement it.
