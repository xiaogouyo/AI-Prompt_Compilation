import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/storage_service.dart';
import '../models/group.dart';

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final selected = app.selectedGroupId;
    final storage = StorageService.instance;
    final List<Group> pathGroups = selected == null ? <Group>[] : storage.buildPathGroups(selected);

    final textStyle = Theme.of(context).textTheme.titleSmall;
    void copyPath() {
      final text = pathGroups.map((g) => g.name).join('/');
      Clipboard.setData(ClipboardData(text: text));
      app.showSnack(context, '已复制路径', detail: text);
    }

    return GestureDetector(
      onSecondaryTapDown: (details) {
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
          items: const [
            PopupMenuItem<String>(value: 'copy', child: Text('复制路径')),
          ],
        ).then((selected) {
          if (selected == 'copy') {
            copyPath();
          }
        });
      },
      child: Row(
        children: [
          if (pathGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('未选择分组', style: textStyle),
            )
          else if (pathGroups.length <= 4) ...[
            for (var i = 0; i < pathGroups.length; i++) ...[
              InkWell(
                onTap: () => app.selectGroup(pathGroups[i].id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(pathGroups[i].name, style: textStyle),
                ),
              ),
              if (i < pathGroups.length - 1) const Icon(Icons.chevron_right, size: 18),
            ]
          ] else ...[
            // 收缩：root / … / parent / current
            InkWell(
              onTap: () => app.selectGroup(pathGroups.first.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(pathGroups.first.name, style: textStyle),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
            PopupMenuButton<String>(
              tooltip: '展开中间路径',
              itemBuilder: (ctx) => [
                for (final g in pathGroups.sublist(1, pathGroups.length - 2))
                  PopupMenuItem<String>(value: g.id, child: Text(g.name)),
              ],
              onSelected: (id) => app.selectGroup(id),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('…'),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
            InkWell(
              onTap: () => app.selectGroup(pathGroups[pathGroups.length - 2].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(pathGroups[pathGroups.length - 2].name, style: textStyle),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
            InkWell(
              onTap: () => app.selectGroup(pathGroups.last.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(pathGroups.last.name, style: textStyle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}