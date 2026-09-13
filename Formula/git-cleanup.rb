# Homebrew formula. Install with:
#   brew tap dblok-changda/git-cleanup https://github.com/dblok-changda/git-cleanup
#   brew install dblok-changda/git-cleanup/git-cleanup
class GitCleanup < Formula
  desc "Audit and safely remove merged Git branches, obsolete worktrees, and stale refs"
  homepage "https://github.com/dblok-changda/git-cleanup"
  head "https://github.com/dblok-changda/git-cleanup.git", branch: "main"

  depends_on "git"

  def install
    bin.install "git-cleanup"
  end

  test do
    assert_match "git-cleanup", shell_output("#{bin}/git-cleanup --version")
  end
end
