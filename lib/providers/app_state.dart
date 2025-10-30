import 'dart:async';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/prompt.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  AppState(this._storage);
  final StorageService _storage;

  String? selectedGroupId;
  String searchQuery = '';
  Timer? _searchDebounce;
  StreamSubscription? _groupWatchSub;
  StreamSubscription? _promptWatchSub;

  // 外观与密度设置
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = const Color(0xFF3B82F6); // 默认蓝色
  bool compactDensity = false; // 列表密度：false=舒适, true=紧凑

  // 排序与过滤
  PromptSortMode sortMode = PromptSortMode.sortOrder;
  bool showOnlyFavorites = false;
  String? tagFilter;

  List<Group> get rootGroups => _storage.getChildren(null);
  List<Group> childrenOf(String parentId) => _storage.getChildren(parentId);

  List<Prompt> get visiblePrompts {
    List<Prompt> list;
    if (searchQuery.trim().isNotEmpty) {
      list = _storage.search(searchQuery);
    } else if (selectedGroupId == null) {
      list = _storage.allPrompts;
    } else {
      list = _storage.collectPromptsUnderSorted(selectedGroupId!);
    }

    if (showOnlyFavorites) {
      list = list.where((p) => p.favorite).toList();
    }
    if ((tagFilter ?? '').trim().isNotEmpty) {
      final t = tagFilter!.trim();
      list = list.where((p) => p.tags.contains(t)).toList();
    }

    int cmpTitle(Prompt a, Prompt b) => a.title.compareTo(b.title);
    int cmpSortOrder(Prompt a, Prompt b) => a.sortOrder.compareTo(b.sortOrder);
    int cmpUpdatedDesc(Prompt a, Prompt b) {
      final au = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bu = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bu.compareTo(au);
    }

    list.sort((a, b) {
      switch (sortMode) {
        case PromptSortMode.updatedAtDesc:
          return cmpUpdatedDesc(a, b);
        case PromptSortMode.titleAsc:
          return cmpTitle(a, b);
        case PromptSortMode.pinnedFirst:
          final pinCmp = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
          if (pinCmp != 0) return pinCmp;
          return cmpSortOrder(a, b);
        case PromptSortMode.sortOrder:
          return cmpSortOrder(a, b);
      }
    });
    return list;
  }

  void bootstrap() {
    // 默认选中第一个根分组（如有）
    if (_storage.allGroups.isNotEmpty) {
      final roots = rootGroups;
      if (roots.isNotEmpty) {
        selectedGroupId = roots.first.id;
      } else {
        selectedGroupId = _storage.allGroups.first.id;
      }
    }

    // 监听存储层变化，自动刷新
    _groupWatchSub = _storage.groupEvents().listen((_) => notifyListeners());
    _promptWatchSub = _storage.promptEvents().listen((_) => notifyListeners());
  }

  void selectGroup(String groupId) {
    selectedGroupId = groupId;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    searchQuery = q;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      notifyListeners();
    });
  }

  // 外观控制
  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  void setSeedColor(Color color) {
    seedColor = color;
    notifyListeners();
  }

  void setCompactDensity(bool v) {
    compactDensity = v;
    notifyListeners();
  }

  void setSortMode(PromptSortMode m) {
    sortMode = m;
    notifyListeners();
  }

  void setShowOnlyFavorites(bool v) {
    showOnlyFavorites = v;
    notifyListeners();
  }

  void setTagFilter(String? tag) {
    tagFilter = (tag == null || tag.isEmpty) ? null : tag;
    notifyListeners();
  }

  // 手动刷新：当存储层有变化（编辑/移动/删除提示词或分组变更）时调用
  void refresh() {
    // 如果当前选中分组已被删除，尝试回退到第一个可用根分组
    if (selectedGroupId != null && _storage.getGroup(selectedGroupId!) == null) {
      final roots = rootGroups;
      selectedGroupId = roots.isNotEmpty ? roots.first.id : null;
    }
    // 依赖 watch 事件自动触发，仍保留显式刷新以应对选择变化
    notifyListeners();
  }

  String currentPathLabel() {
    if (selectedGroupId == null) return '';
    return _storage.buildPathLabel(selectedGroupId!);
  }

  // 统一反馈：成功/失败文案与时长
  void showSnack(
    BuildContext context,
    String message, {
    String? detail,
    bool error = false,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final cs = Theme.of(context).colorScheme;
    final bg = error ? cs.errorContainer.withOpacity(0.95) : cs.surface.withOpacity(0.95);
    final fg = error ? cs.onErrorContainer : cs.onSurface;
    messenger.showSnackBar(
      SnackBar(
        duration: duration ?? Duration(milliseconds: error ? 4000 : 2000),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: fg)),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail, style: TextStyle(color: fg.withOpacity(0.8))),
            ],
          ],
        ),
        backgroundColor: bg,
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _groupWatchSub?.cancel();
    _promptWatchSub?.cancel();
    super.dispose();
  }
}

enum PromptSortMode {
  sortOrder,
  updatedAtDesc,
  titleAsc,
  pinnedFirst,
}