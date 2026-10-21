# nixpkgs conventions

What nixpkgs requires, where it is written down, and which of it is checked by a machine. This
file is the map; upstream is the territory. Where they disagree, upstream wins and this file is
wrong.

How the fork sends things upstream (PRs, comments, issues, disclosure) is a separate concern:
[`upstream.md`](./upstream.md).

## Where the rules live

- `CONTRIBUTING.md` — commits, branches, backports, PRs, reviews, the automation/AI policy.
- `pkgs/README.md` — packaging: naming, versioning, meta, fetchers, patches, tests, update
  scripts, removals. It also carries the reviewer checklists (`:1167` for updates, `:1233` for
  new packages).
- `pkgs/by-name/README.md` — what living in `pkgs/by-name/` obliges you to do.
- `doc/hooks/` — which phases each setup hook already provides.
- `doc/languages-frameworks/` — the conventions of each ecosystem.
- `maintainers/README.md` — maintainer entries and teams.
- `.github/PULL_REQUEST_TEMPLATE.md` — the shape of a PR body.

Read the relevant one before acting, not after a reviewer points at it. Everything below is a
summary of those files, and a summary goes stale.

## What a package has to satisfy

Marks: `[vet]` = nixpkgs-vet fails the PR, `[CI]` = some workflow fails, `[review]` = a human
has to catch it.

- **Path and naming.** `pkgs/by-name/<two-letter-lower-prefix>/<attr-name>/package.nix`; the
  directory name is the attribute name. Do **not** add it to `all-packages.nix`; split files
  only inside its own directory; only top-level, `callPackage`-able packages live here. `[vet]`
- **New packages set `__structuredAttrs = true;` and `strictDeps = true;`.** `[vet]` — and it
  reports them one at a time, so fixing the first does not mean the second is not coming. Some
  builders already set `strictDeps` (`buildRustPackage` does, which is why dashbeam passed with
  only the first one); plain `mkDerivation` sets neither.
- **No import-from-derivation.** `[review]`, and `nixpkgs-review` drops such packages silently,
  so the failure looks like success.
- **No network at build time.** Everything has to arrive through a nixpkgs fetcher. `[CI]`: the
  sandbox fails the build.
- **`meta`, complete.** `description`, `license`, `maintainers` (required for a new package),
  `platforms`, `mainProgram` when there is one, `sourceProvenance` when it is not built from
  source. `[review]`
- **Versioning.** Starts with a digit. No tag to point at: `<version>-unstable-YYYY-MM-DD`.
  `[review]`
- **Sources and hashes.** nixpkgs fetchers, `sha256`, and a full commit hash for GitHub.
  `[review]`, plus the build fails on a wrong hash.
- **Patches.** Anything reachable upstream goes through `fetchpatch2`; a vendored `.patch` is
  only for Nix-specific fixes, and says so in a comment. `[review]`
- **Tests.** `passthru.tests`; a library needs a dependent or a minimal test. `[review]`
- **Updates.** `passthru.updateScript`, or the bot has to guess. `[review]`
- **Formatting.** nixfmt. `[CI]` (treefmt).
- **Removals.** Delete the directory and the `all-packages.nix` entry, leave a `throw` alias
  with a date and a reason — and no release note; the alias is the note. `[review]`

## What a commit and a PR have to satisfy

- **Subject.** `<pkg>: <old> -> <new>` / `init at <version>` / `<what>`, no trailing period, body
  says why (a bump names both versions and links the changelog). `[review]`
- **One logical unit per commit.** A `maintainers: add <handle>` entry is its own commit and
  comes first. `[review]`
- **Base branch.** `master`, unless it is a mass rebuild (500+ rebuilds: consider `staging`;
  1000+: `staging`), or it rebuilds all NixOS tests (`staging-nixos`). Backports are a separate
  step after the merge. `[CI]` labels the rebuild size; the choice is yours.
- **PR body.** Built from upstream's template, ticked honestly. `[review]`
- **Review.** Comments are non-blocking by default; only *Request changes* blocks. Every
  suggestion gets applied or explicitly declined before merge. `[review]` — this is the merge
  gate.
- **Maintainer entries.** The adding commit must be GPG-signed and the `githubId` must match the
  handle; GitHub's "Verified" badge is not enough. `[review]`

## The three that cost us a round trip

All three were in the files above and were missed by not reading them:

1. `cargo-tauri.hook` already installs the bundle — a hand-written `installPhase` meant its own
   install step was pointed at the wrong directory (`buildAndTestSubdir` was unset).
2. Nothing else in nixpkgs unpacked a `.deb` by hand: 70 packages use `cargo-tauri`, 0 use
   `dpkg-deb`. A trick nobody else uses is a diagnosis, not a technique.
3. New by-name packages need `__structuredAttrs = true;`. nixpkgs-vet says so in one line.

The general form of all three: **read `doc/hooks/` and grep `pkgs/by-name` for the same kind of
package before concluding anything is impossible**, and check the by-name list before calling a
package done.
