# NAI 绘世 — 架构地图

> 版本：2026-05-31 / 对应仓库当前 HEAD
> 目标读者：希望快速理解整个工程脉络、定位修改点的开发者。

## 一、整体分层

工程使用 Clean Architecture 三层 + 表现层视图模型：

```
┌──────────────────────────────────────────────────────────────┐
│ presentation                                                │
│  ├─ pages (UI)             ├─ viewmodels (ChangeNotifier)   │
│  └─ widgets                                                 │
└──────────────────────────────────────────────────────────────┘
              │ 依赖
              ▼
┌──────────────────────────────────────────────────────────────┐
│ domain                                                       │
│  ├─ entities (纯数据)       ├─ repositories (抽象接口)        │
│  └─ usecases (业务用例)                                       │
└──────────────────────────────────────────────────────────────┘
              │ 依赖
              ▼
┌──────────────────────────────────────────────────────────────┐
│ data                                                         │
│  ├─ models (json 序列化)    ├─ datasources (local / remote)  │
│  └─ repositories (实现)                                       │
└──────────────────────────────────────────────────────────────┘
              │ 依赖
              ▼
┌──────────────────────────────────────────────────────────────┐
│ core                                                         │
│  constants / di / errors / network / queue / services / utils│
└──────────────────────────────────────────────────────────────┘
```

依赖方向：上层只依赖下层；`data` 实现 `domain` 的抽象，`presentation` 仅依赖 `domain` 与 `core`。

## 二、入口与依赖注入

- `lib/main.dart`：`WidgetsFlutterBinding.ensureInitialized` → `configureDependencies()` → `BackgroundKeepAliveService.init()` → `runApp(NaiHuishiApp)`。
- `lib/core/di/injection.dart`：`get_it` 注册所有数据源、仓储、用例、视图模型。新增依赖一律在这里挂线。
- `lib/presentation/app.dart`：`MaterialApp` + 主题 + 首页 `HomePage`。

## 三、核心模块（core/）

| 路径 | 作用 |
|---|---|
| `constants/api_constants.dart` | 各供应商默认 URL、采样器列表、Nano 尺寸枚举等。|
| `constants/app_constants.dart` | SharedPreferences key 常量。**v2 多中转站 key**：`keyImageProvider{NovelAi,Gpt,Nano}Endpoints/ActiveEndpointId/ActiveModel`。`keyBatchCount` 存批量张数草稿。任务事件名（`taskSuccess` / `taskFailed` 等）也在此。|
| `di/injection.dart` | `get_it` 容器，单例注册。|
| `errors/exceptions.dart` | `ApiException` 等领域异常。|
| `network/robust_http_adapter.dart` | Dio 自定义适配器（重试 / 超时）。|
| `queue/generation_queue.dart` | **串行队列**。提供 `enqueue`、`taskStream`（任务事件流）、`queueStream`（队列状态流）。批量生成靠多次 `enqueue` 叠加，UI 用 `_awaitTaskComplete` 在 stream 上 Completer 等待。|
| `services/background_keepalive_service.dart` | **后台保活**。`flutter_foreground_task` + `wakelock_plus`，引用计数式 acquire/release。`generate()` 在 try/finally 中调用，保证锁屏后台不被杀。|
| `utils/image_utils.dart` | 图像解码、保存到相册等工具。|

## 四、领域层（domain/）

### 实体（entities/）

- `generation_task.dart`：单次出图任务（提示词、参数、seed、imagePath/Url、状态）。
- `nai_model.dart`：模型描述。
- `preset.dart` / `prompt_template.dart`：用户预设、提示词模板。
- `llm_session.dart` / `llm_message.dart`：聊天会话与消息。
- `api_endpoint.dart`：**v2 中转站实体**。一个 endpoint 包含 `id / name / baseUrl / apiKey / models[]`，用于多中转站配置。

### 仓储抽象（repositories/）

- `generation_repository.dart`：提交任务、轮询、获取模型列表。
- `history_repository.dart`：sqflite 历史。
- `llm_chat_repository.dart`：LLM 会话与消息存取。
- `preset_repository.dart` / `prompt_template_repository.dart`：本地存储。
- `settings_repository.dart`：除单值 v1 设置外，新增多 endpoint v2 接口与 `getBatchCount/setBatchCount`。

### 用例（usecases/）

- `generate_image.dart`：把 task push 到 `GenerationQueue`。
- `manage_settings.dart`：聚合所有设置 getter/setter（v1 + v2 endpoints + batch）。
- `manage_llm_chat.dart` / `manage_presets.dart` / `manage_prompt_templates.dart`：CRUD。
- `save_image.dart` / `get_history.dart`：相册保存、历史查询。

## 五、数据层（data/）

### 数据源

- `local/database_helper.dart`：sqflite 句柄。
- `local/llm_chat_local_datasource.dart`：会话表读写。
- `local/settings_local_datasource.dart`：**关键**。负责 v1→v2 endpoint **自动迁移**：第一次 `getEndpoints(provider)` 若空，则用旧的单值 url/key/model 拼成 `name = '默认'` 的 endpoint 写回新 key。Batch 张数 1-30 clamp。
- `remote/novelai_api_service.dart` / `gpt_api_service.dart` / `nano_banana_api_service.dart`：三套 HTTP 客户端，统一 dio 入口。
- `remote/llm_api_service.dart`：聊天补全。
- `remote/bing_search_service.dart`：内置搜索能力。

### 仓储实现

- `repositories/generation_repository_impl.dart`：核心实现 `_resolveCreds(provider)` —— 优先读取 active endpoint，否则回落 v1 单值。`fetchModels` 与 `_submit*` 都走这里。
- 其余 repo 是简单 datasource passthrough。

## 六、表现层（presentation/）

### 页面

| 页面 | 主要职责 |
|---|---|
| `pages/home_page.dart` | 底部 Tab 容器（History / Generate / Settings 等）。|
| `pages/generate_page.dart` | 出图主页：**批量滑块（1-30）**、**结果区缩略图带**、保存按钮基于 `selectedResult ?? lastCompletedTask`。底部 Generate 按钮在批量模式下显示 `n/N` 进度。集成 `ChatDrawer`，`onApplyAll` 把聚合 segments 写回 vm。|
| `pages/api_config_page.dart` | **API 配置子页**。顶部 TabBar（NovelAI / GPT / Nano）。每 provider 一组 endpoint 卡片：可展开、设激活、连测、编辑、删除。`+ 添加中转站` 在底部。保存用 `showFloatingToast('已保存配置')`。|
| `pages/settings_page.dart` | 进入 API 配置、外观、关于。|
| `pages/history_page.dart` / `history_detail_page.dart` | 历史浏览。|

### ViewModel

- `generation_viewmodel.dart`：包含 `imageModelOptions`（聚合多 provider）、`batchCount` / `sessionResults` / `selectedResultTaskId` / `batchRemaining`、`generate()` 批量循环 + 1s 冷却 + `BackgroundKeepAliveService.acquire/release`、`_awaitTaskComplete` 用 `Completer + StreamSubscription` 监听队列任务事件。
- `settings_viewmodel.dart`：v2 endpoint CRUD（`addEndpoint/updateEndpoint/removeEndpoint/setActive`），保留 v1 字段做向后兼容。
- `llm_chat_viewmodel.dart` / `preset_viewmodel.dart` / `prompt_template_viewmodel.dart` / `history_viewmodel.dart`：典型 ChangeNotifier。

### 共享 Widget

- `widgets/floating_toast.dart`：`showFloatingToast(context, text, {duration, icon})`。Reqs 2/3 的保存确认在用。
- `widgets/fullscreen_image_preview.dart`：图片大图预览。
- `widgets/llm_chat/chat_message_bubble.dart`：包含 **`AppliedSegments` 聚合**与 `_ApplyAllButton`。把助手回复中所有 ```code``` 段按 label（角色N / 负向 / 正向 / 通用底模）归类，弹出 `_ApplyAllButton`。
- `widgets/llm_chat/chat_drawer.dart`：聊天侧抽屉，把 `onApplyAll` 透传给 bubble。
- `widgets/llm_chat/chat_settings_sheet.dart`：会话级别配置；保存改用 `showFloatingToast` 而不再 pop。

## 七、后台保活流（Req 5）

```
generate()  ──▶ acquire(notif='批量生成 0/N')
                │
                ├─▶ enqueue task1 ──▶ awaitComplete ──▶ updateNotification('1/N')
                │   …
                │   enqueue taskN ──▶ awaitComplete
                │
                ▼ finally { release() }  ──▶ stopService + WakelockPlus.disable
```

- AndroidManifest 已声明：`FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` / `WAKE_LOCK` / `POST_NOTIFICATIONS` / `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，并注册 `flutter_foreground_task` 的 `ForegroundService` 服务。
- 引用计数：多次 acquire 不重复启服务，最后一次 release 才真正停止。

## 八、关键状态键速查

| 用途 | Key（v1） | Key（v2） |
|---|---|---|
| NovelAI 单 url/key | `keyImageProviderNovelAiBaseUrl` / `keyImageProviderNovelAiApiKey` | `keyImageProviderNovelAiEndpoints` |
| NovelAI 当前 endpoint / 模型 | `keyImageProviderNovelAiModel` | `keyImageProviderNovelAiActiveEndpointId` / `keyImageProviderNovelAiActiveModel_v2` |
| GPT / Nano | 同上模式 | 同上模式 |
| 批量张数 | — | `batch_count_draft` |

## 九、改动落点速查表

| 想做什么 | 改这里 |
|---|---|
| 加新 provider | `domain/entities/api_endpoint.dart` 已通用；`generation_repository_impl.dart` 加 `_submit*` 与 `_resolveCreds` 分支；`api_config_page.dart` 加 TabBar 项；`settings_local_datasource.dart` 加 `_keysFor` 分支；`app_constants.dart` 加 v2 keys。|
| 改保存确认提示 | `presentation/widgets/floating_toast.dart`（动画 / 时长 / 图标）。|
| 调整批量循环节奏 | `generation_viewmodel.dart` 的 `generate()` 中 1s `Future.delayed`。|
| 调整后台通知文案 | `BackgroundKeepAliveService.acquire/updateNotification`。|
| 一键替换全部的归类规则 | `chat_message_bubble.dart` 的 `_isPositiveLabel` / `_characterIndex` / `_aggregateSegments`。|
| 缩略图大小 / 选中样式 | `generate_page.dart` 的 `_buildResultSection` 中 `ListView.separated` 与 `AnimatedContainer.decoration`。|

## 十、构建与同步约定

- 编辑 → `rsync` 到 `C:\Users\Elysia\nai_huishi_build` → `flutter clean && flutter build apk --release` → 把 `app-release.apk` 复制到 `C:\Users\Elysia\Desktop\绘世\`。
- 不在源工程目录直接构建，避免污染。
