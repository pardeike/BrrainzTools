#!/usr/bin/env bash
# Called by install.sh, which captures all output and propagates failure.
set -euo pipefail
binary="$1"
support="$2"
remote_host="$3"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)
if [[ -n "${REMOTE_ADDRESS:-}" ]]; then
  ssh_options+=(-o "HostName=$REMOTE_ADDRESS")
fi
if [[ -n "${REMOTE_HOST_KEY_ALIAS:-}" ]]; then
  ssh_options+=(-o "HostKeyAlias=$REMOTE_HOST_KEY_ALIAS")
fi
stage=$(ssh "${ssh_options[@]}" "$remote_host" 'mktemp -d /tmp/brrainztools-install.XXXXXXXX')
[[ "$stage" == /tmp/brrainztools-install.* && "$stage" != *[!a-zA-Z0-9/.-]* ]]
cleanup() { ssh "${ssh_options[@]}" "$remote_host" "rm -rf '$stage'" || true; }
trap cleanup EXIT
trap 'exit 130' INT TERM
scp "${ssh_options[@]}" "$binary" "$project_dir/Scripts/verify-usage.py" "$remote_host:$stage/"
scp -r "${ssh_options[@]}" "$support" "$remote_host:$stage/support"
expected_hash=$(shasum -a 256 "$binary" | awk '{print $1}')
ssh "${ssh_options[@]}" "$remote_host" bash -s -- "$stage" "$expected_hash" "${REQUIRE_CODEX_FORECAST:-0}" <<'REMOTE'
set -euo pipefail
stage="$1"
expected_hash="$2"
export REQUIRE_CODEX_FORECAST="$3"
codesign --verify --strict --verbose "$stage/brrainztools"
[[ "$(shasum -a 256 "$stage/brrainztools" | awk '{print $1}')" == "$expected_hash" ]]
mkdir -p "$HOME/Scripts"
# Replace by rename so an existing running process keeps its executable mapping.
install -m 755 "$stage/brrainztools" "$HOME/Scripts/brrainztools.new"
mv -f "$HOME/Scripts/brrainztools.new" "$HOME/Scripts/brrainztools"
mkdir -p "$HOME/Scripts/.brrainztools-support"
ditto "$stage/support" "$HOME/Scripts/.brrainztools-support"
codesign --verify --strict --verbose "$HOME/Scripts/brrainztools"
[[ "$(shasum -a 256 "$HOME/Scripts/brrainztools" | awk '{print $1}')" == "$expected_hash" ]]
python3 "$stage/verify-usage.py" "$HOME/Scripts/brrainztools"
REMOTE
