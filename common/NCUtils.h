#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// 调用无参数方法(内部用 NSInvocation,避免 objc_msgSend 在 arm64e 上的转型问题)
id NCInvoke0(id target, NSString *selectorName);
/// 调用单参数方法
id NCInvoke1(id target, NSString *selectorName, id argument);

/// SpringBoard 内获取当前前台 App 的 bundle id(取不到返回 nil)
NSString *NCFrontmostBundleIdentifier(void);

/// 目标 App 是否在保护范围内
BOOL NCShouldProtectFrontmostApp(void);

/// 统一的日志输出,便于出问题时抓取证据
void NCLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
