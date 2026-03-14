# This file is part of MXE. See LICENSE.md for licensing information.

include src/common/pkgutils.mk

pkg				:= libname
$(PKG)_WEBSITE	:= https://github.com/repository/libname
$(PKG)_DESCR	:= Example C++ library for MXE package template
$(PKG)_VERSION	:= 1.2.3  # example tag version; use 'master' or 'main' if the project has no tags or fork project and create a tag
$(PKG)_CHECKSUM	:= XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# GitHub-hosted packages: (remove if not GitHub-hosted)
$(PKG)_GH_CONF 	:= repository/libname/tags,v  # Git-style tag path; keep ',v' only if the repository prepends 'v' to tags (e.g., v1.2.3)

# Non-GitHub packages: (remove the following 3 lines if GitHub-hosted)
$(PKG)_URL		:= https://example.com/$(PKG)/archive/v$($(PKG)_VERSION).tar.gz
$(PKG)_SUBDIR	:= $(PKG)-$($(PKG)_VERSION)  # folder name after extracting archive
$(PKG)_FILE		:= $(PKG)-$($(PKG)_VERSION).tar.gz  # downloaded archive file name

$(PKG)_DEPS		:= cc libname1 libname2 libname3

define $(PKG)_BUILD

	# =========================================================================
	# Build with CMake (Remove this block if the project does not use CMake)
	# =========================================================================
	cd "$(BUILD_DIR)" && \
		'$(TARGET)-cmake' "$(SOURCE_DIR)" \
			-DCMAKE_INSTALL_PREFIX='$(PREFIX)/$(TARGET)' \
			-DCMAKE_PREFIX_PATH='$(PREFIX)/$(TARGET)' \
			-DBUILD_SHARED_LIBS=$(CMAKE_SHARED_BOOL) \
			-DCMAKE_BUILD_TYPE=Release \

	$(MAKE) -C '$(BUILD_DIR)' -j '$(JOBS)'
	$(MAKE) -C '$(BUILD_DIR)' -j 1 install

	# =========================================================================
	# Build with Meson (Remove this block if the project does not use Meson)
	# =========================================================================
	'$(MXE_MESON_WRAPPER)' $(MXE_MESON_OPTS) \
		-Denable_example_flag1=true \
		-Denable_example_flag2=false \
		'$(BUILD_DIR)' '$(SOURCE_DIR)/libname'

	'$(MXE_NINJA)' -C '$(BUILD_DIR)' -j '$(JOBS)'
	'$(MXE_NINJA)' -C '$(BUILD_DIR)' -j 1 install

	# =========================================================================
	# Optional: add support for other build systems here
	# =========================================================================

	# ==============================================================
	# Generate pkg-config (.pc) file (see src/common/pkgutils.mk)
	# ==============================================================
	# Only needed if the project does not ship a .pc file
	# Example:
	# $(call GENERATE_PC, \
	#	$(PREFIX)/$(TARGET), \
	#	libname, \
	#	Library description here, \
	#	$($(PKG)_VERSION), \
	#	libjpeg libpng, \
	#	, \
	#	-lsjpeg -ljpeg -lpng, \
	# )

	# ==============================================================
	# Compile a test program to verify the library is usable
	# ==============================================================
	'$(TARGET)-g++' '$(TEST_FILE)' \
		-o '$(PREFIX)/$(TARGET)/bin/test-$(PKG).exe' \
		`$(TARGET)-pkg-config libname --cflags --libs`
endef

# ================================
# Optional patch example
# ================================
# Use before running make
# tmpfile=$(mktemp) || exit 1
# $(SED) 's/search_str/replace_str/' "$(SOURCE_DIR)/CMakeLists.txt" > "$tmpfile" && mv "$tmpfile" "$(SOURCE_DIR)/CMakeLists.txt"
# Recommended: use a .patch file for reproducible builds
