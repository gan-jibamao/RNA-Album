export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = RNAAlbum
RNAAlbum_FILES = Tweak.xm
RNAAlbum_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RNAAlbum_FRAMEWORKS = UIKit PhotosUI Photos
RNAAlbum_PRIVATE_FRAMEWORKS =

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 12123 || true"
