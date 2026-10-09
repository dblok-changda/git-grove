#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <repo-url> [target-directory]

Initializes a bare Git repository configured for worktree workflows.

Arguments:
  <repo-url>          Git remote URL (SSH or HTTPS)
  [target-directory]  Optional folder name (defaults to repository name)
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

REPO_URL="$1"
DIR_NAME="${2:-}"

# Infer target directory from repo URL if not provided
if [[ -z "$DIR_NAME" ]]; then
  BASE=$(basename "$REPO_URL")
  DIR_NAME="${BASE%.git}"
fi

if [[ -d "$DIR_NAME" ]]; then
  echo "Error: Directory '$DIR_NAME' already exists." >&2
  exit 1
fi

echo "==> Creating project directory: $DIR_NAME"
mkdir -p "$DIR_NAME"
cd "$DIR_NAME"

echo "==> Cloning bare repository into .git..."
git clone --bare "$REPO_URL" .git

echo "==> Configuring remote fetch refspec..."
git --git-dir=.git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

echo "==> Fetching all remote branches..."
git --git-dir=.git fetch origin

# Detect default branch from remote HEAD
DEFAULT_BRANCH=$(git --git-dir=.git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)

if [[ -z "$DEFAULT_BRANCH" ]]; then
  if git --git-dir=.git show-ref --verify --quiet refs/heads/main || git --git-dir=.git show-ref --verify --quiet refs/remotes/origin/main; then
    DEFAULT_BRANCH="main"
  elif git --git-dir=.git show-ref --verify --quiet refs/heads/master || git --git-dir=.git show-ref --verify --quiet refs/remotes/origin/master; then
    DEFAULT_BRANCH="master"
  else
    DEFAULT_BRANCH="main"
  fi
fi

echo "==> Checking out default worktree: '$DEFAULT_BRANCH'..."
git --git-dir=.git worktree add "$DEFAULT_BRANCH" "$DEFAULT_BRANCH"

cat <<EOF

✓ Setup complete!

Project Structure:
  $DIR_NAME/
  ├── .git/              (bare repository)
  └── $DEFAULT_BRANCH/   (active working tree)

To start working:
  cd $DIR_NAME/$DEFAULT_BRANCH
EOF

cat <<'EOF'

Helpful shell aliases (add to your `.zshrc` or `.bashrc`):

  alias gwa="git worktree add"
  alias gwl="git worktree list"
  alias gwr="git worktree remove"
  alias gwp="git worktree prune"

  # Create a new feature worktree from main: gwf feat-my-feature
  gwf() {
    if [ -z "$1" ]; then
      echo "Usage: gwf <feature-branch-name>"
      return 1
    fi
    git worktree add "$1" -b "$1" main
  }
EOF
