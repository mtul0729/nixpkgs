# Upstream: PRs, comments and issues

Scope: how this fork sends things to NixOS/nixpkgs — pull requests, comments and reviews on
other people's PRs, and issues.

What nixpkgs requires of a package, a commit or a branch is not here; it is summarised in
[`nixpkgs-conventions.md`](./nixpkgs-conventions.md), with pointers to the upstream files that
are authoritative. Which package goes through it and how a change is split are
inputs the human provides; what is decided here is the procedure.

## Ground rules

- **Disclosure covers every kind of contribution.** Upstream's *Automation/AI policy*
  (`CONTRIBUTING.md`) applies to commits, PR summaries, comments, reviews and issues alike. A
  commit carries an `Assisted-by:` trailer; everything else — PR body, comment, review, issue —
  carries a sentence naming the tool and the primary model, name and version. `Co-authored-by:`
  does not satisfy it.
- **A responsible person reviews before anything is sent.** Nothing goes out — not a draft PR,
  not a comment — before the human has read it.
- **Check the conventions and the corpus before proposing.** A package that does something no
  other package does gets asked about it in review, and the odd part is usually a
  misdiagnosis. Read `doc/hooks/` and `doc/languages-frameworks/`, and grep `pkgs/by-name`
  for packages of the same kind. Doing it before opening the PR costs less than doing it after
  a reviewer asks — and it is the same check that should have happened when the package was
  written.
- **Verify before asserting.** Facts about upstream (tags, versions, who opened a PR, whether a
  file exists) come from `gh`, not from memory. Build URLs from a sha or ref that was checked,
  never by assembling one by hand — a guessed sha 404s.
- **State what was actually observed** — version, platform, session. Saying where and on what
  version something was seen tells the reader both why it matters and when it may no longer
  apply. Check the number right before sending: the update bot moves branches, so a version
  quoted from an hour ago can already be stale.
- **Exempt:** `nix-update`, r-ryantm, the CI bots and other maintainer-approved bots. AI used
  only for research, testing or debugging is out of scope as long as none of its output lands in
  the contribution.

## 1. Search first

Whatever the form — PR, comment or issue — look for existing work before adding to it. A
duplicate costs reviewer time for nothing:

```bash
gh search prs    --repo NixOS/nixpkgs <name> --state open
gh search prs    --repo NixOS/nixpkgs <name> --state closed --limit 15
gh search issues --repo NixOS/nixpkgs <name> --limit 15
gh pr view <n> --repo NixOS/nixpkgs        # files, review state, when it last moved
```

- An **open** PR for the same package: do not open a competing one. Go to §2 instead.
- A **closed or rejected** one is worth reading: it usually says why, and the new contribution
  has to answer that.
- Search for the **removal** too. A package upstream removed leaves a `throw` alias in
  `pkgs/top-level/aliases.nix`, and the PR that removed it usually holds the discussion.

## 2. Commenting on someone else's PR

Coordinating is the normal outcome of a search, not a consolation prize. What to bring:

- What the fork measured that they could not have: a failure on a platform they do not test, a
  first-run side effect, a fetcher or update-script trap. One item per paragraph, each with what
  it was observed on.
- Read their diff before claiming a gap. If they already do the thing, say so — "worth keeping,
  and here is why" — and raise only the delta actually found. A requirement written as though it
  were missing reads as noise to the author who has it.
- Frame it as an observation plus an offer to test — unless the reasoning is settled, in which
  case say so plainly. Do not hedge a recommendation with a justification that does not apply in
  nixpkgs: dependencies are never the constraint there, so "older distributions" is not a reason
  to choose an older toolkit or an older API.
- Link the fork's work as a **compare view** (`<base>...<head>`, both shas) rather than a blob:
  it shows the whole change, and pinning it to a sha keeps it still after the update bot moves
  the branch.
- End with the disclosure sentence.

## 3. Issues

- Search before opening one (§1). An issue is the right form when there is nothing to propose
  yet but something to establish — whether upstream wants a thing at all.
- **Close an issue we opened when we decide not to pursue it**, and leave what was learned in
  the closing comment. Something we do not intend to drive should not sit in upstream's list;
  the record still has value to whoever picks it up later. This is the default, not a special
  case.

## 4. Opening a PR

`pkg/*` branches carry packages. They feed CI and sysadmin; they are not PR vehicles. The two
purposes want different bases — CI needs `nixos-unstable`, a PR needs `upstream/master` — so one
branch cannot serve both. **Never push `pkg/*` itself as the PR branch, and never rebase it onto
`upstream/master`.** Build a copy, push the copy.

### Decide what one PR contains

- One logical unit per PR, one commit per logical unit.
- Splitting rule of thumb: changes that are *required to make a new version build or run* belong
  with the version bump; changes that stand on their own — offline assets, vendored data, closure
  shrinking, a rework of how the package is assembled — are separate PRs.
- Whether to split is a human decision. Whoever prepares the change lays out the units, the
  human chooses.
- A branch that carries several units still goes out as one PR when the human says so; the commit
  body then has to account for each one.

### Pick the base branch

- Follow the decision tree in [`nixpkgs-conventions.md`](./nixpkgs-conventions.md) — `master`,
  unless the rebuild count pushes it to `staging`.
- Never target `staging-next`.
- `nixos-unstable` and `master` are not rivals here: `nixos-unstable@upstream` is an ancestor of
  `master@upstream` (`git merge-base --is-ancestor` proves it), so re-basing a fork change onto
  master is a re-base, not a rewrite.

### Build the copy

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

### Verify before pushing

- Formatting: `nix fmt` — CI enforces nixfmt.
- Evaluate without IFD: `nix-instantiate --eval --strict --option allow-import-from-derivation
  false -A <attr>.drvPath`. A package that needs IFD is silently dropped by `nixpkgs-review` and
  never reaches the cache.
- Build it, and run the binaries from `./result/bin`, with sandboxing enabled.
- Dependent packages and the other platforms: `gh workflow run review.yml -R
  mtul0729/nixpkgs-review-gha -f pr=<n>`, limited to what `meta.platforms` claims.
- If something does not build, leave the branch alone and report it. Never disable a check to
  make CI green.

### The commit message

- Subject form, the no-trailing-period rule and the why in the body are nixpkgs rules — see
  [`nixpkgs-conventions.md`](./nixpkgs-conventions.md).
- Major or breaking package changes get an entry in `doc/release-notes`.
- Then the part specific to this fork: unless the change came from an exempt bot, the commit has
  to carry a trailer naming the tool and the primary model, name and version:

```
Assisted-by: <tool> <version> (model <name>)
```

Fill it in for whatever produced the change — the policy asks for the primary model name and
version, not a generic label, so it has to match the run that actually did the work.

### Submit

```bash
jj git push --named pr/<pkg>-<ver>=<copy> --remote origin
gh pr create --repo NixOS/nixpkgs --base <master|staging> --head mtul0729:pr/<pkg>-<ver> --draft
```

The PR summary discloses the automation separately — the commit trailer does not cover it. One
sentence is enough:

```
Prepared with <tool> <version> (model <name>); reviewed before submission.
```

Write the body **from upstream's PR template**, not in a format of our own:

```bash
gh api repos/NixOS/nixpkgs/contents/.github/PULL_REQUEST_TEMPLATE.md --jq .content | base64 -d
```

Keep its structure and its link definitions, put the summary where the comment asks for it, and
tick only what actually happened — the template asks not to be removed even when nothing is
checked, and an unticked box is information for the reviewer, not a failure. It carries a
*Follows the automation/AI policy* checkbox of its own: ticking it is a claim, so the disclosure
sentence belongs in the body for that tick to be true.

Link related issues, and leave it draft until the human has reviewed it.

### After the merge

- `jj bookmark delete` and `jj abandon` the copy.
- Backport only if the human wants the change in a release.
- `branches.txt`: leave it alone. Dropping the line afterwards is a human decision.
- A green run does not prove substitutability — compare the store path's `.narinfo` on
  `mtul.cachix.org`.
