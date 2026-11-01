# 提示词 Tag 补全

生成页、局部重绘、角色正负提示词及放大编辑器共用 `PromptTagField`。
界面读取现有主题颜色；候选英文名称为主，中文译文为辅，分类和热度弱化显示。
浮层锚定光标，最多约四行可见，剩余结果滚动查看；避开软键盘及安全区域。

## 使用

- 默认开启离线补全。英文输入两字符后查询，中文输入法提交汉字后查询。
- 点击候选，或用 ↑ / ↓ 和 Tab / Enter 选择。Esc 关闭，Shift + Enter 换行。
- 补全只替换当前 Tag，保留周围的括号、权重、换行和其他提示词，可撤销。
- 现有标签标记“已添加”并后置，不主动删除用户的重复词。
- 设置 → 素材与提示词 → 标签补全：控制补全、中文释义、自动逗号及在线补充。
- 在线补充默认关闭。开启后，仅当前查询词发送给现有 Danbooru 查词服务。
  当前完整标签的候选面板提供“相关”按钮；长按编辑器的菜单或 Ctrl + Shift + Space
  也可主动查询相关词。选择相关词会追加在源标签之后，保留源标签的权重。

## 完整词库

版本 `2026-11-01.1`：400,348 个 Tag、71,504 条别名、316,443 条非空中文译文。
完整保留所用 Danbooru/e621 基础快照及中文译库中的额外标签，不按热度裁剪。
“完整”指这些已固定版本的数据源，不表示实时包含站点上的所有标签。

`assets/tag_completion/catalog.db.gz` 约 40.5 MiB，安装后数据库约 102 MiB。
首次使用才在后台解压和校验 SHA-256；不会将整库读入 Dart 常驻内存。
SQLite B-tree 索引支持英文、别名及词内单词前缀；中文单字/双字索引配合原文过滤。
不依赖不同 Android 系统支持不一的 FTS5。单次取 48 条候选，查询覆盖完整词库。

版本更新随应用发布。先校验新资源，再启用新版本；安装失败继续使用原版本。
设置中的重试可重新解压词库。数据构建脚本、来源和许可证见
`scripts/build_tag_catalog.py` 与 `assets/tag_completion/NOTICE.md`。

## 实现与验证

- `PromptCompletionEdit`：定位、语法保护和插入；支持 `{}`、`[]`、`1.2::…::`、
  `(tag:1.2)`，保留角色名中的字面括号及颜文字。
- `TagCompletionCatalog`：只读数据库、版本化安装和校验回退。
- `TagCompletionService`：偏好持久化、小型查询缓存和可选在线补充。
- `PromptTagField`：输入法、焦点、浮层、键盘及异步请求生命周期。
- 在线请求带取消令牌，旧查询不能覆盖新文本或重新打开已关闭的浮层。

针对性测试：

```text
flutter test test/prompt_completion_edit_test.dart test/tag_completion_catalog_test.dart test/tag_completion_install_test.dart test/presentation/widgets/prompt_tag_field_test.dart
flutter test test/presentation/pages/inpaint_workspace_page_test.dart test/presentation/pages/generation_settings_page_test.dart test/presentation/pages/generation_preview_updates_test.dart test/prompt_text_test.dart
```

设置环境变量 `NAI_COMPLETION_SCREENSHOTS=1` 可在组件测试时输出浅/深色预览至
`build/frontend-preview/`。测试覆盖 390 px 手机宽度、键盘避让和双倍字体；
截图是组件渲染预览，真机输入法行为仍需设备验收。
