PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/camopass

.PHONY: all install uninstall test

all:
	@echo "CamoPass is ready to install! Run 'sudo make install'."

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	mkdir -p $(DESTDIR)$(LIBDIR)
	cp bin/camopass $(DESTDIR)$(BINDIR)/camopass
	chmod 755 $(DESTDIR)$(BINDIR)/camopass
	cp lib/obfuscator.luam $(DESTDIR)$(LIBDIR)/obfuscator.luam
	chmod 644 $(DESTDIR)$(LIBDIR)/obfuscator.luam
	@echo "CamoPass successfully installed to $(DESTDIR)$(BINDIR)/camopass!"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/camopass
	rm -rf $(DESTDIR)$(LIBDIR)
	@echo "CamoPass uninstalled successfully."

test:
	@echo "Running test suite..."
	luam tst/test_obfuscator.luam
