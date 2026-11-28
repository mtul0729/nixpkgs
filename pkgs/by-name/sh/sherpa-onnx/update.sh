#!/usr/bin/env nix-shell
#!nix-shell -I nixpkgs=. -i bash -p nix nix-update python3

# sherpa-onnx vendors its dependencies through CMake FetchContent, which
# cannot download inside the sandbox. package.nix therefore copies a
# pre-fetched archive for each of them into the source tree, and each
# archive moves with a release: nix-update can bump "version" and the
# source hash, but not that list, so it is regenerated here from the
# release's own cmake/*.cmake files.

set -euo pipefail

name=sherpa-onnx
package="pkgs/by-name/sh/$name/package.nix"

# update.nix runs update scripts from the root of the tree being updated.
if [ ! -f "$package" ]; then
  echo "run this from the root of a nixpkgs checkout" >&2
  exit 1
fi

current_version() {
  sed -n 's/^  version = "\(.*\)";$/\1/p' "$package"
}

before="$(current_version)"
nix-update --file . "$name"
after="$(current_version)"

if [ "$before" = "$after" ]; then
  echo "$name: already at $after"
  exit 0
fi

echo "$name: $before -> $after, regenerating the FetchContent cache list"
src="$(nix-build --no-out-link -A "$name.src" .)"
python3 "pkgs/by-name/sh/$name/generate-cache.py" --package "$package" --cmake-dir "$src/cmake"
