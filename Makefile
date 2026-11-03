export TARGET = iphone:clang:latest:14.0

# 允许命令行覆盖: make ARCHS=arm64e / make ARCHS="arm64 arm64e"
ifeq ($(strip $(ARCHS)),)
export ARCHS = arm64 arm64e
else
export ARCHS := $(strip $(ARCHS))
endif

# roothide: 越狱根为随机 jbroot，包内不得带 /var/jb 前缀
# rootless: 传统 /var/jb 布局
# 需要旧布局时: make THEOS_PACKAGE_SCHEME=rootless
ifeq ($(strip $(THEOS_PACKAGE_SCHEME)),)
export THEOS_PACKAGE_SCHEME = roothide
else
export THEOS_PACKAGE_SCHEME := $(strip $(THEOS_PACKAGE_SCHEME))
endif

TWEAK_NAME = RNAAlbum
RNAAlbum_FILES = Tweak.xm
RNAAlbum_CFLAGS = -fobjc-arc -std=c++11 -Wno-deprecated-declarations
RNAAlbum_FRAMEWORKS = UIKit PhotosUI Photos
RNAAlbum_PRIVATE_FRAMEWORKS =

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 12123 || true"
