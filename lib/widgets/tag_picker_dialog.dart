import 'package:flutter/material.dart';

Future<List<String>?> showTagPickerDialog(
  BuildContext context, {
  required List<String> existingTags,
  List<String>? initialSelection,
}) async {
  final selected = <String>{...(initialSelection ?? [])};
  final tags = [...existingTags]..sort();
  // 确保已选择的标签也能在列表中显示（即便不在 existingTags 中）
  for (final t in selected) {
    if (!tags.contains(t)) {
      tags.add(t);
    }
  }
  tags.sort();
  final newTagCtl = TextEditingController();
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('选择标签'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newTagCtl,
                        decoration: const InputDecoration(labelText: '新标签名称'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final name = newTagCtl.text.trim();
                        if (name.isEmpty) return;
                        setState(() {
                          if (!tags.contains(name)) {
                            tags.add(name);
                            tags.sort();
                          }
                          selected.add(name);
                        });
                        newTagCtl.clear();
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in tags)
                          FilterChip(
                            label: Text(t),
                            selected: selected.contains(t),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  selected.add(t);
                                } else {
                                  selected.remove(t);
                                }
                              });
                            },
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
            TextButton(
              onPressed: () => setState(() => selected.clear()),
              child: const Text('清空'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, selected.toList()), child: const Text('确定')),
          ],
        );
      },
    ),
  );
}