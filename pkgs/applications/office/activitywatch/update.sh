#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix curl jq git nix-prefetch-git -I nixpkgs=.

set -euo pipefail

cd "$(dirname "$0")"

# update.sh lives four directories below the nixpkgs root.
repo_root=$(cd ../../../.. && pwd)
owner=ActivityWatch
repo=activitywatch

current_version=$(sed -n 's/^  serverVersion = "\([^"]*\)";$/\1/p' default.nix)
if [ -z "$current_version" ]; then
  echo "error: could not read serverVersion from default.nix" >&2
  exit 1
fi

# `releases/latest` is the maintainer's own statement of what is stable:
# GitHub excludes prereleases from it. A tag listing cannot answer that
# question -- ActivityWatch tags prereleases with a plain
# `v<major>.<minor>.<patch>` and marks them only in the release object -- so
# falling back to tags flipped this branch between 0.14.3 and 0.14.2 every
# hour, whenever the unauthenticated API call hit the rate limit. Use the
# token CI exports; when the API still cannot answer, keep the current
# version and try again next round.
curl_args=(--fail --silent --show-error)
if [ -n "${GH_TOKEN:-}" ]; then
  curl_args+=(-H "Authorization: Bearer ${GH_TOKEN}")
fi
latest_tag=
if ! latest_tag=$(curl "${curl_args[@]}" \
  "https://api.github.com/repos/${owner}/${repo}/releases/latest" |
  jq --raw-output '.tag_name'); then
  echo "activitywatch: Releases API unavailable, keeping ${current_version}" >&2
  exit 0
fi
latest_version=${latest_tag#v}

if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
  echo "error: could not determine the latest release tag" >&2
  exit 1
fi

if [ "$latest_version" = "$current_version" ]; then
  echo "activitywatch is already at ${current_version}"
  exit 0
fi

# Upgrades only move forward. If upstream retracts a release, the version to
# go back to is a human decision, not something an hourly job should infer.
if [ "$(printf '%s\n%s\n' "$current_version" "$latest_version" |
  sort --version-sort | tail -n 1)" = "$current_version" ]; then
  echo "activitywatch: releases/latest is ${latest_version}, behind ${current_version}; not downgrading" >&2
  exit 0
fi

echo "updating activitywatch from ${current_version} to ${latest_version}"

backup=$(mktemp)
cp default.nix "$backup"
trap 'cp "$backup" default.nix; rm -f "$backup"' ERR

# Only the server line moves: version/sources stay at 0.13.2 for the Python
# components (see the note at the top of default.nix).
sed -i "s|^  serverVersion = \"${current_version}\";$|  serverVersion = \"${latest_version}\";|" default.nix

# nix-prefetch-git's --hash is the expected hash, not a "print the result"
# switch, so ask for the JSON summary and read the hash out of it.
old_source_hash=$(
  sed -n '/serverSources = fetchFromGitHub/,/^  };/p' default.nix |
    sed -n 's/^    sha256 = "\([^"]*\)";$/\1/p' |
    head -n 1
)
if [ -z "$old_source_hash" ]; then
  echo "error: could not read the serverSources hash from default.nix" >&2
  exit 1
fi

source_json=$(nix-prefetch-git --fetch-submodules --quiet --rev "v${latest_version}" \
  "https://github.com/${owner}/${repo}")
source_hash=$(jq --raw-output '.hash' <<<"$source_json")
if [ -z "$source_hash" ] || [ "$source_hash" = "null" ]; then
  echo "error: nix-prefetch-git did not return a hash" >&2
  exit 1
fi
sed -i "s|${old_source_hash}|${source_hash}|" default.nix

# Replace a dependency hash with lib.fakeHash, build, and read the hash Nix
# reports back. aw-webui must go first: aw-server-rust embeds it, so a fake
# npmDepsHash would otherwise mask the cargo hash mismatch.
update_hash() {
  local attr=$1 field=$2 output hash

  sed -i "s|^[[:space:]]*${field} = .*|    ${field} = lib.fakeHash;|" default.nix

  # nix-build in this tree takes the expression as a positional file path and
  # does not support -f.
  output=$(
    nix-build \
      --expr "with import ${repo_root} { }; callPackage ${PWD} { }" \
      -A "$attr" --no-out-link 2>&1 || true
  )
  hash=$(sed -n 's/^ *got: *//p' <<<"$output" | tail -n 1)
  if [ -z "$hash" ]; then
    printf '%s\n' "$output" >&2
    echo "error: could not determine ${field} for ${attr}" >&2
    exit 1
  fi

  sed -i "s|^[[:space:]]*${field} = lib.fakeHash;|    ${field} = \"${hash}\";|" default.nix
}

update_hash aw-webui npmDepsHash
update_hash aw-server-rust cargoHash

rm -f "$backup"
trap - ERR

echo "done: activitywatch ${latest_version}"
