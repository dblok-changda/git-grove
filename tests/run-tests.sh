#!/usr/bin/env bash
#
# Self-test for git-cleanup. Builds disposable fixture repositories in a temporary
# directory, runs the tool against them with a fake `gh`, and checks every
# classification plus the effect of --apply. It never touches a real repository.
#
#   tests/run-tests.sh                       # bash from PATH
#   TEST_BASH=/bin/bash tests/run-tests.sh   # e.g. the macOS system bash 3.2
#
# Interactive --apply tests need `expect`; they are skipped when it is missing.

set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
GC=${GIT_CLEANUP:-$(cd "$HERE/.." && pwd -P)/git-cleanup}
BASH_BIN=${TEST_BASH:-bash}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-cleanup-tests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
export GC BASH_BIN

pass=0; fail=0
ok()      { pass=$((pass + 1)); printf '  ok    %s\n' "$*"; }
bad()     { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }

# Report lines look like:  "  <sym> <CLASS>    <name>"  (worktrees: "<path>  [<branch>|detached]")
class_of_branch()   { awk -v n="$2" '$NF == n && $2 ~ /^[A-Z_]+$/ { print $2; exit }' "$1"; }
class_of_worktree() { awk -v n="$2" 'index($0, "/" n "  [") && $2 ~ /^[A-Z_]+$/ { print $2; exit }' "$1"; }
check_branch()   { local got; got=$(class_of_branch "$1" "$3");   if [[ $got == "$2" ]]; then ok "$2  $3"; else bad "expected $2 for $3, got ${got:-nothing}"; fi; }
check_worktree() { local got; got=$(class_of_worktree "$1" "$3"); if [[ $got == "$2" ]]; then ok "$2  worktree $3"; else bad "expected $2 for worktree $3, got ${got:-nothing}"; fi; }
check_grep()     { if grep -qE -- "$2" "$1"; then ok "$3"; else bad "$3"; fi; }
check_nogrep()   { if grep -qE -- "$2" "$1"; then bad "$3"; else ok "$3"; fi; }
# A temp-file line is "held" when one of the next two lines says keeping.
check_held()     { if awk -v n="$2" '$0 ~ ("^  [^ ]+ " n "$") { h = NR } h && NR > h && NR <= h + 2 && /keeping/ { f = 1 } END { exit !f }' "$1"; then ok "held    $2"; else bad "expected $2 to be held for review"; fi; }
check_offered()  { if awk -v n="$2" '$0 ~ ("^  [^ ]+ " n "$") { h = NR } h && NR > h && NR <= h + 2 && /keeping/ { f = 1 } END { exit f }' "$1" && grep -qE -- "^  [^ ]+ $2\$" "$1"; then ok "offered $2"; else bad "expected $2 to be offered"; fi; }
check_present()  { if [[ -e $1 ]]; then ok "kept     ${1#"$FX"/}"; else bad "MISSING  ${1#"$FX"/}"; fi; }
check_gone()     { if [[ -e $1 ]]; then bad "still present ${1#"$FX"/}"; else ok "removed  ${1#"$FX"/}"; fi; }
check_ref()      { if git -C "$FX/work" rev-parse -q --verify "$2" >/dev/null 2>&1; then [[ $1 == present ]] && ok "ref kept    $2" || bad "ref still present $2"; else [[ $1 == gone ]] && ok "ref removed $2" || bad "ref MISSING $2"; fi; }

build()  { "$HERE/make-fixture.sh" "$1" >/dev/null 2>&1 || { echo "fixture build failed"; exit 1; }; }
run_gc() { ( cd "$FX/work" && PATH="$FX/bin:$PATH" "$BASH_BIN" "$GC" "$@" --no-color ); }

printf 'git-cleanup self-test\n  script: %s\n  bash:   %s (%s)\n  git:    %s\n' "$GC" "$BASH_BIN" "$("$BASH_BIN" -c 'echo $BASH_VERSION')" "$(git --version)"

# ---------------------------------------------------------------------------
section "T1  dry run, --fetch, PR data available"
FX=$WORK/t1; build "$FX"
run_gc --fetch --gh-repo acme/fixture --temp --generated > "$WORK/t1.txt" 2>&1 || bad "exit status $?"
check_grep "$WORK/t1.txt" 'GitHub CLI +available' "gh detected through --gh-repo"
check_grep "$WORK/t1.txt" 'Fetch +fetched origin \(nothing pruned' "fetch reports nothing pruned"
check_grep "$WORK/t1.txt" 'Default branch +origin/main +\(origin/HEAD\)' "default branch from origin/HEAD (set by --fetch)"
for spec in \
  "SAFE feature/merged" "SAFE fix/merged-ff" "SAFE_PR feature/squashed" "SAFE_PR feature/pr-behind" \
  "REVIEW feature/pr-diverged" "REVIEW feature/pr-otherbase" "REVIEW feature/pr-dropped" "REVIEW feature/rebased" \
  "UNMERGED experiment/unmerged" "UNMERGED local/only" "PROTECTED develop" "PROTECTED release/1.0" "IN_USE main" \
  "SAFE wt/clean-merged" "SAFE wt/stale" "SAFE wt/ignored-generated" "IN_USE wt/dirty" "IN_USE wt/rebasing" \
  "IN_USE wt/untracked" "IN_USE wt/sensitive" "IN_USE wt/ignored-other" "IN_USE wt/locked" \
  "SAFE origin/tmp/remote-merged" "REVIEW origin/tmp/remote-deleted"; do
  check_branch "$WORK/t1.txt" ${spec%% *} "${spec#* }"
done
for spec in \
  "PROTECTED work" "SAFE wt clean merged" "SAFE wt-detached" "SAFE wt-ignored-generated" "DIRTY wt-dirty" "DIRTY wt-staged" \
  "REVIEW wt-untracked" "REVIEW wt-sensitive" "REVIEW wt-ignored-other" "IN_USE wt-locked" "IN_USE wt-rebasing" \
  "STALE wt-stale" "REVIEW wt-stale-detached"; do
  check_worktree "$WORK/t1.txt" ${spec%% *} "${spec#* }"
done
for f in .DS_Store src/.DS_Store 'notes\.txt~' 'old\.swp' 'scratch\.tmp'; do check_offered "$WORK/t1.txt" "$f"; done
for f in '\.env~' '\.env\.swp' 'recent\.swp'; do check_held "$WORK/t1.txt" "$f"; done
check_grep   "$WORK/t1.txt" '^  [^ ]+ tracked\.tmp$' "tracked .tmp reported but not offered"
check_nogrep "$WORK/t1.txt" 'vendor/inner' "nested repository never entered"
check_grep   "$WORK/t1.txt" 'terraform\.tfstate — keeping' ".terraform kept: holds state"
check_grep   "$WORK/t1.txt" 'secret\.key — keeping' ".turbo kept: holds a key"
check_grep   "$WORK/t1.txt" '\.parcel-cache \(contains a nested repository\)' ".parcel-cache not offered"
check_grep   "$WORK/t1.txt" '^  [^ ]+ dist \(' "dist not offered: tracked files inside"
check_grep   "$WORK/t1.txt" 'a rebase is in progress' "paused rebase detected"
check_grep   "$WORK/t1.txt" 'stash\(es\) exist' "stash listed"
check_grep   "$WORK/t1.txt" 'No changes have been made' "dry-run footer"
check_ref present refs/remotes/origin/tmp/remote-merged
check_ref present refs/remotes/origin/tmp/remote-deleted
[[ -d $FX/wt-untracked && -f $FX/.env~ || -f $FX/work/.env~ ]] && ok "dry run left files alone" || bad "dry run changed files"

# ---------------------------------------------------------------------------
section "T2  dry run without --fetch: PR-based decisions must downgrade"
run_gc --gh-repo acme/fixture > "$WORK/t2.txt" 2>&1 || bad "exit status $?"
check_branch "$WORK/t2.txt" REVIEW feature/squashed
check_branch "$WORK/t2.txt" REVIEW feature/pr-behind
check_grep   "$WORK/t2.txt" 'Re-run with --fetch' "downgrade explains why"
check_worktree "$WORK/t2.txt" SAFE wt-detached
check_grep   "$WORK/t2.txt" 'Stale remote-tracking refs' "stale-ref section present"
check_grep   "$WORK/t2.txt" 'not checked \(pass --fetch' "stale refs not checked without --fetch"

# ---------------------------------------------------------------------------
section "T3  dry run with --no-gh: squash merges cannot be proven"
run_gc --fetch --no-gh > "$WORK/t3.txt" 2>&1 || bad "exit status $?"
check_branch "$WORK/t3.txt" REVIEW feature/squashed
check_branch "$WORK/t3.txt" REVIEW feature/rebased
check_grep   "$WORK/t3.txt" 'patch-equivalent' "rebase-merge evidence from git cherry"
check_grep   "$WORK/t3.txt" 'GitHub CLI +disabled' "gh disabled"

# ---------------------------------------------------------------------------
if ! command -v expect >/dev/null 2>&1; then
  section "T4/T5 skipped: expect is not installed"
else
  section "T4  --apply --yes, every per-item prompt declined"
  FX=$WORK/t4; build "$FX"
  ( cd "$FX/work" && PATH="$FX/bin:$PATH" expect -f "$HERE/apply-yes.exp" ) > "$WORK/t4.txt" 2>&1 || bad "expect exit status $?"
  check_grep "$WORK/t4.txt" 'Cleanup complete\. 11 action' "11 SAFE actions performed"
  check_grep "$WORK/t4.txt" 'Force-removing branch feature/squashed.*skipped \(declined\)' "force delete declined"
  check_grep "$WORK/t4.txt" 'Deleting generated directory node_modules.*skipped \(declined\)' "generated dir declined"
  for f in .env .env~ .env.swp tracked.tmp recent.swp vendor/inner/inner.tmp vendor/inner/.DS_Store \
           .terraform/terraform.tfstate .turbo/secret.key dist/keep.js dist/gen.js node_modules/pkg/index.js .cache/c; do
    check_present "$FX/work/$f"
  done
  for d in wt-dirty wt-staged wt-untracked wt-sensitive wt-ignored-other wt-locked wt-rebasing; do check_present "$FX/$d"; done
  check_present "$FX/work/.git/worktrees/wt-rebasing/rebase-merge"
  for f in .DS_Store src/.DS_Store notes.txt~ old.swp scratch.tmp; do check_gone "$FX/work/$f"; done
  for d in "wt clean merged" wt-detached wt-ignored-generated; do check_gone "$FX/$d"; done
  for b in feature/merged fix/merged-ff wt/clean-merged wt/stale wt/ignored-generated; do check_ref gone "refs/heads/$b"; done
  for b in feature/squashed feature/pr-behind feature/pr-dropped feature/rebased experiment/unmerged local/only develop release/1.0 wt/rebasing; do check_ref present "refs/heads/$b"; done
  check_ref gone    refs/remotes/origin/tmp/remote-merged
  check_ref present refs/remotes/origin/tmp/remote-deleted
  git -C "$FX/work" worktree list --porcelain | grep -q 'wt-stale-detached' && ok "stale detached entry kept" || bad "stale detached entry removed"
  [[ $(git -C "$FX/work" stash list | wc -l) -eq 1 ]] && ok "stash untouched" || bad "stash changed"
  check_grep "$FX/work/.git/git-cleanup.log" 'branch-deleted name=feature/merged .*restore: git branch feature/merged' "recovery log written"

  section "T5  interactive --apply: revalidation skip, one force delete accepted"
  FX=$WORK/t5; build "$FX"
  ( cd "$FX/work" && WORK_REPO=$FX/work PATH="$FX/bin:$PATH" expect -f "$HERE/interactive.exp" ) > "$WORK/t5.txt" 2>&1 || bad "expect exit status $?"
  check_grep "$WORK/t5.txt" 'Removing branch fix/merged-ff .*skipped \(tip changed since the audit' "branch changed after audit was skipped"
  [[ $(git -C "$FX/work" log -1 --format=%s fix/merged-ff 2>/dev/null) == "late commit" ]] && ok "late commit preserved" || bad "late commit lost"
  check_ref gone    refs/heads/feature/squashed
  check_ref present refs/heads/feature/pr-behind
  check_gone    "$FX/work/node_modules"
  check_present "$FX/work/.cache"
  check_present "$FX/work/.turbo/secret.key"
  check_grep "$FX/work/.git/git-cleanup.log" 'branch-force-deleted name=feature/squashed .*pr=#412' "force delete logged with PR number"
fi

# ---------------------------------------------------------------------------
section "Result: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
