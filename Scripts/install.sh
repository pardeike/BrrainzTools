#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/Scripts/quiet-workflow.sh"
product_name="brrainztools"
install_dir="${INSTALL_DIR:-$HOME/Scripts}"
build_dir="$project_dir/.build/install"
target_path="$install_dir/$product_name"
support_source_dir="$project_dir/AgentSupport"
support_root_dir="$install_dir/.brrainztools-support"
support_target_dir="$support_root_dir/AgentSupport"
version="${VERSION:-}"

if [[ -z "$version" ]]; then
  version="$(git -C "$project_dir" describe --tags --always --dirty)"
fi

workflow_step="select signing identity"
identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Apple Development:.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$identity" ]]; then
  identity="-"
fi

mkdir -p "$install_dir"

if [[ ! -d "$support_source_dir" ]]; then
  echo "Missing agent support files at $support_source_dir" >&2
  exit 1
fi

run_step "release build" swift build \
  --package-path "$project_dir" \
  --configuration release \
  --product "$product_name" \
  --build-path "$build_dir"

workflow_step="sign release"
codesign --force --sign "$identity" "$build_dir/release/$product_name"
codesign --verify --strict --verbose "$build_dir/release/$product_name"
workflow_step="local installation"
/usr/bin/install -m 755 "$build_dir/release/$product_name" "$target_path.new"
mv -f "$target_path.new" "$target_path"
if [[ ! -f "$target_path" ]]; then
  echo "Failed to install $product_name to $target_path" >&2
  exit 1
fi

rm -rf "$support_target_dir"
rm -rf "$install_dir/regionshot" "$install_dir/.regionshot-support"
mkdir -p "$support_root_dir"
ditto "$support_source_dir" "$support_target_dir"
printf '%s\n' "$version" > "$support_root_dir/VERSION"

codesign --verify --strict --verbose "$target_path"

echo "Installed $product_name to $target_path"
echo "Installed agent support files to $support_target_dir"
echo "Installed version metadata to $support_root_dir/VERSION"
if [[ "$identity" == "-" ]]; then
  echo "Signed ad-hoc"
else
  echo "Signed with $identity"
fi

run_step 'installed Codex usage verification' python3 "$project_dir/Scripts/verify-usage.py" "$target_path"
if [[ "${VERIFY_CLAUDE_USAGE:-0}" == 1 ]]; then
  run_step 'installed Claude usage verification' python3 "$project_dir/Scripts/verify-usage.py" "$target_path" claude
fi

if [[ -n "${REMOTE_HOST:-}" ]]; then
  run_step 'remote installation and verification' "$project_dir/Scripts/install-remote.sh" "$target_path" "$support_root_dir" "$REMOTE_HOST"
fi
