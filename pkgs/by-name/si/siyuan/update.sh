#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl git jq nix

set -euo pipefail

pkg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(realpath "$pkg_dir/../../../..")"
channels="$pkg_dir/channels.json"

# nix-update sets UPDATE_NIX_ATTR_PATH when it runs this script; the attribute
# decides which channel gets rotated.
attr="${UPDATE_NIX_ATTR_PATH:-siyuan}"
case "$attr" in
  siyuan) channel=stable ;;
  siyuan-preview) channel=preview ;;
  *)
    echo "update.sh: unknown attribute '$attr'" >&2
    exit 1
    ;;
esac

# Placeholder for fixed-output derivations: a declared hash that cannot match
# the real content, so the derivation gets a fresh output path and has to be
# built for real. The real value is read back from the resulting hash mismatch.
placeholder="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

read_pin() {
  jq -r --arg c "$channel" --arg k "$1" '.[$c][$k]' "$channels"
}

write_pin() {
  jq --arg c "$channel" --arg k "$1" --arg v "$2" '.[$c][$k] = $v' "$channels" > "$channels.tmp"
  mv "$channels.tmp" "$channels"
}

current="$(read_pin version)"

# Upstream tags alphas and betas; the stable channel only takes plain versions,
# the preview channel takes the highest of stable/beta/alpha. Cheap enough to run
# first, so an unchanged package costs one ls-remote instead of a full rotation.
tags="$(git ls-remote --tags --refs https://github.com/siyuan-note/siyuan 'v*' \
  | sed 's#.*refs/tags/v##')"

if [ "$channel" = stable ]; then
  latest="$(printf '%s\n' "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
else
  # Sort key X.Y.Z.R.N, R = 0 for alpha, 1 for beta, 2 for a plain release, so
  # that v3.9.1-alpha.1 > v3.9.0 and v3.9.0-beta.2 < v3.9.0.
  latest="$(printf '%s\n' "$tags" \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)\.[0-9]+)?$' \
    | awk -F- '{ if (NF == 1) printf "%s.2.0 %s\n", $1, $0;
                 else { split($2, p, "."); r = (p[1] == "alpha") ? 0 : 1;
                        printf "%s.%d.%s %s\n", $1, r, p[2], $0 } }' \
    | sort -V | tail -1 | cut -d' ' -f2)"
fi

if [ -z "$latest" ]; then
  echo "update.sh: could not list the upstream tags" >&2
  exit 1
fi

# A run that died halfway leaves placeholders behind; rotate again even if the
# tag is unchanged, otherwise the package stays unbuildable.
pending=false
for key in src vendorHash pnpmDeps; do
  if [ "$(read_pin "$key")" = "$placeholder" ]; then
    pending=true
  fi
done

if [ "$latest" = "$current" ] && [ "$pending" = false ]; then
  echo "siyuan: $channel already at $current"
  exit 0
fi

old="$current"
write_pin version "$latest"
for key in src vendorHash pnpmDeps; do
  write_pin "$key" "$placeholder"
done

# src is the hash of the unpacked tarball, which is what fetchFromGitHub checks.
nix32="$(nix-prefetch-url --unpack "https://github.com/siyuan-note/siyuan/archive/v${latest}.tar.gz" | tail -1)"
write_pin src "$(nix hash convert --to sri --hash-algo sha256 "$nix32")"

# Both fixed-output derivations depend on src, so they are rotated after it.
resolve_fod() {
  local installable="$1" log hash
  if log="$(cd "$repo_root" && nix-build --no-link -A "$installable" 2>&1)"; then
    echo "update.sh: $installable built with the placeholder hash" >&2
    exit 1
  fi
  hash="$(printf '%s\n' "$log" | sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+/=]*\)$/\1/p' | tail -1)"
  if [ -z "$hash" ]; then
    printf '%s\n' "$log" | tail -20 >&2
    echo "update.sh: could not read the hash for $installable" >&2
    exit 1
  fi
  printf '%s\n' "$hash"
}

write_pin vendorHash "$(resolve_fod "$attr.kernel.goModules")"
write_pin pnpmDeps "$(resolve_fod "$attr.pnpmDeps")"

# ocr-assets.json is a verbatim copy of upstream's scripts/ocr-assets.json.
# prepare-ocr.py verifies the models by hash, so a release that changes them
# fails the build until this is refreshed.
ocr_name="$(read_pin ocrAssets)"
ocr_file="$pkg_dir/$ocr_name"
ocr_tmp="$(mktemp)"
trap 'rm -f "$ocr_tmp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/siyuan-note/siyuan/v${latest}/scripts/ocr-assets.json" -o "$ocr_tmp"
if cmp -s "$ocr_tmp" "$ocr_file"; then
  echo "$ocr_name: unchanged"
else
  cp "$ocr_tmp" "$ocr_file"
  echo "$ocr_name: updated for $latest"
fi

cat <<EOF
[
  {
    "attrPath": "${attr}",
    "oldVersion": "${old}",
    "newVersion": "${latest}",
    "files": [
      "${channels}",
      "${ocr_file}"
    ]
  }
]
EOF
