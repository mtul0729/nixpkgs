# sherpa-onnx

This directory is maintained on top of the nixpkgs PR carrying the 2.0.3
update, [#594460](https://github.com/NixOS/nixpkgs/pull/594460). The first
commit is that PR's content verbatim; the commit after it is the fork's own
and is destined upstream as a second PR once the first lands. Delete this file
when both are in `nixos-unstable`.

## Upstream-bound

- **`1.13.8 -> 2.0.3` and the FetchContent list** — #594460. Upstream removed
  the espeak-ng/piper-phonemize TTS stack, which is why `espeak.patch` is gone,
  and the set of vendored dependencies changed with it.

- **`update.sh` / `generate-cache.py`** — regenerates the `cache` list between
  the markers in `package.nix` once `nix-update` has moved the version. Held
  back until #594460 merges so the same file does not enter the review queue
  twice.

## Why the list is generated

Upstream pins every CMake FetchContent dependency in its own `cmake/<dep>.cmake`:

```cmake
set(<dep>_URL  "https://...")
set(<dep>_HASH "SHA256=<hex>")
```

and the archive file name it probes under `.../Downloads/<file>` is
hard-coded next to them. All three move with a release, and nothing in the
release tarball lists them, so `nix-update` can bump `version` and the source
hash but leaves the pre-fetched archives stale — the package would then build
against the previous release's dependency set. `generate-cache.py` parses those
files and writes the SRI form of each hash.

Two details that bite:

- The archives are copied into the source root under the exact name CMake
  looks for, so `kaldi_native_io` keeps its underscore.
- `cmake/onnxruntime*.cmake` are skipped, because nixpkgs supplies
  `onnxruntime` through `onnxruntime_SOURCE_DIR`; `portaudio` is skipped
  because the build disables it.

## Notes for the next person

- **`update.sh` assumes cwd is the nixpkgs root.** `nix-update -u` runs update
  scripts from `maintainers/scripts/update.nix`, which copies the script into
  the store and executes it from the root of the tree being updated — deriving
  paths from `$BASH_SOURCE` resolves to `/nix/store`, not to this directory.
  The shebang therefore carries `-I nixpkgs=.`.
- **`asio` and `websocketpp` are no longer behind `lib.optionals
  websocketSupport`.** The generated list is flat. With the default
  `websocketSupport = true` the set is identical to the hand-written one; with
  `false` the two archives are still fetched, but nothing uses them. Keeping
  the conditional would mean hand-maintaining which dependencies belong to the
  websocket feature.
- **`doCheck` stays `true`.** The ctest suite runs inside the sandbox and
  passes (CI build of this branch); it is the PR's requirement, and the first
  commit here is the PR content verbatim rather than a fork variant.
- **No Darwin-specific code.** The expression is the same on every
  `lib.platforms.unix`; `alsa-lib` is the only Linux-only input. Upstream
  review is run on `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`.
