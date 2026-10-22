# V5 Medium / High 渠道切换

工作台沿用结果区的 High / Medium 按钮，支持 NovelAI 官方、ikun、7877 的 V5 Full 和对应局部重绘模型。V5 Curated、V4.5 等没有 Medium 对应模型，不显示切换。

| 命名方式 | High | Medium |
| --- | --- | --- |
| 原生 Full | `nai-diffusion-5-full` | `nai-diffusion-5-full-medium` |
| 原生重绘 | `nai-diffusion-5-full-inpainting` | `nai-diffusion-5-full-medium-inpainting` |
| 网关 Full | `nai-v5-full` | `nai-v5-full-medium` |
| 网关重绘 | `nai-v5-inpaint` | `nai-v5-inpaint-medium` |

网关的 `nai-v5-full-limit`、`nai-v5-inpaint-limit` 可切至同类 Medium，返回 High 时保留原来的 `-limit` 名称。没有新增 `-high` 或 `-medium-limit` 模型。7877 在请求层将上述非 limit 别名映射到原生名称，ikun 保留模型目录提供的名称。

Medium 固定 14 步、`k_euler_ancestral`，任务内 CFG Rescale 为 0；切回 High 会恢复切换前的步数、采样器和 CFG Rescale。显式选择 Medium 模型、历史回填及独立局部重绘工作区也应用对应模型与参数。

第三方 Medium 请求按 LFN 的接口约束处理：

- 每次请求 1 张，宽高为 64 的倍数，面积不超过 1,048,576 像素；工作台批量仍通过原串行队列逐张提交。
- JSON 省略 `cfg_rescale`，因为 LFN 即使收到 `0` 也会拒绝该字段。
- 不提交自定义全局或角色负面词、Vibe、精密参考；工作台原草稿保留，返回 High 后继续使用。
- 文生图、图生图、局部重绘使用独立的 Medium 请求构建，High 保留原渠道格式。

接口依据为 [Love for NAI](https://github.com/fuilyha56-wq/love-for-nai) 的 `4e1cf8df663759796e1031b7992818f8416679fa`（2026-10-22 核读），主要参考 [模型映射](https://github.com/fuilyha56-wq/love-for-nai/blob/4e1cf8df663759796e1031b7992818f8416679fa/src/lib/nai-native-request.ts)、[Medium 校验](https://github.com/fuilyha56-wq/love-for-nai/blob/4e1cf8df663759796e1031b7992818f8416679fa/src/lib/image-request.ts#L107)和 [前端切换](https://github.com/fuilyha56-wq/love-for-nai/blob/4e1cf8df663759796e1031b7992818f8416679fa/src/app/image/studio.tsx#L3063)。这里只参考协议与交互，没有复制上游前端实现。

本地验证使用 ViewModel、实际串行队列、组件交互及 loopback HTTP 请求捕获。它们不代表 Android 真机或第三方付费上游生图已验证；账号仍需拥有目标模型权限。

2026-10-22 验证：原锁定依赖下运行 `flutter test --no-pub --concurrency=1`，324 项通过、1 项原有跳过；`dart analyze lib test` 为 0 errors，10 个既有 warning 和 278 个既有 info，与修改前一致。全量并行运行曾触发两个既有数据库测试共用文件的锁冲突，因此最终全量验证使用串行执行；没有修改数据库测试或降低断言。
