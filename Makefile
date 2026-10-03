export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoRec
AutoRec_FILES = Tweak.x ARCore.m AROverlay.m ARPrefs.m
AutoRec_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore IOKit
AutoRec_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = AutoM8
AutoM8_FILES = AutoM8/main.m AutoM8/AMAppDelegate.m AutoM8/AMViewController.m ARPrefs.m ARCore.m
AutoM8_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore IOKit UniformTypeIdentifiers
AutoM8_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
AutoM8_INFO_PLIST = AutoM8/Info.plist
AutoM8_INSTALL_PATH = /Applications
AutoM8_RESOURCES = AutoM8/Icon-60.png AutoM8/Icon-60@2x.png AutoM8/Icon-60@3x.png

include $(THEOS_MAKE_PATH)/application.mk
