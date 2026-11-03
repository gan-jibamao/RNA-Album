export TARGET = iphone:clang:latest:14.0

# 12123 是 App Store 应用，主程序为 THIN arm64
# 因此默认只编 arm64 —— 纯 arm64e 的 dylib 根本加载不进 arm64 进程
ifeq ($(strip $(ARCHS)),)
export ARCHS = arm64
else
export ARCHS := $(strip $(ARCHS))
endif

ifeq ($(strip $(THEOS_PACKAGE_SCHEME)),)
export THEOS_PACKAGE_SCHEME = roothide
else
export THEOS_PACKAGE_SCHEME := $(strip $(THEOS_PACKAGE_SCHEME))
endif

TWEAK_NAME = RNAAlbum
RNAAlbum_FILES = Tweak.xm
RNAAlbum_CFLAGS = -fobjc-arc -std=c++11 -Wno-deprecated-declarations
RNAAlbum_FRAMEWORKS = UIKit PhotosUI Photos

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 12123 || true"
