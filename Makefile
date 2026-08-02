PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: all install uninstall test clean

all:
	bash bld/build.sh

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	cp bin/camopass $(DESTDIR)$(BINDIR)/camopass
	chmod 755 $(DESTDIR)$(BINDIR)/camopass
	@echo "CamoPass binary successfully installed to $(DESTDIR)$(BINDIR)/camopass!"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/camopass
	@echo "CamoPass uninstalled successfully."

test:
	@echo "Running test suite..."
	luam tst/test_obfuscator.lua
	luam tst/test_cli.lua

clean:
	rm -rf bin/ obj/
	@echo "Cleaned build artifacts."
