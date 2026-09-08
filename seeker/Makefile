THEOS ?= $(abspath ../dev/theos)
TARGET := iphone:clang:16.5:18.0.1
ARCHS := arm64
ifeq ($(PACKAGE_FORMAT),ipa)
THEOS_PACKAGE_SCHEME :=
# Keep IPA signing/staging separate from the existing jailbreak package.
_THEOS_RELATIVE_DATA_DIR := .theos/ipa
else
THEOS_PACKAGE_SCHEME := rootless
endif
FINALPACKAGE := 1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := xz

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Seeker
Seeker_FILES := main.m Detection.m
Seeker_FRAMEWORKS := UIKit Foundation Security
Seeker_CFLAGS := -fobjc-arc -Wall -Wextra -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
ifeq ($(PACKAGE_FORMAT),ipa)
# Ad hoc input for a sideload signer; no jailbreak-only entitlements.
Seeker_CODESIGN_FLAGS := -S
else
Seeker_CODESIGN_FLAGS := -Sentitlements.plist
endif
Seeker_RESOURCE_DIRS := Resources

include $(THEOS_MAKE_PATH)/application.mk

ifneq ($(PACKAGE_FORMAT),ipa)
before-package::
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/postrm
endif
