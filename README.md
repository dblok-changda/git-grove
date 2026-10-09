# git-worktree-init

Clone a repository straight into a worktree-friendly layout: a bare repository in
`.git/` and one folder per branch next to it. Every branch you work on gets its own
directory, so switching tasks never means stashing or rebuilding.

```text
$ git worktree-init git@github.com:me/my-project.git
==> Creating project directory: my-project
==> Cloning bare repository into .git...
==> Configuring remote fetch refspec...
==> Fetching all remote branches...
==> Checking out default worktree: 'main'...

✓ Setup complete!

Project Structure:
  my-project/
  ├── .git/              (bare repository)
  └── main/   (active working tree)

To start working:
  cd my-project/main
```

## Why not `git clone --bare` and `git worktree add`?

A plain bare clone has no `remote.origin.fetch` refspec, so `git fetch` never creates
`origin/*` branches and new remote branches are invisible. git-worktree-init configures
the refspec, fetches everything, detects the remote's default branch (`main`, `master`,
`develop`, or anything else), and checks it out as the first worktree.

## Install

Requirements: Git 2.5 or newer, Bash 3.2 or newer (the macOS system Bash is fine), macOS
or Linux.

Pick one method. Each puts a single file, `git-worktree-init`, on your PATH.

**Homebrew**

```bash
brew tap dblok-changda/git-worktree-init https://github.com/dblok-changda/git-worktree-init
brew install dblok-changda/git-worktree-init/git-worktree-init
```

**One-line installer** (installs to `/usr/local/bin` if writable, otherwise `~/.local/bin`)

```bash
curl -fsSL https://raw.githubusercontent.com/dblok-changda/git-worktree-init/main/install.sh | bash
```

**From a clone**

```bash
git clone https://github.com/dblok-changda/git-worktree-init.git
cd git-worktree-init
make install                 # or: make install PREFIX="$HOME/.local"
```

**Manually**: copy `git-worktree-init` anywhere on your PATH and make it executable.

Afterwards both of these work, because Git runs any `git-<name>` found on PATH:

```bash
git-worktree-init --help
git worktree-init --help
```

Uninstall with `make uninstall`, `./install.sh --uninstall`, or
`brew uninstall git-worktree-init`.

## Usage

```bash
git worktree-init <repo-url> [target-directory]
```

| Argument | Meaning |
|---|---|
| `<repo-url>` | Any URL `git clone` accepts (SSH, HTTPS, `file://`) |
| `[target-directory]` | Folder to create. Defaults to the repository name without `.git`. Must not exist yet. |
| `-h`, `--help` | Show help |
| `--version` | Show version |

## Working in the layout

Run worktree commands from the project folder (`my-project/`) or from any worktree:

```bash
cd my-project
git worktree add feat-login -b feat-login main   # new branch from main
git worktree add fix-123 fix-123                 # existing branch
git worktree list
git worktree remove feat-login
```

When the script finishes it prints a few optional shell aliases (`gwa`, `gwl`, `gwr`,
`gwp`, and a `gwf` helper) you can paste into `~/.zshrc` or `~/.bashrc`.

## Testing

```bash
make test          # builds disposable repositories under $TMPDIR and checks the result
make test-bash3    # same, under the macOS system bash 3.2
make lint          # shellcheck
```

The tests never touch the network or a real repository.
