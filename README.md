# NoCapture

让 App **检测不到**截屏 / 录屏 / 投屏 / 切屏 / 锁屏的越狱插件。

![platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-lightgrey)
![jailbreak](https://img.shields.io/badge/jailbreak-rootless-blue)
![license](https://img.shields.io/badge/license-MIT-green)

这些行为本身全部照常可用——截屏照样能截、录屏照样能录、投屏照样能投、App 也照常切后台再回来，
只是**名单里的 App 收不到任何相关信号**。

> 注意方向:这不是「禁止截屏」插件。禁止截屏会让你自己也拿不到截图,和本插件正好相反。

## 兼容性

| 项目 | 要求 |
| --- | --- |
| 设备 | iPhone 11 (A13) 及更新 |
| 系统 | iOS 15.0 – 16.5 |
| 越狱 | Dopamine 等 **rootless** 越狱 |
| 依赖 | ElleKit 或 MobileSubstrate、PreferenceLoader |

## 安装

1. 到 [Releases](https://github.com/yjln233/NoCapture/releases) 下载最新的 `.deb`
2. 用 Sileo / Zebra / Filza 安装
3. 注销一次(respring)

命令行安装:

```
dpkg -i com.anfangyi.nocapture_*.deb
killall -9 SpringBoard
```

## 使用

安装后打开 **设置 → NoCapture**:

| 项目 | 说明 |
| --- | --- |
| **总开关** | 打开后下面的配置才开始生效 |
| **屏蔽内容** | 按类别逐项开关;行末的 ⓘ 可以看这一项的作用与副作用 |
| **屏蔽的 App** | 选择对哪些 App 生效,新加入名单的 App 需要重启一次 |

所有开关**默认关闭**。名单之外的 App 不受任何影响,不产生任何开销。

## 覆盖的检测项

### 截屏

| 接口 | 处理 |
| --- | --- |
| `UIApplication.userDidTakeScreenshotNotification` | 注册与投递两层都拦掉 |

### 录屏

| 接口 | 处理 |
| --- | --- |
| `UIScreen.isCaptured`(含私有 `_isCaptured`) | 恒返回 NO |
| `UIScreen.capturedDidChangeNotification` | 注册与投递两层都拦掉 |
| `RPScreenRecorder.isRecording` | 恒返回 NO |
| `RPScreenRecorder.isAvailable` | 恒返回 YES |
| `RPScreenRecorderDelegate.screenRecorderDidChangeAvailability:` | 替换为空实现 |
| `RPBroadcastController.isBroadcasting` | 恒返回 NO |

### 投屏

| 接口 | 处理 |
| --- | --- |
| `UIScreen.screens` | 只返回主屏 |
| `UIScreen.mirroredScreen` | 返回 nil |
| `UIScreen.didConnectNotification / didDisconnectNotification` | 注册与投递两层都拦掉 |
| `UISceneSession.role` | 外接屏角色改为 `windowApplication` |

### 切屏(前后台切换)

| 接口 | 处理 |
| --- | --- |
| `UIApplication.applicationState` | 恒返回 Active |
| `UIApplication.backgroundTimeRemaining` | 返回 `DBL_MAX` |
| `UIScene.activationState` | 恒返回 ForegroundActive |
| UIApplication 的 4 个前后台通知 | 注册与投递两层都拦掉 |
| UIScene 的 4 个前后台通知 | 注册与投递两层都拦掉 |
| `UIScene.didDisconnectNotification` | 注册与投递两层都拦掉 |
| AppDelegate / SceneDelegate 的前后台回调 | 替换为空实现 |

### 锁屏

| 接口 | 处理 |
| --- | --- |
| `UIApplication.isProtectedDataAvailable` | 恒返回 YES |
| `UIApplicationProtectedDataWillBecomeUnavailable / DidBecomeAvailable` 通知 | 注册与投递两层都拦掉 |
| `applicationProtectedDataWillBecomeUnavailable: / DidBecomeAvailable:` | 替换为空实现 |

## 实现要点

- **只注入 App 进程**:过滤器是 `Classes = ( UIApplication )`,不做任何 SpringBoard / 守护进程侧的 hook。
- **不在名单就不干活**:名单外的 App 一个 hook 都不装,立即返回。
- **按需装 hook**:只安装「屏蔽内容」里打开的那几组,装得越少冲突越少。
- UIKit 为弱链接,即使被误注入到无 UI 的进程也不会因此崩溃。

## 构建

本地构建(需要 [Theos](https://theos.dev)):

```
./build.sh FINALPACKAGE=1
```

产物在 `packages/` 下。

推送 `v*` 标签会触发 GitHub Actions 构建,并自动把 `.deb` 发布到 Releases;
也可以在 Actions 页面手动触发(手动触发只产出构建产物,不发 Release)。

## 已知限制

1. 委托回调是替换成空实现的,改开关后需要重启对应 App 才会恢复。
2. 屏蔽前后台回调意味着 App 不会执行它原本在切后台时做的事(自动暂停、保存状态等)。
3. 锁屏事件是「数据保护」语义:设备未设密码或只用 Face ID 的场景,系统本来就不发。
4. `AVAudioSession.currentRoute` 的 AirPlay 路由检测、服务端比对、读取相册新增文件等途径不在覆盖范围内。
5. 只适配 rootless 越狱;系统 App(`com.apple.*`)不参与。

## 许可

MIT
