#!/usr/bin/env bash
# Builds a disposable fixture repository that exercises every git-cleanup classification.
# Usage: tests/make-fixture.sh <dir>   (the directory is wiped and recreated)
# Includes a bare "remote", a working clone, worktrees in every state, temp files, and a
# fake `gh` in <dir>/bin that serves merged-PR records from <dir>/prs.
set -euo pipefail
FX=$1
rm -rf "$FX"; mkdir -p "$FX/prs" "$FX/bin"
cd "$FX"
export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.com GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
q() { "$@" >/dev/null 2>&1; }

git init -q --bare -b main remote.git
git init -q -b main seed
( cd seed
  echo base > README.md
  printf 'node_modules/\n.env\n.cache/\n.terraform/\ndist/\n*.local.md\n.turbo/\n.parcel-cache/\n' > .gitignore
  mkdir dist; echo keep > dist/keep.js; git add -f dist/keep.js
  echo tracked > tracked.tmp
  mkdir src; echo 'x' > src/app.js
  git add -A; git commit -qm "initial"
  git remote add origin ../remote.git; git push -qu origin main )
rm -rf seed
git clone -q remote.git work
cd work
git config push.default simple

commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }

# --- feature/merged: real merge commit, remote branch deleted -> SAFE (upstream gone)
q git checkout -b feature/merged; commit a; q git push -u origin feature/merged
q git checkout main; q git merge --no-ff feature/merged -m "Merge feature/merged"; q git push origin main
q git push origin --delete feature/merged

# --- fix/merged-ff: fast-forward merged, remote branch still exists -> SAFE
q git checkout -b fix/merged-ff; commit b; q git push -u origin fix/merged-ff
q git checkout main; q git merge --ff-only fix/merged-ff; q git push origin main

# --- feature/squashed: 2 commits squash-merged, remote deleted -> REVIEW without gh, SAFE_PR with PR #412
q git checkout -b feature/squashed; commit c1; commit c2; q git push -u origin feature/squashed
SQ_HEAD=$(git rev-parse HEAD)
q git checkout main; q git merge --squash feature/squashed; git commit -qm "feature/squashed (#412)"
SQ_MERGE=$(git rev-parse HEAD); q git push origin main; q git push origin --delete feature/squashed
printf '412\t%s\t2026-02-01T10:00:00Z\tmain\thttps://github.com/acme/fixture/pull/412\t%s\n' "$SQ_HEAD" "$SQ_MERGE" > ../prs/feature__squashed.tsv

# --- feature/rebased: rebase-merged (cherry-pick), remote deleted, no PR -> REVIEW (git cherry evidence)
q git checkout -b feature/rebased; commit d; RB=$(git rev-parse HEAD); q git push -u origin feature/rebased
q git checkout main; GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" q git cherry-pick "$RB"; q git push origin main; q git push origin --delete feature/rebased

# --- feature/pr-diverged: PR merged at c1, local added c2 afterwards -> REVIEW
q git checkout -b feature/pr-diverged; commit e1; E1=$(git rev-parse HEAD); q git push -u origin feature/pr-diverged
q git checkout main; q git merge --squash feature/pr-diverged; git commit -qm "pr-diverged (#414)"; PD_MERGE=$(git rev-parse HEAD); q git push origin main
q git push origin --delete feature/pr-diverged
q git checkout feature/pr-diverged; commit e2
printf '414\t%s\t2026-02-02T10:00:00Z\tmain\thttps://github.com/acme/fixture/pull/414\t%s\n' "$E1" "$PD_MERGE" > ../prs/feature__pr-diverged.tsv

# --- feature/pr-behind: PR head = f2, local reset back to f1 (f2 object still local) -> SAFE_PR (ancestor rule)
q git checkout main; q git checkout -b feature/pr-behind; commit f1; F1=$(git rev-parse HEAD); commit f2; F2=$(git rev-parse HEAD)
q git push -u origin feature/pr-behind
q git checkout main; q git merge --squash feature/pr-behind; git commit -qm "pr-behind (#415)"; PB_MERGE=$(git rev-parse HEAD); q git push origin main
q git push origin --delete feature/pr-behind
git branch -f feature/pr-behind "$F1"
printf '415\t%s\t2026-02-03T10:00:00Z\tmain\thttps://github.com/acme/fixture/pull/415\t%s\n' "$F2" "$PB_MERGE" > ../prs/feature__pr-behind.tsv

# --- feature/pr-otherbase: PR merged into develop (not main), merge commit not in main -> REVIEW
q git checkout main; q git checkout -b develop; commit dev1; q git push -u origin develop
q git checkout -b feature/pr-otherbase; commit g1; G1=$(git rev-parse HEAD); q git push -u origin feature/pr-otherbase
q git checkout develop; q git merge --squash feature/pr-otherbase; git commit -qm "otherbase (#416)"; OB_MERGE=$(git rev-parse HEAD); q git push origin develop
q git push origin --delete feature/pr-otherbase
printf '416\t%s\t2026-02-04T10:00:00Z\tdevelop\thttps://github.com/acme/fixture/pull/416\t%s\n' "$G1" "$OB_MERGE" > ../prs/feature__pr-otherbase.tsv

# --- feature/pr-dropped: PR merged, but its merge commit is NOT in main (force-pushed away) -> REVIEW
q git checkout main; q git checkout -b feature/pr-dropped; commit m1; M1=$(git rev-parse HEAD); q git push -u origin feature/pr-dropped
q git checkout main; DROPPED=$(git commit-tree -p main -m "pr-dropped (#417)" "$(git rev-parse 'main^{tree}')")
q git push origin --delete feature/pr-dropped
printf '417\t%s\t2026-02-05T10:00:00Z\tmain\thttps://github.com/acme/fixture/pull/417\t%s\n' "$M1" "$DROPPED" > ../prs/feature__pr-dropped.tsv

# --- experiment/unmerged: unique commit, upstream exists -> UNMERGED
q git checkout main; q git checkout -b experiment/unmerged; commit h; q git push -u origin experiment/unmerged

# --- local/only: never pushed -> UNMERGED (the old script would have -D'd this!)
q git checkout main; q git checkout -b local/only; commit i

# --- release/1.0: merged, but protected pattern must win -> PROTECTED
q git checkout main; git branch release/1.0 main

# --- worktrees
git branch wt/clean-merged main
git worktree add -q "../wt clean merged" wt/clean-merged          # path with spaces -> SAFE

git branch wt/dirty main
git worktree add -q ../wt-dirty wt/dirty
( cd ../wt-dirty; commit j; echo change >> README.md )               # unmerged + modified -> DIRTY

git branch wt/staged main
git worktree add -q ../wt-staged wt/staged
( cd ../wt-staged; echo s > staged.txt; git add staged.txt )         # staged -> DIRTY

git branch wt/untracked main
git worktree add -q ../wt-untracked wt/untracked
( cd ../wt-untracked; echo u > notes.md )                             # untracked -> REVIEW

git branch wt/sensitive main
git worktree add -q ../wt-sensitive wt/sensitive
( cd ../wt-sensitive; echo SECRET=1 > .env; mkdir -p node_modules/x; echo 1 > node_modules/x/i.js )  # ignored .env -> REVIEW

git branch wt/stale main
git worktree add -q ../wt-stale wt/stale; rm -rf ../wt-stale          # -> STALE

git branch wt/locked main
git worktree add -q ../wt-locked wt/locked; git worktree lock --reason "keep me" ../wt-locked   # -> IN_USE

git worktree add -q --detach ../wt-detached main                     # detached, contained -> SAFE

git branch wt/rebasing main
git worktree add -q ../wt-rebasing wt/rebasing
( cd ../wt-rebasing && GIT_SEQUENCE_EDITOR='sed -i.bak "s/^pick/edit/"' git rebase -i HEAD~1 >/dev/null 2>&1 || true )   # paused rebase: clean + detached -> IN_USE

# --- stash made on a removal candidate
q git checkout feature/merged; echo wip >> a.txt; git stash push -qm "half-done"; q git checkout main

# --- temp files in the primary tree
touch .DS_Store src/.DS_Store; echo x > notes.txt~; echo x > old.swp; echo x > scratch.tmp
touch -t 202401010000 old.swp scratch.tmp
echo x > recent.swp                                                   # fresh -> REVIEW
echo SECRET=old > .env~; echo SECRET=old > .env.swp; touch -t 202401010000 .env~ .env.swp   # copies of secrets -> REVIEW
mkdir -p vendor/inner; git -C vendor/inner init -q -b main; echo t > vendor/inner/inner.tmp; touch vendor/inner/.DS_Store
git -C vendor/inner add inner.tmp; git -C vendor/inner commit -qm inner                    # nested repo: never entered
mkdir -p .terraform/providers; echo state > .terraform/terraform.tfstate; echo p > .terraform/providers/p   # generated but holds state -> REVIEW
echo gen > dist/gen.js                                                                     # dist/ ignored but has tracked keep.js -> skipped

git branch wt/ignored-other main
git worktree add -q ../wt-ignored-other wt/ignored-other
( cd ../wt-ignored-other; echo n > notes.local.md )                    # ignored, not build output -> REVIEW
git branch wt/ignored-generated main
git worktree add -q ../wt-ignored-generated wt/ignored-generated
( cd ../wt-ignored-generated; mkdir -p node_modules/x dist; echo 1 > node_modules/x/i.js; echo 1 > dist/gen.js; touch .DS_Store )  # only build output -> SAFE
echo SECRET=2 > .env                                                  # ignored, never a candidate
mkdir -p node_modules/pkg .cache build; echo 1 > node_modules/pkg/index.js; echo 1 > .cache/c; echo 1 > build/out.js   # build/ NOT ignored -> skipped

# prune stale remote-tracking refs so `gone` shows (this is what --fetch would do)
q git fetch --prune origin
# a remote-tracking ref whose remote branch is gone (only --fetch can discover this),
# and no origin/HEAD, so default-branch detection must fall back (and --fetch repairs it)
q git checkout main; q git checkout -b tmp/remote-deleted; commit k; q git push -u origin tmp/remote-deleted; q git checkout main; git branch -D tmp/remote-deleted >/dev/null
git -C ../remote.git branch -D tmp/remote-deleted >/dev/null
git remote set-head origin --delete
# a stale remote-tracking ref whose commits ARE in main (safe to drop) — tmp/remote-deleted above is NOT
q git push origin main:refs/heads/tmp/remote-merged; git -C ../remote.git branch -D tmp/remote-merged >/dev/null
# a stale worktree entry with a detached HEAD nobody holds -> REVIEW (pruning would orphan the commit)
dang=$(git commit-tree -p main -m "dangling" "$(git rev-parse 'main^{tree}')")
git worktree add -q --detach ../wt-stale-detached "$dang"; rm -rf ../wt-stale-detached
# generated dirs that must NOT be offered: holds a key / contains a nested repository
mkdir -p .turbo .parcel-cache/vendor/lib/.git; echo k > .turbo/secret.key; echo 1 > .parcel-cache/x

# --- fake gh: answers auth/repo checks and serves PR records from ../prs
cat > ../bin/gh <<'GH'
#!/usr/bin/env bash
FX="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "repo view")   echo "acme/fixture"; exit 0 ;;
  "pr list")
    head=""; while [[ $# -gt 0 ]]; do [[ $1 == --head ]] && head=${2:-}; shift; done
    f="$FX/prs/${head//\//__}.tsv"; [[ -f $f ]] && cat "$f"; exit 0 ;;
  *) echo "fake gh: unsupported: $*" >&2; exit 1 ;;
esac
GH
chmod +x ../bin/gh
echo "fixture ready at $FX"
