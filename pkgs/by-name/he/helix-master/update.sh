#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nurl nix-update python3 -I nixpkgs=.

set -euo pipefail

# <nixpkgs> is looked up in NIX_PATH: nix-shell needs it for the -p packages
# above, and nix-update defaults --file to it. CI runners have no NIX_PATH, so
# both are pointed at the current checkout instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fast path: languages.toml, and with it grammars.json, is fully determined by
# the pinned rev. When upstream master has not moved, skip the expensive nurl
# prefetch. Read the pin straight out of the expression so the check does not
# evaluate nixpkgs.
current_rev="$(grep -oE 'rev = "[0-9a-f]{40}"' "$SCRIPT_DIR/unwrapped.nix" | head -1 | cut -d'"' -f2 || true)"
upstream_rev="$(timeout 60 git ls-remote https://github.com/helix-editor/helix refs/heads/master 2>/dev/null | cut -f1 || true)"
if [ -n "$current_rev" ] && [ -n "$upstream_rev" ] && [ "$current_rev" = "$upstream_rev" ]; then
  echo "helix-master already pinned to master $current_rev; nothing to update"
  exit 0
fi

nix-update helix-master.unwrapped --version=branch=master --file .

# rev-pinned src is a fixed-output derivation: `nix-instantiate --eval` cannot
# substitute it (the outPath needs an instantiation with IFD), so realise it
# before reading languages.toml.
HELIX_SRC=$(nix-build -A helix-master.unwrapped.src --no-out-link)

echo "Generating grammars.json..."
python3 "$SCRIPT_DIR/../helix/generate_grammars.py" \
  "$HELIX_SRC/languages.toml" \
  -o "$SCRIPT_DIR/grammars.json"

echo "Done! Updated $SCRIPT_DIR/grammars.json"
