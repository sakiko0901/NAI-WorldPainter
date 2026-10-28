# 仓库首页展示资源

这些 PNG 来自当前 Flutter 组件的渲染截图，使用仓库内 `assets/style_presets/style_001.jpg` 和测试用演示数据。它们用于展示界面，不代表真实账户、手机截图或实际在线生图结果。封面 `worldpainter-cover.svg` 为本仓库的独立矢量排版，不含外部字体或脚本。

| 文件 | 对应截图 |
| --- | --- |
| `creation.png` | 创作页、结果预览与导航 |
| `inpaint-workspace.png` | 圆形遮罩与局部重绘工作区 |
| `brush-settings.png` | 笔刷形状与大小 |
| `workspace-settings.png` | 展开的工作区菜单 |
| `prompt-notebook.png` | 笔记本、搜索与条目操作 |
| `prompt-actions.png` | 正向提示词标题快捷入口 |

## 重新生成

在仓库根目录执行。Windows 上可通过 `FRONTEND_QA_FONT` 指向本机支持中文的字体文件；字体只用于本机渲染，不提交字体文件。

```powershell
$env:FRONTEND_QA_FONT='C:\Windows\Fonts\msyh.ttc'
flutter test --no-pub test/mobile_creation_layout_test.dart --plain-name 'capture actual Flutter creation widgets' --dart-define=FRONTEND_CAPTURE=true
flutter test --no-pub test/presentation/pages/inpaint_workspace_page_test.dart --plain-name 'capture rendered inpaint workspace for mobile visual QA' --dart-define=FRONTEND_CAPTURE=true
flutter test --no-pub test/presentation/widgets/prompt_notebook_dialog_test.dart --plain-name 'capture notebook and prompt actions for mobile visual QA' --dart-define=FRONTEND_CAPTURE=true
```

输出位于 `build/frontend-preview/`。人工检查截图后，按上表选择对应图片复制到此目录；保持源截图内容，不使用账号资料或私人照片。
