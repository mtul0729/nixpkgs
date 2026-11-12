#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq gnused nix-update -I nixpkgs=.
# shellcheck shell=bash

set -eu -o pipefail

package_dir=$(dirname "$(readlink --canonicalize-existing "${BASH_SOURCE[0]}")")
package_file="$package_dir/package.nix"

release=$(curl ${GITHUB_TOKEN:+-u ":$GITHUB_TOKEN"} --silent --fail --location \
  "https://api.github.com/repos/openai/codex/releases/latest")
tag=$(jq --exit-status --raw-output '.tag_name' <<<"$release")
version=${tag#rust-v}

current_version=$(sed --regexp-extended --quiet \
  's/^  version = "([^"]+)";$/\1/p' "$package_file")
if [ "$current_version" = "$version" ]; then
  echo "codex: already at $version"
  exit 0
fi

# A fixed version skips release discovery, so the large releases listing that
# times out GitHub's gateway is never requested.
nix-update codex --file . --version="$version"

commit=$(curl ${GITHUB_TOKEN:+-u ":$GITHUB_TOKEN"} --silent --fail --location \
  "https://api.github.com/repos/openai/codex/commits/$tag" \
  | jq --exit-status --raw-output '.sha')
sed --in-place --regexp-extended \
  "s|buildCommit = \"[^\"]+\";|buildCommit = \"$commit\";|" \
  "$package_file"

"$package_dir/update-librusty.sh"
