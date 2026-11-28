# SiYuan

This directory is maintained on top of nixpkgs PR
[#576868](https://github.com/NixOS/nixpkgs/pull/576868) (`siyuan: 3.8.2 ->
3.8.12`). The `siyuan` (stable) expression is otherwise the PR's. The additions
are split below into what can be submitted to nixpkgs on its own and what is
deliberately kept in this fork, so after the PR lands in `nixos-unstable` the
two lists are the remaining delta. Delete this file once the first list is
upstreamed.

## Suitable for nixpkgs

- **Server output.** `siyuan.server`, exposed as `siyuan-server`
  (`pkgs/by-name/si/siyuan-server`), is the kernel plus `serverUi`: the same app
  tree built without Electron packaging. It copies
  `app/pandoc/pandoc-resources` rather than symlinking it, so the 343 MiB
  source tree does not become a runtime dependency.

  The desktop client and `serverUi` stage their OCR resources through
  `ocrSetup` in `package.nix`, so the offline preparation lives in one place.
  Upstream the manifest would stay `./ocr-assets.json`; only the shared helper
  is part of this change, not the per-channel indirection below.

- **Markdown MIME type.** The desktop item declares `text/markdown`, matching
  electron-builder's association. Without it file managers never offer SiYuan
  for `.md` files.

- **Electron major check.** `postConfigure` compares the major in
  `app/package.json` with `electron_44` and fails the build on drift. It costs
  one `jq` at build time and turns a silent runtime breakage into a build
  error.

## Fork-only

- **Preview channel.** `channel ? "stable"`, `channels.json`,
  `ocr-assets-preview.json` and `pkgs/by-name/si/siyuan-preview`. nixpkgs
  packages track the stable release; a second channel doubles the pins and the
  cache surface for a pre-release that nobody has verified on darwin.

  `siyuan-preview` picks the newest of stable/rc/beta/alpha, so it is usually
  ahead of `siyuan` and equal to it right after a release. The manifest copy is
  separate only so the channels rotate independently; it is byte-identical to
  `ocr-assets.json` today because both channels are on 3.8.12.

- **Channel-aware update script.** `update.sh` drops `nix-update` and rotates
  the pins in `channels.json` itself: `UPDATE_NIX_ATTR_PATH` selects the
  channel (`siyuan`/`siyuan-server` → stable, `siyuan-preview` → preview),
  every fixed-output pin is first set to an impossible hash so an interrupted
  run is retried even when the tag has not changed, and the script ends by
  printing the change descriptor `maintainers/scripts/update.py` expects. It
  exists to keep two channels in sync; a single-channel package is better
  served by `nix-update`, as in the PR.

- **This file.** nixpkgs does not carry delta documents for individual
  packages.

## Keeping in sync

Rebase onto the PR head (after the merge, `nixos-unstable`) and carry the files
listed above. The stable pins in `channels.json` must follow the merged
version, and `ocr-assets.json` must stay a verbatim copy of upstream's
`scripts/ocr-assets.json`.
