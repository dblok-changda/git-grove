PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

SCRIPTS = git-cleanup git-worktree-init
TESTS = tests/test-init.sh tests/test-cleanup.sh

.PHONY: install uninstall test test-bash3 lint

install:
	install -d "$(BINDIR)"
	for s in $(SCRIPTS); do install -m 0755 "$$s" "$(BINDIR)/$$s" || exit 1; done
	@echo "Installed $(SCRIPTS) to $(BINDIR)"

uninstall:
	for s in $(SCRIPTS); do rm -f "$(BINDIR)/$$s"; done

test:
	@status=0; for t in $(TESTS); do $$t || status=1; done; exit $$status

# macOS ships bash 3.2 at /bin/bash; every script must keep working there.
test-bash3:
	@status=0; for t in $(TESTS); do TEST_BASH=/bin/bash $$t || status=1; done; exit $$status

lint:
	shellcheck -s bash $(SCRIPTS) install.sh $(TESTS) tests/make-fixture.sh
