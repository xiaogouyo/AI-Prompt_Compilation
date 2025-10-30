# AI Prompt Compilation (Flutter Windows 桌面应用)

用于高效存储、分类、检索和共享完整的 AI 绘图提示词（Prompt），支持最多五级嵌套分组、标签检索、导入导出 JSON、拖拽排序与层级调整。

## 快速开始

1. 安装 Flutter SDK 并启用 Windows 桌面：
   - 安装完成后执行：
     - `flutter doctor`
     - `flutter config --enable-windows-desktop`
2. 在项目根目录运行：
   - `flutter pub get`
   - `flutter run -d windows`

## 主要功能（MVP）

- 分组树（1-5级）：创建、重命名、删除分组，支持拖拽调整顺序与层级
- 左侧树形导航 + 顶部面包屑
- 右侧卡片列表展示提示词，支持折叠/展开与拖拽排序
- 全局检索（标题/内容/标签/分组名）
- 一键复制提示词内容
- 导入/导出 JSON（支持导出全库或当前分组子树）
- 本地存储（Hive）

## 目录结构

- `lib/models/` 数据模型（Group/Prompt）及 Hive 适配器
- `lib/services/` 存储与导入导出逻辑
- `lib/providers/` 应用状态管理
- `lib/widgets/` 组件（树导航、面包屑、卡片、搜索）
- `lib/pages/` 页面（HomePage）

## 说明

- 首次运行会初始化示例数据，便于快速预览功能。
- 已支持通过拖拽调整分组层级/顺序，以及在分组内拖拽排序提示词。