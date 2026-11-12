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

`nixpkgs-ci/nixpkgs-conventions.md` is a summary of the ones above that we have actually needed,
with pointers back to them. It is a map, not a substitute: when it and an upstream file disagree,
the upstream file is right.

If the documentation already covers the case, follow it. Do not invent a workaround around
a tool's limitation — ours or upstream's — before checking whether the documented
mechanism exists. The same goes for tool behaviour: read `--help` or the source instead of
assuming. `nix-update`'s inability to bump a path-based `src` was established that way,
after two wrong guesses.

The same rule covers **how a package is built**, not only how it is structured:

- `doc/hooks/` — every setup hook documents the phases it already provides in
  `<name>.section.md`, with the implementation in the `hook.sh` beside it. A hand-written
  `installPhase` usually means the hook's own install step was missed or pointed at the wrong
  directory, not that the hook is broken.
- `doc/languages-frameworks/` — the conventions for each ecosystem.
- **Compare with the corpus before concluding that something is impossible.**

  ```bash
  grep -rl '<hook or framework>' pkgs/by-name --include=package.nix
  ```

  A trick that no other package uses is evidence the diagnosis is wrong, not that everyone
  else missed it. Run this check when the package is written, and run it again before it is
  proposed upstream.

## Invariants

- `master` carries only CI files and documentation, never package code. It may hold
  more than one commit; what matters is that it stays based on current `nixos-unstable`,
  which CI redoes hourly. Add commits normally instead of rewriting a single amended
  commit.
- Package code never goes on `master`. One topic branch per package.
- **A topic branch must descend from the branch the pipeline uses** (`nixos-unstable`),
  not from `master`. It need not track the upstream tip: `update` builds a private
  candidate rebased onto the unstable fetched for that run, and only pushes it when a
  package actually changes. `integrate` squashes each branch into one generated commit
  when publishing; it never rewrites the topic branch's own history.
- **`ci-failed` is a human gate.** The same candidate is never retried automatically,
  and neither moving the upstream baseline nor updating a sibling package invalidates its
  tag. Decide whether to change the package, choose a different baseline, or delete the
  tag. A successful package update is the only automatic path that moves a branch's
  baseline; otherwise a human moves it.
- Personal files belong in `nixpkgs-ci/`. Do not touch upstream's `ci/` directory.
- Every upstream workflow is already `disabled_manually`. Do not re-enable any of them;
  `nixpkgs-ci` is the only one meant to run.

## Worktrees

The repository root is the long-lived view of the documentation on `master`. It must stay
a clean checkout of `origin/master` with `master` checked out. Other agents may be using
the same checkout concurrently, so it is never an editing surface: do not change files
there, do not commit there, and do not check out a topic branch there.

Every edit, including an edit to `master`, happens in a dedicated git worktree. Run
`git status --short` before editing; if the checkout is not clean, leave it alone and
create a worktree from the intended base.

```bash
# Package code: the same base the CI pipeline uses.
git fetch upstream
git worktree add /tmp/ws-<package> -b pkg/<name> upstream/nixos-unstable

# Documentation or CI files destined for master.
git fetch origin master
git worktree add /tmp/ws-docs-<topic> -b docs/<topic> origin/master
```

To continue existing work, check its branch out into a worktree instead of creating one:

```bash
git fetch origin <branch>
git worktree add /tmp/ws-<name> <branch>
```

Commit in the worktree as usual. There is no separate "seal" step: once a commit is
pushed it is published, and anything spotted later goes into a new commit. Remove a
worktree when its work is finished:

```bash
git worktree remove /tmp/ws-<name>     # add --force if it holds ignored build output
```

After a master worktree has pushed its commits, refresh the root checkout's read-only
view without editing there:

```bash
git fetch origin master
git merge --ff-only origin/master      # run in the root checkout
```

That keeps the root working copy on the current `origin/master`.

## Working on master

Do not edit `master` in the root checkout. It is the clean view described in *Worktrees*.
Before the first edit of a session, create a master worktree from the current remote tip:

```bash
git fetch origin master
git worktree add /tmp/ws-docs-<topic> -b docs/<topic> origin/master
cd /tmp/ws-docs-<topic>
# edit
git commit -m "<what and why>"
git push origin HEAD:master
```

`master` exists to carry the CI workflow, `branches.txt` and this documentation. Nothing
consumes its commits: `integration` is built from `nixos-unstable` plus the topic
branches, and those branches do not descend from `master`.

That push is a fast-forward; no `--force`, no rewriting of earlier commits. CI rebases the
whole stack onto the current `nixos-unstable` once an hour and force-pushes its result, so
if upstream moved under you the rebase happens there — or locally with `git rebase
upstream/nixos-unstable` before pushing.

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

## Talking to upstream

`pkg/*` branches carry packages — they feed CI and sysadmin, they are not PR vehicles. Do not
push `pkg/*` as the PR branch and do not rebase it onto `upstream/master`: build a copy and push
that.

Upstream is not only PRs — comments on other people's PRs and issues are part of it, and they
carry the same disclosure requirements as a commit. Search before any of them. The procedure —
opening a PR, coordinating on someone else's, issues — is in
[`nixpkgs-ci/upstream.md`](./nixpkgs-ci/upstream.md); what nixpkgs requires of the package and
the commit itself is in [`nixpkgs-ci/nixpkgs-conventions.md`](./nixpkgs-ci/nixpkgs-conventions.md).
Read both before starting.

## Adding or changing a package

1. Start from `upstream/nixos-unstable` and add only `pkgs/by-name/<shard>/<name>/`
   (package.nix plus helper files). Never copy an existing nixpkgs package under a
   different name.
2. Declare `passthru.updateScript = nix-update-script { ... };`, or the bot ignores the
   package forever. `extraArgs` only when the feed needs it: `--version-regex` for tag
   lists polluted with non-version tags, `--version=branch=<branch>` for commit tracking.

   **Do not bump the version by hand.** Push the branch with the update script and let
   `update.yml` do it: the bot runs `nix-update` against the `nixos-unstable` it is about to
   build on, and only pushes what it built. A hash computed locally against an older base can
   mismatch once upstream moves — a cargo update changes the vendor staging hash, and the build
   then fails on a value nobody touched.

   The exception is a bump that also changes how the package is built — a new dependency, a
   different build system, a patch that has to be regenerated. The bot cannot make that edit, so
   the change is hand-made; then compute the hashes on the base CI will use (fetch
   `nixos-unstable` first and rebase onto it), not on whatever the checkout happened to be at.
3. Verify, all three:

   ```bash
   nix-instantiate --eval --strict --option allow-import-from-derivation false -A <pkg>.drvPath
   nix-build -A <pkg> --no-out-link
   nix-instantiate --eval --strict --raw -A <pkg>.cargoDeps.vendorStaging.outputHash  # Rust
   ```

4. Add the branch to `nixpkgs-ci/branches.txt` on `master` **only after it exists on the
   fork** — `integrate` fetches every listed branch and fails hard if one is missing.
5. Push the branch, then `gh workflow run update.yml -R mtul0729/nixpkgs -f only=<branch>`.

Push without touching the remote configuration:

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
- For a tag-based `fetchFromGitHub` consumed by the default `nix-update-script`, use
  `rev = "v${version}"` rather than `tag = ...` while CI runs `nix-update` 1.16.0. The
  `tag` spelling exposes `refs/tags/vX` as `rev`, which 1.16.0 compares with the feed's
  `vX` and treats as changed on every no-op run. See `nixpkgs-ci/README.md`.

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
- **Never disable a check to hide a build failure.** If a package does not build, leave
  the branch untouched and report it. `doCheck = false` is the deliberate fork policy
  for `pkg/*` branches; see *Tests on `pkg/` branches* in `nixpkgs-ci/README.md`. A PR
  branch must meet upstream's test requirements.
- **Never turn a `pkg/*` branch into the PR branch** — not by pushing it as-is, not by
  rebasing it onto `upstream/master`. Build a copy (see *Talking to upstream*).

## Changing a package's shape is the last resort

When a package does not fit the pipeline, fix the pipeline side first. This bot exists to
serve nixpkgs conventions, not the other way around: a diff that reorganises a package so
a script can find it is a red flag for a reviewer and for future you.

Order of preference:

1. **Declare the attribute.** A `branches.txt` line may name its packages, e.g.
   `pkg/activitywatch: aw-server-rust`. Several are comma-separated (`pkg/x: a,b`), not
   space-separated — the workflow splits on commas. List every attribute the branch owns:
   discovery otherwise only sees `pkgs/by-name/*/*/package.nix` paths that the diff touches,
   so a branch whose update writes only a sibling file (`channels.json`) names its packages
   here. That is all a package outside `pkgs/by-name/` needs in order to be seen.
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

- The repository is large (several GB of packfiles) and full-history walks are slow. **Put a
  `timeout` on every git command**, scope `git log` with a range or `-n`, and do not
  iterate on `git log --all` blindly.
- **The clone is partial, but its commit history is complete.** Both remotes are promisor
  remotes with `partialclonefilter = blob:none`, so blobs are fetched on demand and
  `git show`, `git checkout` or a rebase that needs a new tree costs network. The old
  `.git/shallow` (11.8k boundaries from past `--depth=1` fetches) was removed on
  2026-11-12: with those boundaries every fetch sent the whole list and GitHub spent
  minutes computing the pack, which looked like a hang. Keep it that way — `test ! -e
  .git/shallow` and `git rev-list --max-parents=0 <rev>` both succeed today. Never add
  `--depth=1`: the cut leaves a new shallow root that a later plain fetch does not remove,
  and only `--unshallow` undoes it.
- Fetching is restricted in `.git/config`: `upstream` maps only `nixos-unstable`
  (`remote.upstream.fetch = +refs/heads/nixos-unstable:refs/remotes/upstream/nixos-unstable`),
  because a plain `git fetch --all` otherwise pulls ~290 upstream branches. Set local
  config with `git config --local`, never by hand-editing `.git/config`.
- **Builds belong to CI; do not compile locally.** `nixpkgs-ci` builds every attribute a branch declares
  and puts the result in `mtul.cachix.org`, so local work is evaluation, not building. Where a store
  path is supposed to exist already, `nix-build … --max-jobs 0` proves it: that substitutes or fails
  instead of quietly starting a local build. If the path is missing, trigger the workflow — do not
  fall back to compiling.
- Upstream `master` is not used by the pipeline: everything is based on `nixos-unstable`.
  Fetch or diff it only when preparing an upstream pull request, to check whether a change
  already landed.
- Do not clone the repository. If you genuinely need a working tree, `git worktree add`
  it, and `git worktree remove` it afterwards — leftover worktrees show up in
  `git worktree list` and hold branches that look live.

## Working with git

Branches, commits and pushes go through plain git. A few conventions keep the shape right:

- **Express intent as a range before hunting for a sha.** `upstream/nixos-unstable..pkg/<name>`
  means "what this branch adds over its base" and keeps working after a fetch; a copied
  commit id like `09063bd1` is a frozen position that goes stale.
- **Pushing.** Push a new branch with an explicit refspec that keeps the local name:
  `git push origin HEAD:refs/heads/pkg/<name>`. To update an existing branch after a
  rebase, use `--force-with-lease=refs/heads/<name>:<old sha>`, never a bare `--force`.
  If the branch exists on the remote but not locally, `git fetch origin <branch>` first.
- **Rebasing onto a new base.** `git rebase --onto upstream/nixos-unstable <old base>
  pkg/<name>`, or plain `git rebase upstream/nixos-unstable` when the branch is already
  based on that tip. Never rebase a branch whose tip has been published as a PR without
  the force-with-lease form above.
- **Look syntax up, do not recall it.** `git help <command>` is the authority.

## Verifying a run

```bash
gh run list -R mtul0729/nixpkgs --limit 5
gh run view <id> -R mtul0729/nixpkgs --log --job=<job id>
```

In `update` look for `branches: ...`, `updatable: [...]`, and `<pkg>: already at
<version>` or `pushed <pkg>: <old> -> <new>`; a leg that built and pushed is the only
thing that moves a branch. `already at` does not push a refreshed baseline. Hundreds of
entries in `updatable` mean the branch-base rule above was violated — stop and fix the
branch. `ci-failed/<branch>/<pkg>/<content-hash>` tags are the backoff record. The hash
covers the package version and its definition directory's effective diff from upstream,
not the baseline tree or a sibling package's changes, so neither a new `nixos-unstable`
commit nor another package updating bypasses a human decision. Retrying the same candidate
requires deleting that exact tag:

```bash
git push <fork> :refs/tags/ci-failed/<branch>/<pkg>/<content-hash>
```

In `integrate`, `will build: ...` lists the attributes the merged branches carry — a
package missing from that list was never checked. A green run does not prove
substitutability: compare the store path's `.narinfo` on `mtul.cachix.org`.

## About this file

Upstream's `.gitignore` ignores `/AGENTS.md`. Tracked files are unaffected by ignore
rules, so this file is committed normally; do not modify `.gitignore` for it, and if you
ever recreate the file from scratch, add it with `git add -f AGENTS.md`.
