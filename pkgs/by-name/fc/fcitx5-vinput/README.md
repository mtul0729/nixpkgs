# fcitx5-vinput

This directory is maintained on top of nixpkgs PR
[#576811](https://github.com/NixOS/nixpkgs/pull/576811) (`fcitx5-vinput: init
at 2.4.2`). The branch is the PR's diff on `nixos-unstable` plus the fork-only
commits listed below. Delete this file once the branch is only that delta.

## Upstream-bound

The first commit, `fcitx5-vinput: init at 2.4.2`, is the PR's content against
CI's base. `pr/fcitx5-vinput-2.4.2` is the same content on `upstream/master`
and is the copy that goes upstream; package changes are made there first.

To resynchronise, cherry-pick the PR's commits onto the current
`nixos-unstable`, then rebase the fork-only commits on top:

```sh
git fetch upstream
git switch -c tmp/fcitx5-vinput-pr upstream/nixos-unstable
git cherry-pick <the PR's commits>
git rebase --onto tmp/fcitx5-vinput-pr <old upstream-bound tip> pkg/fcitx5-vinput
```

Using the PR tip as the base instead drags in everything `upstream/master` is
ahead of `nixos-unstable` by; the commit has to be the PR's diff on unstable.
When the PR merges, `git rebase upstream/nixos-unstable` drops the init commit
by itself and leaves the fork-only ones.

## Fork-only

- **`rev` instead of `tag`.** CI runs `nix-update` 1.16.0, which compares
  `package.rev or package.tag` with the feed's `vX`; `tag` makes every no-op
  run look like an update. `rev = "vX"` fetches the same archive and
  fixed-output path. Delete the commit when the CI pin prefers `tag` again.
- **This file.**

## When the next release lands

Upstream `main` replaced PipeWire capture with PulseAudio (upstream PR `#796`),
but `v2.4.2` still links `libpipewire-0.3` from `src/gui`. The
package matches the release; the first tag after that change needs
`libpulse` in `buildInputs` in place of `pipewire`.
