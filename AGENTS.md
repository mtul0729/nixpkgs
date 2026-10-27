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
  which CI redoes hourly. Add commits normally (`jj new master@origin`, edit, push)
  instead of rewriting a single amended commit.
- Package code never goes on `master`. One topic branch per package.
- **A topic branch must descend from the branch the pipeline uses** (`nixos-unstable`),
  not from `master`. It need not track the upstream tip: `update` builds a private
  candidate rebased onto the unstable fetched for that run, and only pushes it when a
  package actually changes. `integrate` rebases every branch when publishing.
- **`ci-failed` is a human gate.** The same candidate is never retried automatically,
  and neither moving the upstream baseline nor updating a sibling package invalidates its
  tag. Decide whether to change the package, choose a different baseline, or delete the
  tag. A successful package update is the only automatic path that moves a branch's
  baseline; otherwise a human moves it.
- Personal files belong in `nixpkgs-ci/`. Do not touch upstream's `ci/` directory.
- Every upstream workflow is already `disabled_manually`. Do not re-enable any of them;
  `nixpkgs-ci` is the only one meant to run.

## Workspaces

The repository root (`default`) is the long-lived view of the documentation on `master`.
Its `@` must remain a clean, empty descendant of `master@origin`. Other agents may be using
the same checkout concurrently, so it is never an editing surface: do not change files
there, `jj edit` a topic commit there, or run `jj new <topic>` to bring code into it.

Every edit, including an edit to `master`, happens in a dedicated jj workspace. Run
`jj st` before editing; if the checkout is not the clean empty master descendant described
above, leave it alone and create a workspace from the intended base.

```bash
# Package code: the same base the CI pipeline uses.
jj workspace add /tmp/ws-<package> -r nixos-unstable@upstream

# Documentation or CI files destined for master.
jj workspace add /tmp/ws-docs-<topic> -r master@origin
```

To continue existing work, pass its bookmark or change id to `-r` instead. In the
workspace, use `jj new` to start a new change and edit normally. After pushing a commit,
run `jj new` in that workspace before making another edit so the published commit is not
rewritten.

Remove workspaces when their work is finished:

```bash
jj workspace forget <name>
rm -rf /tmp/ws-<name>
```

After a master workspace has pushed its commits, refresh the root checkout's read-only
view without editing there:

```bash
jj git fetch
jj new master@origin
```

That keeps the root working copy on a clean empty descendant of the new `master@origin`.

## Working on master

Do not edit `master` in the root checkout. Its `@` is the clean empty view described in
*Workspaces*. Before the first edit of a session, create or enter a master workspace and
check that its `@` is not sitting on a commit that has already been pushed:

```bash
jj git fetch
jj workspace add /tmp/ws-docs-<topic> -r master@origin
cd /tmp/ws-docs-<topic>
jj new -m "<what and why>"
# edit
```

Then push and seal the change in that workspace:

```bash
jj git push -b master
jj new                       # <- see the trap below; do this before any further edit
```

`master` exists to carry the CI workflow, `branches.txt` and this documentation. Nothing
consumes its commits: `integration` is built from `nixos-unstable` plus the topic
branches, and those branches do not descend from `master`.

A trap in that sequence: `jj describe` does not publish, and `jj git push` does not seal
the change — `@` is still on it. An edit after the push rewrites the commit that is
already on `master`, the next push reports `move sideways from <old> to <new>` instead of
moving forward, and the change id starts rendering as `(divergent)`. It happened here:
two rounds of follow-up edits went into a change already sitting on `master`, and
`master` had to move sideways to take them. Run `jj new` right after pushing; whatever
you spot later goes into its own commit, which is what the paragraph below asks for
anyway.

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

1. Start from `nixos-unstable@upstream` and add only `pkgs/by-name/<shard>/<name>/`
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

- The repository is large (~4.4 GB). There is no artificial memory cap, but any jj revset
  that walks upstream history is slow — the default log revset once took 57 s because of
  the remote bookmarks. **Put a `timeout` on every jj/git command** and do not iterate on
  revsets blindly.
- **The clone is partial and shallow, and jj cannot fill it in.** `remote.upstream` is a
  promisor remote with `partialclonefilter = blob:none`, and `.git/shallow` carries ~11.8k
  boundaries. jj's git backend does not fetch promisor blobs lazily, so anything whose tree
  has not been materialised fails with `Object … of type file not found`: `jj file show -r
  <rev>`, `jj new <rev>`, and rebasing a branch onto a freshly fetched upstream commit all
  break this way. Check `git config --get remote.upstream.partialclonefilter` before planning
  to check out a new base. To put a commit on a tree jj cannot materialise, build it with git
  plumbing (`read-tree`, `update-index --cacheinfo`, `commit-tree`, `update-ref`) and run
  `jj git import` afterwards. Do not add `--depth=1` to a fetch: `blob:none` already limits
  what is downloaded, and the cut leaves a new shallow root that a later plain fetch will not
  remove — `git rev-list --max-parents=0` shows it, and only `--unshallow` undoes it.
- Repo-scoped jj config lives at the path printed by `jj config path --repo`
  (`~/.config/jj/repos/<id>/config.toml`), not in `.jj/repo/`. Set it with
  `jj config set --repo`, never by hand-editing. Current settings narrow `revsets.log`
  and restrict fetching (`remotes.upstream.fetch-bookmarks = "nixos-unstable"`),
  because a plain `jj git fetch` otherwise imports ~290 upstream branches.
- **Builds belong to CI; do not compile locally.** `nixpkgs-ci` builds every attribute a branch declares
  and puts the result in `mtul.cachix.org`, so local work is evaluation, not building. Where a store
  path is supposed to exist already, `nix-build … --max-jobs 0` proves it: that substitutes or fails
  instead of quietly starting a local build. If the path is missing, trigger the workflow — do not
  fall back to compiling.
- Upstream `master` is not used by the pipeline: everything, including `trunk()`, is based on `nixos-unstable`. Fetch or diff it only when preparing an upstream pull request, to check whether a change already landed.
- Do not clone the repository. If you genuinely need a working tree, `jj workspace add`
  it, and `jj workspace forget <name>` plus delete the directory afterwards — leftover
  workspaces clutter `jj log`.

## Working with jj (not git)

Branches, commits and pushes go through jj. Do not reach for the git equivalent (new branch +
cherry-pick) — it produces the wrong shape in this repo. Two rules:

- **Express intent as a revset before hunting for a sha.** `nixos-unstable@upstream..pkg/<name>`
  means "what this branch adds over its base" and follows fetches; a copied commit id like
  `09063bd1` is a frozen position that goes stale.
- **Pushing.** `jj git push --named <name>` needs the `NAME=REVISION` form — `--named
  pr/<pkg>-<ver>=@`; a bare name is an error. To push an existing branch, use `-b <bookmark>`, and
  if that branch exists on the remote but is not tracked locally, jj refuses with `Non-tracking
  remote bookmark <branch>@origin exists`: `jj bookmark track <branch>@origin` first, then `-b`.
- **Use jj wherever jj can do the job; reach for `git` only for what it genuinely cannot do.**
  Mixing them is what makes jj's remote view stale: after a `git push`, `jj git push` refuses
  with `references unexpectedly moved on the remote (reason: stale info)` until a
  `jj git fetch`. So prefer `jj git push` / `jj git fetch` / `jj bookmark`; use git only for the
  handful of things with no jj equivalent (a raw `git merge-base --is-ancestor` check, `git
  rev-parse` for a sha another tool needs), and fetch afterwards if you pushed.
- **Look syntax up, do not recall it.** jj moves fast: `jj <cmd> --help` and
  `jj help -k revsets|glossary|bookmarks|config` are the authority, and a flag that existed in one
  version is gone in the next.

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
ever recreate the file from scratch, add it with `jj file track --include-ignored`.
