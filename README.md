<div align="center">

# NAI-WorldPainter · 绘世

### 面向 Android 的 NovelAI 一站式创作客户端

> 当前功能分支为 `feat/mobile-preview-v5`。本分支的前端和 AI 记忆改动请按[分支安装包构建说明](docs/android_apk_testing.md)验证；下方 Releases 下载入口属于历史发布版本，不能代表本分支最新源码。

从自然语言提示词、精密参照与图像生成，到超分、打标和 Pixiv 发布，在一个应用中完成完整工作流。

[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#系统要求)
[![Framework](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Version](https://img.shields.io/badge/Version-1.2.2-FF6F61?style=for-the-badge)](https://github.com/cocophilia093-wq/NAI-WorldPainter/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-8A63D2?style=for-the-badge)](LICENSE)

<br>

[**下载最新版 APK**](https://github.com/cocophilia093-wq/NAI-WorldPainter/releases/latest/download/app-release.apk)
&nbsp;&nbsp;·&nbsp;&nbsp;
[查看发布说明](https://github.com/cocophilia093-wq/NAI-WorldPainter/releases/latest)
&nbsp;&nbsp;·&nbsp;&nbsp;
[浏览功能](#功能亮点)

> 当前提供 Android arm64-v8a Release APK，约 50 MB。

</div>

---

## 导航

- [功能亮点](#功能亮点)
- [下载与安装](#下载与安装)
- [系统要求](#系统要求)
- [功能清单](#功能清单)
- [架构](#架构)
- [资源目录](#资源目录)
- [致谢](#致谢--credits)

## 功能亮点

<table>
<tr>
<td width="50%" valign="top">

### NovelAI 专业生图
多角色提示词、坐标控制、Vibe Transfer、独立 Precise Reference、涂改重绘、批量队列与完整高级参数。

</td>
<td width="50%" valign="top">

### 大白话提示词 Agent
用自然语言描述画面，Agent 自动检索真实 Danbooru tag、编排提示词并在确认后执行生图。

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 图片后期工作台
集成 Director Tools、WD-Tagger、NAI 元数据解析，以及 Real-ESRGAN / RealCUGAN 本地超分。

</td>
<td width="50%" valign="top">

### 完整发布工作流
本地历史、提示词记忆、风格与艺术家预设，并支持 Pixiv 上传队列和自动标题、标签处理。

</td>
</tr>
</table>

## 下载与安装

### 推荐：直接下载安装包

<div align="center">

[![Download APK](https://img.shields.io/badge/下载-最新版_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/cocophilia093-wq/NAI-WorldPainter/releases/latest/download/app-release.apk)

[所有版本与更新说明](https://github.com/cocophilia093-wq/NAI-WorldPainter/releases)

</div>

1. 下载 `app-release.apk`。
2. 在 Android 系统中允许浏览器或文件管理器“安装未知应用”。
3. 安装并启动绘世。
4. 打开「设置 → API 配置」，填写 NovelAI 兼容网关的 Base URL、API Key 与模型。

> Android 若提示“文件可能有害”，这是侧载 APK 的通用提示。请仅从本仓库 Releases 下载，并核对发布者为 `cocophilia093-wq`。

## 系统要求

| 项目 | 要求 |
|---|---|
| **系统** | Android 设备 |
| **架构** | arm64-v8a |
| **版本** | 1.2.2+208011 |
| **安装包** | 约 50 MB |
| **网络** | 使用云端生图、LLM、打标及 Pixiv 功能时需要网络 |
| **必要配置** | NovelAI 兼容网关 Base URL、API Key、可用模型 |
| **可选配置** | OpenAI 兼容 LLM、Pixiv Cookie、代理等 |

## 架构

Clean Architecture 分层，每层职责清晰：

```
┌──────────────────────────────────────────────────────────┐
│  presentation/   页面 · viewmodel · widget               │
├──────────────────────────────────────────────────────────┤
│  domain/         实体 · 用例 · 仓库接口 · Agent 工具      │
├──────────────────────────────────────────────────────────┤
│  data/           数据源 · 仓库实现 · 模型                │
├──────────────────────────────────────────────────────────┤
│  core/           DI · 常量 · 网络 · 错误处理             │
└──────────────────────────────────────────────────────────┘
```

**关键依赖：**

| 依赖 | 用途 |
|---|---|
| `dio` | HTTP / API 调用 |
| `sqflite` | 历史 / 提示词记忆 / 聊天持久化 |
| `image_gallery_saver_plus` | 保存到相册 |
| `flutter_foreground_task` + `wakelock_plus` | 生图时后台保活与亮屏 |
| `image` | PNG 元数据处理 |
| `image_picker` | 选图 |
| `html` | DuckDuckGo Lite HTML 解析 |
| `google_fonts` | 排版 |

## 功能清单

### 1. NovelAI 图像生成（核心）

> 全功能生图工作台，支持权重语法、涂改重绘、批量生成与后台保活。

- 正/负向提示词编辑，支持 NAI 权重语法 `{}` / `[]` / `()`
- 本地涂改重绘（mask 画板），支持 inpaint 正/负向提示词
- 模型选择（从配置的 NAI 兼容网关拉取可用模型列表）
- Vibe Transfer 与独立 Precise Reference（参考类型、强度、忠实度）
- 多角色提示词、负向提示词与坐标控制
- 分辨率、采样器、噪声调度、CFG scale、seed 全可调
- 单次批量 1–30 张
- 预览、全屏查看、一键保存到相册
- 串行生成队列 + Android 前台服务通知，避免后台被杀
- 结果持久化到 SQLite，可在「历史」页回看

### 2. LLM 提示词助手（抽屉式）

> 在生成页侧滑抽屉里调出聊天界面，用大白话就能得到高质量提示词。

- OpenAI 兼容接口，可接入任意 LLM Provider
- 主模型负责 Agent 循环与最终回复，识图模型由系统在用户上传图片时自动调用
- 聊天历史持久化到本地 SQLite
- 联网搜索手动开关（跨会话持久化）
- 多 Provider 管理与角色绑定（见 [§7](#7-llm-provider-多供应商管理)）

### 3. Danbooru 标签智能校准

> LLM 每次回复后自动对正向提示词做一次校准，让 LLM 不再胡编 tag。

| 能力 | 说明 |
|---|---|
| **标签标准化** | 把 LLM 写的非标准词替换成 Danbooru 真实存在的标签，规避角色名/作品名幻觉 |
| **共现补充** | 基于 NPMI 共现统计补充常一同出现的细节标签 |
| **元数据展示** | 每个 tag 附带中文名、wiki 释义、热度，悬浮可见 |

**双端点自动故障转移：** ModelScope 创空间端点（国内直连）→ HuggingFace Space 备份端点。两个端点都是公共免费服务，无需 API Key。

**设置入口：** LLM 抽屉齿轮 → 「Danbooru 校准」，可启用/关闭、自定义 Base URL（可填自托管地址）。校准结果显示在 LLM 消息底部，与全局 NSFW 开关联动。

### 4. Agent 工具循环

> LLM 可在多步对话中串联调用以下工具，覆盖从查询到生图到上传的全链路。

| 工具 | 说明 | 需确认 |
|---|---|:---:|
| `read_current_prompts` | 读取 4 个提示词框 + 6 个角色槽 + 涂改重绘模式 | 否 |
| `write_prompt` | 写入提示词框（positive / negative / inpaint_positive / inpaint_negative），支持 append / replace | 否 |
| `search_danbooru` | 直查 Danbooru 真实 tag 池，单次返回最多 30 个 | 否 |
| `web_search` | DuckDuckGo Lite（免费、无 API Key） | 否 |
| `generate_image` | 用当前生成页配置生图 | 是 |
| `save_image` | 保存到相册 | 是 |
| `upscale_image` | 调用原生超分通道（Real-ESRGAN / RealCUGAN） | 是 |
| `upload_to_pixiv` | 上传 1–30 张到 Pixiv（需标题、tag、可选正文、R18） | 是 |
| `save_memory` | 保存到本地记忆库（默认 `pendingLlmCandidate` 状态） | 否 |
| `get_memories` | 模糊匹配用户文本，返回相关记忆 | 否 |
| `remove_character` / `clear_characters` | 删除角色槽 | 否 |

**记忆库分类：**

| 类型 type | 取值 |
|---|---|
| 8 类 | `characterName` · `characterFeature` · `style` · `other` · `fact` · `preference` · `observation` · `decision` |
| 4 来源 source | `manual` · `userInstruction` · `llmCandidate` · `pendingLlmCandidate` |

### 5. Pixiv 上传队列

> 全自动 Pixiv 上传流水线，从元数据剥离到标题生成到冷却风控一应俱全。

**页面：**
- `pixiv_upload_page` — 上传表单：选图、标题/正文/tag 编辑、R18 开关
- `pixiv_queue_page` — 队列监控：暂停/继续，单任务状态 `pending` / `uploading` / `cooldown` / `completed` / `failed` / `canceled`
- `pixiv_settings_page` — 配置页

**核心实现：**

| 模块 | 说明 |
|---|---|
| **元数据剥离** | `PixivImageCloaker` 移除 PNG tEXt/iTXt 块并用 stealth alpha LSB 重编码，大图走 Isolate 避免卡 UI |
| **标题生成** | `PixivTitleGenerator` 用 `assets/pixiv/characters.json` 与 `surroundings.json` 匹配提示词，自动生成中文标题（如"角色名~"或"和角色名在场景涩涩~"） |
| **Tag 建议** | 调用 Pixiv `/rpc/suggest_tags_by_image.php`（需有效 cookie） |
| **冷却** | 基础分钟数 ±5 分钟随机抖动，避免风控 |
| **代理** | 支持 HTTP / SOCKS 代理 |

**必填项：** `Cookie` 与 `x-csrf-token`（从浏览器登录 Pixiv 后提取）。缺少任一项会以 `PixivAuthException` 失败。

**配置字段：** cookie · csrfToken · 代理 · 正文前缀 · 默认 tag · R18 默认 · 允许编辑 tag · 剥离元数据 · 启用 tag 建议 · 冷却分钟数 · tag 替换百分比 · 垃圾文本填充

### 6. 图片打标与元数据解析

> 两种分析来源可组合使用，从图片反向提取 prompt 与 tag。

**NAI 元数据解析：**
- 读取 PNG tEXt/iTXt 块（`Title` / `Description` / `Software` / `Source` / `Comment`）
- 支持 stealth alpha LSB 回退（magic: `stealth_pngcomp`）
- 兼容 v3 与 v4 多角色格式（`v4_prompt.caption.char_captions`）
- 可还原 prompt、negative prompt、seed、steps、sampler、scale、cfg_rescale、noise_schedule、宽高

**WD-Tagger：**

| 项目 | 详情 |
|---|---|
| 模型 | HuggingFace Space 上 SmilingWolf 维护的 WD-Tagger |
| 预置 | SwinV2 v3 · ConvNext v3 · ViT v3 · MOAT v2 · SwinV2 v2 · ConvNextV2 v2 |
| 协议 | Gradio 6.x SSE（upload → submit → poll） |
| 重试 | 503/502/429 冷启动自动指数退避（最多 8 次，约 4 分钟） |
| 输出 | general / character / rating 三类 tag 与置信度，阈值可调 |

选中 tag 可复制到剪贴板或一键送入生成页提示词框。

### 7. LLM Provider 多供应商管理

> 一套应用支持多个 LLM 服务商，主模型与识图模型可分别绑定。

- 多 Provider 列表，每个 Provider 含名称、API Key、Base URL、模型列表
- 角色绑定：主模型（chat）与识图模型（vision）各绑定到指定 Provider ID
- 接口协议：OpenAI 兼容 chat completions，文本与多模态任务共用
- 入口：设置 → API 配置 → LLM Tab

### 8. 图片超分增强

> 原生 NCNN 集成，通过 `MethodChannel` / `EventChannel` 与 Flutter 通信。

| 模型 | 放大倍率 | 特点 |
|---|:---:|---|
| Real-ESRGAN (anime) | 4x | 动漫画风，线条锐利，强降噪 |
| RealCUGAN | 2x | 保守，保留自然细节 |
| RealCUGAN | 4x | 保守，4 倍放大 |

**流程：** 相册选图 → 选模型与倍率 → 运行 → 拖拽对比前后 → 保存到相册

**技术细节：** 模型文件位于 `filesDir/sr_models/`。ELF 改名 `.so` 放 jniLibs 以绕过 Android W^X 限制，模型走原生 assets 分发。

### 9. 风格预设

> 24 个预置风格，一键应用。

24 个预置风格（`assets/style_presets/style_001.jpg` ~ `style_024.jpg`），元数据存于 `style_presets.json`。浏览预览图、查看与编辑 prompt 字符串、一键应用到生成页。

### 10. 艺术家提示词管理

> 137 个艺术家参考图，分类浏览与权重调整。

137 个艺术家参考图（`assets/artist_prompts/artist_001.jpg` ~ `artist_137.jpg`），元数据存于 `artist_prompts.json`。分类浏览、调整权重、生成 NAI 艺术家风提示词串。

### 11. Danbooru 标签搜索页

> 直查 Danbooru tag 数据库。

结果显示 tag 名、中文名、分类、热度。可单独复制。复用 §3 的 `DanbooruApiService`。

### 12. 提示词记忆库

> SQFLite 持久化的 trigger→content 映射，Agent 可读写。

- 每条记忆含 id、trigger、content、type（8 类）、source（4 来源）、hitCount、createdAt、updatedAt
- Agent 通过 `save_memory` / `get_memories` 工具读写
- 独立管理页可手动 CRUD 与查看命中次数

### 13. 提示词胶囊库

> ~6747 条 tag 条目，分类覆盖创作全场景。

~6747 条 tag 条目（`lib/core/constants/prompt_capsule_library.dart`），紧凑编码（`|` 与 `=` 分隔）。在生成页通过底部 sheet 浏览并插入 tag。

**分类覆盖：**

```
人物  ·  服饰  ·  姿势动作  ·  场景  ·  画质画风  ·  光影色彩  ·  …
```

`assets/pixiv/characters.json` 与 `surroundings.json` 还兼任 Pixiv 标题生成的字典。

### 14. 历史记录

> 全部生成结果持久化到 SQLite，随时回看与复用。

- **列表页：** 缩略图、状态、时间戳
- **详情页：** 完整 prompt、negative prompt、参数（seed / steps / sampler / scale / cfg_rescale / noise_schedule / 宽高）、全屏图、保存/分享

### 15. API 配置

> 三 Tab 配置，覆盖所有外部服务。

| Tab | 配置项 |
|---|---|
| **NovelAI** | 端点、API Key、模型选择（拉取在线模型列表） |
| **LLM** | 端点、API Key、模型（与 §7 的 Provider 管理互补） |
| **Nano Banana** | 独立的 Nano Banana 网关端点与 API Key |

### 16. Director Tools

> 直接在应用内完成 NovelAI Director 图像处理。

- 去杂物、背景移除、线稿化与草图化
- 智能上色与表情调整
- 支持源图预览、参数编辑、处理结果查看与保存

### 17. 主题与全局 UI

- 浅/深色主题切换（生成页左上角动画切换按钮，sun ↔ moon）
- 持久化到 SharedPreferences
- 全局 UI 反馈走悬浮窗，浅/深色与选中态全局一致

## 资源目录

| 路径 | 内容 |
|---|---|
| `assets/style_presets/` | 24 张风格预览 JPG + `style_presets.json` |
| `assets/artist_prompts/` | 137 张艺术家参考 JPG + `artist_prompts.json` |
| `assets/pixiv/` | `characters.json`、`surroundings.json`（标题生成字典） |
| `assets/icons/` | `app_icon.png` 启动图标 |
| `lib/assets/` | `nsfw_knowledge.json`（NSFW 参考数据，编译期打包） |

## 致谢 / Credits

本项目的 NovelAI 绘图接口适配基于/参考了 [tt-P607](https://github.com/tt-P607) 的相关项目：

- [novelai-gateway](https://github.com/tt-P607/novelai-gateway)
- [new-api](https://github.com/tt-P607/new-api)

感谢原作者提供 NovelAI 绘图转 New API 相关接口方案。本项目主要提供 Android APK 客户端封装与界面实现，接口相关能力与原始方案归原作者所有。

提示词辅助写手的 Danbooru 校准与标签检索能力接入了 **SuzumiyaAkizuki** 开源的 [DanbooruSearchOnline](https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline) 项目。感谢作者提供基于语义匹配的 Danbooru 标签搜索、共现关联推荐及公开 API 服务。

- **项目主页：** [SuzumiyaAkizuki/DanbooruSearchOnline](https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline)
- **在线服务：** [DanbooruSearch](https://huggingface.co/spaces/SAkizuki/DanbooruSearch)
- **数据库管线：** [danbooru-tag-pipeline](https://github.com/SuzumiyaAkizuki/danbooru-tag-pipeline)
- **上游许可证：** [GNU GPLv3](https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline/blob/main/LICENSE)

图片打标功能基于 [SmilingWolf](https://huggingface.co/SmilingWolf) 的 WD-Tagger 模型（HuggingFace Space 托管）。

图片超分功能基于 [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) 与 [RealCUGAN-NCNN](https://github.com/nihui/realcugan-ncnn-vulkan) 的 NCNN 推理实现。

---

<div align="center">

**[↑ 返回顶部](#nai-worldpainter)**

</div>
