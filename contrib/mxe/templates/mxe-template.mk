# This file is part of MXE. See LICENSE.md for licensing information.

# BEGIN_INCLUDE
include src/common/pkgutils.mk
# END_INCLUDE

PKG             := ${PACKAGE}
$(PKG)_WEBSITE  := ${WEBSITE}
$(PKG)_DESCR    := ${DESCRIPTION}
$(PKG)_VERSION  := ${VERSION}
$(PKG)_IGNORE   := ${IGNORE}
$(PKG)_CHECKSUM := ${CHECKSUM}
# BEGIN_GITHUB
$(PKG)_GH_CONF  := ${OWNER_REPO}/tags${ARCHIVE_FORMAT}
# END_GITHUB
# BEGIN_NON_GITHUB
$(PKG)_URL      := ${ARCHIVE_URL}
$(PKG)_SUBDIR   := $(PKG)-$($(PKG)_VERSION)
$(PKG)_FILE     := $(PKG)-$($(PKG)_VERSION).tar.gz
# END_NON_GITHUB
$(PKG)_DEPS     := ${DEPENDENCIES}

define $(PKG)_BUILD

# BEGIN_CMAKE
	# configure package with cmake
	cd "$(BUILD_DIR)" && '$(TARGET)-cmake' "$(SOURCE_DIR)" \
		-DCMAKE_INSTALL_PREFIX='$(PREFIX)/$(TARGET)' \
		-DCMAKE_PREFIX_PATH='$(PREFIX)/$(TARGET)' \
		-DBUILD_SHARED_LIBS=$(CMAKE_SHARED_BOOL) \
${BUILD_OPTIONS_MULTILINE}

	# build cmake package and install
	$(MAKE) -C '$(BUILD_DIR)' -j '$(JOBS)'
	$(MAKE) -C '$(BUILD_DIR)' -j 1 install
# END_CMAKE
# BEGIN_MESON
	# configure package with meson
	'$(MXE_MESON_WRAPPER)' $(MXE_MESON_OPTS) \
		-Dprefix=/usr/local \
		-Dlibdir=lib \
		-Dbindir=bin \
${BUILD_OPTIONS_MULTILINE}
		'$(BUILD_DIR)' '$(SOURCE_DIR)/$(PKG)'

	# build meson package and install
	'$(MXE_NINJA)' -C '$(BUILD_DIR)' -j '$(JOBS)'
	'$(MXE_NINJA)' -C '$(BUILD_DIR)' -j 1 install
# END_MESON
# BEGIN_OTHER_BUILD_SYSTEM
    # Configure package
	# Build package and install
# END_OTHER_BUILD_SYSTEM

# BEGIN_PC_FILE
	# Only needed if the project does not ship a .pc file
	# $(call GENERATE_PC, \
	#	$(PREFIX)/$(TARGET), \
	#	$(PKG), \
	#	$($(PKG)_DESCR), \
	#	$($(PKG)_VERSION), \
	#	${REQUIRES}, \
	#	${REQUIRES_PRIVATE}, \
	#	${LIBS}, \
	#	${LIBS_PRIVATE}, \
	#	${CFLAGS}, \
	#	${CFLAGS_PRIVATE}, \
	# )
# END_PC_FILE

	# compile a test program to verify the library is usable
	'$(TARGET)-g++' '$(TEST_FILE)' \
		-o '$(PREFIX)/$(TARGET)/bin/test-$(PKG).exe' \
		`$(TARGET)-pkg-config $(PKG) --cflags --libs`
endef
