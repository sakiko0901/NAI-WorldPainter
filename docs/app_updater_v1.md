# 应用内更新 V1

V1 从官方 GitHub Release 获取稳定版清单，下载完整 APK，校验后交给 Android 系统安装。入口位于“工具 → 应用 → 软件更新”。本功能不构建、重签、上传或发布安装包。

## 支持范围与安装行为

- 支持正式包 `com.naihuishi.nai_huishi`、单一 `arm64-v8a` ABI、数字稳定版本（如 `1.2.5` 或 `1.2.5.1`）。预览包、其他平台、其他 ABI 和预发行版本不使用应用内更新。
- 设备系统必须满足新 APK 的实际 `minSdk`。清单允许的范围为 API 21–100；当前线上 `220052` 包的最低系统是 API 24，新包以最终 APK 的检测结果为准。
- 自动检查默认开启，每次重新启动应用时自动检查，即使当天已经检查过；进程未重启、仅从后台回到前台时仍按 24 小时间隔静默检查。关闭自动检查后，原有更新页的手动检查仍可使用，并且不受自动检查间隔限制。
- 自动检查发现兼容且未忽略的新版本时，在首页空闲后提示“发现新版本”，同一运行期间同一版本只提示一次。编辑输入、未保存的工作区、忙碌任务、其他页面或弹窗存在时延后提示，后台不弹窗。可选择“稍后”“忽略此版本”或“查看更新”；查看更新进入原有更新页，不直接下载或安装。手动进入更新页也会消费该版本的待提示记录。
- 自动检查失败、清单缺失或清单不合法时不弹错误窗口，也不会显示“已是最新版本”；手动检查仍在更新页显示错误和重试入口。已在下载或已准备好的安装包不触发新的启动提示。
- 下载由 Android 系统管理，离开更新页不会取消；用户可显式取消。下载结束后校验字节数、SHA-256、实际包名、版本及当前签名证书，安装前再次校验。
- 安装必须由用户点击。未允许“安装未知应用”时跳转系统授权页；返回应用只核对状态，不自动安装，仍须再次点击“立即安装”。系统安装界面返回后核对是否完成；不能把启动安装器当成已成功安装。
- 生图队列、图片处理、超分、漫画保存、Pixiv 上传、AI 助手等已接入的忙碌任务会阻止安装；已下载且验证过的 APK 保留，任务完成后可再尝试。
- 临时工作区或输入尚未保存时，显式点击安装后显示“安装前保存工作区”。选择“返回保存”回到上级；选择“已保存，继续安装”才允许丢弃临时内存编辑。安装可能关闭应用，临时遮罩、图层、撤销记录、未发送内容等不能保证保留；应先保存重要图片和内容。
- “稍后”返回上级，不安装、不清除已准备好的更新。更新说明只按纯文本展示，外部入口统一为“打开发布页”。

下载与安装不会携带生图或聊天 API 的凭据。发布源限定为 `https://github.com/sakiko0901/NAI-WorldPainter`；GitHub Release 资源的重定向按客户端白名单处理。

## 首次接入与线上现状

旧版本不含更新器，需要先手动安装一个包含本功能、包名及签名相同、实际 `versionCode` 更大的正式版本。此次手动覆盖安装是 bootstrap；后续版本才能使用应用内更新。不要为了升级先卸载旧版。

2026-10-31 09:50:33 UTC 实测：[`latest/download/update.json`](https://github.com/sakiko0901/NAI-WorldPainter/releases/latest/download/update.json) 跳转至 `v1.2.4-220052/update.json` 后返回 **404**。这表示当前最新 Release 尚无清单，不表示安装版本已经最新。该状态是当时的线上快照，后续发布后应重新检查。

当时的 [正式发布页](https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.2.4-220052) 标明源码版本为 `1.2.4+218052`，实际 APK 的 Android `versionCode` 为 `220052`。因此不能仅凭 `pubspec.yaml` 的 build 数字判断升级顺序，也不能用它替代最终 APK 信息。

## 版本、签名与清单契约

安装资格比较 **最终 APK 的实际 `versionCode`**，新值必须严格大于上一次已发布版本。`versionName` 来自 APK；Release tag 必须精确为 `v<versionName>-<versionCode>`，例如 `v1.2.5-220053`。脚本不修改源码版本、APK 内版本或签名。

当前 `android/app/build.gradle.kts` 的 release 配置仍引用 debug signingConfig，历史正式发布也使用 Android Debug 证书。这不代表任一本机默认 `debug.keystore` 都可信或都能覆盖已安装版本。必须保留与已发布 APK 对应的原签名私钥及备份，不能换一份本机新建的默认 key 后继续沿用发布身份。私钥、密码不提交仓库。V1 不处理证书轮换或多个当前签名者。

脚本必须使用以下一种显式信任来源：

1. `BaselineApkPath`：来源已核对的上一次正式发布 APK。先与可信发布记录、已保存校验回执核对 SHA-256；脚本再对它执行 `aapt dump badging` 与 `apksigner verify --print-certs`，读取真实 code 与证书并同新包比较。
2. `ExpectedSignerSha256` 与 `BaselineVersionCode`：证书指纹和上次实际 code 都已独立核对。指纹允许大小写、冒号分隔；不能临时从任意新 APK 或本机默认 key 提取一个值来充当信任依据。

同时传入两种来源会交叉核对，任一不一致即失败。仅提供证书指纹而没有 baseline code 也会失败，以免无法检查升级顺序。

[`New-AppUpdateManifest.ps1`](../scripts/New-AppUpdateManifest.ps1) 与 [Dart 模型](../lib/domain/entities/app_update.dart) 使用相同字段：

| 范围 | 字段及约束 |
| --- | --- |
| 顶层 | `schemaVersion: 1`、`channel: stable`、`packageName`、`versionName`、`versionCode`、UTC `publishedAt`、纯文本 `releaseNotes`、`releaseUrl`、`apk` |
| `apk` | `url`、从实际文件得到的 `sizeBytes` 与 `sha256`、`abi: arm64-v8a`、APK 实际 `minSdk` |
| URL | `https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/<tag>` 与同 tag 的 `releases/download/<tag>/app-release.apk` |
| 大小 | APK 1 字节–512 MiB；说明最多 65536 字符，无禁止的控制字符；编码后的整个清单最多 128 KiB |

生成的 `SHA256SUMS.txt` 包含 `app-release.apk` 与 `update.json` 两行 SHA-256。输入 APK 不改名、不复制、不覆盖；如果本地文件名不同，上传资源时必须使用同字节副本并命名为 `app-release.apk`。已有输出文件会被拒绝覆盖，应为每个发布使用独立目录。

脚本用只读共享方式打开输入，防止 Windows 上校验期间被另一个进程改写。包名、签名、tag、code、ABI、工具退出码或其他必要输入不一致时，不生成可发布清单。它不替代安装体验、完整 Android 构建或真实设备验证。

## 本地生成命令

使用可信 Android SDK Build Tools 中的 `aapt.exe` 和 `apksigner.bat`；运行 `apksigner` 还需要可用 Java。工具不齐时脚本会报错，不会自动安装 SDK。下列路径及 `1.2.5 / 220053` 是命令示例，必须替换为真实最终签名产物的信息；本次开发没有据此构建或发布新 APK。

```powershell
Set-Location 'E:\NAI-WorldPainter\手机端'
$buildTools = 'D:\Android\Sdk\build-tools\36.0.0'
$apk = 'D:\release-input\final-signed\app-release.apk'
$baseline = 'D:\release-input\published-v1.2.4-220052.apk'
$notes = 'D:\release-input\release-notes.txt' # UTF-8 纯文本
$output = 'D:\release-staging\v1.2.5-220053'
$tag = 'v1.2.5-220053'

# 先从可信已发布记录核对 baseline；下面是 220052 发布页所列的文件哈希。
$expectedBaselineHash = '8BEAD1DD10816A4F35813AA56347D77E730A7AA5A3760F99A527CE9319856A46'
if ((Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash -ine $expectedBaselineHash) {
    throw 'Baseline APK differs from the trusted published artifact.'
}

& "$buildTools\aapt.exe" dump badging $apk
& "$buildTools\apksigner.bat" verify --print-certs $apk

$result = & '.\scripts\New-AppUpdateManifest.ps1' `
    -ApkPath $apk `
    -BaselineApkPath $baseline `
    -ReleaseTag $tag `
    -ReleaseNotesPath $notes `
    -OutputDirectory $output `
    -BuildToolsDirectory $buildTools `
    -PublishedAt '2026-10-31T12:00:00Z'
$result | Format-List
Get-Content -LiteralPath $result.ManifestPath -Raw -Encoding UTF8
Get-Content -LiteralPath $result.ChecksumsPath -Raw -Encoding UTF8
```

没有 baseline APK、但已保存可信证书指纹与实际发布 code 时，改用下面的路线。示例从已有可信文本记录读取指纹，不能把占位文字当作指纹：

```powershell
$trustedSigner = (Get-Content -LiteralPath 'D:\release-input\verified-release-signer-sha256.txt' -Raw).Trim()
$result = & '.\scripts\New-AppUpdateManifest.ps1' `
    -ApkPath $apk `
    -ExpectedSignerSha256 $trustedSigner `
    -BaselineVersionCode 220052 `
    -ReleaseTag $tag `
    -ReleaseNotesPath $notes `
    -OutputDirectory 'D:\release-staging\v1.2.5-220053-from-pin' `
    -BuildToolsDirectory $buildTools
```

`PublishedAt` 默认取生成时的 UTC 时间，也可显式提供带时区的实际发布时间。`AaptPath` 与 `ApkSignerPath` 可分别覆盖工具路径。只有可信真实工具的检查才构成 APK 校验证据；注入伪工具只用于下面的离线夹具测试。

## 先完成 draft，再发布

以下是发布者审核后的执行流程，不由生成脚本自动执行。先确认目标提交正是构建该 APK 的已审核源码，且候选的 tag/code/签名、三个文件及上传后的内容一致，再公开发布。上传过程中始终保持 draft，避免用户读到只有 APK、缺少清单的半成品 Release。[GitHub CLI 的 create](https://cli.github.com/manual/gh_release_create) 支持 `--draft` 与指定提交；[upload](https://cli.github.com/manual/gh_release_upload) 上传资源；[edit](https://cli.github.com/manual/gh_release_edit) 最后公开草稿并标为 Latest。

延续上面的 baseline 示例变量：

```powershell
$repo = 'sakiko0901/NAI-WorldPainter'
$releaseCommit = 'REPLACE_WITH_REVIEWED_FULL_COMMIT_SHA'
if ($releaseCommit -cnotmatch '^[a-f0-9]{40}$') { throw 'Set the reviewed build commit first.' }

# 为固定资源名建立副本；原始签名 APK 保留，复制后再次核对字节哈希。
$assetApk = Join-Path $output 'app-release.apk'
if (Test-Path -LiteralPath $assetApk) { throw 'APK staging file already exists.' }
Copy-Item -LiteralPath $apk -Destination $assetApk
if ((Get-FileHash -LiteralPath $assetApk).Hash -cne (Get-FileHash -LiteralPath $apk).Hash) {
    throw 'Staged APK differs from the validated APK.'
}

gh release create $tag --repo $repo --draft --target $releaseCommit --title $tag --notes-file $notes
if ($LASTEXITCODE -ne 0) { throw 'Draft creation failed.' }
gh release upload $tag $assetApk $result.ManifestPath $result.ChecksumsPath --repo $repo
if ($LASTEXITCODE -ne 0) { throw 'Asset upload failed; leave the release as draft.' }
gh release view $tag --repo $repo --json tagName,isDraft,isPrerelease,assets
```

审核页面应仍为 draft、非 prerelease，资源名应包含 `app-release.apk`、`update.json`、`SHA256SUMS.txt`。不要对已发布的资产直接使用 `--clobber`。可在独立目录用 `gh release download` 下载这三项，并分别与待发布原文件核对 SHA-256。签名与真实设备覆盖安装也应在公开前单独验收。全部审核通过后，才执行：

```powershell
gh release edit $tag --repo $repo --draft=false --latest
if ($LASTEXITCODE -ne 0) { throw 'Publishing failed.' }
# 此后再以未登录请求确认 latest/download/update.json、APK URL 和清单内容可用。
```

## 已执行验证与剩余验收

运行离线测试：

```powershell
pwsh -NoProfile -File '.\scripts\Test-AppUpdateManifest.ps1'
# Windows PowerShell 5.1 也可运行：
powershell.exe -NoProfile -File '.\scripts\Test-AppUpdateManifest.ps1'
```

本次在 PowerShell 7.6.5 和 Windows PowerShell 5.1 分别通过 23 个夹具案例，覆盖从 APK 工具输出读取版本而非 `pubspec.yaml`、显式信任来源、错签名、preview 包、tag/code 不符、旧 code、多 ABI、工具失败、输入改写、说明/清单限制及不覆盖已有输出。

测试中的 `.apk` 实际是 JSON 夹具，注入的 `.ps1` 模拟 `aapt` 与 `apksigner` 输出。**这些结果不是真实 APK 签名验证，也不是完整 Android 构建、真机安装或系统授权回跳验收。** 发布前仍需使用真实 SDK 工具对最终签名 APK 跑生成器，并验证真实设备上的下载、取消、进程重启恢复、校验失败、权限拒绝/授权、取消安装、覆盖安装与数据保存行为。本次脚本测试没有上传或发布资源。

工具语义依据 [Android apksigner 文档](https://developer.android.com/tools/apksigner)（verify 与证书输出）和 [AAPT2 dump 文档](https://developer.android.com/tools/aapt2#dump)（badging 读取 APK 清单）；脚本默认调用 SDK 的 `aapt dump badging`。

V1 仅处理完整 APK。差分下载、补丁合成、更多 ABI、其他渠道及签名轮换留待后续版本单独设计和验证。
