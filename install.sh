#!/usr/bin/env bash
#
# Installer for git-grove: installs git-grove, git-cleanup and git-worktree-init together.
# Works from a clone (copies the local scripts) or when piped from GitHub (downloads them):
#
#   ./install.sh                                  # from a clone
#   curl -fsSL https://raw.githubusercontent.com/dblok-changda/git-grove/main/install.sh | bash
#
# Options:
#   --bindir DIR    install into DIR (default: /usr/local/bin if writable, else ~/.local/bin)
#   --prefix DIR    same as --bindir DIR/bin
#   --ref REF       branch or tag to download when not installing from a clone (default: main)
#   --uninstall     remove the installed commands
#   -h, --help
#
# Because Git runs any git-<name> found on PATH, the commands are also available as
# `git grove`, `git cleanup` and `git worktree-init`.

set -u
# GIT_GROVE_RAW_URL overrides the download base; the tests point it at a local directory.
REPO_RAW=${GIT_GROVE_RAW_URL:-https://raw.githubusercontent.com/dblok-changda/git-grove}
TOOLS=(git-grove git-cleanup git-worktree-init)
REF="main"; BINDIR=""; UNINSTALL=0

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

# A symlink into a Homebrew Cellar belongs to Homebrew; replacing or removing it breaks brew.
brew_owned() { case $(readlink "$1" 2>/dev/null) in */Cellar/*) return 0 ;; esac; return 1; }

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
  else BINDIR=$HOME/.local/bin; fi
fi

if [[ $UNINSTALL -eq 1 ]]; then
  found=0; failed=0
  for t in "${TOOLS[@]}"; do
    [[ -e $BINDIR/$t ]] || continue
    found=1
    if brew_owned "$BINDIR/$t"; then
      printf 'install: %s is managed by Homebrew; remove it with brew uninstall\n' "$BINDIR/$t" >&2; failed=1; continue
    fi
    rm -f -- "$BINDIR/$t" 2>/dev/null
    if [[ -e $BINDIR/$t ]]; then printf 'install: cannot remove %s (try: sudo %s --uninstall)\n' "$BINDIR/$t" "$0" >&2; failed=1
    else printf 'Removed %s\n' "$BINDIR/$t"; fi
  done
  [[ $failed -eq 0 ]] || die "uninstall incomplete"
  [[ $found -eq 1 ]] || printf 'Nothing installed in %s\n' "$BINDIR"
  exit 0
fi

# Requirements: git 2.31+ (git-cleanup uses --path-format=absolute) and any bash 3.2+.
command -v git >/dev/null 2>&1 || die "git is required"
gv=$(git --version | sed -E 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/')
read -r gmaj gmin <<< "$gv"
if [[ ${gmaj:-0} -lt 2 || ( ${gmaj:-0} -eq 2 && ${gmin:-0} -lt 31 ) ]]; then die "git 2.31 or newer is required (found $(git --version))"; fi

# Source: the scripts next to this installer when run from a clone, otherwise downloads.
# Everything is fetched and checked before anything is written, so a failed download
# never leaves a partial install.
src_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)
if [[ -n $src_dir && -f $src_dir/git-grove && ${BASH_SOURCE[0]:-} != "" ]]; then
  SRC_DIR=$src_dir
else
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-grove.XXXXXX") || die "cannot create a temp dir"
  trap 'rm -rf "$tmp"' EXIT
  for t in "${TOOLS[@]}"; do
    url="$REPO_RAW/$REF/$t"
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$tmp/$t" || die "download failed: $url"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$tmp/$t" "$url" || die "download failed: $url"
    else die "curl or wget is required to download"; fi
  done
  SRC_DIR=$tmp
fi
for t in "${TOOLS[@]}"; do
  [[ -f $SRC_DIR/$t ]] || die "missing $t"
  head -n 1 "$SRC_DIR/$t" | grep -q 'bash' || die "$t does not look like the script"
done

for t in "${TOOLS[@]}"; do
  brew_owned "$BINDIR/$t" && die "$BINDIR/$t is managed by Homebrew; update with: brew update && brew upgrade git-grove (or install elsewhere with --bindir ~/.local/bin)"
done

mkdir -p -- "$BINDIR" || die "cannot create $BINDIR"
for t in "${TOOLS[@]}"; do
  install -m 0755 -- "$SRC_DIR/$t" "$BINDIR/$t" 2>/dev/null || { cp -- "$SRC_DIR/$t" "$BINDIR/$t" && chmod 0755 "$BINDIR/$t"; } || die "cannot write $BINDIR/$t (try: sudo $0, or --bindir ~/.local/bin)"
done

ver=$("$BINDIR/git-grove" --version 2>/dev/null); ver=${ver##* }
printf 'Installed git-grove %s (%s) to %s\n' "${ver:-version unknown}" "${TOOLS[*]}" "$BINDIR"
# shellcheck disable=SC2016  # the literal $PATH below is meant for the user's profile
case ":$PATH:" in
  *":$BINDIR:"*) printf 'Run:  git grove help\n' ;;
  *) printf '\n%s is not on your PATH. Add this to your shell profile (~/.zshrc or ~/.bashrc):\n\n    export PATH="%s:$PATH"\n\n' "$BINDIR" "$BINDIR" ;;
esac
