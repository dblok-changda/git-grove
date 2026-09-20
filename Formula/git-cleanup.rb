# Homebrew formula. Install with:
#   brew tap dblok-changda/git-cleanup https://github.com/dblok-changda/git-cleanup
#   brew install dblok-changda/git-cleanup/git-cleanup
class GitCleanup < Formula
  desc "Audit and safely remove merged Git branches, obsolete worktrees, and stale refs"
  homepage "https://github.com/dblok-changda/git-cleanup"
  url "https://github.com/dblok-changda/git-cleanup/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "680d5cfb8403566046c6cd0a93082b76d227518b0681c0347876551d1cf6d4e5"
  head "https://github.com/dblok-changda/git-cleanup.git", branch: "main"

  depends_on "git"

  def install
    bin.install "git-cleanup"
  end

  test do
    assert_match "git-cleanup", shell_output("#{bin}/git-cleanup --version")
  end
end
