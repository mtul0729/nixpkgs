# Opening upstream PRs from this fork

Scope: every pull request this fork sends to NixOS/nixpkgs — version bumps, packaging reworks,
new packages, removals. What is decided here is the *procedure*; which packages go through it and
how each change is split are inputs the human provides.

`pkg/*` branches carry packages. They feed CI and sysadmin; they are not PR vehicles. The two
purposes want different bases — CI needs `nixos-unstable`, a PR needs `upstream/master` — so one
branch cannot serve both. **Never push `pkg/*` itself as the PR branch, and never rebase it onto
`upstream/master`.** Build a copy, push the copy.

## 1. Decide what one PR contains

- One logical unit per PR, one commit per logical unit.
- Splitting rule of thumb: changes that are *required to make a new version build or run* belong
  with the version bump; changes that stand on their own — offline assets, vendored data, closure
  shrinking, a rework of how the package is assembled — are separate PRs.
- Whether to split is a human decision. Whoever prepares the change lays out the units, the
  human chooses.
- A branch that carries several units still goes out as one PR when the human says so; the commit
  body then has to account for each one.

## 2. Pick the base branch

- `master` by default.
- `staging` when the change causes a mass rebuild — ofborg's rebuild labels are the signal, 500+
  is the rule of thumb and 1000+ means it belongs there.
- Never target `staging-next`.
- `nixos-unstable` and `master` are not rivals here: `nixos-unstable@upstream` is an ancestor of
  `master@upstream` (`git merge-base --is-ancestor` proves it), so re-basing a fork change onto
  master is a re-base, not a rewrite.
- Backporting to a release branch is a separate step *after* the merge, and only for changes
  acceptable for releases (CONTRIBUTING.md, *Changes acceptable for releases*).

## 3. Before touching anything

Upstream's *Automation/AI policy* (`CONTRIBUTING.md`) governs everything headed upstream:

- **A responsible person must be in the loop** and must have reviewed the change before it is
  submitted. No PR goes out — not even a draft — before the human has read the diff.
- **Non-trivial automation must be disclosed.** For LLM tooling used on commits that means an
  `Assisted-by:` trailer naming at least the tool and the primary model, name and version.
  `Co-authored-by:` does not satisfy the policy.
- **The PR summary discloses separately** — the commit trailer does not cover it — and so does
  every later comment or review posted on the PR.
- **Exempt:** `nix-update`, r-ryantm, the CI bots and other maintainer-approved bots. AI used
  only for research, testing or debugging is out of scope as long as none of its output lands in
  the commit.

## 4. Build the copy

```bash
jj git fetch --remote upstream --branch master   # upstream fetch is pinned to nixos-unstable; -b overrides it
jj file show -r 'master@upstream' 'pkgs/by-name/<sh>/<pkg>/package.nix'   # has upstream already got it?
```

```bash
jj duplicate -r 'nixos-unstable@upstream..pkg/<name>' --onto 'master@upstream'
JJ_USER=<you> JJ_EMAIL=<you@example.com> jj metaedit -r <copy> --update-author -m '<pkg>: <old> -> <new>'
```

Duplicate the **range**, not the tip: `-r <tip>` drops earlier commits. Roots land on `--onto`
and the rest stack in the original order, so history survives intact. Name the branch directly
(`pkg/<name>`) rather than matching by pattern — most `pkg/*` branches live only on `origin`, so
pattern matching needs `remote_bookmarks(glob:"pkg/*")`, which is what `revsets.log` uses.

The author has to be the person who will stand behind the PR. `jj describe` cannot change it — it
refreshes the committer and leaves the author alone — so use `jj metaedit`, which changes metadata
without touching content:

- `--update-author` takes the configured user; `JJ_USER`/`JJ_EMAIL` override it (also `--config
  user.name` / `--config user.email`).
- `--author 'Name <email>'` sets it directly, no environment needed.
- Add `--update-author-timestamp` only if the timestamp should move too; by default it is kept.
- `-m` sets the message in the same call, so one `metaedit` fixes author and message together.
- Skip the author flag entirely when the fork commit is already authored by the person submitting.

The copy is decoupled from the original: later bot pushes to `pkg/*` do not move the PR, and work
on the PR does not disturb what CI consumes. Confirm it afterwards:

```bash
jj diff -r <copy> -s                      # complete change
jj log -r 'master@upstream..<copy>' -T 'separate(" ", commit_id.short(), author.name(), author.email())'
                                          # complete history, and a human author
```

## 5. Verify before pushing

- Formatting: `nix fmt` — CI enforces nixfmt.
- Evaluate without IFD: `nix-instantiate --eval --strict --option allow-import-from-derivation
  false -A <attr>.drvPath`. A package that needs IFD is silently dropped by `nixpkgs-review` and
  never reaches the cache.
- Build it, and run the binaries from `./result/bin`, with sandboxing enabled.
- Dependent packages and the other platforms: `gh workflow run review.yml -R
  mtul0729/nixpkgs-review-gha -f pr=<n>`, limited to what `meta.platforms` claims.
- If something does not build, leave the branch alone and report it. Never disable a check to
  make CI green.

## 6. The commit message

- Subject forms: version bump `<pkg>: <old> -> <new>`; new package `<pkg>: init at <version>`;
  anything else `<pkg>: <what>`. No trailing period.
- Body: why, not what. A bump names the attribute, both versions, and points at the changelog.
- Adding yourself to `maintainer-list.nix` is its own commit — `maintainers: add <handle>` —
  placed before the package commit.
- Major or breaking package changes get an entry in `doc/release-notes`.
- Then the trailer, unless the change came from an exempt bot. The policy requires the tool name
  and the primary model name and version:

```
Assisted-by: <tool> <version> (model <name>)
```

Fill it in for whatever produced the change — the policy asks for the primary model name and
version, not a generic label, so it has to match the run that actually did the work.

## 7. Submit

```bash
jj git push --named pr/<pkg>-<ver>=<copy> --remote origin
gh pr create --repo NixOS/nixpkgs --base <master|staging> --head mtul0729:pr/<pkg>-<ver> --draft
```

The PR summary discloses the automation separately — the commit trailer does not cover it. One
sentence is enough:

```
Prepared with <tool> <version> (model <name>); reviewed before submission.
```

Fill the template checkboxes with what actually happened, link related issues, and leave it draft
until the human has reviewed it.

## 8. After the merge

- `jj bookmark delete` and `jj abandon` the copy.
- Backport only if the human wants the change in a release.
- `branches.txt`: leave it alone. Dropping the line afterwards is a human decision.
- A green run does not prove substitutability — compare the store path's `.narinfo` on
  `mtul.cachix.org`.

