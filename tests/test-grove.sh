#!/usr/bin/env bash
#
# Self-test for the git-grove dispatcher and the shared installer. Stub subcommands check
# routing exactly; the real scripts check the end-to-end path. It never touches the
# network or a real repository.
#
#   tests/test-grove.sh                       # bash from PATH
#   TEST_BASH=/bin/bash tests/test-grove.sh   # e.g. the macOS system bash 3.2

set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
BASH_BIN=${TEST_BASH:-bash}
SAFE_PATH=/usr/bin:/bin   # no Homebrew dirs: an installed git-cleanup must not leak in
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-grove-tests.XXXXXX") || exit 1
WORK=$(cd "$WORK" && pwd -P)
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()      { pass=$((pass + 1)); printf '  ok    %s\n' "$*"; }
bad()     { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }

check_grep()    { if grep -qE -- "$2" "$1"; then ok "$3"; else bad "$3"; fi; }
check_exit()    { if [[ $1 -eq $2 ]]; then ok "$3"; else bad "$3 (exit $1, expected $2)"; fi; }
check_eq()      { if [[ $1 == "$2" ]]; then ok "$3"; else bad "$3 (got '${1}', expected '${2}')"; fi; }
check_present() { if [[ -e $1 ]]; then ok "exists   ${1#"$WORK"/}"; else bad "MISSING  ${1#"$WORK"/}"; fi; }
check_absent()  { if [[ -e $1 ]]; then bad "unexpected ${1#"$WORK"/}"; else ok "absent   ${1#"$WORK"/}"; fi; }

# make_stubs <dir>: a copy of the dispatcher plus stub subcommands that print their name,
# each argument as [arg], and one line of stdin if any, then exit with $STUB_EXIT.
make_stubs() {
  local t
  mkdir -p "$1"
  cp "$ROOT/git-grove" "$1/"
  for t in git-cleanup git-worktree-init; do
    cat >"$1/$t" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}"
for a in "$@"; do printf '[%s]\n' "$a"; done
if IFS= read -r line; then printf 'stdin: %s\n' "$line"; fi
exit "${STUB_EXIT:-0}"
EOF
    chmod 0755 "$1/$t"
  done
}

STUBS=$WORK/stubs
make_stubs "$STUBS"
grove() { "$BASH_BIN" "$STUBS/git-grove" "$@" </dev/null; }

V=$("$BASH_BIN" "$ROOT/git-grove" --version 2>/dev/null); V=${V##* }

# shellcheck disable=SC2016  # $BASH_VERSION is expanded by the bash under test, not this one
printf 'git-grove self-test\n  root:   %s\n  bash:   %s (%s)\n  git:    %s\n' \
  "$ROOT" "$BASH_BIN" "$("$BASH_BIN" -c 'echo $BASH_VERSION')" "$(git --version)"

# ---------------------------------------------------------------------------
section "T1  routing to subcommands"
out=$(grove init 'my repo' '' '*' --help 2>&1); rc=$?
check_exit $rc 0 "init exits 0"
check_eq "$out" "$(printf '%s\n' git-worktree-init '[my repo]' '[]' '[*]' '[--help]')" "init passes arguments to git-worktree-init unchanged"
out=$(grove cleanup --fetch --apply 2>&1)
check_eq "$out" "$(printf '%s\n' git-cleanup '[--fetch]' '[--apply]')" "cleanup passes arguments to git-cleanup unchanged"
STUB_EXIT=3 grove cleanup >/dev/null 2>&1; check_exit $? 3 "cleanup exit status propagates"
STUB_EXIT=7 grove init x >/dev/null 2>&1; check_exit $? 7 "init exit status propagates"
out=$(printf 'yes\n' | "$BASH_BIN" "$STUBS/git-grove" cleanup --apply 2>&1)
check_grep <(printf '%s\n' "$out") '^stdin: yes$' "cleanup receives stdin (for --apply prompts)"

# ---------------------------------------------------------------------------
section "T2  help, version, errors"
for h in help -h --help; do
  out=$(grove "$h" 2>&1); rc=$?
  check_exit $rc 0 "$h exits 0"
  check_grep <(printf '%s\n' "$out") '^Usage: git grove <command>' "$h prints usage"
done
check_grep <(grove help) '^  init ' "usage lists init"
check_grep <(grove help) '^  cleanup ' "usage lists cleanup"
out=$(grove 2>&1); rc=$?
check_exit $rc 1 "no arguments exits 1"
check_grep <(printf '%s\n' "$out") '^Usage: git grove' "no arguments prints usage"
out=$(grove --version 2>&1); rc=$?
check_exit $rc 0 "--version exits 0"
check_grep <(printf '%s\n' "$out") '^git-grove [0-9]+\.[0-9]+\.[0-9]+$' "--version prints the version"
out=$(grove frobnicate 2>&1); rc=$?
check_exit $rc 1 "unknown command exits 1"
check_grep <(printf '%s\n' "$out") "unknown command 'frobnicate'" "unknown command is named"

# ---------------------------------------------------------------------------
section "T3  finding subcommands"
# Homebrew layout: <prefix>/bin/git-grove -> ../Cellar/.../bin/git-grove (relative link)
make_stubs "$WORK/Cellar/bin"
mkdir -p "$WORK/opt/bin" "$WORK/hop"
ln -s ../../Cellar/bin/git-grove "$WORK/opt/bin/git-grove"
ln -s "$WORK/opt/bin/git-grove" "$WORK/hop/git-grove"
out=$(PATH=$SAFE_PATH "$BASH_BIN" "$WORK/opt/bin/git-grove" cleanup x </dev/null 2>&1)
check_eq "$out" "$(printf '%s\n' git-cleanup '[x]')" "relative symlink: finds sibling next to link target"
out=$(PATH=$SAFE_PATH "$BASH_BIN" "$WORK/hop/git-grove" init y </dev/null 2>&1)
check_eq "$out" "$(printf '%s\n' git-worktree-init '[y]')" "symlink to symlink: finds sibling next to final target"
mkdir -p "$WORK/lonely"
cp "$ROOT/git-grove" "$WORK/lonely/"
make_stubs "$WORK/pathbin"
rm "$WORK/pathbin/git-grove"
out=$(PATH="$WORK/pathbin:$SAFE_PATH" "$BASH_BIN" "$WORK/lonely/git-grove" cleanup z </dev/null 2>&1)
check_eq "$out" "$(printf '%s\n' git-cleanup '[z]')" "falls back to PATH when there is no sibling"
out=$(PATH=$SAFE_PATH "$BASH_BIN" "$WORK/lonely/git-grove" cleanup </dev/null 2>&1); rc=$?
check_exit $rc 1 "missing subcommand exits 1"
check_grep <(printf '%s\n' "$out") 'cannot find git-cleanup' "missing subcommand is named"

# ---------------------------------------------------------------------------
section "T4  real scripts"
check_eq "$("$BASH_BIN" "$ROOT/git-grove" init --version </dev/null 2>&1)" "$("$BASH_BIN" "$ROOT/git-worktree-init" --version 2>&1)" "git grove init reaches git-worktree-init"
check_eq "$("$BASH_BIN" "$ROOT/git-grove" cleanup --version </dev/null 2>&1)" "$("$BASH_BIN" "$ROOT/git-cleanup" --version 2>&1)" "git grove cleanup reaches git-cleanup"
for t in git-cleanup git-worktree-init; do
  tv=$("$BASH_BIN" "$ROOT/$t" --version 2>&1)
  check_eq "${tv##* }" "$V" "$t version matches git-grove ($V)"
done

# ---------------------------------------------------------------------------
TOOLS="git-grove git-cleanup git-worktree-init"

section "T5  installer from a clone"
BIN=$WORK/bin
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" >"$WORK/t5.txt" 2>&1
check_exit $? 0 "install.sh exits 0"
for t in $TOOLS; do
  if [[ -x $BIN/$t ]]; then ok "installed $t"; else bad "$t not installed or not executable"; fi
done
check_grep "$WORK/t5.txt" "^Installed git-grove $V " "reports the installed version"
for c in "grove --version" "cleanup --version" "worktree-init --version" "grove init --version" "grove cleanup --version"; do
  # shellcheck disable=SC2086  # $c is split into a git subcommand and its arguments on purpose
  out=$(PATH="$BIN:$PATH" git $c </dev/null 2>&1); rc=$?
  check_exit $rc 0 "git $c runs from PATH"
  check_eq "${out##* }" "$V" "git $c reports $V"
done

# ---------------------------------------------------------------------------
section "T6  installing over an older git-cleanup"
BIN2=$WORK/bin2
mkdir -p "$BIN2"
printf '#!/usr/bin/env bash\necho "git-cleanup 1.0.0"\n' >"$BIN2/git-cleanup"
chmod 0755 "$BIN2/git-cleanup"
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN2" >/dev/null 2>&1
check_exit $? 0 "install over an existing git-cleanup exits 0"
check_eq "$("$BIN2/git-cleanup" --version)" "git-cleanup $V" "old git-cleanup replaced"

# ---------------------------------------------------------------------------
section "T7  piped installer downloads all three, or installs nothing"
mkdir -p "$WORK/raw/main"
for t in $TOOLS; do cp "$ROOT/$t" "$WORK/raw/main/"; done
BIN3=$WORK/bin3
GIT_GROVE_RAW_URL="file://$WORK/raw" "$BASH_BIN" -s -- --bindir "$BIN3" <"$ROOT/install.sh" >"$WORK/t7.txt" 2>&1
check_exit $? 0 "piped install exits 0"
for t in $TOOLS; do
  if cmp -s "$BIN3/$t" "$ROOT/$t"; then ok "downloaded $t"; else bad "$t missing or differs from the published script"; fi
done
rm "$WORK/raw/main/git-worktree-init"
BIN4=$WORK/bin4
GIT_GROVE_RAW_URL="file://$WORK/raw" "$BASH_BIN" -s -- --bindir "$BIN4" <"$ROOT/install.sh" >"$WORK/t7b.txt" 2>&1
check_exit $? 1 "piped install exits 1 when a download fails"
check_grep "$WORK/t7b.txt" 'download failed: .*/git-worktree-init' "names the failed download"
for t in $TOOLS; do check_absent "$BIN4/$t"; done

# ---------------------------------------------------------------------------
section "T8  uninstall"
rm "$BIN3/git-grove" "$BIN3/git-worktree-init"   # like a pre-grove, git-cleanup-only install
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN3" --uninstall >/dev/null 2>&1
check_exit $? 0 "uninstall with only git-cleanup present exits 0"
check_absent "$BIN3/git-cleanup"
chmod 0555 "$BIN"
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" --uninstall >"$WORK/t8.txt" 2>&1
check_exit $? 1 "--uninstall exits 1 when files cannot be removed"
check_grep "$WORK/t8.txt" "cannot remove" "explains why"
check_present "$BIN/git-grove"
chmod 0755 "$BIN"
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" --uninstall >/dev/null 2>&1
check_exit $? 0 "--uninstall exits 0"
for t in $TOOLS; do check_absent "$BIN/$t"; done
"$BASH_BIN" "$ROOT/install.sh" --bindir "$BIN" --uninstall >"$WORK/t8b.txt" 2>&1
check_exit $? 0 "uninstall with nothing installed exits 0"
check_grep "$WORK/t8b.txt" "Nothing installed" "says nothing was installed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
