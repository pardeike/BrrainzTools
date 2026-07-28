# RegionShot

RegionShot is a small macOS command line tool for screenshots, window capture,
menu capture, UI inspection, and Accessibility-driven UI actions.

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

Download `RegionShot-v1.1.2-macos.dmg` from the GitHub release, open it, and run
`Install RegionShot.command`.

The installer copies `regionshot` to `~/Scripts/regionshot`.

If your shell does not find it, add `~/Scripts` to your PATH:

```bash
echo 'export PATH="$HOME/Scripts:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Check the install:

```bash
command -v regionshot
regionshot --version
regionshot --help
```

## Permissions

macOS may ask for Screen Recording permission when RegionShot captures the
screen or lists windows.

macOS may ask for Accessibility permission when RegionShot inspects UI elements,
presses buttons, or works with menu-bar items.

The permission is granted to the app that starts `regionshot`, usually Terminal,
iTerm, or Codex. After granting permission in System Settings, run the command
again.

## Common Commands

```bash
regionshot capture 0 0 800 600
regionshot displays
regionshot capture --display DISPLAY_ID --output ~/Desktop/display.png
regionshot apps Terminal
regionshot ax --app Terminal windows
regionshot ax --app Terminal tree --interactive --flat
regionshot ax --app Terminal set-value "text" --path 0.3.1
regionshot ax --app Terminal key cmd+s
regionshot ax --app Terminal raise --window-index 0
regionshot launch com.apple.TextEdit --wait-window
regionshot quit --app TextEdit
regionshot windows --app Terminal --visible
regionshot capture --app Terminal --visible-window --output ~/Desktop/terminal.png
regionshot capture --app Terminal --with-ocr --max-dimension 1200
regionshot menu --app Drafty list
regionshot menu --app Drafty press --menu-bar-index 0
regionshot menu --app Drafty press-item "Quick Tasks" --menu-bar-index 0
regionshot ascii ~/Desktop/terminal.png --ocr-only
regionshot doctor
regionshot clipboard
```

Running `regionshot` without arguments prints a short command summary. Existing
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
regionshot --help
```

For a repo-local prototype binary that does not touch `~/Scripts/regionshot`,
run:

```bash
./Scripts/build-private.sh
```

That writes `.build/private-bin/regionshot-private`.

## Agent Support

The install scripts also copy the bundled agent support files. When those files
are present, `regionshot` keeps the RegionShot skill and managed instruction
block up to date for Codex (`~/.codex/skills/regionshot` and
`~/.codex/AGENTS.md`) and Claude Code (`~/.claude/skills/regionshot` and
`~/.claude/CLAUDE.md`).

If the support files are missing, the binary skips this step and still works.

## Maintainers

Release packaging and notarization are documented in
[docs/release.md](docs/release.md).
