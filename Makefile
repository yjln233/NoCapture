ifeq ($(THEOS),)
export THEOS = $(HOME)/theos
endif

export THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0

# 本机 $(THEOS)/sdks 下若没有任何 iPhoneOS SDK,则回退到 Xcode 自带的 SDK
ifeq ($(wildcard $(THEOS)/sdks/*.sdk),)
export SYSROOT = $(shell xcrun --sdk iphoneos --show-sdk-path)
endif

# 注意:这里刻意不含 SpringBoard 侧 tweak。
# 早期版本曾在 SpringBoard 里无条件 hook FBScene.sendActions: 做"源头截屏事件过滤",
# 那是 scene 事件分发的核心方法,hook 它会在热路径上执行偏好读取并可能拖垮 SpringBoard,
# 现已整体移除,所有屏蔽逻辑都放在 App 进程内完成。
SUBPROJECTS += tweak-app prefs

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
