# BrrainzTools Command Guide

This page lists the main command forms. Run `brrainztools --help` for the
subcommand index, or `brrainztools <subcommand> --help` for focused help from the
installed binary. Existing flag-first forms still work as compatibility aliases.

## Subcommands

```bash
brrainztools capture 120 240 800 600
brrainztools apps Terminal
brrainztools windows --app Terminal --visible
brrainztools ax --app Terminal tree --depth 2
brrainztools menu --app Drafty list
brrainztools ascii /tmp/screenshot.png --ocr-only
brrainztools displays
brrainztools reveal ./README.md
```

## Output

Commands return compact JSON envelopes on stdout by default. Successful
responses include `ok`, `mode`, `version`, and one mode-specific field:
`data` for structured inspection/action results, `output` for a written capture
file, or `report` for ASCII report text. Capture commands can include
`--with-ascii` to add `report`, or `--with-ocr` to add OCR-only `data`, for the
same written image. Errors are compact JSON envelopes on stderr with
`error.kind`, `error.message`, and `error.exitCode`.

Add `--raw` to capture, menu-capture, or ASCII commands when a script needs the
legacy bare path or report output. `--raw` cannot be combined with
`--with-ascii` or `--with-ocr`.

## Version

```bash
brrainztools --version
```

## Doctor

```bash
brrainztools doctor
```

`doctor` returns non-prompting Screen Recording and Accessibility permission
status, the BrrainzTools version, and the parent host process that macOS
permissions apply to.

## Clipboard

```bash
brrainztools clipboard
brrainztools clipboard --set "copied text"
```

`clipboard` reads or sets plain text on the general pasteboard and returns the
clipboard payload as `data`.

## Reveal In Finder

```bash
brrainztools reveal PATH
```

`reveal` resolves relative paths and `~`, opens Finder, and selects the file or
directory at the resolved path. The command returns that absolute path as
`data.path`. A missing target exits with code 66 and a `pathNotFound` error.

## App Lifecycle

```bash
brrainztools activate --app "System Settings"
brrainztools activate --pid 12345
brrainztools launch com.apple.TextEdit --wait-window --timeout 10
brrainztools launch .build/debug/MyDebugApp --wait-window --args --fixture smoke
brrainztools quit --app "My Debug App" --wait
brrainztools quit --pid 12345 --force --wait --timeout 10
```

`activate` resolves a running app by name, bundle id, or process id, asks macOS
to activate it, and returns data describing the app and whether macOS accepted
the activation request.

`launch` starts an app bundle path, bundle id, or executable path. Add
`--wait-window` to wait until the launched process exposes its first accessibility
window. Add `--no-prompt` with `--wait-window` to fail instead of showing the
system Accessibility permission prompt. Arguments after `--args` are passed to
the launched app unchanged.

`quit` resolves a running app and asks it to terminate. Add `--force` to call
force-terminate instead. Add `--wait` to return only after the process terminates;
the default timeout is 5 seconds and can be changed with `--timeout SECONDS`.
Without `--wait`, the command remains non-blocking. The response reports whether
macOS accepted the request, whether waiting was requested, and whether termination
had been observed when the command returned. A wait timeout exits with code 75
and an `operationTimedOut` error.

## Displays

```bash
brrainztools --list-displays
brrainztools --display DISPLAY_ID --output ~/Desktop/display.png
brrainztools --all-displays --format jpeg --quality 0.7 --max-dimension 1600
```

`--list-displays` returns active displays, including the display id, point
frame, pixel size, scale, and whether the display is the main display.

Use `--display DISPLAY_ID` to capture one active display by id, or
`--all-displays` to capture the union of all active display frames. These forms
support the same capture output options as rectangle capture, including
`--output`, `--format`, `--quality`, `--max-dimension`, `--with-ascii`,
`--with-ocr`, and `--raw`.

## Basic Capture

```bash
brrainztools
brrainztools 120 240 800 600
brrainztools --x 120 --y 240 --width 800 --height 600
brrainztools 120 240 800 600 --output ~/Desktop/region.png
brrainztools 120 240 800 600 --raw
brrainztools 120 240 800 600 --with-ascii
brrainztools 120 240 800 600 --with-ocr
brrainztools 120 240 800 600 --format jpeg --quality 0.7 --max-dimension 1200
```

Without `--app`, rectangle capture uses ScreenCaptureKit display capture for
the visible pixels in that screen region.

By default, capture commands create a temporary file and return its path as
`output`. Add `--raw` to print only the path.

Use `--with-ascii` when the next step is text inspection; BrrainzTools captures
the image, runs the existing ASCII/OCR renderer on that file, and returns both
`output` and `report` in one envelope. Use `--with-ocr` when only OCR blocks are
needed; it returns `output` plus OCR `data` without rendering the ASCII canvas.
The usual ASCII sizing and language options can be used with `--with-ascii`;
`--with-ocr` accepts `--ascii-language`.

Capture output defaults to PNG. Use `--format jpeg` for smaller image files,
`--quality 0...1` to tune JPEG compression, and `--max-dimension N` to downscale
the longest image edge before writing. Temporary output paths use `.png` or
`.jpg` to match the selected format; explicit `--output` paths are left exactly
as provided.

## Find Apps

```bash
brrainztools --find-app Terminal
brrainztools --find-app RimWorld
```

Use this when you do not know the exact running app name. The output includes
matching app names, process ids, bundle identifiers, paths, activation policy,
and visible-window counts.

`--app` accepts an app name, a bundle identifier, or a process id. Pure integer
values keep the historical behavior and are treated as process ids. Use
`--pid` for explicit process-id selection, or `--app-name` to force name/bundle
matching when an app name is numeric:

```bash
brrainztools --app "System Settings"
brrainztools --app com.apple.systempreferences
brrainztools --app 12345
brrainztools --pid 12345
brrainztools --app-name "2048"
```

## Windows

```bash
brrainztools --app "System Settings" --list-windows
brrainztools --app "System Settings" --frontmost-window
brrainztools --app "System Settings" --window-index 0
brrainztools --app "System Settings" --window-name "<window title>"
brrainztools --app "System Settings" --frontmost-window --window-crop 40,80,300,160
```

Window indices are frontmost first within the selected app.

`--window-crop x,y,width,height` is relative to the selected window's top-left
corner in points.

## Visible Windows

```bash
brrainztools --app "RimWorld" --list-visible-windows
brrainztools --app "RimWorld" --visible-window
brrainztools --app "Drafty" --visible-window --output ~/Desktop/drafty-panel.png
```

`--list-visible-windows` and `--visible-window` use the current visible window
stack instead of ScreenCaptureKit's app/window catalog. Visible-window capture
then captures that screen rectangle with ScreenCaptureKit display capture. This
is useful when app/window capture is unavailable, times out, or when visible
pixels are exactly what you need.

Visible-window modes include normal windows and app-owned floating panels. They
capture what is visible in that rectangle, so windows in front of the target are
included.

## App-Filtered Rectangles

```bash
brrainztools 120 240 800 600 --app "System Settings"
brrainztools 120 240 800 600 --app 12345
```

In app rectangle mode, the output contains only the selected app's windows
inside the rectangle, even if other apps are visually in front.

## Menu-Bar Items

```bash
brrainztools --app "Drafty" --list-menu-bar-items
brrainztools --app "Drafty" --capture-menu
brrainztools --app "Drafty" --menu-bar-index 0 --capture-menu
brrainztools --app "Drafty" --menu-bar-index 0 --press-menu-item "Quick Tasks"
brrainztools --app "Drafty" --menu-bar-item "Drafty" --press-menu-item "Preferences..."
```

Menu-bar modes work with accessibility menu-bar items exposed by the selected
app. They are useful for status-item apps and menu-like popovers.

If you omit `--menu-bar-index` or `--menu-bar-item`, BrrainzTools selects the
single status-item entry when exactly one is available. If there are multiple
candidates, the command fails and prints suggestions.

`--press-menu-item TEXT` opens the selected menu-bar item, then presses a child
menu item by title, description, or identifier.

## Accessibility Inspection And Actions

```bash
brrainztools --app "System Settings" --list-elements
brrainztools --app "System Settings" --list-elements --depth 2 --max-children 12
brrainztools --app "System Settings" --list-elements --roles AXButton,AXTextField --interactive --flat
brrainztools --app "System Settings" --wait-for-window "Network" --timeout 10
brrainztools --app "System Settings" --get --path 0.3.1
brrainztools --app "System Settings" --get --role AXTextField --title Name
brrainztools --app "System Settings" --wait-for-element --role AXButton --title Done --timeout 10
brrainztools --app "System Settings" --set-value "Andreas" --path 0.3.1
brrainztools --app "System Settings" --set-value "Andreas" --role AXTextField --title Name
brrainztools --app "System Settings" --type "typed text"
brrainztools --app "System Settings" --key "cmd+s"
brrainztools --app "System Settings" --click 24,24
brrainztools --app "System Settings" --click 24,24 --right
brrainztools --app "System Settings" --drag 24,24,160,24
brrainztools --app "System Settings" --scroll 0,-800
brrainztools --app "System Settings" --scroll 0,-800 --path 0.3.1
brrainztools --app "System Settings" --scroll 0,-800 --role AXScrollArea
brrainztools --app "System Settings" --press --role AXButton --title Done
brrainztools --app "System Settings" --press-at 14,14
brrainztools --app "System Settings" --element-at 14,14
brrainztools --app "System Settings" --window-name "<window title>" --press --role AXButton --title Done
```

`--list-elements` prints a bounded JSON accessibility tree for the selected
window. If you omit a window selector, BrrainzTools uses the focused window, then
the main window, then the first accessibility window.
Element JSON includes structural fields plus readable state when macOS exposes
it: `path`, `value`, `enabled`, `focused`, and `selected`.
Use `--depth N` and `--max-children N` with `--list-elements` to reduce or
expand the tree. Use `--roles ROLE[,ROLE...]` to keep only matching roles and
their ancestors, `--interactive` to keep elements with actions and their
ancestors, and `--flat` to return a flat `elements` array instead of a nested
tree. Empty `actions` arrays are omitted from element JSON.
Use `--path PATH` with `--get`, `--wait-for-element`, `--set-value`, `--scroll`,
or `--press` to target a listed element directly. Paths cannot be combined with
fuzzy selector fields such as `--role` or `--title`.

`--wait-for-window TITLE` polls the app's accessibility windows until one title
matches, then returns that window as JSON. Use `--timeout SECONDS` to adjust the
wait.

`--get` finds one accessibility element using selector fields and returns its
full JSON attributes without performing an action. It uses the same selector
fields and matching rules as `--press`.

`--wait-for-element` polls until exactly one matching accessibility element is
available, then returns it using the same JSON shape as `--get`. Use
`--timeout SECONDS` to adjust the wait.

`--set-value TEXT` finds one accessibility element using selector fields, writes
the element's `AXValue`, and returns the updated element. Empty text is valid and
can be used to clear text fields that support `AXValue` writes.

`--type TEXT` activates the app and posts Unicode keyboard input to its process.
`--key CHORD` posts a shortcut or named key such as `cmd+s`, `cmd+shift+s`,
`escape`, or `return`.

`--click X,Y`, `--drag X1,Y1,X2,Y2`, and `--scroll DX,DY` activate the app,
raise the selected window when supported, and post CGEvent mouse input. Click and
drag coordinates are window-relative points. Scroll accepts signed
horizontal/vertical deltas. Without an element selector, it is posted at the
selected window's center. With `--path`, `--role`, `--title`, or another element
selector, it is posted at the center of the matched element's visible frame and
the JSON response includes the selector and matched element. A frame-less or
fully off-window match fails without posting input.

`--press` finds a pressable accessibility element using selector fields such as
`--role`, `--subrole`, `--title`, `--identifier`, and `--description`, then
performs `AXPress`.

For `--title`, `--identifier`, and `--description`, matching prefers exact
case-insensitive matches. It only falls back to substring matching when no exact
match exists.

If a selector is ambiguous, the command fails and prints a short candidate list
instead of pressing an arbitrary element.

`--press-at x,y` is a fallback for weak accessibility trees. It resolves the
deepest visible element at a window-relative point, walks up to the nearest
ancestor that supports `AXPress`, and presses that element.

`--element-at x,y` returns data for the visible accessibility element at a
window-relative point plus its ancestor chain.

## ASCII And OCR View

```bash
brrainztools --ascii /tmp/screenshot.png
brrainztools --ascii /tmp/screenshot.png --ascii-width 160 --ascii-max-height 80
brrainztools --ascii /tmp/screenshot.png --ascii-style tone --ascii-width 100 --ascii-max-height 60
brrainztools --ascii /tmp/screenshot.png --ascii-language de-DE,sv-SE
brrainztools --ascii /tmp/screenshot.png --ocr-only
brrainztools --ascii /tmp/screenshot.png --raw
```

`--ascii IMAGE` reads an existing screenshot or image file and returns a compact
text inspection report as `report`. Add `--raw` to print only the report text.

The default `layout` style renders sparse borders, dividers, and scrollbars,
then overlays Vision OCR text at approximate screenshot positions. The OCR
block list is printed below the layout map with pixel bounds and confidence.
By default BrrainzTools asks Vision to detect text languages automatically. Use
`--ascii-language CODE[,CODE...]` to pass explicit OCR language codes instead.

Useful options:

- `--ascii-width N`, range `16...240`
- `--ascii-max-height N`, range `8...240`
- `--ascii-style tone`
- `--ascii-language CODE[,CODE...]`
- `--ascii-invert`
- `--ascii-no-ocr`
- `--ocr-only`

`--ocr-only` skips ASCII rendering and returns OCR blocks with pixel bounds as
`data`, which is cheaper when text is the only needed signal.

## Timeouts

ScreenCaptureKit app/window operations time out after five seconds by default.

Use `--timeout SECONDS` when the system is slow:

```bash
brrainztools --app "System Settings" --frontmost-window --timeout 10
```

If app/window capture times out, try visible-window capture:

```bash
brrainztools --app "System Settings" --list-visible-windows
brrainztools --app "System Settings" --visible-window --output ~/Desktop/window.png
```

## Accessibility Windows

```bash
brrainztools --app "Terminal" --list-accessibility-windows
brrainztools --app "Terminal" --window-index 0 --raise-window
brrainztools --app "Terminal" --window-name "server logs" --raise-window
brrainztools --app "Terminal" --window-name "server logs" --raise
brrainztools --app "Terminal" --window-name "server logs" --close-window
brrainztools --app "Terminal" --window-name "server logs" --minimize-window
brrainztools --app "Terminal" --window-name "server logs" --move-window 120,80
brrainztools --app "Terminal" --window-name "server logs" --resize-window 900,600
```

`--list-accessibility-windows` lists windows through Accessibility instead of
ScreenCaptureKit. The JSON includes each window's title, frame, supported AX
actions, `isFocused`, `isMain`, `isFrontmostApplication`, and
`isFrontmostWindow`.

`isFrontmostWindow` means the selected app is the current
`NSWorkspace.frontmostApplication`, and the window is that app's focused AX
window. If the app exposes no focused AX window, BrrainzTools falls back to the
main window, then index 0.

`--raise-window` activates the app and performs `AXRaise` on the selected AX
window. Select the window with `--window-index`, `--window-name`, or
`--frontmost-window`; if you omit a selector, BrrainzTools uses the same focused,
main, then first-window fallback as other Accessibility modes.

`--close-window` presses the selected AX window's close button using the same
window-selection rules.

`--minimize-window` presses the selected AX window's minimize button using the
same window-selection rules.

`--move-window X,Y` sets the selected AX window's `AXPosition`; negative
coordinates are allowed for multi-display layouts. `--resize-window W,H` sets
the selected AX window's `AXSize`; width and height must be positive.

## Permissions

Capture and app/window listing require Screen Recording permission for the host
process.

Accessibility inspection and actions require Accessibility permission for the
host process.

The host process is the app that starts `brrainztools`, such as Terminal, iTerm,
or Codex.

Use `brrainztools doctor` to check both permissions without triggering a system
permission prompt.

Add `--no-prompt` to Accessibility, menu-bar, or `launch --wait-window` commands
to fail immediately when Accessibility permission is missing instead of asking
macOS to show the permission prompt.

## Exit Codes

BrrainzTools uses distinct exit codes so automation can decide whether to retry,
ask for a more specific selector, or hand the issue to the user:

- `64`: usage error or invalid arguments
- `65`: ambiguous app or window match
- `66`: app or window not found
- `69`: unavailable feature or missing permission
- `70`: capture, Accessibility, or encoding failure
- `75`: timed out operation
