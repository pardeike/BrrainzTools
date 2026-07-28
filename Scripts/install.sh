#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --product "$product_name" \
  --build-path "$build_dir"

/usr/bin/install -m 755 "$build_dir/release/$product_name" "$target_path"
if [[ ! -f "$target_path" ]]; then
  echo "Failed to install $product_name to $target_path" >&2
  exit 1
fi

rm -rf "$support_target_dir"
rm -rf "$install_dir/regionshot" "$install_dir/.regionshot-support"
mkdir -p "$support_root_dir"
ditto "$support_source_dir" "$support_target_dir"
printf '%s\n' "$version" > "$support_root_dir/VERSION"

codesign --force --sign "$identity" "$target_path"
codesign --verify --verbose "$target_path"

echo "Installed $product_name to $target_path"
echo "Installed agent support files to $support_target_dir"
echo "Installed version metadata to $support_root_dir/VERSION"
if [[ "$identity" == "-" ]]; then
  echo "Signed ad-hoc"
else
  echo "Signed with $identity"
fi
