# This file is part of MXE. See LICENSE.md for licensing information.
# Initial package scaffold generated with the "gsrc" tool:
# https://github.com/hkunz/git-fetcher

# BEGIN_INCLUDE
include src/common/pkgconfig-generator.mk
# END_INCLUDE

PKG             := ${PACKAGE}
$(PKG)_WEBSITE  := ${WEBSITE}
$(PKG)_DESCR    := ${DESCRIPTION}
$(PKG)_VERSION  := ${VERSION}
$(PKG)_IGNORE   := ${IGNORE}
$(PKG)_CHECKSUM := ${CHECKSUM}
# BEGIN_GITHUB
$(PKG)_GH_CONF  := ${OWNER_REPO}/${GH_MODE}${ARCHIVE_FORMAT}
# END_GITHUB
# BEGIN_NON_GITHUB
$(PKG)_FILE     := ${TAR_NAME}
$(PKG)_SUBDIR   := ${SUBDIR_NAME}
$(PKG)_URL      := ${ARCHIVE_URL}
# END_NON_GITHUB
$(PKG)_DEPS     := ${DEPENDENCIES}

define $(PKG)_BUILD

# BEGIN_CMAKE
	# configure package with cmake
	cd "$(BUILD_DIR)" && "$(TARGET)-cmake" "$(SOURCE_DIR)" \
		-DCMAKE_INSTALL_PREFIX="$(PREFIX)/$(TARGET)" \
		-DCMAKE_PREFIX_PATH="$(PREFIX)/$(TARGET)" \
		-DBUILD_SHARED_LIBS=$(CMAKE_SHARED_BOOL) \
${BUILD_OPTIONS_MULTILINE}
# END_CMAKE
# BEGIN_MESON
	# configure package with meson
	$(MXE_MESON_WRAPPER) $(MXE_MESON_OPTS) \
${BUILD_OPTIONS_MULTILINE}
		"$(BUILD_DIR)" "$(SOURCE_DIR)${PKG_SUBFOLDER}"
# END_MESON
# BEGIN_OTHER_BUILD_SYSTEM
	# Configure package
	cd "$(BUILD_DIR)" && "$(SOURCE_DIR)/configure" \
		$(MXE_CONFIGURE_OPTS) \
		--host="$(TARGET)" \
		--prefix="$(PREFIX)/$(TARGET)"
# END_OTHER_BUILD_SYSTEM

	# build package and install
	$(${MAKE_CMD}) -C "$(BUILD_DIR)" -j $(JOBS)
	$(${MAKE_CMD}) -C "$(BUILD_DIR)" -j 1 install

# BEGIN_PC_FILE
	# Only needed if the project does not ship a .pc file
	$(call GENERATE_PC, \
		$(PREFIX)/$(TARGET), \
		$(PKG), \
		$($(PKG)_DESCR), \
		$($(PKG)_VERSION), \
		${REQUIRES}, \
		${REQUIRES_PRIVATE}, \
		${LIBS}, \
		${LIBS_PRIVATE}, \
		${CFLAGS}, \
		${CFLAGS_PRIVATE}, \
	)
# END_PC_FILE

	# compile a test program to verify the library is usable
	"$(TARGET)-g++" -Wall -Wextra "$(TEST_FILE)" \
		-o "$(PREFIX)/$(TARGET)/bin/test-$(PKG).exe" \
		`"$(TARGET)-pkg-config" "${PC_FILE_NAME}" --cflags --libs`
endef
