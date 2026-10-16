# Android 安装测试包

本地工具链配置于 2026-10-12：Flutter 3.47.7、Temurin JDK 21.0.12.1、Android Platform 36（插件同时使用 34/35）、Build Tools 35.0.0/36.0.0、NDK 28.2.13676358、CMake 3.22.1。SDK 和 JDK 位于工作区上级 `.tools`，通过 `flutter config --android-sdk ... --jdk-dir ...` 配置；不提交本机路径、SDK、签名私钥或 APK 到源码仓库。

## 安装隔离

`mobilePreview` 为显式启用的 Gradle 属性：

| 设置 | 包名 | 应用名称 |
| --- | --- | --- |
| 未设置 / false | `com.naihuishi.nai_huishi` | NAI 绘世 |
| true | `com.naihuishi.nai_huishi.preview` | NAI 绘世测试版 |

测试包使用现有 release 构建模式与本机 debug 签名，供安装测试，不用于正式发布。独立包名允许与旧版并存；设置、API Token 和历史数据各自独立，首次启动需重新配置。

## 重建

本次交付仅包含源码，见文末“2026-10-16 前端同步”。下面的 preview.2 命令保留为历史工具链配置示例。

从与 pub cache 同盘的英文路径运行。本机使用目录联接 `E:\NAI-WorldPainter\.tools\mobile-workspace`，指向原仓库 `E:\NAI-WorldPainter\手机端`，没有复制或迁移源码。

首次配置别名时运行（路径已存在时先确认其目标，不覆盖已有目录）：

```powershell
New-Item -ItemType Junction -Path 'E:\NAI-WorldPainter\.tools\mobile-workspace' -Target 'E:\NAI-WorldPainter\手机端'
```

```powershell
Set-Location 'E:\NAI-WorldPainter\.tools\mobile-workspace'
$env:PUB_CACHE = 'E:\NAI-WorldPainter\.tools\pub-cache'
$env:JAVA_HOME = 'E:\NAI-WorldPainter\.tools\jdk-21.0.12.1+1'
$env:ANDROID_HOME = 'E:\NAI-WorldPainter\.tools\android-sdk'
& 'E:\NAI-WorldPainter\.tools\flutter\bin\flutter.bat' build apk --release --target-platform android-arm64 --no-pub --build-name=1.2.3-mobile-preview.2 --build-number=212016 --android-project-arg=mobilePreview=true
```

新环境首次运行需先 `flutter pub get`。输出为 `build/app/outputs/flutter-apk/app-release.apk`。包名开关只在上述命令内生效；常规构建不传入该参数即可保持原应用身份。应直接传递 `--android-project-arg`，本机通过 Flutter 间接传递 `ORG_GRADLE_PROJECT_mobilePreview` 环境变量时，实际产物仍使用原包名，不能据环境变量设置成功判断测试身份已生效。

本机已遇到并保留日志的路径问题：从 `M:` 映射盘构建时，Kotlin 增量缓存因源码与 pub cache 跨盘符而异常，回退编译后虽然成功，但不作为推荐路径；直接从中文路径构建时，Dart AOT snapshotter 无法读取被错误编码的 `app.dill` 路径。使用上述同盘英文别名规避两个路径条件，不改动 Flutter/Kotlin 源码或关闭检查。

验证应包括 `apksigner verify`、`zipalign -c -P 16 4`、AAPT 包名/版本/最低系统/启动 Activity 信息、ZIP 完整性与 SHA-256。没有连接 Android 设备时，构建与静态校验不代表真机启动和功能测试通过。

## 2026-10-12 首版产物 preview.1

- 文件：`NAI-WorldPainter-mobile-preview-v5-arm64.apk`，52,207,579 字节（49.8 MiB）。
- 版本：`1.2.3-mobile-preview.1` / `212015`；最低 Android 7.0（API 24），目标 API 36，ARM64。
- SHA-256：`71948660baf5ee8cb5ba59f3586b518a553d5686f5b9b69dcc5255d8344a5b9b`。
- AAPT 确认测试包名、测试名称、启动 Activity 及独立 Provider authority；APK v2 签名验证通过。
- ZIP CRC、16 KB ZIP 对齐及 APK 内全部 8 个原生 ELF 库 LOAD 段的 16 KB 对齐验证通过。
- 最终构建从同盘英文路径成功，无 Kotlin 增量缓存异常。仍有现有 Gradle/AGP/Kotlin 后续版本支持提示，未在本次扩大升级范围。
- `flutter doctor -v` 的 Android toolchain 检查通过；`adb devices -l` 无 Android 设备，未执行安装或真机测试。

本机交付目录为仓库外的 `E:\NAI-WorldPainter\安装包\2026-10-12`，同时保存校验脚本、校验结果和各轮构建日志。仓库原有 `release/app-release.apk` 未覆盖。开发工作保留在 `feat/mobile-preview-v5`，不合并主分支。

## 局部重绘修订产物 preview.2

- 文件：`NAI-WorldPainter-mobile-preview.2-arm64.apk`，52,224,075 字节（49.8 MiB）。
- 版本：`1.2.3-mobile-preview.2` / `212016`；ARM64、最低 API 24、目标 API 36。
- SHA-256：`c352c4a819f5962bd56c437d4823e6d6a71824d06be83d44cb783faca7213b0e`。
- 包名与签名证书均和 preview.1 一致，可直接更新安装测试版；原有测试版数据保留。
- 签名、AAPT 安装信息、Provider/前台服务声明、ZIP CRC、16 KB ZIP 对齐与全部原生 ELF 对齐验证通过。
- 交付目录：`E:\NAI-WorldPainter\安装包\2026-10-12\inpaint-preview.2`。本地截图、测试日志和校验结果一并保留；无真机测试。

## 前台生成服务

补齐 `flutter_foreground_task` 已有保活功能缺失的 `ForegroundService` 清单声明。生成过程涉及网络传输，使用 [Android 官方定义的 dataSync 类型](https://developer.android.com/develop/background-work/services/fgs/service-types#data-sync) 和原有对应权限；服务不导出，移除应用任务时停止。未引入插件示例中与本应用无关的 remoteMessaging 类型或权限。真机上仍需验证通知授权、前后台切换及系统电池限制下的实际行为。

## 2026-10-13 磨砂玻璃产物 preview.3

- 文件：`NAI-WorldPainter-mobile-preview.3-arm64.apk`，52,246,675字节（49.8 MiB）。
- 版本：`1.2.3-mobile-preview.3` / `212017`；ARM64、最低API 24、目标API 36。
- SHA-256：`06d031bc7734a9117f9a5bbb9281feaf2d4c380a48762c3069300cf4ef3bef91`。
- 继续使用 `com.naihuishi.nai_huishi.preview`，签名与preview.1/2一致，可覆盖更新测试版并保留其数据。
- 签名、安装身份、Provider/前台服务声明、ZIP CRC、16 KB ZIP对齐及全部8个原生ELF库对齐检查通过。
- 215项Flutter测试通过，实际组件截图完成设计对照。尚未连接真机，未验证真实API或手机GPU性能。
- 交付目录：`E:\NAI-WorldPainter\安装包\2026-10-13\frosted-preview.3`。最终构建日志、校验脚本和结果同目录保留。

重建沿用上方命令，将 `--build-name` 改为 `1.2.3-mobile-preview.3`、`--build-number` 改为 `212017`。源码保留在 `feat/mobile-preview-v5`，没有合并主分支或覆盖原发布APK。

## 2026-10-16 前端同步

功能分支此前的 `ca2c070` 包含记忆优化，但未包含主分支当天新增的 `14aaa97`、`5d74305` 和 `ad98a04`。因此，按该分支源码重建仍会得到 10 月 15 日的前端。本次仅将这三个提交合入 `feat/mobile-preview-v5`，主分支不修改；保留已确认的磨砂风格、工作区修复与记忆系统。

同步内容包括 High/Medium 等级、官方流式预览、结果切换和批次清理、图片元数据编辑及工具页调整。生成期间的删除按钮禁用，防止 ViewModel 拒绝删除而界面误报成功。

从功能分支最新提交重建，先核对分支和提交：

```powershell
git fetch origin
git switch feat/mobile-preview-v5
git pull --ff-only origin feat/mobile-preview-v5
git rev-parse HEAD
git merge-base --is-ancestor ad98a04971cc7f5cf451f07d22f5d08fd750266b HEAD
# 上一命令退出码应为 0，表示已包含今天的前端提交。
```

本次只推送源码，不创建新的 APK。`pubspec.yaml` 的版本随主分支同步至 `1.2.4+218025`；本机不再要求保留 Android 打包工具，Flutter/Dart 和依赖缓存保留用于源码验证。自行构建时需使用自己的 JDK/Android SDK，并沿用项目依赖镜像及锁文件；Flutter 3.47.7 所要求的四个 SDK 间接依赖版本保留在锁文件中，没有全量升级依赖。

本机已卸载 Android 平台、Build Tools、Platform Tools、NDK、CMake 共 8 个 SDK 组件，并清除 Flutter 中的本机 SDK/JDK 路径配置；上文工具链路径仅作为历史记录。现有源码和已交付的历史安装包保留。

构建输出为 `build/app/outputs/flutter-apk/app-release.apk`，仓库根目录下 `release/app-release.apk` 是历史包，不是构建输出。`mobilePreview` 只改变安装包名和应用名称，不切换前端版本。完整已有测试 271 项通过，新增的等级切换及流式/历史图操作回归 2 项通过；实际 Flutter 夹具截图已检查，不代表真机或真实 API 验证。
