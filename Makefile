PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: install uninstall test test-bash3 lint

install:
	install -d "$(BINDIR)"
	install -m 0755 git-cleanup "$(BINDIR)/git-cleanup"
	@echo "Installed $(BINDIR)/git-cleanup  (also available as: git cleanup)"

uninstall:
	rm -f "$(BINDIR)/git-cleanup"

test:
	tests/test-cleanup.sh

# macOS ships bash 3.2 at /bin/bash; the tool must keep working there.
test-bash3:
	TEST_BASH=/bin/bash tests/test-cleanup.sh

lint:
	shellcheck -s bash git-cleanup install.sh tests/test-cleanup.sh tests/make-fixture.sh
