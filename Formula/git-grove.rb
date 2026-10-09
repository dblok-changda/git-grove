# Homebrew formula. Install with:
#   brew tap dblok-changda/git-grove https://github.com/dblok-changda/git-grove
#   brew install dblok-changda/git-grove/git-grove
class GitGrove < Formula
  desc "Bare-repo and worktree workflow: set up with init, tidy with cleanup"
  homepage "https://github.com/dblok-changda/git-grove"
  url "https://github.com/dblok-changda/git-grove/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "13035ea644582fa9b87fa2a010bbf5ea04bd6747fad42bf10b10f59bcf5b9412"
  head "https://github.com/dblok-changda/git-grove.git", branch: "main"

  depends_on "git"

  def install
    bin.install "git-grove", "git-cleanup", "git-worktree-init"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/git-grove --version")
    assert_match version.to_s, shell_output("#{bin}/git-grove cleanup --version")
    assert_match version.to_s, shell_output("#{bin}/git-grove init --version")
  end
end
