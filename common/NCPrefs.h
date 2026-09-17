#import <Foundation/Foundation.h>

extern NSString *const NCPrefsDomain;
extern NSString *const NCPrefsChangedDarwinNotification;

/// 总开关
extern NSString *const NCPrefsKeyEnabled;

// ---- 截屏检测 ----
extern NSString *const NCPrefsKeyScreenshotNotice;      // UIApplicationUserDidTakeScreenshotNotification

// ---- 录屏检测 ----
extern NSString *const NCPrefsKeyCaptureState;          // UIScreen.isCaptured
extern NSString *const NCPrefsKeyCaptureNotice;         // UIScreenCapturedDidChangeNotification
extern NSString *const NCPrefsKeyRecordingState;        // ReplayKit: isRecording/isAvailable/委托回调

// ---- 投屏检测 ----
extern NSString *const NCPrefsKeyExternalDisplay;       // UIScreen.screens/mirroredScreen/连接通知/UISceneSession.role

// ---- 切屏(前后台)检测 ----
extern NSString *const NCPrefsKeyForegroundState;       // applicationState / backgroundTimeRemaining / UIScene.activationState
extern NSString *const NCPrefsKeyForegroundNotice;      // UIApplication、UIScene 前后台通知
extern NSString *const NCPrefsKeyForegroundCallback;    // AppDelegate / SceneDelegate 前后台回调

// ---- 锁屏检测 ----
extern NSString *const NCPrefsKeyProtectedData;         // isProtectedDataAvailable + 锁屏/解锁通知与回调

extern NSString *const NCPrefsKeyProtectAllApps;
extern NSString *const NCPrefsKeyBlockedApps;

@interface NCPrefs : NSObject

/// 单例。注意:构造过程不做同步磁盘 I/O,首次访问时缓存里是全部默认值(关闭),
/// 真实偏好由后台队列异步载入。
+ (instancetype)sharedInstance;

/// 重新从磁盘读取偏好(应在后台线程调用)
- (void)reload;
/// 同步读取一次偏好。只应在进程启动、需要立即确定生效状态时调用一次,
/// 不要放在高频路径上。
- (void)reloadSynchronously;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL screenshotNotice;
@property (nonatomic, readonly) BOOL captureState;
@property (nonatomic, readonly) BOOL captureNotice;
@property (nonatomic, readonly) BOOL recordingState;
@property (nonatomic, readonly) BOOL externalDisplay;
@property (nonatomic, readonly) BOOL foregroundState;
@property (nonatomic, readonly) BOOL foregroundNotice;
@property (nonatomic, readonly) BOOL foregroundCallback;
@property (nonatomic, readonly) BOOL protectedData;
@property (nonatomic, readonly) BOOL protectAllApps;
@property (nonatomic, readonly, copy) NSArray<NSString *> *blockedApps;

- (BOOL)shouldProtectBundleIdentifier:(NSString *)bundleIdentifier;

@end

id NCReadPref(NSString *key);
void NCWritePref(NSString *key, id value);
void NCPostPrefsChanged(void);
NSString *NCJailbreakRootPath(void);
