#!/usr/bin/env bash
#
# Installer for git-worktree-init. Works from a clone (copies the local script) or when
# piped from GitHub (downloads it):
#
#   ./install.sh                                  # from a clone
#   curl -fsSL https://raw.githubusercontent.com/dblok-changda/git-worktree-init/main/install.sh | bash
#
# Options:
#   --bindir DIR    install into DIR (default: /usr/local/bin if writable, else ~/.local/bin)
#   --prefix DIR    same as --bindir DIR/bin
#   --ref REF       branch or tag to download when not installing from a clone (default: main)
#   --uninstall     remove the installed command
#   -h, --help
#
# After installation the tool is available as `git-worktree-init` and, because Git looks
# up git-<name> on PATH, also as `git worktree-init`.

set -u
REPO_RAW="https://raw.githubusercontent.com/dblok-changda/git-worktree-init"
REF="main"; BINDIR=""; UNINSTALL=0

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --bindir)    [[ $# -ge 2 ]] || die "--bindir needs a value"; BINDIR=$2; shift ;;
    --bindir=*)  BINDIR=${1#*=} ;;
    --prefix)    [[ $# -ge 2 ]] || die "--prefix needs a value"; BINDIR=$2/bin; shift ;;
    --prefix=*)  BINDIR=${1#*=}/bin ;;
    --ref)       [[ $# -ge 2 ]] || die "--ref needs a value"; REF=$2; shift ;;
    --ref=*)     REF=${1#*=} ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)   sed -n '2,17p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# Pick a destination: a system dir we can write to, otherwise a per-user one.
if [[ -z $BINDIR ]]; then
  if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then BINDIR=/usr/local/bin
  elif [[ -d /opt/homebrew/bin && -w /opt/homebrew/bin ]]; then BINDIR=/opt/homebrew/bin
  else BINDIR=$HOME/.local/bin; fi
fi
TARGET="$BINDIR/git-worktree-init"

if [[ $UNINSTALL -eq 1 ]]; then
  if [[ -e $TARGET ]]; then
    rm -f -- "$TARGET" 2>/dev/null
    [[ ! -e $TARGET ]] || die "cannot remove $TARGET (try: sudo $0 --uninstall)"
    printf 'Removed %s\n' "$TARGET"
  else printf 'Nothing installed at %s\n' "$TARGET"; fi
  exit 0
fi

command -v git >/dev/null 2>&1 || die "git is required"

# Source: the script next to this installer when run from a clone, otherwise a download.
src_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)
tmp=""
if [[ -n $src_dir && -f $src_dir/git-worktree-init && ${BASH_SOURCE[0]:-} != "" ]]; then
  SRC="$src_dir/git-worktree-init"
else
  tmp=$(mktemp "${TMPDIR:-/tmp}/git-worktree-init.XXXXXX") || die "cannot create a temp file"
  trap 'rm -f "$tmp"' EXIT
  url="$REPO_RAW/$REF/git-worktree-init"
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$tmp" || die "download failed: $url"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$tmp" "$url" || die "download failed: $url"
  else die "curl or wget is required to download"; fi
  SRC=$tmp
fi
head -n 1 "$SRC" | grep -q 'bash' || die "downloaded file does not look like the script"

mkdir -p -- "$BINDIR" || die "cannot create $BINDIR"
install -m 0755 -- "$SRC" "$TARGET" 2>/dev/null || { cp -- "$SRC" "$TARGET" && chmod 0755 "$TARGET"; } || die "cannot write $TARGET (try: sudo $0, or --bindir ~/.local/bin)"

printf 'Installed %s (%s)\n' "$TARGET" "$("$TARGET" --version 2>/dev/null || echo 'version unknown')"
# shellcheck disable=SC2016  # the literal $PATH below is meant for the user's profile
case ":$PATH:" in
  *":$BINDIR:"*) printf 'Run:  git-worktree-init --help     or     git worktree-init --help\n' ;;
  *) printf '\n%s is not on your PATH. Add this to your shell profile (~/.zshrc or ~/.bashrc):\n\n    export PATH="%s:$PATH"\n\n' "$BINDIR" "$BINDIR" ;;
esac
