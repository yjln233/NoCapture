#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "NCPrefs.h"
#import "NCPRootListController.h"
#import "NCPSectionListController.h"
#import "NCPAppListController.h"
#import "NCPApps.h"

/// 用 PSLinkCell 呈现、点了要执行动作(而不是跳转)的行,把动作名放在这个键里。
static NSString *const NCActionKey = @"ncAction";

static NSString *const NCSourceCodeAction = @"ncOpenSourceCode";
static NSString *const NCSourceCodeURL = @"https://github.com/yjln233/NoCapture";

@implementation NCPRootListController

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];

        NSUInteger appCount = NCBlockedAppIdentifiers().count;

        // 分组标题用中文:系统设置会把分组标题渲染成全大写,纯英文标题会显示成 NOCAPTURE 那种样子
        PSSpecifier *header = [PSSpecifier groupSpecifierWithName:@"防捕获设置"];
        [specifiers addObject:header];

        PSSpecifier *master = [PSSpecifier preferenceSpecifierNamed:@"总开关"
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
        [master setProperty:NCPrefsKeyEnabled forKey:@"key"];
        [master setProperty:NCPrefsDomain forKey:@"defaults"];
        [master setProperty:@(NO) forKey:@"default"];
        [specifiers addObject:master];

        [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"生效范围"]];

        PSSpecifier *content = [PSSpecifier preferenceSpecifierNamed:@"屏蔽内容"
                                                              target:self
                                                                 set:nil
                                                                 get:nil
                                                              detail:[NCPSectionListController class]
                                                                cell:PSLinkCell
                                                                edit:nil];
        [specifiers addObject:content];

        // 注意:这里刻意不使用 SparkAppList 的控制器。
        // 继承外部类会在编译期产生符号引用,而 bundle 是 dynamic_lookup,
        // 加载时必须能解析到该符号 —— 设备上没装 libSparkAppList 时整个面板会载入失败。
        NSString *appsTitle = appCount > 0 ? [NSString stringWithFormat:@"屏蔽的 App(%lu 个)", (unsigned long)appCount]
                                           : @"屏蔽的 App";
        PSSpecifier *apps = [PSSpecifier preferenceSpecifierNamed:appsTitle
                                                           target:self
                                                              set:nil
                                                              get:nil
                                                           detail:[NCPAppListController class]
                                                             cell:PSLinkCell
                                                             edit:nil];
        [specifiers addObject:apps];

        [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"其他"]];

        // 「源代码」行:用 PSLinkCell 拿到右侧箭头,点击动作由 didSelectRowAtIndexPath 处理。
        PSSpecifier *source = [PSSpecifier preferenceSpecifierNamed:@"源代码"
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSLinkCell
                                                               edit:nil];
        [source setProperty:NCSourceCodeAction forKey:NCActionKey];
        UIImage *sourceIcon = [UIImage imageNamed:@"source.png"
                                         inBundle:[NSBundle bundleForClass:[self class]]
                    compatibleWithTraitCollection:nil];
        if (sourceIcon) {
            [source setProperty:sourceIcon forKey:@"iconImage"];
        }
        [specifiers addObject:source];

        NSString *version = [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";

        PSSpecifier *footer = [PSSpecifier groupSpecifierWithName:nil];
        [footer setProperty:[NSString stringWithFormat:@"NoCapture %@\n© 2026 by yjln233", version]
                     forKey:@"footerText"];
        [specifiers addObject:footer];

        _specifiers = specifiers;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 每次进入都重建:已选 App 的个数会变
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NCPostPrefsChanged();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:NCActionKey]) {
        // 会执行动作的行显示成链接样式
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([[specifier propertyForKey:NCActionKey] isEqualToString:NCSourceCodeAction]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        NSURL *url = [NSURL URLWithString:NCSourceCodeURL];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NoCapture";
}

@end
