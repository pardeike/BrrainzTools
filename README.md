# BrrainzTools

BrrainzTools is a macOS command line toolbox for desktop automation:
screenshots, window capture, menu capture, UI inspection, Accessibility-driven
UI actions, input synthesis, and app lifecycle control.

It is built for agents and scripts. It helps them ask macOS for the right
thing instead of guessing screen rectangles:

- find a running app
- list app windows
- capture a window or a visible floating panel
- list, raise, move, resize, close, and minimize accessibility windows
- open and capture a menu-bar item
- read accessibility element state and press/set/type/key/click/drag/scroll UI
- launch, activate, quit, and wait for local apps
- read or set clipboard text
- convert a screenshot to a compact text view

## Install

Download `BrrainzTools-v2.0.0-macos.dmg` from the GitHub release, open it, and run
`Install BrrainzTools.command`.

The installer copies `brrainztools` to `~/Scripts/brrainztools`.

If your shell does not find it, add `~/Scripts` to your PATH:

```bash
echo 'export PATH="$HOME/Scripts:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Check the install:

```bash
command -v brrainztools
brrainztools --version
brrainztools --help
```

## Permissions

macOS may ask for Screen Recording permission when BrrainzTools captures the
screen or lists windows.

macOS may ask for Accessibility permission when BrrainzTools inspects UI elements,
presses buttons, or works with menu-bar items.

The permission is granted to the app that starts `brrainztools`, usually Terminal,
iTerm, or Codex. After granting permission in System Settings, run the command
again.

## Common Commands

```bash
brrainztools capture 0 0 800 600
brrainztools displays
brrainztools capture --display DISPLAY_ID --output ~/Desktop/display.png
brrainztools apps Terminal
brrainztools ax --app Terminal windows
brrainztools ax --app Terminal tree --interactive --flat
brrainztools ax --app Terminal set-value "text" --path 0.3.1
brrainztools ax --app Terminal scroll 0,-800 --role AXScrollArea
brrainztools ax --app Terminal key cmd+s
brrainztools ax --app Terminal raise --window-index 0
brrainztools launch com.apple.TextEdit --wait-window
brrainztools quit --app TextEdit
brrainztools windows --app Terminal --visible
brrainztools capture --app Terminal --visible-window --output ~/Desktop/terminal.png
brrainztools capture --app Terminal --with-ocr --max-dimension 1200
brrainztools menu --app Drafty list
brrainztools menu --app Drafty press --menu-bar-index 0
brrainztools menu --app Drafty press-item "Quick Tasks" --menu-bar-index 0
brrainztools ascii ~/Desktop/terminal.png --ocr-only
brrainztools doctor
brrainztools clipboard
```

Running `brrainztools` without arguments prints a short command summary. Existing
flag-first commands remain accepted for compatibility.

For the full command guide, see [docs/usage.md](docs/usage.md).

## Build From Source

Requirements:

- macOS 27 or newer
- Swift tools 6.4 or newer to build

The Swift tools requirement is build-time only. The binary still targets macOS
27 or newer.

Build and install:

```bash
./Scripts/install.sh
brrainztools --help
```

For a repo-local prototype binary that does not touch `~/Scripts/brrainztools`,
run:

```bash
./Scripts/build-private.sh
```

That writes `.build/private-bin/brrainztools-private`.

## Agent Support

The install scripts also copy the bundled agent support files. When those files
are present, `brrainztools` keeps the BrrainzTools skill and managed instruction
block up to date for Codex (`~/.codex/skills/brrainztools` and
`~/.codex/AGENTS.md`) and Claude Code (`~/.claude/skills/brrainztools` and
`~/.claude/CLAUDE.md`).

If the support files are missing, the binary skips this step and still works.

## Maintainers

Release packaging and notarization are documented in
[docs/release.md](docs/release.md).
