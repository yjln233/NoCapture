#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "NCPAppListController.h"
#import "NCPApps.h"
#import "NCPrefs.h"

@implementation NCPAppListController {
    NSMutableSet<NSString *> *_selectedIdentifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"屏蔽的 App";
    _selectedIdentifiers = [NSMutableSet setWithArray:NCBlockedAppIdentifiers()];

    SEL searchableSelector = NSSelectorFromString(@"setSearchable:");
    if ([self respondsToSelector:searchableSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:searchableSelector withObject:@(YES)];
#pragma clang diagnostic pop
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _selectedIdentifiers = [NSMutableSet setWithArray:NCBlockedAppIdentifiers()];
}

- (id)specifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:@"打开某个 App 的开关,就把它加进屏蔽名单。名单里的 App 会按「屏蔽内容」里打开的项生效;新加入的 App 要重开一次。"
                 forKey:@"footerText"];
    [specifiers addObject:group];

    NSArray<NCPAppInfo *> *apps = NCInstalledApps();
    if (apps.count == 0) {
        [specifiers addObject:[PSSpecifier preferenceSpecifierNamed:@"暂时读不到已安装的 App"
                                                             target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
    }

    for (NCPAppInfo *info in apps) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:info.name
                                                          target:self
                                                             set:@selector(setAppSelection:specifier:)
                                                             get:@selector(appSelection:)
                                                          detail:nil
                                                            cell:PSSwitchCell
                                                            edit:nil];
        [row setProperty:info.bundleIdentifier forKey:@"ncBundleID"];
        [row setProperty:@(NO) forKey:@"default"];
        [specifiers addObject:row];
    }

    _specifiers = specifiers;
    return _specifiers;
}

- (id)appSelection:(PSSpecifier *)specifier {
    NSString *bundleIdentifier = [specifier propertyForKey:@"ncBundleID"];
    if (bundleIdentifier.length == 0) return @(NO);
    return @([_selectedIdentifiers containsObject:bundleIdentifier]);
}

- (void)setAppSelection:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundleIdentifier = [specifier propertyForKey:@"ncBundleID"];
    if (bundleIdentifier.length == 0) return;

    if ([value boolValue]) {
        [_selectedIdentifiers addObject:bundleIdentifier];
    } else {
        [_selectedIdentifiers removeObject:bundleIdentifier];
    }
    NCSetBlockedAppIdentifiers(_selectedIdentifiers.allObjects);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *bundleIdentifier = [specifier propertyForKey:@"ncBundleID"];
    if (bundleIdentifier.length > 0) {
        cell.detailTextLabel.text = bundleIdentifier;
    }
    return cell;
}

@end
