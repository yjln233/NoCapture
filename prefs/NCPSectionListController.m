#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "NCPSectionListController.h"
#import "NCPrefs.h"

/// 行末的 ⓘ 表示这一行可以点开看说明;点右侧开关仍然是切换开关,不弹说明。
static NSString *const NCHelpMark = @" ⓘ";

static void NCPresentHelp(PSListController *host, PSSpecifier *specifier) {
    NSString *title = [specifier propertyForKey:@"ncHelpTitle"];
    NSString *body = [specifier propertyForKey:@"ncHelpBody"];
    if (body.length == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:body
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}

@implementation NCPSectionListController

#pragma mark - 构造 specifier

- (void)addGroupWithName:(NSString *)name footer:(NSString *)footer to:(NSMutableArray *)specifiers {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:name];
    if (footer.length > 0) {
        [group setProperty:footer forKey:@"footerText"];
    }
    [specifiers addObject:group];
}

- (void)addSwitchWithTitle:(NSString *)title
                       key:(NSString *)key
                helpDetail:(NSString *)helpDetail
                        to:(NSMutableArray *)specifiers {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:[title stringByAppendingString:NCHelpMark]
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:NCPrefsDomain forKey:@"defaults"];
    [specifier setProperty:@(NO) forKey:@"default"];
    [specifier setProperty:title forKey:@"ncHelpTitle"];
    [specifier setProperty:helpDetail forKey:@"ncHelpBody"];
    [specifiers addObject:specifier];
}

#pragma mark - 界面

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];

        // ---- 截屏 ----
        [self addGroupWithName:@"截屏" footer:nil to:specifiers];
        [self addSwitchWithTitle:@"截屏通知"
                             key:NCPrefsKeyScreenshotNotice
                      helpDetail:@"【作用】\nApp 通过系统通知得知你按了截屏键。社交 App 里「对方截屏了」的提示就来自它。\n\n【副作用】\n该 App 永远收不到截屏事件,它自己的截图相关功能(截图后提示保存、截图上报)也会一起失效。\n\n【涉及接口】\nUIApplicationUserDidTakeScreenshotNotification"
                              to:specifiers];

        // ---- 录屏 ----
        [self addGroupWithName:@"录屏" footer:nil to:specifiers];
        [self addSwitchWithTitle:@"屏幕捕获状态"
                             key:NCPrefsKeyCaptureState
                      helpDetail:@"【作用】\nApp 用这个状态判断屏幕是否正在被录制、镜像或投屏,处于这些状态时系统会返回 YES。插件同时接管私有接口 _isCaptured。\n\n【副作用】\nApp 会认为屏幕从未被捕获,不再触发自己的保护逻辑(例如停止播放、遮挡画面)。\n\n【涉及接口】\nUIScreen.isCaptured、_isCaptured"
                              to:specifiers];
        [self addSwitchWithTitle:@"捕获状态变化通知"
                             key:NCPrefsKeyCaptureNotice
                      helpDetail:@"【作用】\n捕获状态变化时系统发出的通知,App 用它做实时响应,例如一检测到录屏就暂停播放。\n\n【副作用】\nApp 收不到状态变化事件。与上一项叠加时,App 的保护逻辑会彻底失效。\n\n【涉及接口】\nUIScreenCapturedDidChangeNotification"
                              to:specifiers];
        [self addSwitchWithTitle:@"录屏接口状态"
                             key:NCPrefsKeyRecordingState
                      helpDetail:@"【作用】\n包含是否正在录制、是否可录制、录制可用性变化回调(AirPlay、TVOut 时会触发)以及直播状态。\n\n【副作用】\nApp 会认为随时可录制、且当前没有在录。若它真的在 AirPlay 状态下发起录制,系统会返回错误,App 没处理错误时可能异常;它「正在录制中」的自我保护也会失效。\n\n【涉及接口】\nRPScreenRecorder.isRecording / isAvailable、screenRecorderDidChangeAvailability:、RPBroadcastController.isBroadcasting"
                              to:specifiers];

        // ---- 投屏 ----
        [self addGroupWithName:@"投屏" footer:nil to:specifiers];
        [self addSwitchWithTitle:@"外接屏与镜像"
                             key:NCPrefsKeyExternalDisplay
                      helpDetail:@"【作用】\n包含屏幕数量、镜像屏对象、镜像时的捕获状态、屏幕连接与断开通知,以及外接屏场景的角色标识。App 用这些发现你在投屏。\n\n【副作用】\nApp 看不到外接屏。若它本身有「外接屏显示不同内容」的功能(演示、双屏应用),该功能会一起失效。\n\n【涉及接口】\nUIScreen.screens / mirroredScreen、UIScreenDidConnect / DidDisconnectNotification、UISceneSession.role"
                              to:specifiers];

        // ---- 切屏 ----
        [self addGroupWithName:@"切屏" footer:nil to:specifiers];
        [self addSwitchWithTitle:@"前后台状态"
                             key:NCPrefsKeyForegroundState
                      helpDetail:@"【作用】\n包含 App 的应用状态、后台剩余时间与场景激活状态。App 靠它们判断自己在前台还是后台。\n\n【副作用(重要)】\nApp 真实在后台时仍认为自己在前台,于是继续渲染、继续跑定时器、继续占用相机或定位。后台这样可能被系统判为异常占用而强杀,表现为「切到后台一会儿就被杀、切回来是冷启动」。\n\n【涉及接口】\nUIApplication.applicationState / backgroundTimeRemaining、UIScene.activationState"
                              to:specifiers];
        [self addSwitchWithTitle:@"前后台通知"
                             key:NCPrefsKeyForegroundNotice
                      helpDetail:@"【作用】\n进入后台、回到前台、将要失活等通知,App 常用来做暂停、恢复、保存进度。\n\n【副作用(重要)】\nApp 收不到「即将进入后台」的通知,就不会自动暂停、保存进度、结束后台任务。与上一项叠加时更容易被系统杀掉或被判为异常。\n\n【涉及接口】\nUIApplication 与 UIScene 的前后台通知、UIScene.didDisconnectNotification"
                              to:specifiers];
        [self addSwitchWithTitle:@"前后台回调"
                             key:NCPrefsKeyForegroundCallback
                      helpDetail:@"【作用】\nApp 与场景的委托回调(进入后台、回到前台等),是 App 做收尾工作的主要入口。\n\n【副作用(重要)】\n这些回调被替换成空实现后,App 完全不会执行对应的收尾逻辑。另外这是运行时替换、无法热撤销,本项一旦生效,需要重启对应 App 才能恢复。\n\n【涉及接口】\nAppDelegate 与 SceneDelegate 的前后台回调方法"
                              to:specifiers];

        // ---- 锁屏 ----
        [self addGroupWithName:@"锁屏" footer:nil to:specifiers];
        [self addSwitchWithTitle:@"锁屏状态与事件"
                             key:NCPrefsKeyProtectedData
                      helpDetail:@"【作用】\n包含数据保护可用状态、锁屏与解锁通知,以及 App 的对应回调。这是 iOS 上判断设备锁屏的唯一公开信号。\n\n【副作用】\n设备真实锁屏时 App 仍认为数据可读,若它此时去读受保护的加密文件会失败,处理不当会异常或崩溃。另外设备未设密码、或只用 Face ID 的场景,系统本来就不发这些事件。\n\n【涉及接口】\nisProtectedDataAvailable、UIApplicationProtectedDataWillBecomeUnavailable / DidBecomeAvailableNotification"
                              to:specifiers];

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - 说明弹窗

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"ncHelpBody"]) {
        // 让这一行可以被选中,选中后弹说明;右侧的开关控件不受影响
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"ncHelpBody"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        NCPresentHelp(self, specifier);
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

#pragma mark - 其它

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NCPostPrefsChanged();
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"屏蔽内容";
}

@end
