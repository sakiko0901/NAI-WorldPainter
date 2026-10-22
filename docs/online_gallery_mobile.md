# 手机端在线图库

入口位于「工具 → 素材与提示词」第一项。在线图库是独立路由，底部仍为创作、AI 助手、工具三个入口，本地生成历史不受影响。

## 参考与范围

参照 PC 端 `feat/online-gallery-discovery` 的 `2a3bac4`，按其当前协议在 Flutter 中实现原生页面。参考文件包括 `docs/ONLINE_GALLERY_DISCOVERY.md`、`desktop/src/gallery-discovery.ts`、`civitai-gallery.ts`、`quicktag.ts`、`tags-gallery.ts` 及对应 Electron 图库接口。

| 图源 | 手机端能力与边界 |
| --- | --- |
| AI TAG | 搜索、最新、月榜及历史时间范围；摘要缺少图片时按可见卡片读取详情。 |
| 画师排行榜 | 排行与名称查询，进入画师作品集合，再打开作品详情。 |
| Danbooru / Safebooru | 标签查询、排序、时间范围、列表与详情。 |
| Gelbooru | DAPI 标签查询与排序；需用户在图库筛选设置中填写自己的 User ID、API Key。 |
| QuickTagCloud | 集合、类型、分类目录、跨集合搜索、完整集合排序后分页、多图和角色提示词块。 |
| TAGs Gallery | V4.5 / V5、九类目录及各自排序；拼接上游 60 条分页，隔离不同模型图片与推荐区内容。 |
| Civitai | 用户名查询、图片排序和时间范围、公开元数据、opaque cursor 续页；没有公开提示词时显示缺失状态。 |

筛选仅展示图源支持的选项。上游可能隐藏作品、缺图、缺提示词、限流或改变页面结构，失败可重试或打开来源网站。Civitai 不将搜索框伪装为全文提示词搜索，也不跟随上游返回的任意 `nextPage` URL。

## 主要交互

- 双列瀑布流；搜索、切换来源和筛选重置分页，旧请求不能覆盖新结果；详情返回保留列表位置。
- 独立收藏页，收藏按图源、集合和条目身份区分；收藏写入成功后才更新界面。
- 详情显示来源、尺寸、公开模型信息、正负提示词、分类及说明，支持复制和打开来源网站。
- 「用于创作」先预览并选择正向/负向提示词与追加/替换方式，然后返回创作草稿。来源没有负向词时保留原草稿；不修改生图渠道、模型、Seed，也不自动生成。QuickTag 角色块可单独复制。
- 下载校验图片内容，保留来源图片字节并读取相册插件保存回执；失败不显示成功。画风保存复用现有画风库的持久图片导入路径。

## 数据与网络

`OnlineGalleryRepository` 负责图源适配、收藏、缓存、下载和画风导入；`OnlineGalleryViewModel` 只管理页面状态。图库使用单独的 Dio，正常验证 HTTPS，不继承生图 Token 或中转站授权头。

收藏和上次筛选存入独立、带版本号的 SharedPreferences 键；Gelbooru 凭据只存入 FlutterSecureStorage，不复制 PC 端内置凭据。网络错误不会在 UI 显示带凭据的请求 URL。

预览缓存位于临时目录 `online_gallery_cache`，上限 160 MiB；原始下载位于应用文档目录 `online_gallery_downloads`。清理图库缓存保留原图、收藏和画风库，不触碰生成历史或生成计数。图片请求最多四个并发，单张下载最多 40 MiB，解码前检查格式和尺寸。

来源网站通过 Android `ACTION_VIEW` 通道交给浏览器。相册保存复用项目已锁定的 `image_gallery_saver_plus`，未新增依赖。

## 验证

适配器 fixture 测试检查真实请求参数、上游分页映射、不同模型图像隔离、多图/提示词字段及推荐区排除。存储测试检查收藏重新读取、并发写入、凭据隔离、图片字节、保存回执、缓存清理、详情模式隔离和持久画风导入。页面测试检查入口顺序、来源筛选、列表位置、回填边界和窄屏布局。

匿名真实端点验证覆盖七个无需凭据图源的公开列表和详情元数据，Civitai 包含游标下一页。另抽样读取 Danbooru、AI TAG、QuickTag、TAGs Gallery、Civitai 各一张公开预览，均通过图片格式与尺寸解析；只在内存中读取，没有保存真实作品到相册或调用付费生图接口。Gelbooru 没有配置真实账号，仅验证模拟协议与凭据设置。Flutter widget 截图使用合成示例数据，不能替代 Android 真机、相册权限、浏览器跳转或完整 CDN 下载验收。

本次不打包 APK、不合并主分支。

2026-10-22 验证记录：

- `flutter test --no-pub --concurrency=1`：370 项通过，1 项原有跳过项；下载保存回执补充测试另行复测通过。
- `dart analyze`：0 error；原有 288 条诊断与修改前逐项匹配，没有新增诊断。
- 393 × 852 实际 Flutter widget 渲染核对五个页面；另测试 320 × 640、1.3 倍字体及键盘避让。截图使用合成渐变图与示例提示词。

参考协议：[Civitai images API](https://github.com/civitai/civitai-developer-docs/blob/main/site/reference/images.md)、[Android 浏览器 Intent](https://developer.android.com/guide/components/intents-common#Browser)。
