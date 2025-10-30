import 'package:flutter/material.dart';
import '../utils/query_parser.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/prompt.dart';
import '../services/storage_service.dart';
import '../providers/app_state.dart';
import '../widgets/tag_picker_dialog.dart';

class PromptCard extends StatefulWidget {
  const PromptCard({super.key, required this.prompt});
  final Prompt prompt;

  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.prompt;
    final pathLabel = StorageService.instance.buildPathLabel(p.groupId);
    final app = context.watch<AppState>();
    final query = app.searchQuery;
    final parts = parseQuery(query);
    final preview = _firstLines(p.content, lines: expanded ? 999 : (app.compactDensity ? 2 : 3));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Padding(
        padding: EdgeInsets.all(app.compactDensity ? 10.0 : 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题区（与操作区分层）
            RichText(
              text: _buildHighlightedSpan(
                p.title,
                [...parts['title']!, ...parts['general']!],
                Theme.of(context).textTheme.titleMedium,
                Theme.of(context).textTheme.titleMedium?.copyWith(
                  backgroundColor: Colors.yellow.withOpacity(0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText.rich(
              _buildHighlightedSpan(
                preview,
                [...parts['content']!, ...parts['general']!],
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: app.compactDensity ? 1.25 : 1.4,
                ),
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: app.compactDensity ? 1.25 : 1.4,
                  backgroundColor: Colors.yellow.withOpacity(0.3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in p.tags)
                  Chip(
                    label: RichText(
                      text: _buildHighlightedSpan(
                        t,
                        [...parts['tag']!, ...parts['general']!],
                        Theme.of(context).textTheme.labelSmall,
                        Theme.of(context).textTheme.labelSmall?.copyWith(backgroundColor: Colors.yellow.withOpacity(0.3)),
                      ),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.22),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 底部：路径标签与操作区分层
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: '分组路径：'),
                        _buildHighlightedSpan(
                          pathLabel,
                          [...parts['path']!, ...parts['general']!],
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            backgroundColor: Colors.yellow.withOpacity(0.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '复制完整提示词',
                  icon: const Icon(Icons.copy_all),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.content));
                    if (context.mounted) {
                      app.showSnack(context, '提示词内容已复制');
                    }
                  },
                ),
                    IconButton(
                      tooltip: p.pinned ? '取消置顶' : '置顶',
                      icon: Icon(p.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      onPressed: () async {
                        await StorageService.instance.togglePinned(p.id, !p.pinned);
                        if (context.mounted) setState(() {});
                      },
                    ),
                IconButton(
                  tooltip: p.favorite ? '取消收藏' : '收藏',
                  icon: Icon(p.favorite ? Icons.star : Icons.star_border),
                  onPressed: () async {
                    await StorageService.instance.toggleFavorite(p.id, !p.favorite);
                    if (context.mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: expanded ? '折叠' : '展开全文',
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => expanded = !expanded),
                ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final ok = await _showEditPromptDialog(context, p);
                        if (ok == true && context.mounted) {
                          app.showSnack(context, '已更新提示词');
                        }
                      },
                    ),
                    IconButton(
                      tooltip: '移动到…',
                      icon: const Icon(Icons.drive_file_move_outline),
                      onPressed: () async {
                        final newGroupId = await _pickLeafGroup(context);
                        if (newGroupId != null) {
                          try {
                            await StorageService.instance.movePrompt(p.id, newGroupId);
                            if (context.mounted) {
                              app.showSnack(context, '已移动提示词');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              app.showSnack(context, '移动失败', detail: e.toString(), error: true);
                            }
                          }
                        }
                      },
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: const Text('确认删除该提示词？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await StorageService.instance.deletePrompt(p.id);
                          if (context.mounted) {
                            app.showSnack(context, '已删除提示词');
                            setState(() {});
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _firstLines(String text, {int lines = 2}) {
    final parts = text.split('\n');
    if (parts.length <= lines || lines >= 999) return text;
    return '${parts.take(lines).join('\n')}\n...';
  }
}

  // 解析逻辑统一使用 utils/query_parser.dart 的 parseQuery

TextSpan _buildHighlightedSpan(String text, List<String> terms, TextStyle? base, TextStyle? highlight) {
  final children = <TextSpan>[];
  final lower = text.toLowerCase();
  final needles = terms.map((e) => e.toLowerCase()).where((e) => e.isNotEmpty).toSet().toList();
  int i = 0;
  while (i < text.length) {
    int matchIndex = -1;
    String? matched;
    for (final n in needles) {
      final idx = lower.indexOf(n, i);
      if (idx != -1 && (matchIndex == -1 || idx < matchIndex)) {
        matchIndex = idx;
        matched = n;
      }
    }
    if (matchIndex == -1 || matched == null) {
      children.add(TextSpan(text: text.substring(i), style: base));
      break;
    }
    if (matchIndex > i) {
      children.add(TextSpan(text: text.substring(i, matchIndex), style: base));
    }
    final end = matchIndex + matched.length;
    children.add(TextSpan(text: text.substring(matchIndex, end), style: highlight ?? base));
    i = end;
  }
  return TextSpan(children: children, style: base);
}

Future<bool?> _showEditPromptDialog(BuildContext context, Prompt p) async {
  final titleCtl = TextEditingController(text: p.title);
  final contentCtl = TextEditingController(text: p.content);
  final descCtl = TextEditingController(text: p.description ?? '');
  final storage = StorageService.instance;
  final allTags = storage.allPrompts
      .expand((x) => x.tags)
      .where((t) => t.trim().isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final selectedTags = p.tags.toList();
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('编辑提示词'),
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
                        // 打开前重新获取最新标签集合，避免在本对话框生命周期内出现过期数据
                        final latestTags = storage.allPrompts
                            .expand((x) => x.tags)
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
              final updated = p.copyWith(
                title: title,
                content: content,
                tags: selectedTags,
                description: desc,
                updatedAt: DateTime.now(),
              );
              await StorageService.instance.updatePrompt(updated);
              // 刷新整个页面的数据源（包括全局标签列表与筛选栏）
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
    ),
  );
}

Future<String?> _pickLeafGroup(BuildContext context) async {
  String? selectedId;
  return showDialog<String?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('选择叶子分组'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView(
            children: _buildGroupRadioTree(ctx, null, selectedId, (v) => setState(() => selectedId = v), onlyLeaf: true),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, selectedId), child: const Text('确定')),
        ],
      ),
    ),
  );
}

List<Widget> _buildGroupRadioTree(BuildContext context, String? parentId, String? selectedId, void Function(String?) setSelected,
    {bool onlyLeaf = false}) {
  final storage = StorageService.instance;
  final children = storage.getChildren(parentId);
  return children.map((g) {
    final kids = storage.getChildren(g.id);
    final leaf = kids.isEmpty;
    final titleTile = ListTile(
      title: Text(g.name),
      trailing: Icon(selectedId == g.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      onTap: () => setSelected(g.id),
      dense: true,
    );
    if (leaf || !onlyLeaf) {
      if (kids.isEmpty) return titleTile;
      return ExpansionTile(
        key: PageStorageKey('leaf_${g.id}'),
        title: titleTile,
        children: _buildGroupRadioTree(context, g.id, selectedId, setSelected, onlyLeaf: onlyLeaf),
      );
    } else {
      if (kids.isEmpty) return ListTile(title: Text(g.name), dense: true);
      return ExpansionTile(
        key: PageStorageKey('leaf_${g.id}'),
        title: Text(g.name),
        children: _buildGroupRadioTree(context, g.id, selectedId, setSelected, onlyLeaf: onlyLeaf),
      );
    }
  }).toList();
}