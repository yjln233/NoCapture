include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NoCapturePrefs

NoCapturePrefs_FILES = NCPRootListController.m \
                       NCPSectionListController.m \
                       NCPAppListController.m \
                       NCPApps.m \
                       ../common/NCPrefs.m \
                       ../common/NCUtils.m

NoCapturePrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I.. -I../common
NoCapturePrefs_FRAMEWORKS = UIKit Foundation
# 只对 Preferences.framework(设备私有框架)做动态查找。
# 注意:不要在这里引用 libSparkAppList 之类的第三方库的类,
# 继承外部类会在加载期产生必须解析的符号,缺失时整个面板载入失败。
NoCapturePrefs_LDFLAGS = -undefined dynamic_lookup
NoCapturePrefs_INSTALL_PATH = /Library/PreferenceBundles
NoCapturePrefs_RESOURCE_FILES = resources/Info.plist resources/icon.png resources/icon@2x.png resources/icon@3x.png \
                               resources/source.png resources/source@2x.png resources/source@3x.png

include $(THEOS_MAKE_PATH)/bundle.mk
