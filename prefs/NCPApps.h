#import <Foundation/Foundation.h>

@interface NCPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *name;
@end

/// 已安装的用户 App(按名称排序)
NSArray<NCPAppInfo *> *NCInstalledApps(void);
/// 取 App 名称,取不到时回退为 bundle id
NSString *NCAppDisplayName(NSString *bundleIdentifier);

/// 读取/写入"屏蔽的 App"列表
NSArray<NSString *> *NCBlockedAppIdentifiers(void);
void NCSetBlockedAppIdentifiers(NSArray<NSString *> *bundleIdentifiers);
