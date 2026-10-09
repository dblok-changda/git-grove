PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: install uninstall test test-bash3 lint

install:
	install -d "$(BINDIR)"
	install -m 0755 git-worktree-init "$(BINDIR)/git-worktree-init"
	@echo "Installed $(BINDIR)/git-worktree-init  (also available as: git worktree-init)"

uninstall:
	rm -f "$(BINDIR)/git-worktree-init"

test:
	tests/run-tests.sh

# macOS ships bash 3.2 at /bin/bash; the tool must keep working there.
test-bash3:
	TEST_BASH=/bin/bash tests/run-tests.sh

lint:
	shellcheck -s bash git-worktree-init install.sh tests/run-tests.sh
