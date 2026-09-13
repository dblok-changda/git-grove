# git-cleanup reference

This document describes exactly what `git-cleanup` inspects, how it classifies each
item, what `--apply` does, and how to recover. For installation and a quick start see
the [README](../README.md).

## Contents

1. [Invocation and options](#invocation-and-options)
2. [Repository detection](#repository-detection)
3. [Remote state and `--fetch`](#remote-state-and---fetch)
4. [GitHub pull-request lookups](#github-pull-request-lookups)
5. [Branch classification](#branch-classification)
6. [Worktree classification](#worktree-classification)
7. [Stale remote-tracking refs](#stale-remote-tracking-refs)
8. [Temporary files](#temporary-files)
9. [Generated directories](#generated-directories)
10. [Stashes](#stashes)
11. [The apply flow](#the-apply-flow)
12. [Revalidation before each action](#revalidation-before-each-action)
13. [Recovery log](#recovery-log)
14. [Configuration](#configuration)
15. [Exit codes](#exit-codes)
16. [Portability](#portability)
17. [Extending the lists](#extending-the-lists)
18. [Test harness](#test-harness)

## Invocation and options

```text
git-cleanup [options]        (or: git cleanup [options])
```

| Option | Default | Description |
|---|---|---|
| `--apply` | off | Perform cleanup after the audit. Without it the tool is read-only. |
| `--yes`, `-y` | off | With `--apply`, skip the single batch confirmation for items that passed every SAFE check. Has no effect on per-item prompts and relaxes no check. Without a terminal, `--apply --yes` performs SAFE items and skips everything that would have asked. |
| `--fetch` | off | Run `git fetch <remote>` before analysis, with `fetch.prune` and `fetch.pruneTags` forced off. Also sets `<remote>/HEAD` if it was never set. Required for SAFE_PR, detached-worktree removal, and stale-ref handling. |
| `--no-gh` | off | Do not consult the GitHub CLI. |
| `--gh-repo SLUG` | derived | `[HOST/]OWNER/REPO` for PR lookups when the remote URL is not a recognisable GitHub URL. Still verified with `gh repo view`. |
| `--temp` | off | Scan for disposable temp files (see [Temporary files](#temporary-files)). |
| `--generated` | off | List ignored generated directories (see [Generated directories](#generated-directories)). |
| `--protected PAT` | see below | Add a protected branch glob. Repeatable, or comma-separated. |
| `--remote NAME` | `origin` or the only remote | Remote to evaluate against. Required when several remotes exist and none is `origin`. |
| `--default BRANCH` | detected | Override default-branch detection. |
| `--verbose`, `-v` | off | Print the evidence gathered for every item. |
| `--no-color` | auto | Disable colour. `NO_COLOR` in the environment does the same. |
| `--version`, `-h`, `--help` | | |

Default protected patterns: `main master develop development staging production trunk
release/* hotfix/*`, plus every value of `git config --get-all cleanup.protected`.
Patterns are shell globs matched against the full branch name.

## Repository detection

- The tool may be run from the primary worktree or any linked worktree. It records
  where it was invoked (the *current* worktree, never removable) and then operates
  from the primary worktree, which is the first entry of `git worktree list`.
- The current branch is the branch checked out where the tool was invoked. It is always
  `IN_USE`.
- Remote: `--remote`, else `origin`, else the only remote. With no remote at all the
  default branch is the local one and "merged" means merged into it.
- Default branch: `--default`, else `<remote>/HEAD`. Fallback: exactly one of `main`,
  `master`, `trunk` existing as `<remote>/<name>`, then as a local branch. If two
  candidates exist the tool stops and asks for `--default`. It never guesses.
- The reference used for "merged" is `refs/remotes/<remote>/<default>` when it exists,
  otherwise `refs/heads/<default>`. The header shows which.

## Remote state and `--fetch`

Without `--fetch`, the audit uses the remote-tracking refs as they are. That is fine
for ancestry-based `SAFE` decisions, because `git branch -d` performs Git's own merged
check again at deletion time. It is not fine for decisions that Git does not
double-check, so those require a fetch that succeeded in the same run:

- `SAFE_PR` (force delete after a merged PR),
- removal of a clean detached worktree, unless a local branch contains its HEAD,
- removal of a stale worktree entry with a detached HEAD, same exception,
- removal of stale remote-tracking refs, which are only discovered with `--fetch`.

Without a fresh fetch these items become `REVIEW` with a note saying to re-run with
`--fetch`.

The fetch itself never prunes. Stale refs are listed via `git remote prune --dry-run`
and handled as audited items, see [Stale remote-tracking refs](#stale-remote-tracking-refs).

## GitHub pull-request lookups

Used only when `gh` is installed, authenticated, and can access the repository.
The repository slug is derived from the remote URL (`https://`, `ssh://`, and
`git@host:owner/repo` forms; non-`github.com` hosts become `HOST/OWNER/REPO`) or given
with `--gh-repo`.

For each branch that fails the ancestry test, the tool runs
`gh pr list --head <branch> --state merged` and applies these rules in order:

1. The PR must report a merge commit. That commit must exist locally and be reachable
   from the default branch. This is what protects against a merge that was later undone
   by a force push, and against a stale `origin/main`. If the PR was merged into a base
   other than the default branch, the same check applies to that merge commit.
2. If the PR head equals the local tip: `SAFE_PR`.
3. Else, if the PR head commit is available locally and the local tip is an ancestor of
   it: `SAFE_PR` (every local commit was part of the PR).
4. Else, if the PR head is an ancestor of the local tip: `REVIEW`, N commits were added
   after the PR.
5. Else: `REVIEW`, the tips diverged, or the PR head is not available locally.

A `SAFE_PR` result is downgraded to `REVIEW` unless `--fetch` succeeded in this run.

## Branch classification

Applied to every local branch, in this order:

1. Current branch: `IN_USE`.
2. Default branch: `PROTECTED`.
3. Matches a protected pattern: `PROTECTED`.
4. Named in a worktree's in-progress rebase (`rebase-merge/head-name`,
   `rebase-apply/head-name`) or bisect (`BISECT_START`): `IN_USE`.
5. Merge status, independent of checkout:
   - `git merge-base --is-ancestor <tip> <default-ref>` succeeds: `SAFE`.
   - Otherwise count unique commits with `git rev-list --count <default>..<tip>` and, if
     GitHub is available, apply the PR rules above.
   - If still undecided and every unique commit is patch-equivalent to a commit already
     in the default branch (`git cherry`): `REVIEW`, probably rebase-merged.
   - If still undecided and the upstream no longer exists on the remote (`[gone]`, or a
     remote-tracking ref that `--fetch` found stale): `REVIEW`, possibly squash-merged.
   - Otherwise: `UNMERGED`.
6. If the branch is checked out in a worktree:
   - in the primary worktree: `IN_USE`;
   - in a linked worktree whose directory is missing, and the branch is SAFE or SAFE_PR:
     keeps that class; the stale entry is removed first;
   - in a linked worktree that is clean, unlocked, not the current one, has no untracked
     files, no sensitive or unrecognised ignored files, and no operation in progress,
     and the branch is SAFE or SAFE_PR: keeps that class; the worktree is removed first;
   - otherwise `IN_USE`, with the reason (uncommitted changes, untracked files, ignored
     files needing review, operation in progress).

## Worktree classification

Applied to every entry of `git worktree list --porcelain`:

| Condition | Class |
|---|---|
| Primary worktree, or bare repository entry | `PROTECTED` |
| Directory missing (prunable), branch attached | `STALE` |
| Directory missing, detached HEAD held by a local branch, or by the default branch after a fetch in this run | `STALE` |
| Directory missing, detached HEAD held by nothing | `REVIEW` with a `git branch keep/...` command |
| The worktree the tool was launched from | `IN_USE` |
| Locked | `IN_USE` |
| Rebase, merge, cherry-pick, revert, or bisect in progress | `IN_USE` |
| Status could not be read | `UNKNOWN` |
| Staged or modified files | `DIRTY` |
| Untracked files | `REVIEW` |
| Ignored files matching the sensitive pattern (`.env*`, `*.pem`, `*.key`, `*.tfstate`, `*.sqlite`, `credentials*`, `id_rsa*`, ...) | `REVIEW` |
| Ignored files or directories that are not recognised build output or temp patterns | `REVIEW` |
| Detached HEAD held by a local branch, or by the default branch after a fetch in this run | `SAFE` |
| Detached HEAD only in the default branch as last fetched | `REVIEW`, re-run with `--fetch` |
| Branch is SAFE / SAFE_PR / UNMERGED / REVIEW / PROTECTED | same class |

`git worktree remove` deletes ignored files along with the tree, which is why ignored
content is inspected. Ignored entries under recognised generated-directory names are
accepted as regenerable, but are still scanned for sensitive files. The report states
how many ignored entries would be deleted.

Removal never uses `--force`. Git itself refuses to remove a worktree with untracked or
modified files, which acts as a second line of defence.

## Stale remote-tracking refs

Only with `--fetch`. Refs reported by `git remote prune --dry-run <remote>` are
classified:

- commits reachable from the default branch: `SAFE`;
- commits reachable from any other non-stale local or remote-tracking ref: `SAFE`;
- otherwise `REVIEW`: N commits are reachable only through this ref, and the report
  shows `git branch keep/<name> <sha>` to preserve them.

A stale upstream also counts as "gone" for branch classification even though the ref
still exists locally.

Removal uses `git update-ref -d <ref> <audited-sha>`, which fails if the ref moved.

## Temporary files

Only with `--temp`. Candidates are taken from `git ls-files --others`, so only files
Git considers untracked in the primary worktree are considered. Tracked files never
qualify, whatever their name. Nested repositories, submodules, and linked worktrees
inside the tree appear as opaque directories and are never entered. `node_modules` is
skipped for speed.

Matching rules, by file name:

| Rule | Pattern |
|---|---|
| macOS Finder metadata | `.DS_Store` |
| Vim swap file | `*.swp`, `*.swo` |
| Editor backup | `*~` |
| Temporary file | `*.tmp` |

Held as `REVIEW` instead of offered:

- the name with its temp suffix removed matches the sensitive pattern (for example
  `.env~`, `.env.swp`, `credentials.tmp`), since such copies contain the secrets;
- a swap or `.tmp` file modified in the last 24 hours, which may belong to an open
  editor session or a running process.

Symlinks are never removed. Tracked files that merely look temporary are listed so you
know they were seen.

## Generated directories

Only with `--generated`, and always listed rather than deleted. Names recognised:
`node_modules dist build coverage .terraform .cache .parcel-cache .next .nuxt .turbo
__pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .gradle target`.

Discovery goes through `git ls-files --others --directory`, so a directory is offered
only when it is:

- ignored by Git (`git check-ignore`),
- free of tracked files,
- free of any nested `.git`,
- free of sensitive-looking files (a `.terraform` holding `terraform.tfstate`, or a
  cache holding a `.key`, is listed as `REVIEW` and kept).

Under `--apply` every generated directory asks individually, even with `--yes`, and
all four conditions are re-checked immediately before `rm -rf`.

## Stashes

Always listed, never removed. Each stash made on a branch that is a removal candidate
is flagged so you can inspect it before cleaning up.

## The apply flow

1. The audit runs and the full report is printed, exactly as in dry-run mode.
2. A numbered **cleanup plan** is printed, in execution order:
   1. SAFE worktrees, then SAFE_PR worktrees (asks first),
   2. STALE worktree entries,
   3. SAFE branches (`git branch -d`), then SAFE_PR branches (asks first, `git branch -D`),
   4. SAFE stale remote-tracking refs,
   5. temp files (one step),
   6. generated directories (each asks first).
3. **One batch prompt** covers every item that does not ask individually. `--yes`
   answers it. Declining aborts with nothing changed.
4. **Per-item prompts** show the evidence and a recovery command. Without a terminal
   these items are skipped, never assumed.
5. Each step prints progress, `[3/11] Removing branch feature/auth ...... ✓`, and on
   failure Git's own message. A `git branch -d` refusal is reported and never escalated.
6. `Ctrl-C` stops before the next step; completed steps are already in the log.

## Revalidation before each action

Immediately before touching an item the tool re-checks it and skips it with a reason
if anything changed:

| Item | Checks repeated |
|---|---|
| Branch | still exists; tip SHA unchanged; not checked out anywhere; still an ancestor of the default ref (SAFE) or the PR head and merge-commit conditions still hold and the fetch was fresh (SAFE_PR) |
| Worktree | directory exists; still registered; HEAD unchanged; same branch (or still detached); no operation in progress; status still clean; branch tip unchanged and merge/PR predicate still holds; detached HEAD still held |
| Stale worktree entry | directory still missing; still registered; HEAD unchanged; branch still exists or detached HEAD still held |
| Stale remote ref | ref exists; SHA unchanged (also enforced by `git update-ref -d` with the old value); commits still held elsewhere |
| Temp file | still a regular file; still untracked; still matches its rule; not a sensitive copy; not modified in the last 24 hours |
| Generated directory | still a directory; still ignored; no tracked files; no nested repository; no sensitive files |

## Recovery log

Every removal appends one line to `<git-common-dir>/git-cleanup.log`, normally
`.git/git-cleanup.log`:

```text
2026-09-13T22:07:45Z branch-deleted name=feature/auth tip=<sha>  restore: git branch feature/auth <sha>
2026-09-13T22:07:45Z branch-force-deleted name=feature/search tip=<sha> pr=#412  restore: git branch feature/search <sha>
2026-09-13T22:07:45Z worktree-removed path=/path/to/wt branch=feature/auth head=<sha>
2026-09-13T22:07:46Z remote-ref-removed ref=refs/remotes/origin/old sha=<sha>  restore: git update-ref refs/remotes/origin/old <sha>
2026-09-13T22:07:46Z temp-file-removed path=src/.DS_Store
2026-09-13T22:07:50Z generated-dir-removed path=node_modules
```

Commits of deleted branches remain in the object database until `git gc` expires
unreachable objects, two weeks by default (`gc.pruneExpire`). Worktree removal deletes
the working directory; recreate it with `git worktree add <path> <branch>`.

## Configuration

```bash
git config --add cleanup.protected 'wip/*'      # per repository
git config --global --add cleanup.protected 'me/*'
```

`NO_COLOR=1` disables colour.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Audit completed; or cleanup completed; or the user declined at the batch prompt |
| 1 | Not a repository, ambiguous or missing default branch, bad option, or no terminal for a required confirmation |
| 130 | Interrupted |

## Portability

Bash 3.2 or newer (no associative arrays, `mapfile`, or other Bash 4 features are
used). Git 2.31 or newer, needed for `rev-parse --path-format=absolute`; everything
else requires 2.13 or earlier. External commands: `find`, `du`, `sed`, `grep`,
`head`, `cut`, `tr`, `paste`, `date`, with flags valid on both BSD and GNU. Machine-
readable Git output is used throughout: `for-each-ref --format`, `worktree list
--porcelain`, `status --porcelain=v1`, `ls-files -z`, `remote prune --dry-run`.

## Extending the lists

Three lists near the top of `git-cleanup` are meant to be edited:

- `PROTECTED` default protected globs,
- `GENERATED_NAMES` directory names treated as regenerable build output,
- `SENSITIVE_RE` the extended regular expression that marks files as secrets or state.

## Test harness

`tests/make-fixture.sh <dir>` builds a disposable repository with a bare "remote", a
clone, about twenty branches and worktrees in every state the tool distinguishes, a
stash, temp files, generated directories, and a fake `gh` that serves merged-PR
records. `tests/run-tests.sh` builds fixtures under `$TMPDIR`, runs dry runs with and
without `--fetch` and with and without PR data, then drives `--apply` interactively with
`expect` (declining and accepting prompts, and mutating a branch between audit and
apply), and asserts the classifications, the files and refs that survive, and the log.

```bash
make test
TEST_BASH=/bin/bash make test     # under the macOS system bash
```
