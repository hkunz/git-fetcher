# This file is part of MXE. See LICENSE.md for licensing information.

include src/common/pkgutils.mk

PKG				:= ${PACKAGE}
$(PKG)_WEBSITE	:= ${WEBSITE}
$(PKG)_DESCR	:= ${DESCRIPTION}
$(PKG)_VERSION	:= ${VERSION}
$(PKG)_IGNORE	:= ${IGNORE}
$(PKG)_CHECKSUM	:= ${CHECKSUM}
${GITHUB_CONF}
$(PKG)_GH_CONF 	:= ${OWNER_REPO}/tags,v
${NON_GITHUB}
$(PKG)_URL		:= https://example.com/$(PKG)/archive/v$($(PKG)_VERSION).tar.gz
$(PKG)_SUBDIR	:= $(PKG)-$($(PKG)_VERSION)  # folder name after extracting archive
$(PKG)_FILE		:= $(PKG)-$($(PKG)_VERSION).tar.gz  # downloaded archive file name
$(PKG)_DEPS		:= ${DEPENDENCIES}

define $(PKG)_BUILD

	# configure package with cmake
	cd "$(BUILD_DIR)" && '$(TARGET)-cmake' "$(SOURCE_DIR)" \
		-DCMAKE_INSTALL_PREFIX='$(PREFIX)/$(TARGET)' \
		-DCMAKE_PREFIX_PATH='$(PREFIX)/$(TARGET)' \
		-DBUILD_SHARED_LIBS=$(CMAKE_SHARED_BOOL) \
${CMAKE_FLAGS}

	# build cmake package and install
	$(MAKE) -C '$(BUILD_DIR)' -j '$(JOBS)'
	$(MAKE) -C '$(BUILD_DIR)' -j 1 install

	# Only needed if the project does not ship a .pc file
	# $(call GENERATE_PC, \
	#	$(PREFIX)/$(TARGET), \
	#	$(PKG), \
	#	${DESCRIPTION}, \
	#	$($(PKG)_VERSION), \
	#	${REQUIRES}, \
	#	${REQUIRES_PRIVATE}, \
	#	${LIBS}, \
	#	${LIBS_PRIVATE}, \
	#	${CFLAGS}, \
	#	${CFLAGS_PRIVATE}, \
	# )

	# compile a test program to verify the library is usable
	'$(TARGET)-g++' '$(TEST_FILE)' \
		-o '$(PREFIX)/$(TARGET)/bin/test-$(PKG).exe' \
		`$(TARGET)-pkg-config $(PKG) --cflags --libs`
endef
