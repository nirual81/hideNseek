THEOS ?= $(abspath ../dev/theos)
TARGET := iphone:clang:16.5:18.0.1
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
FINALPACKAGE := 1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := xz
# Clang 22 emits the current arm64e ABI. Keep Theos's existing linker/signing tools.
TARGET_CC := bash $(abspath ../dev/hider-clang.sh)
TARGET_CXX := $(TARGET_CC)
# Theos otherwise replaces TARGET_LD with TARGET_CXX for Objective-C++ files.
override TARGET_LD := $(THEOS)/toolchain/linux/iphone/bin/clang++
# Pinned Theos otherwise selects legacy libroot just because the host is Linux.
override IS_NEW_ABI := 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Hider
Hider_FILES := Tweak.xm
Hider_FRAMEWORKS := Foundation
Hider_CFLAGS := -fobjc-arc -Wall -Wextra -gdwarf-4 -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
Hider_INSTALL_PATH := /usr/lib/TweakInject

BUNDLE_NAME := HiderPrefs
HiderPrefs_FILES := Settings.m
HiderPrefs_FRAMEWORKS := UIKit Foundation CoreServices
HiderPrefs_PRIVATE_FRAMEWORKS := Preferences
HiderPrefs_CFLAGS := -fobjc-arc -Wall -Wextra -gdwarf-4 -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
HiderPrefs_INSTALL_PATH := /Library/PreferenceBundles
HiderPrefs_RESOURCE_DIRS := Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

before-package::
	chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
