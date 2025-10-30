# AI Prompt Compilation

Flutter Windows 桌面与 Web 应用，用于高效存储、分类、检索和共享 AI 绘图提示词（Prompt）。支持最多五级嵌套分组、标签检索、导入导出 JSON、拖拽排序与层级调整，以及自动/手动保存快照与历史记录查看。

## 功能亮点

- 分组树（1–5级）：创建、重命名、删除，支持拖拽调整顺序与层级
- 面包屑导航：快速定位分组路径
- 提示词卡片：折叠/展开、拖拽排序、一键复制内容
- 全局检索：按标题/内容/标签/分组名组合查询
- 导入/导出：支持导出全库或当前分组子树的 JSON
- 自动/手动保存：快照文件合并展示，明确标注“自动/手动”
- 本地持久化：使用 Hive 进行数据存储

## 快捷键

- 搜索栏聚焦：桌面默认 `Ctrl+K`，Web 默认 `Ctrl+Shift+K`
- 手动保存快照：桌面默认 `Ctrl+S`，Web 默认 `Ctrl+Shift+S`
- 说明：应用使用 `SingleActivator` 捕获组合键；键盘事件基于当前焦点链分发，点击空白区域会恢复到根焦点以保证全局快捷键可用。

## 自动/手动保存与历史

- 自动保存开关与参数：
  - `autoSaveEnabled`：是否启用自动保存
  - `autoSaveIntervalMinutes`：自动保存间隔（分钟）
  - `autoSaveRetainCount`：自动保存保留条数（超出后自动清理最旧记录）
- 保存目录：
  - `autoSaveDirPath`：默认位于应用支持目录下的 `autosaves` 子目录（非 Web）
- 文件命名：
  - 自动：`ai_prompt_autosave_YYYYMMDD_hhmmss.json`
  - 手动：`ai_prompt_manual_YYYYMMDD_hhmmss.json`
- 历史记录弹窗：
  - 同时列出自动与手动快照，按修改时间倒序展示
  - 支持“导入”“删除”“复制路径”等操作

## 安装与运行

- 先安装 Flutter SDK 并启用 Windows 桌面：
  - `flutter doctor`
  - `flutter config --enable-windows-desktop`
- 拉取依赖并运行（桌面）：
  - `flutter pub get`
  - `flutter run -d windows`
- 运行（Web，本地预览）：
  - `flutter run -d web-server --web-port 8828`
  - 打开浏览器访问 `http://localhost:8828/`

## 打包与分发（Windows）

- Release 构建：`flutter build windows`
- 生成 MSIX 安装包（使用 `pubspec.yaml` 中的 `msix_config`）：
  - `flutter pub run msix:create`
- 也可使用 `installer/` 内的 Inno Setup / NSIS 脚本生成安装包
- 项目附带示例安装包：`dist/AI-Prompt-Compilation-Setup-1.0.1.exe`

## 目录结构

- `lib/models/` 数据模型（`Group`/`Prompt`）及 Hive 适配器
- `lib/services/` 存储、导入/导出、自动/手动快照与历史
- `lib/providers/` 应用状态（快捷键、设置等）
- `lib/widgets/` 组件（树导航、面包屑、提示词卡片、搜索栏）
- `lib/pages/` 页面（`HomePage`）
- `web/` PWA 资源（图标、清单、入口）

## 开发提示

- 快捷键在控件焦点变化后仍可用：空白区域点击会把焦点还给根节点，保证全局快捷键生效。
- 为保证桌面稳定性，避免在键盘事件处理期间弹出 `SnackBar` 等 UI 叠层。
- 单元测试：`flutter test`
- 依赖更新：如需升级依赖，建议先运行 `flutter pub outdated` 评估兼容性。

## 许可

当前项目未明确开源许可。如需分发或二次开发，请先与作者确认。