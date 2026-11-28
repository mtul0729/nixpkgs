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

Upstream `main` dropped the native PipeWire capture backend and the `wpctl`
output-ducking call in favour of a single libpulse client (issue `#796`, PR
`#801`). It is not a step away from PipeWire: `libpulse` speaks the PulseAudio
protocol to `pipewire-pulse`, PipeWire's own drop-in server, which translates
to the PipeWire graph. One client then covers both PulseAudio desktops and
PipeWire ones, at the cost of the PulseAudio module surface (`module-*`,
tunnels) and of hosts running bare PipeWire without the compat socket.

The reason is the target environment: Kylin V10 SP1, UOS V20, Deepin 20.9 and
Debian 11 ship only PulseAudio, and the native path was already broken on
PipeWire 0.3.48 (issue `#169`). A runtime fallback was rejected because a
Wayland session with screen sharing runs an empty `pipewire` daemon with no
audio nodes, so a successful `pw_context_connect` enumerates zero devices and
detection cannot fall back.

`v2.4.2` still links `libpipewire-0.3` from `src/gui/CMakeLists.txt`. The
package matches the release; the first tag after that change needs
`libpulseaudio` in `buildInputs` in place of `pipewire` (upstream's `flake.nix`
already uses it, `cmake/Dependencies.cmake` asks pkg-config for `libpulse`).
