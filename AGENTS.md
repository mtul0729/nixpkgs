# AGENTS.md

Rules for agents working in this fork. `nixpkgs-ci/README.md` explains the design; this
file is the checklist. Nothing here overrides upstream nixpkgs policy for package code —
it only describes how this fork is operated.

## Read the docs before designing

Two redesigns this month could have been avoided by reading the documentation first.
Before proposing a structure change, an update mechanism or a CI workaround, read:

- `pkgs/README.md` — packaging rules, and the *Automatic package updates* section that
  describes `passthru.updateScript`
- `pkgs/by-name/README.md` — what the by-name structure requires, and when moving a
  package there is appropriate
- `doc/stdenv/passthru.chapter.md` — `passthru.updateScript` and the other passthru hooks
- `doc/contributing/` — review and PR conventions

If the documentation already covers the case, follow it. Do not invent a workaround around
a tool's limitation — ours or upstream's — before checking whether the documented
mechanism exists. The same goes for tool behaviour: read `--help` or the source instead of
assuming. `nix-update`'s inability to bump a path-based `src` was established that way,
after two wrong guesses.

## Invariants

- `master` carries only CI files and documentation, never package code. It may hold
  more than one commit; what matters is that it stays based on current `nixos-unstable`,
  which CI redoes hourly. Add commits normally (`jj new master@origin`, edit, push)
  instead of rewriting a single amended commit.
- Package code never goes on `master`. One topic branch per package.
- **A topic branch's base must be the same branch the pipeline uses** (`nixos-unstable`).
  A branch cut from `master` makes `merge-base` collapse to the upstream tip, so the
  update bot sees every package upstream changed since then and pushes them onto your
  branch. This has happened twice.
- Personal files belong in `nixpkgs-ci/`. Do not touch upstream's `ci/` directory.
- Every upstream workflow is already `disabled_manually`. Do not re-enable any of them;
  `nixpkgs-ci` is the only one meant to run.

## Working on master

`master` exists to carry the CI workflow, `branches.txt` and this documentation. Nothing
consumes its commits: `integration` is built from `nixos-unstable` plus the topic
branches, and those branches do not descend from `master`.

Change it by appending:

```bash
jj new master@origin -m "<what and why>"
# edit
jj git push -b master        # or: git push <sha>:refs/heads/master
```

That is a fast-forward; no `--force`, no rewriting of earlier commits. CI rebases the
whole stack onto the current `nixos-unstable` once an hour, so if upstream moved under
you the rebase happens there — or locally with `jj rebase -d upstream/nixos-unstable`.

Do not squash the history into one commit, and do not amend published commits here. Each
rule in this file and in `nixpkgs-ci/README.md` earned its own commit for a reason;
collapsing them loses the why, and rewriting a remote commit means force-pushing, which
has already cost us stale-lease failures and a lost morning.
## Branch hygiene

Before pushing anything to a topic branch, check what the bot will think belongs to it:

```bash
base=$(git merge-base upstream/nixos-unstable <branch>)
git diff --name-only --diff-filter=AM "$base" <branch> -- 'pkgs/by-name/*/*/package.nix'
```

A package branch lists one or two paths. Hundreds means the branch predates the
`nixos-unstable` base and has to be rebuilt:

```bash
GIT_INDEX_FILE=/tmp/idx git read-tree 09063bd1          # current nixos-unstable tip
git ls-tree -r <branch> -- pkgs/by-name/<shard>/<name> \
  | while read -r mode type sha path; do
      GIT_INDEX_FILE=/tmp/idx git update-index --add --cacheinfo "$mode,$sha,$path"; done
GIT_INDEX_FILE=/tmp/idx git write-tree     # -> tree
git commit-tree <tree> -p 09063bd1 -m "<pkg>: <version>"
```

Then force-push the new commit with `--force-with-lease=refs/heads/<branch>:<old sha>`.
Any extra files the branch needs (an alias removed from `pkgs/top-level/aliases.nix`, a
patch) must be added to the index the same way — copying only `pkgs/by-name/...` silently
drops them. `magpie` needs upstream's throw-alias for the removed magnifier deleted.

## Adding or changing a package

1. Start from `nixos-unstable@upstream` and add only `pkgs/by-name/<shard>/<name>/`
   (package.nix plus helper files). Never copy an existing nixpkgs package under a
   different name.
2. Declare `passthru.updateScript = nix-update-script { ... };`, or the bot ignores the
   package forever. `extraArgs` only when the feed needs it: `--version-regex` for tag
   lists polluted with non-version tags, `--version=branch=<branch>` for commit tracking.
3. Verify, all three:

   ```bash
   nix-instantiate --eval --strict --option allow-import-from-derivation false -A <pkg>.drvPath
   nix-build -A <pkg> --no-out-link
   nix-instantiate --eval --strict --raw -A <pkg>.cargoDeps.vendorStaging.outputHash  # Rust
   ```

4. Add the branch to `nixpkgs-ci/branches.txt` on `master` **only after it exists on the
   fork** — `integrate` fetches every listed branch and fails hard if one is missing.
5. Push the branch, then `gh workflow run nixpkgs-ci.yml -R mtul0729/nixpkgs -f only=<branch>`.

Push without touching the remote configuration or moving bookmarks:

```bash
git push --force-with-lease=refs/heads/<branch>:<old sha> \
  https://x-access-token:$(gh auth token)@github.com/mtul0729/nixpkgs.git <sha>:refs/heads/<branch>
```

### updateScript specifics

- CI has no `NIX_PATH`. A `#!nix-shell -p ...` shebang evaluates `import <nixpkgs>`
  *before* the script body, so such scripts need `-I nixpkgs=.` in the shebang (see
  `pkgs/by-name/he/helix/update.sh` and `generate_grammars.py`). `nix-update` also
  defaults `--file` to `<nixpkgs>`; pass `--file .` explicitly.
- A fast path is allowed and wanted: compare the pinned rev with `git ls-remote` and exit
  before the expensive part. helix does this; without it every hourly run paid for
  prefetching every grammar only to report `already at`.

## Hard bans

- **No import-from-derivation.** `nix eval --option allow-import-from-derivation false`
  must produce a `.drvPath`. A package that needs IFD is silently dropped by
  `nixpkgs-review` (no warning, exit 0) and never lands in the cache. The usual cause is
  `cargoLock.lockFile = "${finalAttrs.src}/..."`; use `cargoHash`.
- **No new attribute name that shadows upstream.** To change an existing package, modify
  it on the branch; the bot sees those because the update job diffs with
  `--diff-filter=AM`. Do not add a parallel `<name>-git` attribute.
- **Never push `integration` by hand**, and never push `master` with `GITHUB_TOKEN` — it
  needs `PUSH_TOKEN`.
- **Never disable a check to make CI green.** If a package does not build, leave the
  branch untouched and report it.

## Changing a package's shape is the last resort

When a package does not fit the pipeline, fix the pipeline side first. This bot exists to
serve nixpkgs conventions, not the other way around: a diff that reorganises a package so
a script can find it is a red flag for a reviewer and for future you.

Order of preference:

1. **Declare the attribute.** A `branches.txt` line may name its packages, e.g.
   `pkg/activitywatch: aw-server-rust`. That is all a package outside `pkgs/by-name/`
   needs in order to be seen.
2. **Write an update script.** `passthru.updateScript = ./update.sh` is the documented
   mechanism for "the default heuristics cannot edit this correctly" (see
   `pkgs/README.md`, *Automatic package updates*). A shared `sources` fetch with a
   path-based `src` is exactly that case: `nix-update` can rewrite `version` but has no
   `outputHash` to bump, so the script has to do the hashes.
3. **Change the structure** only when it stands on its own merits. Moving an existing
   package into `pkgs/by-name` is optional — `pkgs/by-name/README.md` describes it as a
   way to opt into automerge, and says `callPackage` definitions in `all-packages.nix`
   with custom arguments must not be removed. "My bot cannot see it otherwise" is not a
   reason, and removing the attribute from `all-packages.nix` can break `.override`.

Before touching a package's layout, read `pkgs/README.md` (*Automatic package updates*)
and `pkgs/by-name/README.md` first. If a change would be hard to justify in an upstream
PR, it is probably the wrong change for the fork too.
## Local environment

- The repository is large (~4.4 GB). There is no artificial memory cap, but any jj revset
  that walks upstream history is slow — the default log revset once took 57 s because of
  the remote bookmarks. **Put a `timeout` on every jj/git command** and do not iterate on
  revsets blindly.
- Repo-scoped jj config lives at the path printed by `jj config path --repo`
  (`~/.config/jj/repos/<id>/config.toml`), not in `.jj/repo/`. Set it with
  `jj config set --repo`, never by hand-editing. Current settings narrow `revsets.log`
  and restrict fetching (`remotes.upstream.fetch-bookmarks = "nixos-unstable"`),
  because a plain `jj git fetch` otherwise imports ~290 upstream branches.
- Upstream `master` is not used by the pipeline: everything, including `trunk()`, is based on `nixos-unstable`. Fetch or diff it only when preparing an upstream pull request, to check whether a change already landed.
- Do not clone the repository. If you genuinely need a working tree, `jj workspace add`
  it, and `jj workspace forget <name>` plus delete the directory afterwards — leftover
  workspaces clutter `jj log`.

## Verifying a run

```bash
gh run list -R mtul0729/nixpkgs --limit 5
gh run view <id> -R mtul0729/nixpkgs --log --job=<job id>
```

In `update` look for `branches: ...`, `updatable: [...]`, and `<pkg>: already at
<version>` or `candidate <pkg>: <old> -> <new>`. Hundreds of entries in `updatable`
mean the branch-base rule above was violated — stop and fix the branch. `update` only
pushes to `ci/<branch>`; the branch itself moves in `verify`, and a `verify` leg that
failed leaves it untouched. In `verify` the package must appear under
`this derivation will be built:`; a package missing from that list is a silent eval
failure, not a success. `integrate` only does git; the safety net is
`review-integration`, which runs after `integration` is pushed and therefore cannot block
anything — a red run there means the merged tree (or upstream) broke a package. A green
run does not prove substitutability: compare the store path's `.narinfo` on
`mtul.cachix.org`.

## About this file

Upstream's `.gitignore` ignores `/AGENTS.md`. Tracked files are unaffected by ignore
rules, so this file is committed normally; do not modify `.gitignore` for it, and if you
ever recreate the file from scratch, add it with `jj file track --include-ignored`.
