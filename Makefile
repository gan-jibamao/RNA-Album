export TARGET = iphone:clang:latest:14.0

# 允许命令行覆盖: make ARCHS=arm64e / make ARCHS="arm64 arm64e"
# 不传时默认双架构
ifeq ($(strip $(ARCHS)),)
export ARCHS = arm64 arm64e
else
export ARCHS := $(strip $(ARCHS))
endif

export THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = RNAAlbum
RNAAlbum_FILES = Tweak.xm
RNAAlbum_CFLAGS = -fobjc-arc -std=c++11 -Wno-deprecated-declarations
RNAAlbum_FRAMEWORKS = UIKit PhotosUI Photos
RNAAlbum_PRIVATE_FRAMEWORKS =

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 12123 || true"
