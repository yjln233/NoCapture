#import <Preferences/PSListController.h>

/// 兜底用的 App 列表页。
/// 设备上装了 libSparkAppList 时优先用它的标准控制器(见 NCPSparkAppListController),
/// 没装时用这一页,避免因为缺一个可选依赖就完全无法配置。
@interface NCPAppListController : PSListController
@end
