THEOS ?= $(abspath ../dev/theos)
TARGET := iphone:clang:16.5:18.0.1
ARCHS := arm64
THEOS_PACKAGE_SCHEME := rootless
FINALPACKAGE := 1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := xz

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Seeker
Seeker_FILES := main.m Detection.m
Seeker_FRAMEWORKS := UIKit Foundation Security
Seeker_CFLAGS := -fobjc-arc -Wall -Wextra -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
Seeker_CODESIGN_FLAGS := -Sentitlements.plist
Seeker_RESOURCE_DIRS := Resources

include $(THEOS_MAKE_PATH)/application.mk

before-package::
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/postrm
