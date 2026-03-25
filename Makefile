# ==============================
# Minimal Standard Template Makefile
# ==============================

# Package info
PACKAGE_NAME    ?= mypackage
PACKAGE_NAME_ORIGINAL ?= mypackage
VERSION         ?= undefined
ARCHIVE_VERSION ?= undefined
ARCHIVE_URL     ?= https://example.com/$(PACKAGE_NAME)-$(ARCHIVE_VERSION).tar.gz
ARCHIVE_FILE    ?= $(PACKAGE_NAME)-$(ARCHIVE_VERSION).tar.gz

# Directories
SRC_DIR         ?= tmp/src/$(PACKAGE_NAME)
BUILD_DIR       ?= tmp/build/$(PACKAGE_NAME)
DOWNLOAD_DIR    ?= downloads

# Tools (override if needed)
CURL    ?= curl -L -o
TAR     ?= tar xzf
MAKE    ?= make
CC      ?= gcc
CXX     ?= g++

# Flags
CFLAGS  ?= -O2 -Wall
CXXFLAGS ?= $(CFLAGS)
LDFLAGS ?=

# ==============================
# Targets
# ==============================

.PHONY: all clean

all:
	@echo "[*] Placeholder target for $(PACKAGE_NAME)"
	@echo "[*] Fill this with actual build steps"

clean:
	@echo "[*] Removing temporary and download directories"
	@rm -rf tmp/ $(DOWNLOAD_DIR)/
