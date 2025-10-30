// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// import removed: implicitly_animated_reorderable_list

import '../providers/app_state.dart';
import '../services/storage_service.dart';
import '../models/prompt.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/group_tree_nav.dart';
import '../widgets/prompt_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/tag_picker_dialog.dart';

class SearchFocusIntent extends Intent {
  const SearchFocusIntent();
}

class ManualSaveIntent extends Intent {
  const ManualSaveIntent();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appWatch = context.watch<AppState>();
    // 使用 Shortcuts + Actions 基于 LogicalKeySet 的绑定，提升兼容性
    final LogicalKeySet? searchKeySet = (() {
      final s = appWatch.searchFocusShortcut.trim().toLowerCase();
      if (s.isEmpty || s == 'none') return null;
      final base = LogicalKeyboardKey.keyK;
      if (s == 'ctrl+shift+k' || s == 'control+shift+k') {
        return LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, base);
      }
      if (s == 'ctrl+alt+k' || s == 'control+alt+k') {
        return LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.alt, base);
      }
      return LogicalKeySet(LogicalKeyboardKey.control, base);
    })();
    final LogicalKeySet? manualKeySet = appWatch.buildManualSaveKeySet();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // 调试：记录按键事件，便于定位桌面端快捷键问题
        if (event is KeyDownEvent) {
          debugPrint('KeyDown: ' + (event.logicalKey.debugName ?? event.logicalKey.keyLabel ?? 'unknown'));
          // 兜底：在桌面端直接用硬件键盘状态匹配组合键，避免 Shortcuts 未命中的情况
          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          final isAlt = HardwareKeyboard.instance.isAltPressed;
          // 搜索快捷键匹配
          final s = appWatch.searchFocusShortcut.trim().toLowerCase();
          bool searchMatch = false;
          if (s.isNotEmpty && s != 'none') {
            if (event.logicalKey == LogicalKeyboardKey.keyK) {
              if ((s == 'ctrl+k' || s == 'control+k') && isCtrl && !isShift && !isAlt) searchMatch = true;
              if ((s == 'ctrl+shift+k' || s == 'control+shift+k') && isCtrl && isShift && !isAlt) searchMatch = true;
              if ((s == 'ctrl+alt+k' || s == 'control+alt+k') && isCtrl && !isShift && isAlt) searchMatch = true;
            }
          }
          if (searchMatch) {
            debugPrint('Shortcut matched: search focus');
            FocusScope.of(context).requestFocus(_searchFocusNode);
            appWatch.showSnack(context, '已聚焦到搜索框');
            return KeyEventResult.handled;
          }
          // 手动保存快捷键匹配
          final m = appWatch.manualSaveShortcut.trim().toLowerCase();
          bool manualMatch = false;
          if (m.isNotEmpty && m != 'none') {
            if (event.logicalKey == LogicalKeyboardKey.keyS) {
              if ((m == 'ctrl+s' || m == 'control+s') && isCtrl && !isShift && !isAlt) manualMatch = true;
              if ((m == 'ctrl+shift+s' || m == 'control+shift+s') && isCtrl && isShift && !isAlt) manualMatch = true;
              if ((m == 'ctrl+alt+s' || m == 'control+alt+s') && isCtrl && !isShift && isAlt) manualMatch = true;
            }
          }
          if (manualMatch) {
            debugPrint('Shortcut matched: manual save');
            appWatch.triggerManualSave(context);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          if (searchKeySet != null) searchKeySet: const SearchFocusIntent(),
          if (manualKeySet != null) manualKeySet: const ManualSaveIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            SearchFocusIntent: CallbackAction<SearchFocusIntent>(
              onInvoke: (intent) {
                FocusScope.of(context).requestFocus(_searchFocusNode);
                return null;
              },
            ),
            ManualSaveIntent: CallbackAction<ManualSaveIntent>(
              onInvoke: (intent) {
                appWatch.triggerManualSave(context);
                return null;
              },
            ),
          },
          child: Scaffold(
      appBar: AppBar(
        title: const Text('AI Prompt Compilation'),
        actions: [
          // 外观设置：主题与密度
          IconButton(
            tooltip: '主题与外观',
            icon: const Icon(Icons.tune),
            onPressed: () => _showAppearanceSheet(context),
          ),
          IconButton(
            tooltip: '导入 JSON',
            icon: const Icon(Icons.file_open),
            onPressed: () async {
              final app = context.read<AppState>();
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                final file = result?.files.single;
                if (file != null && file.path != null) {
                  final text = await File(file.path!).readAsString();
                  final data = json.decode(text) as Map<String, dynamic>;
                  final progressValue = ValueNotifier<double?>(0.0);
                  final progressText = ValueNotifier<String>('正在导入…');
                  // 显示导入进度弹窗
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: const Text('导入中'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ValueListenableBuilder<String>(
                            valueListenable: progressText,
                            builder: (ctx, text, _) => Text(text),
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<double?>(
                            valueListenable: progressValue,
                            builder: (ctx, v, _) => LinearProgressIndicator(value: v),
                          ),
                        ],
                      ),
                    ),
                  );
                  await StorageService.instance.importJson(
                    data,
                    mergeDuplicates: true,
                    onProgress: (cur, total) {
                      if (total <= 0) {
                        progressValue.value = null; // 不确定总量，采用不定进度
                        progressText.value = '正在导入…';
                      } else {
                        progressValue.value = cur / total;
                        progressText.value = '已导入 $cur / $total';
                      }
                    },
                  );
                  // 关闭进度弹窗
                  Navigator.of(context, rootNavigator: true).pop();
                  app.showSnack(context, '导入成功', detail: file.name);
                }
              } catch (e) {
                final msg = e is FormatException ? '文件格式错误或 JSON 语法异常' : e.toString();
                context.read<AppState>().showSnack(
                  context,
                  '导入失败',
                  detail: '$msg（可在 README 查看示例 JSON 模板）',
                  error: true,
                );
              }
            },
          ),
          IconButton(
            tooltip: '导出 JSON（整个库或当前分组）',
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              final app = context.read<AppState>();
              if (kIsWeb) {
                // Web 端：无法直接写入目录，改为复制 JSON 到剪贴板
                final data = StorageService.instance.exportJson(rootGroupId: app.selectedGroupId);
                final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
                await Clipboard.setData(ClipboardData(text: jsonStr));
                app.showSnack(context, '已复制 JSON 到剪贴板', detail: '请粘贴保存为 ai_prompt_export.json');
                return;
              }
              final dirPath = await FilePicker.platform.getDirectoryPath();
              if (dirPath == null) return;
              final file = await StorageService.instance.saveExportJsonToDirectory(
                dirPath,
                rootGroupId: app.selectedGroupId,
              );
              app.showSnack(context, '已导出', detail: file.path);
            },
          ),
          IconButton(
            tooltip: '自动保存设置',
            icon: const Icon(Icons.settings),
            onPressed: () => _showAutoSaveSettingsDialog(context),
          ),
          IconButton(
            tooltip: '查看历史保存记录',
            icon: const Icon(Icons.history),
            onPressed: () => _showAutoSaveHistoryDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          const SizedBox(
            width: 280,
            child: GroupTreeNav(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: BreadcrumbBar()),
                      const SizedBox(width: 12),
                      SizedBox(width: 360, child: GlobalSearchBar(focusNode: _searchFocusNode)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Consumer<AppState>(
                    builder: (context, app, _) {
                      final storage = StorageService.instance;
                      final allTags = storage.allPrompts
                          .expand((p) => p.tags)
                          .where((t) => t.trim().isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();
                      String sortLabel(PromptSortMode m) {
                        switch (m) {
                          case PromptSortMode.updatedAtDesc:
                            return '按更新时间（新→旧）';
                          case PromptSortMode.titleAsc:
                            return '按标题（A→Z）';
                          case PromptSortMode.pinnedFirst:
                            return '置顶优先（保持分组内顺序）';
                          case PromptSortMode.sortOrder:
                            return '按手动排序（分组内顺序）';
                        }
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('排序：'),
                              const SizedBox(width: 6),
                              DropdownButton<PromptSortMode>(
                                value: app.sortMode,
                                items: PromptSortMode.values
                                    .map((m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(sortLabel(m)),
                                        ))
                                    .toList(),
                                onChanged: (m) => m != null ? app.setSortMode(m) : null,
                              ),
                            ],
                          ),
                          FilterChip(
                            label: const Text('只看收藏'),
                            selected: app.showOnlyFavorites,
                            onSelected: (v) => app.setShowOnlyFavorites(v),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('标签：'),
                              const SizedBox(width: 6),
                              DropdownButton<String>(
                                value: (app.tagFilter != null && allTags.contains(app.tagFilter)) ? app.tagFilter : null,
                                hint: const Text('按标签过滤'),
                                items: allTags
                                    .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                                    .toList(),
                                onChanged: (v) => app.setTagFilter(v),
                              ),
                              if (app.tagFilter != null)
                                TextButton(onPressed: () => app.setTagFilter(null), child: const Text('清除')),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: Consumer<AppState>(
                      builder: (context, app, _) {
                        final storage = StorageService.instance;
                        final searching = app.searchQuery.trim().isNotEmpty;
                        final groupId = app.selectedGroupId;
                        final hasChildren = !searching && groupId != null && storage.getChildren(groupId).isNotEmpty;
                        if (hasChildren) {
                          return _buildChildGroups(context, app);
                        }
                        final prompts = app.visiblePrompts;
                        if (prompts.isEmpty) {
                          return _buildEmptyPrompts(context, app);
                        }
                        return ListView.builder(
                          itemCount: prompts.length,
                          itemBuilder: (context, index) {
                            final p = prompts[index];
                            final storage = StorageService.instance;
                            final app = context.read<AppState>();

                            Widget gap(bool before) {
                              return DragTarget<Prompt>(
                                builder: (ctx, candidates, rejects) {
                                  final active = candidates.isNotEmpty;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    height: active ? 10 : 6,
                                    margin: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: active ? Colors.blueAccent.withOpacity(0.18) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: active
                                          ? [
                                              BoxShadow(
                                                color: Colors.blueAccent.withOpacity(0.18),
                                                blurRadius: 6,
                                                spreadRadius: 0.5,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                  );
                                },
                                onWillAcceptWithDetails: (details) {
                                  final data = details.data;
                                  return data.id != p.id;
                                },
                                onAcceptWithDetails: (details) async {
                                  final data = details.data;
                                  try {
                                    final groupId = p.groupId;
                                    final list = storage.getPromptsInGroup(groupId);
                                    final targetIdx = list.indexWhere((x) => x.id == p.id);
                                    final newIndex = before ? targetIdx : targetIdx + 1;
                                    await storage.reorderPromptToIndex(data.id, groupId, newIndex);
                                  } catch (e) {
                                    app.showSnack(context, '排序失败', detail: e.toString(), error: true);
                                  }
                                },
                              );
                            }

                            return Column(
                              children: [
                                gap(true),
                                Draggable<Prompt>(
                                  data: p,
                                  dragAnchorStrategy: pointerDragAnchorStrategy,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 480),
                                      child: Card(
                                        elevation: 0,
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(p.title, style: Theme.of(context).textTheme.titleMedium),
                                        ),
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(opacity: 0.7, child: PromptCard(prompt: p)),
                                  child: PromptCard(prompt: p),
                                ),
                                gap(false),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      
      floatingActionButton: (() {
        final app = context.watch<AppState>();
        final gid = app.selectedGroupId;
        final storage = StorageService.instance;
        final isEmptyLeaf = gid != null && storage.getChildren(gid).isEmpty && storage.getPromptsInGroup(gid).isEmpty;
        if (isEmptyLeaf) return null;
        return FloatingActionButton.extended(
          onPressed: () async {
            final groupId = app.selectedGroupId;
            if (groupId == null) return;
            final hasChildren = storage.getChildren(groupId).isNotEmpty;
            if (hasChildren) {
              app.showSnack(context, '请在叶子分组下新增提示词', error: true);
              return;
            }
            final ok = await _showCreatePromptDialog(context);
            if (ok == true) {
              app.showSnack(context, '已新增提示词');
            }
          },
          label: const Text('新增提示词'),
          icon: const Icon(Icons.add),
        );
      })(),
          ),
        ),
      ),
    );
  }

  Future<void> _showAutoSaveSettingsDialog(BuildContext context) async {
    final app = context.read<AppState>();
    final isWeb = kIsWeb;
    final intervalController = TextEditingController(text: app.autoSaveIntervalMinutes.toString());
    final retainController = TextEditingController(text: app.autoSaveRetainCount.toString());
    await showDialog(
      context: context,
      builder: (ctx) {
        final appWatch = ctx.watch<AppState>();
        final dirPath = appWatch.autoSaveDirPath ?? '';
        return AlertDialog(
          title: const Text('自动保存设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('启用自动保存')),
                    Switch(
                      value: appWatch.autoSaveEnabled && !isWeb,
                      onChanged: isWeb
                          ? null
                          : (v) {
                              ctx.read<AppState>().setAutoSaveEnabled(v);
                            },
                    ),
                  ],
                ),
                if (isWeb)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text('Web 端不支持保存到本地目录。'),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '自动保存频率（分钟）',
                    hintText: '例如：10',
                  ),
                  onSubmitted: (v) {
                    final m = int.tryParse(v) ?? appWatch.autoSaveIntervalMinutes;
                    ctx.read<AppState>().setAutoSaveIntervalMinutes(m);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: retainController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '历史留存数量',
                    hintText: '例如：20',
                  ),
                  onSubmitted: (v) {
                    final n = int.tryParse(v) ?? appWatch.autoSaveRetainCount;
                    ctx.read<AppState>().setAutoSaveRetainCount(n);
                  },
                ),
                const SizedBox(height: 8),
                if (!isWeb)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '保存目录：${dirPath.isEmpty ? '（未设置，将使用默认）' : dirPath}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final newDir = await FilePicker.platform.getDirectoryPath();
                              if (newDir != null) {
                                await ctx.read<AppState>().setAutoSaveDirPath(newDir);
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                            label: const Text('选择目录'),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text('快捷键设置', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('手动保存快捷键')),
                    DropdownButton<String>(
                      value: appWatch.manualSaveShortcut,
                      items: const [
                        DropdownMenuItem(value: 'Ctrl+S', child: Text('Ctrl+S')),
                        DropdownMenuItem(value: 'Ctrl+Shift+S', child: Text('Ctrl+Shift+S')),
                        DropdownMenuItem(value: 'Ctrl+Alt+S', child: Text('Ctrl+Alt+S')),
                        DropdownMenuItem(value: 'None', child: Text('禁用')),
                      ],
                      onChanged: (v) async {
                        if (v != null) {
                          await ctx.read<AppState>().setManualSaveShortcut(v);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('搜索框快捷键')),
                    DropdownButton<String>(
                      value: appWatch.searchFocusShortcut,
                      items: const [
                        DropdownMenuItem(value: 'Ctrl+K', child: Text('Ctrl+K')),
                        DropdownMenuItem(value: 'Ctrl+Shift+K', child: Text('Ctrl+Shift+K')),
                        DropdownMenuItem(value: 'Ctrl+Alt+K', child: Text('Ctrl+Alt+K')),
                        DropdownMenuItem(value: 'None', child: Text('禁用')),
                      ],
                      onChanged: (v) async {
                        if (v != null) {
                          await ctx.read<AppState>().setSearchFocusShortcut(v);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAutoSaveHistoryDialog(BuildContext context) async {
    final app = context.read<AppState>();
    if (kIsWeb) {
      app.showSnack(context, 'Web 端不支持本地历史记录', error: true);
      return;
    }
    final list = await StorageService.instance.listAutoSaveHistory();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('历史保存记录'),
        content: SizedBox(
          width: 560,
          child: list.isEmpty
              ? const Text('暂无自动保存记录')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = list[i];
                    final path = item['path'] as String;
                    final modified = item['modified'] as DateTime;
                    final size = item['size'] as int;
                    return ListTile(
                      dense: true,
                      title: Text('${modified.toString().replaceFirst('T', ' ').split('.').first}'),
                      subtitle: Text('$path\n${(size / 1024).toStringAsFixed(1)} KB'),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              try {
                                final text = await File(path).readAsString();
                                final data = json.decode(text) as Map<String, dynamic>;
                                final progressValue = ValueNotifier<double?>(0.0);
                                final progressText = ValueNotifier<String>('正在导入…');
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('导入中'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ValueListenableBuilder<String>(
                                          valueListenable: progressText,
                                          builder: (ctx, text, _) => Text(text),
                                        ),
                                        const SizedBox(height: 12),
                                        ValueListenableBuilder<double?>(
                                          valueListenable: progressValue,
                                          builder: (ctx, v, _) => LinearProgressIndicator(value: v),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                await StorageService.instance.importJson(
                                  data,
                                  mergeDuplicates: true,
                                  onProgress: (cur, total) {
                                    if (total <= 0) {
                                      progressValue.value = null;
                                      progressText.value = '正在导入…';
                                    } else {
                                      progressValue.value = cur / total;
                                      progressText.value = '已导入 $cur / $total';
                                    }
                                  },
                                );
                                Navigator.of(context, rootNavigator: true).pop();
                                app.showSnack(context, '导入成功', detail: path);
                              } catch (e) {
                                Navigator.of(context, rootNavigator: true).pop();
                                app.showSnack(context, '导入失败', detail: e.toString(), error: true);
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: const Text('导入'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              try {
                                await File(path).delete();
                                Navigator.pop(context);
                                _showAutoSaveHistoryDialog(context); // 重新打开刷新
                              } catch (e) {
                                app.showSnack(context, '删除失败', detail: e.toString(), error: true);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('删除'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: path));
                              app.showSnack(context, '已复制路径', detail: path);
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('复制路径'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

}


Future<bool?> _showCreatePromptDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final groupId = app.selectedGroupId!;
  final titleCtl = TextEditingController();
  final contentCtl = TextEditingController();
  final descCtl = TextEditingController();
  final storage = StorageService.instance;
  final allTags = storage.allPrompts
      .expand((p) => p.tags)
      .where((t) => t.trim().isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final selectedTags = <String>[];
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            return CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(ctx, false),
                const SingleActivator(LogicalKeyboardKey.enter): () async {
                  final title = titleCtl.text.trim();
                  final content = contentCtl.text.trim();
                  final desc = descCtl.text.trim().isEmpty ? null : descCtl.text.trim();
                  if (title.isEmpty || content.isEmpty) return;
                  await StorageService.instance.createPrompt(
                    title: title,
                    content: content,
                    tags: selectedTags,
                    description: desc,
                    groupId: groupId,
                  );
                  // Enter 保存同样触发刷新，确保标签下拉与选择器立即包含新标签
                  if (ctx.mounted) {
                    try {
                      ctx.read<AppState>().refresh();
                    } catch (_) {}
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
              },
              child: AlertDialog(
            title: const Text('新增提示词'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: titleCtl, decoration: const InputDecoration(labelText: '标题')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contentCtl,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: '提示词内容（支持多行）'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('标签：'),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('选择标签'),
                          onPressed: () async {
                            // 打开前重新获取最新标签集合，避免使用对话框创建时捕获的旧列表
                            final latestTags = storage.allPrompts
                                .expand((p) => p.tags)
                                .where((t) => t.trim().isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort();
                            final chosen = await showTagPickerDialog(
                              ctx,
                              existingTags: latestTags,
                              initialSelection: selectedTags,
                            );
                            if (chosen != null) {
                              setState(() {
                                selectedTags
                                  ..clear()
                                  ..addAll(chosen);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in selectedTags)
                          Chip(
                            label: Text(t),
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.22),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: descCtl, decoration: const InputDecoration(labelText: '介绍/备注（可选）')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              ElevatedButton(
                onPressed: () async {
                  final title = titleCtl.text.trim();
                  final content = contentCtl.text.trim();
                  final desc = descCtl.text.trim().isEmpty ? null : descCtl.text.trim();
                  if (title.isEmpty || content.isEmpty) return;
                  await StorageService.instance.createPrompt(
                    title: title,
                    content: content,
                    tags: selectedTags,
                    description: desc,
                    groupId: groupId,
                  );
                  // 保存后刷新：确保全局标签列表包含新标签
                  if (ctx.mounted) {
                    try {
                      ctx.read<AppState>().refresh();
                    } catch (_) {}
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// 空态视图：根据搜索状态/分组选择显示不同引导
Widget _buildEmptyPrompts(BuildContext context, AppState app) {
  final searching = app.searchQuery.trim().isNotEmpty;
  final icon = searching ? Icons.search_off : Icons.inbox_outlined;
  final title = searching ? '未找到匹配结果' : '当前分组暂无提示词';
  final hint = searching ? '试试调整搜索条件（比如减少筛选前缀）' : '在叶子分组下新增提示词以便管理';
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (searching)
          OutlinedButton(
            onPressed: () => app.setSearchQuery(''),
            child: const Text('清空搜索'),
          )
        else
          ElevatedButton(
            onPressed: () async {
              final groupId = app.selectedGroupId;
              if (groupId == null) return;
              final storage = StorageService.instance;
              final hasChildren = storage.getChildren(groupId).isNotEmpty;
              if (hasChildren) {
                app.showSnack(context, '请在叶子分组下新增提示词', error: true);
                return;
              }
              final ok = await _showCreatePromptDialog(context);
              if (ok == true) app.showSnack(context, '已新增提示词');
            },
            child: const Text('新增提示词'),
          ),
      ],
    ),
  );
}

// 非叶子分组的浏览：显示子分组列表以逐级浏览
Widget _buildChildGroups(BuildContext context, AppState app) {
  final storage = StorageService.instance;
  final groupId = app.selectedGroupId;
  if (groupId == null) {
    return const Center(child: Text('未选择分组'));
  }
  final children = storage.getChildren(groupId);
  if (children.isEmpty) {
    return _buildEmptyPrompts(context, app);
  }
  return ListView.separated(
    itemCount: children.length,
    separatorBuilder: (ctx, i) => const Divider(height: 1),
    itemBuilder: (ctx, i) {
      final g = children[i];
      final subCount = storage.getChildren(g.id).length;
      final promptCount = storage.getPromptsInGroup(g.id).length;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(g.name),
          subtitle: Text('子分组 $subCount • 提示词 $promptCount'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => app.selectGroup(g.id),
        ),
      );
    },
  );
}

// 外观设置底部弹窗：主题模式、主题色、列表密度
void _showAppearanceSheet(BuildContext context) {
  final app = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final seedOptions = <Color>[
        const Color(0xFF3B82F6), // 蓝
        const Color(0xFF22C55E), // 绿
        const Color(0xFFEF4444), // 红
        const Color(0xFFF59E0B), // 橙
        const Color(0xFFA855F7), // 紫
      ];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('主题与外观', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('跟随系统'),
                  selected: app.themeMode == ThemeMode.system,
                  onSelected: (_) => app.setThemeMode(ThemeMode.system),
                ),
                ChoiceChip(
                  label: const Text('浅色'),
                  selected: app.themeMode == ThemeMode.light,
                  onSelected: (_) => app.setThemeMode(ThemeMode.light),
                ),
                ChoiceChip(
                  label: const Text('深色'),
                  selected: app.themeMode == ThemeMode.dark,
                  onSelected: (_) => app.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('主题色', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in seedOptions)
                  GestureDetector(
                    onTap: () => app.setSeedColor(c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: app.seedColor == c
                              ? Theme.of(ctx).colorScheme.onPrimary
                              : Colors.white.withOpacity(0.8),
                          width: app.seedColor == c ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('紧凑列表密度'),
              value: app.compactDensity,
              onChanged: app.setCompactDensity,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      );
    },
  );
}