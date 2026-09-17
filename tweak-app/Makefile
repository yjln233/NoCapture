include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoCaptureApp

NoCaptureApp_FILES = Tweak.x ../common/NCPrefs.m ../common/NCUtils.m
NoCaptureApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I.. -I../common
NoCaptureApp_FRAMEWORKS = Foundation
# UIKit 弱链接:本 dylib 只注入含 UIApplication 的 App 进程(见 NoCaptureApp.plist),
# 弱链接可以避免误注入到 rm 这类无 UI 进程时 dyld 强加载 UIKit 导致崩溃。
NoCaptureApp_LDFLAGS = -weak_framework UIKit

# NC_DEBUG_BUILD=1 时编译出「注入即全开」的调试版(绕过设置面板验证功能)
ifdef NC_DEBUG_BUILD
NoCaptureApp_CFLAGS += -DNC_FORCE_ALWAYS=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk
