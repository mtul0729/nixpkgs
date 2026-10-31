#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nurl nix-update python3 -I nixpkgs=.

set -euo pipefail

# <nixpkgs> is looked up in NIX_PATH: nix-shell needs it for the -p packages
# above, and nix-update defaults --file to it. CI runners have no NIX_PATH, so
# both are pointed at the current checkout instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE="${1:-helix}"

case "$PACKAGE" in
  helix)
    # Fast path (same trick as the old helix-flake): languages.toml, and with it
    # grammars.json, is fully determined by the pinned rev. When upstream master
    # has not moved, the expensive part — nurl prefetching every grammar and a
    # full rebuild — would run for nothing, so compare revs first and bail out.
    # Read the pin straight out of the expression: evaluating it would mean a full
    # nixpkgs evaluation (~4 minutes) just to answer "did anything move?".
    current_rev="$(grep -oE 'rev = "[0-9a-f]{40}"' "$SCRIPT_DIR/../helix-unwrapped/package.nix" | head -1 | cut -d'"' -f2 || true)"
    upstream_rev="$(timeout 60 git ls-remote https://github.com/helix-editor/helix refs/heads/master 2>/dev/null | cut -f1 || true)"
    if [ -n "$current_rev" ] && [ -n "$upstream_rev" ] && [ "$current_rev" = "$upstream_rev" ]; then
      echo "helix already pinned to master $current_rev; nothing to update"
      exit 0
    fi
    nix-update helix-unwrapped --version=branch=master --file .
    SOURCE_ATTR="helix-unwrapped.src"
    # rev-pinned src is a fixed-output derivation: `nix-instantiate --eval`
    # cannot substitute it (the outPath needs an instantiation with IFD),
    # so it has to be realised with nix-build before reading languages.toml.
    SOURCE_IS_FOD=1
    GRAMMARS_JSON="pkgs/by-name/he/helix/grammars.json"
    ;;
  steelix)
    nix-update steelix.unwrapped --version=branch=steel-event-system --file .
    SOURCE_ATTR="steelix.unwrapped.src.outPath"
    SOURCE_IS_FOD=0
    GRAMMARS_JSON="pkgs/by-name/st/steelix/grammars.json"
    ;;
  *)
    exit 1
    ;;
esac

echo "Fetching updated $PACKAGE source..."
if [ "$SOURCE_IS_FOD" = 1 ]; then
  HELIX_SRC=$(nix-build -A "$SOURCE_ATTR" --no-out-link)
else
  HELIX_SRC=$(nix-instantiate --eval -A "$SOURCE_ATTR" --raw)
fi

echo "Generating grammars.json..."
"$SCRIPT_DIR/generate_grammars.py" \
  "$HELIX_SRC/languages.toml" \
  -o "$GRAMMARS_JSON"

if [ $? -ne 0 ]; then
  echo "Error: Failed to generate grammars.json" >&2
  exit 1
fi

echo "Done! Updated $GRAMMARS_JSON"
