# BrrainzTools

BrrainzTools is a macOS command line toolbox for desktop automation:
screenshots, window capture, menu capture, UI inspection, Accessibility-driven
UI actions, input synthesis, and app lifecycle control.

It is built for agents and scripts. It helps them ask macOS for the right
thing instead of guessing screen rectangles:

- poll live Codex and Claude subscription limits
- find a running app
- list app windows
- capture a window or a visible floating panel
- list, raise, move, resize, close, and minimize accessibility windows
- inspect nested menu hierarchies, or open and capture a menu-bar item
- read accessibility element state and press/set/type/key/click/drag/scroll UI
- launch, activate, quit, and wait for local apps
- open a document through macOS's normal app handoff, including with a specific app
- reveal a file or directory as a Finder selection
- read or set clipboard text
- convert a screenshot to a compact text view
- ask Codex a direct question about an existing image

## Install

Download `BrrainzTools-v2.1.0-macos.dmg` from the GitHub release, open it, and run
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

## Agent subscription limits

```bash
brrainztools usage codex
brrainztools usage claude
brrainztools usage all   # also the default for `usage`
```

Returns the standard JSON envelope with `mode: "usage"` and `data.providers`.
Each provider includes `status`, `source`, `checkedAt`, and `windows` containing
`name`, `usedPercent`, `remainingPercent`, and available reset times. Codex also
includes its plan and additional model limits; Claude includes reported weekly
model limits. Percentages apply to the signed-in account, not individual agents,
and cannot be converted into a remaining token count.

Codex account-wide weekly windows also include `forecast`, using TokenCoffee's
local copy of its iCloud-synced history and its adjusted graph forecast model.
The optimistic/pessimistic scenarios report `usedPercentAtReset` and
`reaches100At`, with an explicit null when 100% is not reached before reset.
`recentRatePercentPointsPerHour` measures recent consumption, including idle time;
`recentRateSpanSeconds` gives the observation period. These are scenarios, not
statistical confidence bounds. There is no angle tied to chart dimensions.

Forecasts require at least three matching samples spanning one hour, an observed
usage increase, and a latest sample no older than 30 minutes. `status` is `ok`,
`exhausted`, `insufficient_history`, `stale_history`, or `unavailable`; missing
forecasts do not change provider success or the live allowance. `reason` explains
missing or inconsistent history. `latestSampleAt`, `lastSuccessfulSyncAt`,
`syncCaughtUp`, `sampleCount`, and `historySpanSeconds` describe the evidence when
available. A current percentage of 100 or more reports `exhausted` immediately;
its crossing timestamp means observed exhausted now, not the historical first hit.

TokenCoffee remains responsible for polling and iCloud sync. BrrainzTools only
reads `quota-samples.jsonl` and selected sync metadata; it never changes the app's
data or starts a cloud sync. It prefers the installed app's sandbox under
`~/Library/Containers/com.pardeike.TokenCoffee/Data/Library/Application Support/TokenCoffee`.
If the container does not exist, it uses `~/Library/Application Support/TokenCoffee`.
Set `BRRAINZTOOLS_TOKENCOFFEE_DIRECTORY` to select an explicit data directory.
A sandbox access failure does not silently select an older development store.

The current TokenCoffee sample format has no account ID. Forecast JSON explicitly
reports `accountMatch: "unverified"`; matching limit, plan, reset and nondecreasing
usage does not establish account identity. Use the same Codex account in both
apps. Additional model limits, five-hour limits and Claude have no forecast.
See [forecast source provenance](docs/tokencoffee-forecast-source.md).

The shipped agent skill and managed AGENTS instructions tell models to poll at
the start of substantial work, before spawning parallel agents, and after a
usage-limit interruption. During sustained work, check at meaningful checkpoints
and at least every five minutes, increasing to every minute at 5% or less
remaining. Stop substantive work and affected sub-agents as soon as any applicable
account or current-model window reaches 1% remaining or less. Give a brief progress
handoff with the reset time; resume only after a fresh poll confirms more than 1%
remaining in all applicable windows, or an explicit user override. Back off on
HTTP 429 and pause further substantial work when allowance cannot be established.
Other sessions share the allowance, so polling cannot guarantee a reserve.

Codex reads `auth.json` under `CODEX_HOME` or `~/.codex`.
Claude uses a separate file-based subscription login in `~/.brrainztools/auth.json`.
No Keychain lookup, Claude Code credential copying, or API key is involved.
The auth directory is private to your user, mode 0700; token files use mode 0600.

Authorize Claude once:

```bash
brrainztools usage claude login
# Open data.authorizationURL from the JSON result in your browser and authorize.
brrainztools usage claude login --complete
# Paste the browser's complete code#state when prompted, then press Return.
brrainztools usage claude
```

The login requests `user:profile` access for usage reporting. Pending login state
expires after 30 minutes. Authorization codes are read from stdin, never command
arguments, and tokens are never included in output. Claude Code's login remains
separate. A regular API key or an inference-only `claude setup-token` credential
cannot replace this usage login.

Polling refreshes the stored OAuth credential when it expires within 60 seconds.
A file lock prevents concurrent agents from rotating the same refresh token, and
successful refreshes are saved atomically. Failed refreshes preserve the existing
file and return an error without retries. If another process holds the lock, poll
again after it finishes. Revoked or expired authorization requires a new login.
Polling never opens browser login or permission dialogs.

Each provider request has a 20-second timeout. Exit status is 0 when all requested
providers succeed, or 1 when any is unavailable. Provider failures appear in the
JSON on stdout alongside successful results, with `status: "unavailable"` and
`error`; unavailable data must not be interpreted as unused allowance. Invalid
command arguments use the normal stderr error envelope. These provider endpoints
were ported from TownHall's `codex-budget` and `claude-budget` scripts and may
change independently of BrrainzTools.

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
brrainztools open-file ./README.md
brrainztools open-file ./Review.markreview --app /tmp/MarkReview.app --wait-window
brrainztools quit --app TextEdit --wait
brrainztools reveal ./README.md
brrainztools windows --app Terminal --visible
brrainztools capture --app Terminal --visible-window --output ~/Desktop/terminal.png
brrainztools capture --app Terminal --with-ocr --max-dimension 1200
brrainztools menu --app Drafty list
brrainztools menu --app Finder tree
brrainztools menu --app Drafty press --menu-bar-index 0
brrainztools menu --app Drafty press-item "Quick Tasks" --menu-bar-index 0
brrainztools ascii ~/Desktop/terminal.png --ocr-only
brrainztools ask-image ~/Desktop/terminal.png "What is weird about this image?"
brrainztools ask-image ~/Desktop/terminal.png "List the visible controls." --json
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

## Project verification and delivery

Run `Scripts/verify.sh` for focused usage, authentication and forecast tests.
Run `Scripts/install.sh` to build, sign, install locally and verify live Codex usage.
The installer preserves the existing Apple Development signing convention;
`CODESIGN_IDENTITY` can select another explicit identity.

To deploy that same signed binary and support files to a remote Mac, with hash,
signature and installed usage verification:

```bash
REMOTE_HOST=mba REMOTE_ADDRESS=10.10.9.3 REMOTE_HOST_KEY_ALIAS=mba.home.arpa Scripts/install.sh
```

These workflows print only `ok` on success. Full output goes to ignored
`.build/logs/` files. Failures report the failed step, diagnostics and log path.
They do not commit, push or publish anything. A live provider login is required
for delivery verification. Set `REQUIRE_CODEX_FORECAST=1` to require an available forecast during delivery
verification. Forecast status is reported in the log, including
missing history or a macOS denial of access to TokenCoffee's sandbox.
