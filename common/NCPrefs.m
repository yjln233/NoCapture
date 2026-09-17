#import "NCPrefs.h"
#import <Foundation/NSUserDefaults+Private.h>
#import <os/lock.h>

NSString *const NCPrefsDomain = @"com.anfangyi.nocapture";
NSString *const NCPrefsChangedDarwinNotification = @"com.anfangyi.nocapture.prefsChanged";

NSString *const NCPrefsKeyEnabled = @"enabled";
NSString *const NCPrefsKeyScreenshotNotice = @"screenshotNotice";
NSString *const NCPrefsKeyCaptureState = @"captureState";
NSString *const NCPrefsKeyCaptureNotice = @"captureNotice";
NSString *const NCPrefsKeyRecordingState = @"recordingState";
NSString *const NCPrefsKeyExternalDisplay = @"externalDisplay";
NSString *const NCPrefsKeyForegroundState = @"foregroundState";
NSString *const NCPrefsKeyForegroundNotice = @"foregroundNotice";
NSString *const NCPrefsKeyForegroundCallback = @"foregroundCallback";
NSString *const NCPrefsKeyProtectedData = @"protectedData";
NSString *const NCPrefsKeyProtectAllApps = @"protectAllApps";
NSString *const NCPrefsKeyBlockedApps = @"blockedApps";

/// 保护缓存读写:偏好刷新发生在后台队列,而读取可能来自主线程、通知分发线程等任意线程,
/// 直接替换/读取 NSDictionary 存在数据竞争(读到正在释放的对象会随机崩溃)。
static os_unfair_lock NCPrefsCacheLock = OS_UNFAIR_LOCK_INIT;

static NSArray<NSString *> *NCPrefsAllKeys(void) {
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[NCPrefsKeyEnabled, NCPrefsKeyScreenshotNotice, NCPrefsKeyCaptureState,
                 NCPrefsKeyCaptureNotice, NCPrefsKeyRecordingState, NCPrefsKeyExternalDisplay,
                 NCPrefsKeyForegroundState, NCPrefsKeyForegroundNotice, NCPrefsKeyForegroundCallback,
                 NCPrefsKeyProtectedData, NCPrefsKeyProtectAllApps, NCPrefsKeyBlockedApps];
    });
    return keys;
}

NSString *NCJailbreakRootPath(void) {
    static NSString *rootPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rootPath = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    });
    return rootPath;
}

/// 偏好的候选文件位置。rootless 下由 cfprefsd 重定向到 /var/jb,但不同越狱/版本
/// 的落地路径不完全一致,所以这里全列出来逐个找。
static NSArray<NSString *> *NCPrefsFilePaths(void) {
    static NSArray<NSString *> *paths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *relative = @"/var/mobile/Library/Preferences/com.anfangyi.nocapture.plist";
        NSMutableArray *candidates = [NSMutableArray array];
        NSString *root = NCJailbreakRootPath();
        if (root.length > 0) {
            [candidates addObject:[root stringByAppendingString:relative]];
        }
        [candidates addObject:relative];
        [candidates addObject:[@"/var/jb/private" stringByAppendingString:relative]];
        paths = candidates;
    });
    return paths;
}

static NSString *NCPrefsFilePath(void) {
    return NCPrefsFilePaths().firstObject;
}

id NCReadPref(NSString *key) {
    if (key.length == 0) return nil;

    // 同步磁盘 I/O:只允许在后台队列(见 -reload)、构造期(见 reloadSynchronously)
    // 或设置 App 里调用。
    //
    // 读法用三通道,原因是"App 进程能否读到设置 App 写的偏好"在沙箱下不是必然成立:
    // 设 A: CFPreferences 当前用户 —— 设置面板写入用的就是这个
    // 设 B: CFPreferences 任意用户/任意主机 —— 跨进程最可靠的读法
    // 设 C: 直接读 plist 文件 —— cfprefsd 因沙箱拒答时最后的兜底
    // 首选 theos 官方模板的做法:-[NSUserDefaults objectForKey:inDomain:]
    // 这是 Foundation 的私有方法,专为读指定域设计,跨进程读设置面板写入值最可靠。
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key inDomain:NCPrefsDomain];
    if (value) {
        return value;
    }

    CFStringRef domain = (__bridge CFStringRef)NCPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef cfValue = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    if (cfValue) {
        return (__bridge_transfer id)cfValue;
    }

    cfValue = CFPreferencesCopyValue((__bridge CFStringRef)key, domain,
                                     kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    if (cfValue) {
        return (__bridge_transfer id)cfValue;
    }

    for (NSString *path in NCPrefsFilePaths()) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (plist[key]) {
            return plist[key];
        }
    }
    return nil;
}

void NCPostPrefsChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)NCPrefsChangedDarwinNotification,
                                         NULL, NULL, true);
}

void NCWritePref(NSString *key, id value) {
    if (key.length == 0) return;
    CFStringRef domain = (__bridge CFStringRef)NCPrefsDomain;

    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key inDomain:NCPrefsDomain];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             domain);
    CFPreferencesAppSynchronize(domain);

    // 再同步落一份文件:App 进程受沙箱限制,cfprefsd 有可能会拒答跨进程域的读取,
    // 写成 plist 文件能保证被注入的 App 进程一定读得到同一份开关。
    NSString *path = NCPrefsFilePath();
    if (path.length > 0) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
        if (!dict) dict = [NSMutableDictionary dictionary];
        dict[key] = value;
        [dict writeToFile:path atomically:YES];
    }

    NCPostPrefsChanged();
}

static void NCPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                   const void *object, CFDictionaryRef userInfo) {
    NCPrefs *prefs = (__bridge NCPrefs *)observer;
    if (!prefs) return;
    // 不在通知分发线程上做同步 I/O
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [prefs reload];
    });
}

@implementation NCPrefs {
    NSDictionary *_cache;
}

+ (instancetype)sharedInstance {
    static NCPrefs *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NCPrefs alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 关键:构造过程绝不读磁盘。
        // 本类第一次被访问的位置可能是 NSNotificationCenter 的分发路径、UI 事件回调等
        // 任意线程,同步读偏好会造成可感知卡顿,严重时触发看门狗。
        // 因此这里先用"全部关闭"的空缓存,真实偏好交给后台队列异步载入。
        _cache = @{};

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self reload];
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        NCPrefsChangedCallback,
                                        (__bridge CFStringRef)NCPrefsChangedDarwinNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)reload {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *key in NCPrefsAllKeys()) {
        id value = NCReadPref(key);
        if (value) dict[key] = value;
    }
    NSDictionary *snapshot = [dict copy];

    os_unfair_lock_lock(&NCPrefsCacheLock);
    _cache = snapshot;
    os_unfair_lock_unlock(&NCPrefsCacheLock);
}

- (void)reloadSynchronously {
    // 同步读一次磁盘:用于进程启动时立即确定生效状态。
    // 高频路径不要调用这个,用缓存的读取接口。
    [self reload];
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    os_unfair_lock_lock(&NCPrefsCacheLock);
    id value = _cache[key];
    BOOL result = value ? [value boolValue] : defaultValue;
    os_unfair_lock_unlock(&NCPrefsCacheLock);
    return result;
}

- (BOOL)enabled { return [self boolForKey:NCPrefsKeyEnabled defaultValue:NO]; }
- (BOOL)screenshotNotice { return [self boolForKey:NCPrefsKeyScreenshotNotice defaultValue:NO]; }
- (BOOL)captureState { return [self boolForKey:NCPrefsKeyCaptureState defaultValue:NO]; }
- (BOOL)captureNotice { return [self boolForKey:NCPrefsKeyCaptureNotice defaultValue:NO]; }
- (BOOL)recordingState { return [self boolForKey:NCPrefsKeyRecordingState defaultValue:NO]; }
- (BOOL)externalDisplay { return [self boolForKey:NCPrefsKeyExternalDisplay defaultValue:NO]; }
- (BOOL)foregroundState { return [self boolForKey:NCPrefsKeyForegroundState defaultValue:NO]; }
- (BOOL)foregroundNotice { return [self boolForKey:NCPrefsKeyForegroundNotice defaultValue:NO]; }
- (BOOL)foregroundCallback { return [self boolForKey:NCPrefsKeyForegroundCallback defaultValue:NO]; }
- (BOOL)protectedData { return [self boolForKey:NCPrefsKeyProtectedData defaultValue:NO]; }
- (BOOL)protectAllApps { return [self boolForKey:NCPrefsKeyProtectAllApps defaultValue:NO]; }

- (NSArray<NSString *> *)blockedApps {
    os_unfair_lock_lock(&NCPrefsCacheLock);
    id value = _cache[NCPrefsKeyBlockedApps];
    NSArray *result = [value isKindOfClass:[NSArray class]] ? value : @[];
    os_unfair_lock_unlock(&NCPrefsCacheLock);
    return result;
}

- (BOOL)shouldProtectBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return NO;
    if (!self.enabled) return NO;
    if ([bundleIdentifier hasPrefix:@"com.apple."]) return NO;
    if (self.protectAllApps) return YES;
    return [self.blockedApps containsObject:bundleIdentifier];
}

@end
