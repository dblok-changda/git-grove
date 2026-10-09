#!/usr/bin/env bash
#
# Self-test for git-worktree-init. Builds disposable "remote" repositories in a temporary
# directory, runs the tool against them over file:// URLs, and checks the resulting
# layout plus the installer. It never touches the network or a real repository.
#
#   tests/run-tests.sh                       # bash from PATH
#   TEST_BASH=/bin/bash tests/run-tests.sh   # e.g. the macOS system bash 3.2

set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
GWI=${GIT_WORKTREE_INIT:-$ROOT/git-worktree-init}
BASH_BIN=${TEST_BASH:-bash}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-worktree-init-tests.XXXXXX") || exit 1
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()      { pass=$((pass + 1)); printf '  ok    %s\n' "$*"; }
bad()     { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }

check_grep()    { if grep -qE -- "$2" "$1"; then ok "$3"; else bad "$3"; fi; }
check_exit()    { if [[ $1 -eq $2 ]]; then ok "$3"; else bad "$3 (exit $1, expected $2)"; fi; }
check_eq()      { if [[ $1 == "$2" ]]; then ok "$3"; else bad "$3 (got '${1}', expected '${2}')"; fi; }
check_present() { if [[ -e $1 ]]; then ok "exists   ${1#"$WORK"/}"; else bad "MISSING  ${1#"$WORK"/}"; fi; }
check_absent()  { if [[ -e $1 ]]; then bad "unexpected ${1#"$WORK"/}"; else ok "absent   ${1#"$WORK"/}"; fi; }

# make_remote <name> <default-branch> [branch...]: a bare repo with the default branch,
# feature/x, and any extra branches.
make_remote() {
  local name=$1 default=$2 src="$WORK/src-$1" b; shift 2
  git init -q -b "$default" "$src"
  git -C "$src" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
  for b in feature/x "$@"; do git -C "$src" branch "$b"; done
  git clone -q --bare "$src" "$WORK/remotes/$name.git"
}

run_gwi() { ( cd "$WORK/out" && "$BASH_BIN" "$GWI" "$@" ); }

# shellcheck disable=SC2016  # $BASH_VERSION is expanded by the bash under test, not this one
printf 'git-worktree-init self-test\n  script: %s\n  bash:   %s (%s)\n  git:    %s\n' \
  "$GWI" "$BASH_BIN" "$("$BASH_BIN" -c 'echo $BASH_VERSION')" "$(git --version)"

mkdir -p "$WORK/remotes" "$WORK/out"
make_remote fixture main
make_remote devrepo develop main
make_remote ambiguous main origin/main
git --git-dir="$WORK/remotes/ambiguous.git" tag main

# ---------------------------------------------------------------------------
section "T1  default branch main, directory inferred from URL"
run_gwi "file://$WORK/remotes/fixture.git" >"$WORK/t1.txt" 2>&1
check_exit $? 0 "exits 0"
P=$WORK/out/fixture
check_present "$P/.git"
check_present "$P/main/.git"
check_eq "$(git --git-dir="$P/.git" config --bool core.bare)" true "project .git is a bare repository"
check_eq "$(git --git-dir="$P/.git" config remote.origin.fetch)" "+refs/heads/*:refs/remotes/origin/*" "fetch refspec configured"
check_eq "$(git -C "$P/main" rev-parse --abbrev-ref HEAD)" main "worktree main is on branch main"
check_eq "$(git -C "$P/main" rev-parse --abbrev-ref '@{upstream}' 2>&1)" origin/main "main tracks origin/main"
if git --git-dir="$P/.git" rev-parse -q --verify refs/remotes/origin/feature/x >/dev/null; then ok "remote-tracking ref origin/feature/x fetched"; else bad "origin/feature/x not fetched"; fi
check_grep "$WORK/t1.txt" "cd fixture/main" "prints next step"

# ---------------------------------------------------------------------------
section "T2  default branch develop, explicit target directory"
run_gwi "file://$WORK/remotes/devrepo.git" my-dir >"$WORK/t2.txt" 2>&1
check_exit $? 0 "exits 0"
P=$WORK/out/my-dir
check_present "$P/develop/.git"
check_absent "$P/main"
check_absent "$WORK/out/devrepo"
check_eq "$(git -C "$P/develop" rev-parse --abbrev-ref HEAD)" develop "worktree develop is on branch develop"
check_eq "$(git -C "$P/develop" rev-parse --abbrev-ref '@{upstream}' 2>&1)" origin/develop "develop tracks origin/develop"

# ---------------------------------------------------------------------------
section "T2b default branch develop, Git that does not create origin/HEAD on fetch (< 2.48)"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.followRemoteHEAD GIT_CONFIG_VALUE_0=never \
  run_gwi "file://$WORK/remotes/devrepo.git" old-git >"$WORK/t2b.txt" 2>&1
check_exit $? 0 "exits 0"
P=$WORK/out/old-git
if git --git-dir="$P/.git" rev-parse -q --verify refs/remotes/origin/HEAD >/dev/null; then bad "origin/HEAD exists; simulation ineffective"; else ok "origin/HEAD absent (simulation in effect)"; fi
check_present "$P/develop/.git"
check_absent "$P/main"
check_eq "$(git -C "$P/develop" rev-parse --abbrev-ref '@{upstream}' 2>&1)" origin/develop "develop tracks origin/develop"

# ---------------------------------------------------------------------------
section "T2c branch named origin/main and tag named main (ambiguous short names)"
for v in always never; do
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.followRemoteHEAD GIT_CONFIG_VALUE_0=$v \
    run_gwi "file://$WORK/remotes/ambiguous.git" "ambiguous-$v" >"$WORK/t2c-$v.txt" 2>&1
  check_exit $? 0 "exits 0 (followRemoteHEAD=$v)"
  P=$WORK/out/ambiguous-$v
  check_present "$P/main/.git"
  check_absent "$P/remotes"
  check_absent "$P/heads"
  check_eq "$(git -C "$P/main" symbolic-ref HEAD 2>&1)" refs/heads/main "worktree is on refs/heads/main"
  check_eq "$(git -C "$P/main" rev-parse --symbolic-full-name '@{upstream}' 2>&1)" refs/remotes/origin/main "main tracks refs/remotes/origin/main"
done

# ---------------------------------------------------------------------------
section "T3  target directory already exists"
mkdir -p "$WORK/out/taken" && touch "$WORK/out/taken/keep"
run_gwi "file://$WORK/remotes/fixture.git" taken >"$WORK/t3.txt" 2>&1
check_exit $? 1 "exits 1"
check_grep "$WORK/t3.txt" "already exists" "explains why"
check_present "$WORK/out/taken/keep"
check_absent "$WORK/out/taken/.git"

# ---------------------------------------------------------------------------
section "T4  command line"
out=$("$BASH_BIN" "$GWI" --version 2>&1); rc=$?
check_exit $rc 0 "--version exits 0"
check_grep <(printf '%s\n' "$out") '^git-worktree-init [0-9]+\.[0-9]+\.[0-9]+$' "--version prints the version"
out=$("$BASH_BIN" "$GWI" --help 2>&1); rc=$?
check_exit $rc 0 "--help exits 0"
check_grep <(printf '%s\n' "$out") '^Usage: ' "--help prints usage"
"$BASH_BIN" "$GWI" >/dev/null 2>&1; check_exit $? 1 "no arguments exits 1"
"$BASH_BIN" "$GWI" --bogus >/dev/null 2>&1; check_exit $? 1 "unknown option exits 1"
"$BASH_BIN" "$GWI" a b c >/dev/null 2>&1; check_exit $? 1 "too many arguments exits 1"

# ---------------------------------------------------------------------------
section "T5  installer"
BIN=$WORK/bin
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" >"$WORK/t5.txt" 2>&1
check_exit $? 0 "install.sh exits 0"
if [[ -x $BIN/git-worktree-init ]]; then ok "installed executable"; else bad "not installed or not executable"; fi
check_grep "$WORK/t5.txt" 'Installed .*git-worktree-init \(git-worktree-init [0-9.]+\)' "reports installed version"
check_eq "$(PATH="$BIN:$PATH" git worktree-init --version 2>&1)" "$("$BASH_BIN" "$GWI" --version)" "available as 'git worktree-init'"
chmod 0555 "$BIN"
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" --uninstall >"$WORK/t5u.txt" 2>&1
check_exit $? 1 "--uninstall exits 1 when the file cannot be removed"
check_grep "$WORK/t5u.txt" "cannot remove" "explains why"
check_present "$BIN/git-worktree-init"
chmod 0755 "$BIN"
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" --uninstall >/dev/null 2>&1
check_exit $? 0 "install.sh --uninstall exits 0"
check_absent "$BIN/git-worktree-init"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
