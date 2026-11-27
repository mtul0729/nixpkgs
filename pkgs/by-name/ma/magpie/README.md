# magpie

Out-of-tree package for [magpie](https://usemagpie.ai/), maintained on the
`pkg/magpie` branch. Everything except this file is the content prepared for
upstream; the branch feeds CI and sysadmin, while the copy destined for
nixpkgs lives on `pr/magpie-<version>`, based on `upstream/master`, and is
never pushed from here.

## Why not upstream (yet)

[#575839](https://github.com/NixOS/nixpkgs/pull/575839) proposed this package
and was closed on 2026-10-23. The review found the expression still too
complicated, mainly because of the carried patches and the explanatory
comments. The current expression needs no patch: upstream treats a binary in
`/nix/store` as package-managed and leaves updating to the package manager
(`internal/update/packaged.go`), and writes its autostart and desktop entries
through the wrapper's `MAGPIE_EXECUTABLE` (`internal/appdir/launcher.go`).

Upstream publishes often, so a nixpkgs copy will always be behind. The
packaging itself changes rarely.

## What is here

- `package.nix` builds both outputs from one expression: `magpie` (GUI) and
  `magpie-cli` (`withGui = false`, exposed in `all-packages.nix`). The names
  match upstream's own flake outputs.
- Only Linux is packaged. The macOS app bundle, its codesigning and the
  minimum-version handling are deliberately left out; they belong in a
  separate contribution.

Linux uses GTK 4 and WebKitGTK 6 (`production` tag). Upstream's optional
`gtk3` tag is a compatibility build for older distributions, and its release
binaries link GTK 3. `bun` is a runtime dependency and is passed to the
wrapper as `MAGPIE_BUN`; the wrapper also names `MAGPIE_EXECUTABLE` so
autostart and desktop entries point at the profile link.

## Upstream's release repository

[`yetone/magpie-releases`](https://github.com/yetone/magpie-releases) is
upstream's distribution repository: the signed release builds, the Homebrew
tap, the Scoop bucket, the winget manifests, and a flake that wraps those
binaries as `magpie` and `magpie-cli`. Its flake is the reference for
everything that is not visible in the source tree, and this expression
follows it: the two output names, `MAGPIE_BUN` pointing at nixpkgs' `bun`
(the one magpie downloads is built for other systems' glibc), and
`MAGPIE_EXECUTABLE` naming the profile link rather than the store path.

That flake wraps prebuilt binaries, so it carries the GTK 3 / WebKitGTK 4.1
builds upstream ships for older distributions. Here the `production` tag is
compiled from source and links GTK 4 / WebKitGTK 6; nothing from the release
assets is an input, and neither the macOS app bundle nor its notarisation
comes along with it.

## Removed

`tray-watcher.patch` carried an unmerged fix for a duplicate tray icon on
COSMIC ([yetone/magpie#2804](https://github.com/yetone/magpie/issues/2804),
from `skygunner/magpie@7256f0d`). It was dropped on 2026-11-27 along with the
COSMIC session that needed it; the fix is still unmerged upstream. Re-add it
only if that desktop is used again, or wait for the fix to land upstream.

## Updating

```sh
nix-update magpie
nix build .#magpie .#magpie-cli
```

`magpie` and `magpie-cli` share the version, so updating one updates both.
The update script restricts versions to `vX.Y.Z`, so the non-version `pf-v1`
tags are ignored.

## If this is ever submitted

- Remove comments that are not obvious from the code.
- Confirm `nix-update` still picks the intended release.
- The PR removes the `magpie` throw alias, which needs a reviewer's explicit
  agreement: the name belonged to a different program.
- Darwin stays out of scope; a separate PR should add it.

`doCheck = false` because the tests need a real GUI and secret store;
`versionCheckHook` still runs the installed binary.

## Keeping in sync

The branch is two commits on `upstream/nixos-unstable`: `magpie: init at
0.1.4972`, whose content is the PR's, and the commit that adds this file.
When the PR moves, replay its commits onto the current `nixos-unstable` and
rebase this file's commit onto the result. Once the PR lands, `git rebase
upstream/nixos-unstable` drops the init commit by itself and only this file
is carried. A conflict means upstream changed a line this directory also
changes; resolve it here, never in the PR copy.
