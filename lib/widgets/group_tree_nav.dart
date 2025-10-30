// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/storage_service.dart';
import '../models/group.dart';
import '../models/prompt.dart';

class GroupTreeNav extends StatefulWidget {
  const GroupTreeNav({super.key});

  @override
  State<GroupTreeNav> createState() => _GroupTreeNavState();
}

class _GroupTreeNavState extends State<GroupTreeNav> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final storage = StorageService.instance;
    final roots = storage.getChildren(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '分组',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: '新建根分组',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () async {
                final name = await promptGroupName(context, '新建根分组');
                if (name != null && name.trim().isNotEmpty) {
                  await storage.createGroup(name.trim());
                  setState(() {});
                  app.showSnack(context, '已创建根分组');
                }
              },
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: roots.isEmpty
              ? _buildEmptyGroups(context, app)
              : ListView(
                  children: [
                    ..._buildTiles(null, app),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _buildTiles(String? parentId, AppState app) {
    final storage = StorageService.instance;
    final children = storage.getChildren(parentId);
    final items = <Widget>[];
    // 列表开头的唯一落点（插入到索引 0）
    items.add(_siblingGap(app, parentId, 0));
    for (int i = 0; i < children.length; i++) {
      final g = children[i];
      final hasChildren = storage.getChildren(g.id).isNotEmpty;
      final selected = app.selectedGroupId == g.id;
      final title = InkWell(
        onTap: () => app.selectGroup(g.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  g.name,
                  style: selected
                      ? Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold)
                      : Theme.of(context).textTheme.bodyMedium,
                ),
              ),
                IconButton(
                  tooltip: '重命名',
                  icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                onPressed: () async {
                  final name = await promptGroupName(context, '重命名分组');
                  if (name != null && name.trim().isNotEmpty) {
                    await storage.renameGroup(g.id, name.trim());
                    setState(() {});
                  }
                },
              ),
                IconButton(
                  tooltip: '合并到…',
                  icon: const Icon(Icons.merge_type, size: 18),
                  onPressed: () async {
                    String? selectedTargetId;
                    String mode = 'structure'; // 'structure' or 'content'
                    bool dedup = true;
                    bool removeSource = true;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        return StatefulBuilder(builder: (ctx, setState) {
                          return AlertDialog(
                            title: const Text('选择目标分组与合并模式'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('来源：${g.name}'),
                                  const SizedBox(height: 8),
                                  Text('目标分组：'),
                                  ..._buildParentOptions(context, null, selectedTargetId, (id) => setState(() => selectedTargetId = id)),
                                  const Divider(),
                                  RadioListTile<String>(
                                    title: const Text('结构合并（迁移子分组到目标）'),
                                    value: 'structure',
                                    groupValue: mode,
                                    onChanged: (v) => setState(() => mode = v ?? 'structure'),
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('内容合并（提示词合并到目标叶子）'),
                                    value: 'content',
                                    groupValue: mode,
                                    onChanged: (v) => setState(() => mode = v ?? 'content'),
                                  ),
                                  if (mode == 'content')
                                    CheckboxListTile(
                                      title: const Text('按标题+内容去重'),
                                      value: dedup,
                                      onChanged: (v) => setState(() => dedup = v ?? true),
                                    ),
                                  CheckboxListTile(
                                    title: const Text('完成后删除源分组'),
                                    value: removeSource,
                                    onChanged: (v) => setState(() => removeSource = v ?? true),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确定'),
                              ),
                            ],
                          );
                        });
                      },
                    );
                    if (ok == true && selectedTargetId != null && selectedTargetId != g.id) {
                      try {
                        if (mode == 'structure') {
                          await storage.mergeGroupStructure(g.id, selectedTargetId!, removeSource: removeSource);
                        } else {
                          final leafId = await storage.ensureLeafUnder(selectedTargetId!, defaultName: '未分类');
                          await storage.flattenPromptsUnderToLeaf(g.id, leafId, deduplicate: dedup);
                          if (removeSource) {
                            await storage.deleteGroupKeepChildren(g.id);
                          }
                        }
                        setState(() {});
                        app.selectGroup(selectedTargetId!);
                      } catch (e) {
                        app.showSnack(context, '合并失败', detail: e.toString(), error: true);
                      }
                    }
                  },
                ),
                IconButton(
                  tooltip: '移动到…',
                  icon: const Icon(Icons.drive_file_move, size: 18),
                onPressed: () async {
                  final newParentId = await _pickGroupParent(context);
                  if (newParentId == null) return;
                  try {
                    await storage.moveGroup(g.id, newParentId: newParentId == '__root__' ? null : newParentId);
                    setState(() {});
                  } catch (e) {
                    app.showSnack(context, '移动失败', detail: e.toString(), error: true);
                  }
                },
              ),
                IconButton(
                  tooltip: '删除分组',
                  icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final app = context.read<AppState>();
                  if (hasChildren) {
                    final ok = await _confirm(context, '确认删除该分组并保留其子分组，同时并入该组的提示词到父级叶子？');
                    if (ok == true) {
                      await storage.deleteGroupKeepChildren(g.id);
                      setState(() {});
                      app.refresh();
                    }
                  } else {
                    final ok = await _confirm(context, '确认删除该叶子分组及其提示词？');
                    if (ok == true) {
                      await storage.deleteGroup(g.id);
                      setState(() {});
                      app.refresh();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
      // 可拖拽的分组标题（长按触发）
      final draggableTitle = Draggable<Group>(
        data: g,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
            ),
            child: Text(g.name, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.6, child: title),
        child: title,
      );

      // 接受分组拖入（作为子分组）与提示词拖入（移动到该分组）
      Widget groupWidget;
      // 依赖 Hive 监听实现自动刷新，无需持有 AppState
      final baseWidget = hasChildren
          ? ExpansionTile(
              key: PageStorageKey(g.id),
              title: draggableTitle,
              children: _buildTiles(g.id, app),
            )
          : ListTile(title: draggableTitle, dense: true);

      groupWidget = DragTarget<Object>(
        builder: (ctx, candidates, rejects) {
          final hasCandidate = candidates.isNotEmpty;
          final hasReject = rejects.isNotEmpty;
          final candidateIsPrompt = candidates.any((e) => e is Prompt);
          final candidateIsGroup = candidates.any((e) => e is Group);
          final rejectIsPrompt = rejects.any((e) => e is Prompt);
          final borderColor = hasReject
              ? Colors.redAccent
              : (hasCandidate ? Colors.blueAccent : Colors.transparent);
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: baseWidget,
              ),
              if (candidateIsGroup)
                Positioned(
                  right: 12,
                  top: 6,
                  child: _hintBadge(
                    context,
                    '成为子分组',
                  ),
                ),
              if (candidateIsPrompt && !hasChildren)
                Positioned(
                  right: 12,
                  top: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.blueAccent),
                      const SizedBox(width: 4),
                      _hintBadge(context, '可投放到叶子'),
                    ],
                  ),
                ),
              if (rejectIsPrompt && hasChildren)
                Positioned(
                  right: 12,
                  top: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.block, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      _hintBadge(context, '不可投放'),
                    ],
                  ),
                ),
            ],
          );
        },
        onWillAcceptWithDetails: (details) {
          final data = details.data;
          if (data is Group) {
            // 不接受拖到自身
            return data.id != g.id;
          }
          // 仅允许提示词拖入叶子分组（提前校验，避免存储层抛错）
          if (data is Prompt) {
            return !hasChildren;
          }
          return false;
        },
        onAcceptWithDetails: (details) async {
          final data = details.data;
          try {
            if (data is Group) {
              // 若目标分组含有提示词，则先迁移到其子叶分组再放置为子分组
              final hasPrompts = storage.getPromptsInGroup(g.id).isNotEmpty;
              if (hasPrompts) {
                final proceed = await _confirm(context, '目标分组包含提示词，将其迁移到子叶分组后再进行操作，是否继续？');
                if (proceed != true) {
                  return;
                }
                final leafId = await storage.ensureLeafUnder(g.id, defaultName: '未分类');
                final prompts = storage.getPromptsInGroup(g.id);
                for (final p in prompts) {
                  await storage.movePrompt(p.id, leafId);
                }
              }
              await storage.moveGroup(data.id, newParentId: g.id);
              // 自动选中被移动的分组，便于查看其提示词与子分组
              app.selectGroup(data.id);
            } else if (data is Prompt) {
              final list = storage.getPromptsInGroup(g.id);
              await storage.reorderPromptToIndex(data.id, g.id, list.length);
            }
            setState(() {});
          } catch (e) {
            app.showSnack(context, '拖拽失败', detail: e.toString(), error: true);
          }
        },
      );

      // 旧的 gap 定义已移除，改为唯一插入点 _siblingGap()

      // 追加分组项与其后唯一落点（插入到索引 i+1）
      items.add(groupWidget);
      items.add(_siblingGap(app, parentId, i + 1));
    }
    return items;
  }

  // 统一使用顶层 promptGroupName()

  Future<bool?> _confirm(BuildContext context, String msg) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<String?> _pickGroupParent(BuildContext context) async {
    String? selectedId;
    return showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('选择新父分组'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('根分组（无父级）'),
                    trailing: Icon(
                      selectedId == '__root__' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    ),
                    onTap: () => setState(() => selectedId = '__root__'),
                  ),
                  ..._buildParentOptions(ctx, null, selectedId, (v) => setState(() => selectedId = v)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, selectedId), child: const Text('确定')),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildParentOptions(BuildContext context, String? parentId, String? selectedId, void Function(String?) setSelected) {
    final storage = StorageService.instance;
    final children = storage.getChildren(parentId);
    return children.map((g) {
      final kids = storage.getChildren(g.id);
      final titleTile = ListTile(
        title: Text(g.name),
        trailing: Icon(selectedId == g.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        onTap: () => setSelected(g.id),
        dense: true,
      );
      if (kids.isEmpty) {
        return titleTile;
      }
      return ExpansionTile(
        key: PageStorageKey('picker_${g.id}'),
        title: titleTile,
        children: _buildParentOptions(context, g.id, selectedId, setSelected),
      );
    }).toList();
  }

  // 同级内的唯一插入落点（根据 insertIndex 定位目标位置）
  Widget _siblingGap(AppState app, String? parentId, int insertIndex) {
    final storage = StorageService.instance;
    return DragTarget<Group>(
      builder: (ctx, candidates, rejects) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: active ? 24 : 10,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.blueAccent.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? Colors.blueAccent : Colors.transparent),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.18),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: active
              ? Center(
                  child: _hintBadge(
                    context,
                    '插入到此处',
                  ),
                )
              : null,
        );
      },
      onWillAcceptWithDetails: (details) {
        // DragTarget<Group> 已限定类型为 Group，这里直接接受以进入排序逻辑
        return true;
      },
      onAcceptWithDetails: (details) async {
        final data = details.data;
        try {
          // 如跨父级，先迁移到当前父级
          if (data.parentId != parentId) {
            await storage.moveGroup(data.id, newParentId: parentId);
          }
          await storage.reorderSiblingToIndex(data.id, insertIndex);
          // 自动选中被移动的分组，便于查看其提示词与子分组
          app.selectGroup(data.id);
          setState(() {});
        } catch (e) {
          app.showSnack(context, '排序失败', detail: e.toString(), error: true);
        }
      },
    );
  }

  Widget _hintBadge(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.blueAccent),
      ),
    );
  }
}

Widget _buildEmptyGroups(BuildContext context, AppState app) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text('暂无分组', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('创建一个根分组开始组织提示词', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            final storage = StorageService.instance;
            final name = await promptGroupName(context, '新建根分组');
            if (name != null && name.trim().isNotEmpty) {
              await storage.createGroup(name.trim());
              app.showSnack(context, '已创建根分组');
            }
          },
          child: const Text('创建分组'),
        ),
      ],
    ),
  );
}

Future<String?> promptGroupName(BuildContext context, String title) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: '输入分组名称'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确定')),
      ],
    ),
  );
}