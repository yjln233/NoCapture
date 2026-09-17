// NoCapture — App 侧:让 App 检测不到截屏 / 录屏 / 投屏 / 切屏 / 锁屏
//
// 三条硬性约束(按重要性排序):
//   1. 不在保护范围内的 App,【一个 hook 都不装】—— 不产生任何开销和冲突。
//   2. 保护范围内的 App,也【只装开关打开的那几组 hook】—— 装得越少越安全。
//   3. hook 内部一律读无锁的全局标志,不做加锁、不做偏好查询 —— 热路径零成本。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>

#import "NCPrefs.h"
#import "NCUtils.h"

static BOOL sActive = NO;
static BOOL (*NCOriginalPrivateIsCaptured)(id, SEL) = NULL;
static NSMutableSet<NSString *> *sHookedDelegateSelectors = nil;

/// 开关快照:由 NCRefreshFlags 更新,hook 内部只读这些变量,访问无锁。
static BOOL sFlagScreenshotNotice = NO;
static BOOL sFlagCaptureState = NO;
static BOOL sFlagCaptureNotice = NO;
static BOOL sFlagRecordingState = NO;
static BOOL sFlagExternalDisplay = NO;
static BOOL sFlagForegroundState = NO;
static BOOL sFlagForegroundNotice = NO;
static BOOL sFlagForegroundCallback = NO;
static BOOL sFlagProtectedData = NO;

static NSString *const NCScreenshotNoticeName = @"UIApplicationUserDidTakeScreenshotNotification";
static NSString *const NCCapturedChangeName = @"UIScreenCapturedDidChangeNotification";
static NSString *const NCSuppressedName = @"NCSuppressedCaptureNotification";

static NSString *const NCApplicationRole = @"UIWindowSceneSessionRoleApplication";
static NSString *const NCExternalDisplayRolePrefix = @"UIWindowSceneSessionRoleExternalDisplay";

#pragma mark - 开关快照

/// 调试/测试开关(不依赖设置面板):
///   touch /var/mobile/nocapture.force    → 注入到用户 App 后一律全部生效
///   rm    /var/mobile/nocapture.force    → 交回设置面板控制
/// 用途:设置页面本身有问题时,仍然可以直接验证"屏蔽功能到底有没有工作"。
static BOOL NCForceModeEnabled(void) {
    static BOOL forced = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#ifdef NC_FORCE_ALWAYS
        // 调试构建:注入即全开,不依赖 plist / 设置面板 / force 文件
        forced = YES;
#else
        forced = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/nocapture.force"];
#endif
    });
    return forced;
}

static void NCRefreshFlags(void) {
    BOOL force = NCForceModeEnabled();
    NCPrefs *prefs = [NCPrefs sharedInstance];

    sFlagScreenshotNotice = force ? YES : prefs.screenshotNotice;
    sFlagCaptureState = force ? YES : prefs.captureState;
    sFlagCaptureNotice = force ? YES : prefs.captureNotice;
    sFlagRecordingState = force ? YES : prefs.recordingState;
    sFlagExternalDisplay = force ? YES : prefs.externalDisplay;
    sFlagForegroundState = force ? YES : prefs.foregroundState;
    sFlagForegroundNotice = force ? YES : prefs.foregroundNotice;
    sFlagForegroundCallback = force ? YES : prefs.foregroundCallback;
    sFlagProtectedData = force ? YES : prefs.protectedData;
}

#pragma mark - 通知名单

static NSSet<NSString *> *NCForegroundNotificationNames(void) {
    static NSSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[@"UIApplicationDidBecomeActiveNotification",
                                    @"UIApplicationWillResignActiveNotification",
                                    @"UIApplicationDidEnterBackgroundNotification",
                                    @"UIApplicationWillEnterForegroundNotification",
                                    @"UISceneDidActivateNotification",
                                    @"UISceneWillDeactivateNotification",
                                    @"UISceneDidEnterBackgroundNotification",
                                    @"UISceneWillEnterForegroundNotification",
                                    @"UISceneDidDisconnectNotification"]];
    });
    return set;
}

static NSSet<NSString *> *NCProtectedDataNotificationNames(void) {
    static NSSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[@"UIApplicationProtectedDataWillBecomeUnavailableNotification",
                                    @"UIApplicationProtectedDataDidBecomeAvailableNotification"]];
    });
    return set;
}

static NSSet<NSString *> *NCScreenConnectionNotificationNames(void) {
    static NSSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[@"UIScreenDidConnectNotification",
                                    @"UIScreenDidDisconnectNotification"]];
    });
    return set;
}

static BOOL NCIsSuppressedNotification(NSString *name) {
    if (name.length == 0) return NO;

    // 先做便宜的判断再谈其它;这两个通知名是绝大多数 App 都不会用的
    if (![name hasPrefix:@"UIApplication"] &&
        ![name hasPrefix:@"UIScene"] &&
        ![name hasPrefix:@"UIScreen"]) {
        return NO;
    }

    if ([name isEqualToString:NCScreenshotNoticeName]) return sFlagScreenshotNotice;
    if ([name isEqualToString:NCCapturedChangeName]) return sFlagCaptureNotice;
    if (sFlagForegroundNotice && [NCForegroundNotificationNames() containsObject:name]) return YES;
    if (sFlagProtectedData && [NCProtectedDataNotificationNames() containsObject:name]) return YES;
    if (sFlagExternalDisplay && [NCScreenConnectionNotificationNames() containsObject:name]) return YES;
    return NO;
}

#pragma mark - 通知:拦注册 + 拦投递

%group Notifications
%hook NSNotificationCenter

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSNotificationName)aName object:(id)anObject {
    if (NCIsSuppressedNotification(aName)) {
        NCLog(@"已阻断通知监听: %@", aName);
        return;
    }
    %orig;
}

- (id)addObserverForName:(NSNotificationName)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *))block {
    if (NCIsSuppressedNotification(name)) {
        NCLog(@"已阻断 block 监听: %@", name);
        name = NCSuppressedName;
        obj = nil;
        queue = nil;
        block = ^(NSNotification *note){};
    }
    return %orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    if (NCIsSuppressedNotification(name)) return;
    %orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (NCIsSuppressedNotification(name)) return;
    %orig;
}

- (void)postNotification:(NSNotification *)notification {
    if (NCIsSuppressedNotification(notification.name)) return;
    %orig;
}

%end
%end

#pragma mark - 录屏 / 投屏:UIScreen

%group ScreenState
%hook UIScreen

- (BOOL)isCaptured {
    if (sFlagCaptureState) return NO;
    return %orig;
}

- (UIScreen *)mirroredScreen {
    if (sFlagExternalDisplay) return nil;
    return %orig;
}

+ (NSArray<UIScreen *> *)screens {
    if (sFlagExternalDisplay) {
        UIScreen *mainScreen = [self mainScreen];
        if (mainScreen) return @[mainScreen];
    }
    return %orig;
}

%end
%end

static BOOL NCScreenPrivateIsCaptured(id self, SEL _cmd) {
    if (sFlagCaptureState) return NO;
    if (NCOriginalPrivateIsCaptured) return NCOriginalPrivateIsCaptured(self, _cmd);
    return NO;
}

static void NCHookPrivateScreenSelectors(void) {
    // 用 objc_getClass 而不是 [UIScreen class]:
    // 给类发消息会触发 +[UIScreen initialize],而本函数运行在 dyld 构造函数阶段
    // (App 的 main 还没跑),UIKit 的初始化需要 App 启动上下文,会死锁 → 看门狗杀进程。
    Class screenClass = objc_getClass("UIScreen");
    SEL selector = NSSelectorFromString(@"_isCaptured");
    if (class_getInstanceMethod(screenClass, selector)) {
        MSHookMessageEx(screenClass, selector, (IMP)&NCScreenPrivateIsCaptured, (IMP *)&NCOriginalPrivateIsCaptured);
        NCLog(@"已接管 UIScreen 私有 _isCaptured");
    }
}

#pragma mark - 投屏:外接屏场景角色

%group SceneSession
%hook UISceneSession

- (UISceneSessionRole)role {
    UISceneSessionRole role = %orig;
    if (sFlagExternalDisplay && [role hasPrefix:NCExternalDisplayRolePrefix]) {
        return NCApplicationRole;
    }
    return role;
}

%end
%end

#pragma mark - 切屏:UIApplication / UIScene 状态

%group AppState
%hook UIApplication

- (UIApplicationState)applicationState {
    if (sFlagForegroundState) return UIApplicationStateActive;
    return %orig;
}

- (NSTimeInterval)backgroundTimeRemaining {
    if (sFlagForegroundState) return DBL_MAX;
    return %orig;
}

- (BOOL)isProtectedDataAvailable {
    if (sFlagProtectedData) return YES;
    return %orig;
}

%end
%end

%group SceneState
%hook UIScene

- (UISceneActivationState)activationState {
    if (sFlagForegroundState) return UISceneActivationStateForegroundActive;
    return %orig;
}

%end
%end

#pragma mark - 切屏 / 锁屏:委托回调

static void NCNoopLifecycleIMP(id self, SEL _cmd) {
    // 故意什么都不做:让 App 收不到这些生命周期回调
}

static NSArray<NSString *> *NCApplicationForegroundSelectors(void) {
    return @[@"applicationWillResignActive:",
             @"applicationDidEnterBackground:",
             @"applicationWillEnterForeground:",
             @"applicationDidBecomeActive:"];
}

static NSArray<NSString *> *NCSceneForegroundSelectors(void) {
    return @[@"sceneWillResignActive:",
             @"sceneDidEnterBackground:",
             @"sceneWillEnterForeground:",
             @"sceneDidBecomeActive:",
             @"sceneDidDisconnect:"];
}

static NSArray<NSString *> *NCProtectedDataSelectors(void) {
    return @[@"applicationProtectedDataWillBecomeUnavailable:",
             @"applicationProtectedDataDidBecomeAvailable:"];
}

static NSArray<NSString *> *NCReplayKitDelegateSelectors(void) {
    return @[@"screenRecorderDidChangeAvailability:"];
}

static void NCHookDelegateIfNeeded(id delegate, NSArray<NSString *> *selectors) {
    if (!delegate) return;
    Class cls = object_getClass(delegate);
    if (!cls) return;

    NSString *className = NSStringFromClass(cls);
    if (className.length == 0) return;

    for (NSString *name in selectors) {
        NSString *key = [className stringByAppendingFormat:@"|%@", name];
        @synchronized (sHookedDelegateSelectors) {
            if ([sHookedDelegateSelectors containsObject:key]) continue;
            [sHookedDelegateSelectors addObject:key];
        }

        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;

        // 空实现只对返回 void 的方法成立
        const char *typeEncoding = method_getTypeEncoding(method);
        if (!typeEncoding || typeEncoding[0] != 'v') {
            NCLog(@"跳过非 void 回调: %@ - %@", className, name);
            continue;
        }

        IMP original = NULL;
        MSHookMessageEx(cls, selector, (IMP)&NCNoopLifecycleIMP, (IMP *)&original);
        NCLog(@"已屏蔽生命周期回调: %@ - %@", className, name);
    }
}

static void NCHookLifecycleDelegates(void) {
    if (!sActive) return;

    if (sFlagForegroundCallback) {
        NCHookDelegateIfNeeded([UIApplication sharedApplication].delegate, NCApplicationForegroundSelectors());
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                NCHookDelegateIfNeeded(scene.delegate, NCSceneForegroundSelectors());
            }
        }
    }

    if (sFlagProtectedData) {
        NCHookDelegateIfNeeded([UIApplication sharedApplication].delegate, NCProtectedDataSelectors());
    }
}

#pragma mark - 录屏:ReplayKit

%group ReplayKit
%hook RPScreenRecorder

- (BOOL)isRecording {
    if (sFlagRecordingState) return NO;
    return %orig;
}

- (BOOL)isAvailable {
    if (sFlagRecordingState) return YES;
    return %orig;
}

- (void)setDelegate:(id)delegate {
    %orig;
    if (sFlagRecordingState) {
        NCHookDelegateIfNeeded(delegate, NCReplayKitDelegateSelectors());
    }
}

%end
%hook RPBroadcastController

- (BOOL)isBroadcasting {
    if (sFlagRecordingState) return NO;
    return %orig;
}

%end
%end

#pragma mark - 初始化

static void NCHookReplayKitDelegateIfNeeded(void) {
    Class recorderClass = NSClassFromString(@"RPScreenRecorder");
    if (!recorderClass) return;
    id recorder = NCInvoke0((id)recorderClass, @"sharedRecorder");
    if (!recorder) return;
    id delegate = NCInvoke0(recorder, @"delegate");
    NCHookDelegateIfNeeded(delegate, NCReplayKitDelegateSelectors());
}

static NSMutableArray<NSNumber *> *sPendingDelegateDelays = nil;

static void NCScheduleDelegateHooks(void) {
    sPendingDelegateDelays = [NSMutableArray array];
    for (NSNumber *delay in @[@0.5, @1.5, @3.0, @6.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NCHookLifecycleDelegates();
            NCHookReplayKitDelegateIfNeeded();
        });
    }
}

/// 用户改设置后:刷新开关快照。hook 已经装好的部分会立刻按新开关生效;
/// 新加入名单的 App 需要重启该 App 才会装上 hook。
static void NCPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                   const void *object, CFDictionaryRef userInfo) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NCRefreshFlags();
        NCHookLifecycleDelegates();
        NCHookReplayKitDelegateIfNeeded();
    });
}

%ctor {
    @autoreleasepool {
        // ★进程判断:只用确定的信号,不做字符串匹配★
        //
        // App 进程一定有 bundle identifier;命令行工具(rm、dpkg 等)、多数 daemon 取不到。
        // 系统进程的 bundle id 一律以 com.apple. 开头。
        // 这两条都是确定的,不依赖路径格式,也不依赖 UIKit 是否加载。
        //
        // (曾经用过 [[NSProcessInfo processInfo] arguments][0] 做路径匹配,
        //  它在部分 iOS 版本上只给短名,导致所有 App 被误判为非 App、功能全灭。)
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier.length == 0) {
            // 极少数取不到 bundle id 的情况:用 bundle 路径兜一次,避免误杀正常 App
            if (![[[NSBundle mainBundle] bundlePath] containsString:@"/Application/"]) {
                return;
            }
            bundleIdentifier = @"(unknown)";
        }
        if ([bundleIdentifier hasPrefix:@"com.apple."]) {
            return;
        }

        // 构造期同步读一次偏好:必须在"装不装 hook"这个决策上拿到真实值。
        // 偏好平时是异步加载的,不这样读会读到默认值,导致 hook 永远装不上。
        NCPrefs *prefs = [NCPrefs sharedInstance];
        [prefs reloadSynchronously];

        // ★核心约束★ 不在保护范围内的 App,一个 hook 都不装。
        // 生效范围判定(严格按名单,不做任何退化):
        //   总开关开 且 (开了「所有 App」 或 当前 App 在白名单里) 才生效。
        //   白名单读不到就是"不生效" —— 这是正确行为,读不到本身才是要修的问题。
        BOOL inScope = NCForceModeEnabled() || [prefs shouldProtectBundleIdentifier:bundleIdentifier];
        if (!inScope) {
            return;
        }

        // 注意:这里【绝不】给 UIKit 类发消息、也不主动 dlopen UIKit。
        // 本段运行在 dyld 构造函数阶段,此时触发 UIKit 初始化会死锁,
        // 主线程会卡满 20 秒并被看门狗杀掉(日志里的 0x8BADF00D / +[UIScreen initialize] 就是它)。
        // 进程是否含 UIKit 由 filter(Classes = UIApplication)保证,不需要在这里拉。
        if (objc_getClass("UIApplication") == NULL) return;

        sActive = YES;
        sHookedDelegateSelectors = [NSMutableSet set];
        NCRefreshFlags();

        // ★只在构造函数里装 NSNotificationCenter 的 hook★
        // 理由:它不涉及 UIKit 类,而且是唯一"必须尽量早装"的 —— App 通常在启动早期就注册
        // UIApplicationUserDidTakeScreenshotNotification,晚一步就拦不到了。
        if (sFlagScreenshotNotice || sFlagCaptureNotice || sFlagForegroundNotice ||
            sFlagProtectedData || sFlagExternalDisplay) {
            %init(Notifications);
        }

        // 其余 hook 全部推迟到 App 启动完成后再装。
        // 原因:它们要 hook UIScreen / UIApplication / UIScene 这些 UIKit 类,
        // 而本函数运行在 dyld 构造函数阶段(App 的 main 还没跑),
        // 那时触碰 UIKit 会死锁,主线程卡满 20 秒被看门狗杀掉(0x8BADF00D)。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (sFlagCaptureState || sFlagExternalDisplay) {
                %init(ScreenState);
            }
            if (sFlagForegroundState || sFlagProtectedData) {
                %init(AppState);
            }
            if (sFlagForegroundState && NSClassFromString(@"UIScene") != Nil) {
                %init(SceneState);
            }
            if (sFlagExternalDisplay && NSClassFromString(@"UISceneSession") != Nil) {
                %init(SceneSession);
            }
            if (sFlagCaptureState) {
                NCHookPrivateScreenSelectors();
            }
            if (sFlagRecordingState) {
                if (NSClassFromString(@"RPScreenRecorder") == Nil) {
                    dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY | RTLD_GLOBAL);
                }
                if (NSClassFromString(@"RPScreenRecorder") != Nil) {
                    %init(ReplayKit);
                }
            }
            if (sFlagForegroundCallback || sFlagProtectedData || sFlagRecordingState) {
                NCScheduleDelegateHooks();
            }
        });

        NCLog(@"%@ 已按开关安装 hook(截屏=%d 录屏状态=%d 录制通知=%d 录制接口=%d 投屏=%d 前后台状态=%d 前后台通知=%d 前后台回调=%d 锁屏=%d)",
              bundleIdentifier,
              sFlagScreenshotNotice, sFlagCaptureState, sFlagCaptureNotice, sFlagRecordingState,
              sFlagExternalDisplay, sFlagForegroundState, sFlagForegroundNotice,
              sFlagForegroundCallback, sFlagProtectedData);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NCPrefsChangedCallback,
                                        (__bridge CFStringRef)NCPrefsChangedDarwinNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
