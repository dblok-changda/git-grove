# git-cleanup

Audit, and only when you say so remove, the local Git leftovers that pile up after
feature branches and pull requests are finished: merged local branches, obsolete
worktrees, stale remote-tracking refs, and a narrow set of disposable temp files.

It is **dry-run by default**, shows the evidence behind every decision, and follows
one rule: **when in doubt, keep it.**

```text
Git Cleanup  (dry run)
────────────────────────────────────────
  Repository          /Users/me/src/my-project
  Current branch      main
  Default branch      origin/main  (origin/HEAD)
  Remote              origin  git@github.com:me/my-project.git
  Fetch               fetched origin (nothing pruned; stale refs are audited below)
  GitHub CLI          available — me/my-project (used to recognise squash/rebase-merged pull requests)

Branches
────────────────────────────────────────
  ✓ SAFE      feature/auth
    fully merged into origin/main
    Safe to remove (git branch -d)

  ✓ SAFE_PR   feature/search
    PR #412 merged (2026-02-01); local tip 6d5e560ff4 is exactly the PR head; merge commit 9c1e2a77b0 is in origin/main
    Safe to remove after explicit confirmation (git branch -D, PR #412)

  ! REVIEW    feature/api
    upstream origin/feature/api was deleted but 2 unique commit(s) remain — possibly squash-merged; cannot prove it
    Needs your review — keeping

  ! UNMERGED  experiment/cache
    3 commit(s) not in origin/main
    Keeping

Worktrees
────────────────────────────────────────
  ✓ SAFE      /Users/me/src/my-project-auth  [feature/auth]
    clean; branch feature/auth is fully merged into origin/main
    Safe to remove (git worktree remove)

  ! DIRTY     /Users/me/src/my-project-api  [feature/api]
    3 modified and 0 staged file(s)
    Keeping

Summary
────────────────────────────────────────
  Safe branches:      1  (+ 1 via merged PR, confirm each)
  Safe worktrees:     1  (+ 0 via merged PR, confirm each; 0 stale entries)
  Needs review:       1
  ...

No changes have been made.
Run with --apply to review and perform cleanup.
```

## Why not `git branch --merged | xargs git branch -d`?

That one-liner misses every squash-merged or rebase-merged branch, and the popular
alternative of deleting any branch without a same-named remote destroys unpushed work.
git-cleanup decides with Git plumbing (`git merge-base --is-ancestor`), optionally
confirms squash and rebase merges through the GitHub CLI, never trusts a branch name or
its age, re-validates every item immediately before touching it, and writes a recovery
log for everything it removes.

## Install

Requirements: Git 2.31 or newer, Bash 3.2 or newer (the macOS system Bash is fine),
macOS or Linux. Optional: the GitHub CLI (`gh`), logged in, to recognise squash and
rebase-merged pull requests.

Pick one method. Each puts a single file, `git-cleanup`, on your PATH.

**Homebrew**

```bash
brew tap dblok-changda/git-cleanup https://github.com/dblok-changda/git-cleanup
brew install dblok-changda/git-cleanup/git-cleanup
```

**One-line installer** (installs to `/usr/local/bin` if writable, otherwise `~/.local/bin`)

```bash
curl -fsSL https://raw.githubusercontent.com/dblok-changda/git-cleanup/main/install.sh | bash
```

**From a clone**

```bash
git clone https://github.com/dblok-changda/git-cleanup.git
cd git-cleanup
make install                 # or: make install PREFIX=~/.local
```

**Manually**: copy `git-cleanup` anywhere on your PATH and make it executable.

Afterwards both of these work, because Git runs any `git-<name>` found on PATH:

```bash
git-cleanup --help
git cleanup --help
```

Uninstall with `make uninstall`, `./install.sh --uninstall`, or `brew uninstall git-cleanup`.

## Getting started

From inside any repository:

```bash
git cleanup --fetch
```

That fetches the remote, audits everything, prints the report above, and changes
nothing. Read it. Items marked `REVIEW` usually come with the exact command that would
make them safe. When the report has no surprises:

```bash
git cleanup --fetch --apply
```

You get a numbered plan, one `y/N` prompt for everything that passed every SAFE check,
and a separate prompt, with evidence and a recovery command, for each item that needs a
force delete. Anything that changed since the audit is skipped automatically.

## Cheatsheet

```bash
git cleanup                       # audit only, no fetch, changes nothing
git cleanup --fetch               # audit with fresh remote state (recommended)
git cleanup --fetch -v            # same, plus the evidence behind each decision
git cleanup --fetch --temp --generated    # also scan temp files and build directories

git cleanup --fetch --apply       # plan, confirm, clean up
git cleanup --fetch --apply --yes # skip the one batch prompt for SAFE items only
```

| Flag | Effect |
|---|---|
| `--fetch` | `git fetch` first. Never prunes. Required for SAFE_PR and detached-worktree removal. |
| `--apply` | Perform cleanup after the audit. Without it nothing is ever deleted. |
| `--yes` | Skips only the batch prompt for SAFE items. Force deletes and generated dirs still ask one by one. Never relaxes a check. |
| `--temp` | Include `.DS_Store`, `*.swp`, `*.swo`, `*~`, `*.tmp`. Tracked files and copies of secrets are excluded. |
| `--generated` | List ignored `node_modules`, `dist`, `.terraform`, and similar. Each deletion needs its own `yes`. |
| `--protected PAT` | Extra protected branch glob, repeatable. Persist per repo with `git config --add cleanup.protected 'wip/*'`. |
| `--no-gh` | Skip GitHub pull-request lookups. |
| `--gh-repo OWNER/REPO` | Set the GitHub repo when it cannot be derived from the remote URL. |
| `--remote NAME`, `--default BRANCH` | Override remote or default-branch detection. |
| `-v`, `--no-color`, `--version`, `-h` | Output control and help. |

## How decisions are made

| Class | Meaning | Action under `--apply` |
|---|---|---|
| `SAFE` | Git proves the branch tip is already in the default branch. For worktrees: clean, and its branch is SAFE. | `git branch -d` (Git re-checks) or `git worktree remove` |
| `SAFE_PR` | Ancestry fails (squash/rebase merge) but a MERGED pull request has this tip as its head, its merge commit is in the freshly fetched default branch, and no local commits came after. | `git branch -D`, asked per item, never automatic |
| `STALE` | Worktree entry whose directory is gone and whose commits a branch still holds. | `git worktree remove` on the entry |
| `REVIEW` | Might be removable, cannot be proven. | Never touched |
| `UNMERGED` | Has commits not in the default branch. | Never touched |
| `DIRTY` | Uncommitted changes. | Never touched |
| `IN_USE` | Current branch, checked out elsewhere, locked, or a rebase/merge/bisect is in progress. | Never touched |
| `PROTECTED` | Default branch or matches a protected pattern. | Never touched |
| `UNKNOWN` | A check failed. | Never touched |

Stale remote-tracking refs, found only with `--fetch`, are SAFE when their commits are
in the default branch or another ref, and REVIEW otherwise.

Default protected patterns: `main master develop development staging production trunk
release/* hotfix/*`.

## What is never deleted

Stashes. `.env` and `.env.*`, credentials, keys, certificates, Terraform state,
databases, and backup or swap copies of any of those. Untracked files and ignored files
that are not recognised build output. Anything in a nested repository or submodule.
Generated directories containing tracked files or secrets. Branches or worktrees with an
operation in progress. `git clean` is never run, and `-d` never silently becomes `-D`.

## Recovery

Every removal is appended to `.git/git-cleanup.log` with a restore command, for
example:

```text
2026-09-13T22:07:45Z branch-deleted name=feature/auth tip=df179ea0...  restore: git branch feature/auth df179ea0...
```

Deleted branch tips stay in the object store until `git gc` expires them, about two
weeks by default.

## Typical workflow

1. After a batch of PRs lands, run `git cleanup --fetch --temp` in the repo.
2. Resolve `REVIEW` items by hand: move an `.env` out of a worktree, create a
   `keep/...` branch for commits you want, or delete things you know are throwaway.
3. Run `git cleanup --fetch --apply --temp`, answer the prompts.
4. If something was removed by mistake, use the restore line from the log.

## Limitations

Squash and rebase merge detection works only through GitHub via `gh` (GitHub
Enterprise included when `gh` is logged in to that host). GitLab and Bitbucket users
still get the full ancestry-based cleanup, and their squash-merged branches land in
REVIEW. One default branch is assumed; audit twice with `--default` if you merge into
two. Windows is supported only through WSL.

## Testing

```bash
make test          # builds disposable fixtures under $TMPDIR and checks about 130 assertions
make test-bash3    # same, under the macOS system bash 3.2
make lint          # shellcheck
```

The tests never touch a real repository. See [docs/reference.md](docs/reference.md)
for the full option reference, the exact rules behind each classification, the apply
and revalidation flow, and the log format.
