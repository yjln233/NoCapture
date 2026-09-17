#import "NCPApps.h"
#import "NCPrefs.h"
#import "NCUtils.h"

@implementation NCPAppInfo
@end

/// 首选 AppList(rpetrich/AppList,社区标准库)读取应用列表:
/// 它给出的是与系统设置一致的显示名,比自己枚举 LSApplicationWorkspace 更可靠。
/// 该库以注入方式提供 ALApplicationList 类;没装时返回 nil,由调用方回退。
static NSDictionary<NSString *, NSString *> *NCApplicationsFromAppList(void) {
    Class appListClass = NSClassFromString(@"ALApplicationList");
    if (!appListClass) return nil;

    id sharedList = NCInvoke0((id)appListClass, @"sharedApplicationList");
    if (!sharedList) return nil;

    id applications = NCInvoke0(sharedList, @"applications");
    if (![applications isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    [(NSDictionary *)applications enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || [key length] == 0) return;
        if ([key hasPrefix:@"com.apple."]) return;   // 系统 App 不参与
        result[key] = [value isKindOfClass:[NSString class]] ? value : key;
    }];
    return result.count > 0 ? result : nil;
}

/// 回退一:通过 LSApplicationWorkspace 取已安装应用(iOS 上访问安装列表的标准私有入口)
static NSArray *NCRawInstalledApplications(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return @[];

    id workspace = NCInvoke0(workspaceClass, @"defaultWorkspace");
    if (!workspace) return @[];

    NSArray *candidates = @[@"allInstalledApplications", @"allApplications", @"installedApplications"];
    for (NSString *selector in candidates) {
        id applications = NCInvoke0(workspace, selector);
        if ([applications isKindOfClass:[NSArray class]] && [applications count] > 0) {
            return applications;
        }
    }
    return @[];
}

/// 回退方案:直接扫描 App 容器目录读 Info.plist。
/// 某些越狱环境下(或设置 App 进程权限受限时)LSApplicationWorkspace 会返回空,
/// 那样「选择 App」页面就会一个 App 都没有,看起来像"加不上"。
static NSArray<NCPAppInfo *> *NCInstalledAppsFromContainers(void) {
    NSMutableArray<NCPAppInfo *> *result = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[@"/var/containers/Bundle/Application",
                                   @"/private/var/containers/Bundle/Application"];

    for (NSString *root in roots) {
        for (NSString *uuidDirectory in [fileManager contentsOfDirectoryAtPath:root error:nil]) {
            NSString *uuidPath = [root stringByAppendingPathComponent:uuidDirectory];
            for (NSString *item in [fileManager contentsOfDirectoryAtPath:uuidPath error:nil]) {
                if (![item hasSuffix:@".app"]) continue;

                NSString *infoPath = [[uuidPath stringByAppendingPathComponent:item]
                                      stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                if (![info isKindOfClass:[NSDictionary class]]) continue;

                NSString *bundleIdentifier = info[@"CFBundleIdentifier"];
                if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) continue;
                if ([bundleIdentifier hasPrefix:@"com.apple."]) continue;

                NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bundleIdentifier;
                if (![name isKindOfClass:[NSString class]] || name.length == 0) name = bundleIdentifier;

                NCPAppInfo *appInfo = [[NCPAppInfo alloc] init];
                appInfo.bundleIdentifier = bundleIdentifier;
                appInfo.name = name;
                [result addObject:appInfo];
            }
        }
        if (result.count > 0) break;
    }
    return result;
}

NSArray<NCPAppInfo *> *NCInstalledApps(void) {
    NSMutableDictionary<NSString *, NCPAppInfo *> *result = [NSMutableDictionary dictionary];

    void (^addApp)(NSString *, NSString *) = ^(NSString *bundleIdentifier, NSString *name) {
        if (bundleIdentifier.length == 0) return;
        NCPAppInfo *info = [[NCPAppInfo alloc] init];
        info.bundleIdentifier = bundleIdentifier;
        info.name = (name.length > 0) ? name : bundleIdentifier;
        result[bundleIdentifier] = info;
    };

    // 首选 AppList;没有该库时再走下面的私有接口与目录扫描
    NSDictionary<NSString *, NSString *> *appListApps = NCApplicationsFromAppList();
    if (appListApps.count > 0) {
        for (NSString *bundleIdentifier in appListApps) {
            addApp(bundleIdentifier, appListApps[bundleIdentifier]);
        }
    }

    for (id proxy in NCRawInstalledApplications()) {
        NSString *bundleIdentifier = NCInvoke0(proxy, @"applicationIdentifier");
        if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) {
            bundleIdentifier = NCInvoke0(proxy, @"bundleIdentifier");
        }
        if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) continue;
        if ([bundleIdentifier hasPrefix:@"com.apple."]) continue;   // 系统 App 不参与

        NSString *name = NCInvoke0(proxy, @"localizedName");
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            name = NCInvoke0(proxy, @"itemName");
        }
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            name = [[bundleIdentifier componentsSeparatedByString:@"."] lastObject];
        }
        addApp(bundleIdentifier, name);
    }

    // 私有接口拿不到列表时(返回空)走目录扫描
    if (result.count == 0) {
        for (NCPAppInfo *info in NCInstalledAppsFromContainers()) {
            addApp(info.bundleIdentifier, info.name);
        }
    }

    // 把已选中但本次没枚举到的 App 也保留,避免列表凭空消失
    for (NSString *bundleIdentifier in NCBlockedAppIdentifiers()) {
        if (result[bundleIdentifier]) continue;
        addApp(bundleIdentifier, nil);
    }

    return [result.allValues sortedArrayUsingComparator:^NSComparisonResult(NCPAppInfo *a, NCPAppInfo *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
}

NSString *NCAppDisplayName(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) return @"";
    for (NCPAppInfo *info in NCInstalledApps()) {
        if ([info.bundleIdentifier isEqualToString:bundleIdentifier]) {
            return info.name;
        }
    }
    return bundleIdentifier;
}

NSArray<NSString *> *NCBlockedAppIdentifiers(void) {
    id value = NCReadPref(NCPrefsKeyBlockedApps);
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *filtered = [NSMutableArray array];
        for (id item in value) {
            if ([item isKindOfClass:[NSString class]]) [filtered addObject:item];
        }
        return filtered;
    }
    return @[];
}

void NCSetBlockedAppIdentifiers(NSArray<NSString *> *bundleIdentifiers) {
    NCWritePref(NCPrefsKeyBlockedApps, bundleIdentifiers ?: @[]);
}
