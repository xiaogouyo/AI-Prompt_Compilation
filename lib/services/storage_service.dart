import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/query_parser.dart';

import '../models/group.dart';
import '../models/prompt.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  late Box<Group> _groupBox;
  late Box<Prompt> _promptBox;
  late Box _settingsBox;
  int _opsSinceCompact = 0;
  DateTime _lastCompactAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 只读缓存：在分组结构变更时清空
  final Map<String?, List<Group>> _childrenCache = {};
  final Map<String, List<Group>> _pathGroupsCache = {};
  final Map<String, String> _pathLabelCache = {};

  Future<void> init() async {
    _groupBox = await Hive.openBox<Group>('groups');
    _promptBox = await Hive.openBox<Prompt>('prompts');
    _settingsBox = await Hive.openBox('settings');
    // 初始化默认设置
    _settingsBox.put('autoSaveEnabled', _settingsBox.get('autoSaveEnabled') ?? false);
    _settingsBox.put('autoSaveIntervalMinutes', _settingsBox.get('autoSaveIntervalMinutes') ?? 10);
    _settingsBox.put('autoSaveRetainCount', _settingsBox.get('autoSaveRetainCount') ?? 20);
    if (_settingsBox.get('manualSaveShortcut') == null) {
      _settingsBox.put('manualSaveShortcut', kIsWeb ? 'Ctrl+Shift+S' : 'Ctrl+S');
    }
    if (_settingsBox.get('searchFocusShortcut') == null) {
      _settingsBox.put('searchFocusShortcut', kIsWeb ? 'Ctrl+Shift+K' : 'Ctrl+K');
    }
    // 路径为空则使用默认路径（非 Web）
    if (!kIsWeb && _settingsBox.get('autoSaveDirPath') == null) {
      try {
        final def = await _defaultAutoSaveDirPath();
        _settingsBox.put('autoSaveDirPath', def);
      } catch (_) {}
    }
  }

  // 监听/可监听接口供 UI 使用
  Stream<BoxEvent> groupEvents() => _groupBox.watch();
  Stream<BoxEvent> promptEvents() => _promptBox.watch();
  ValueListenable<Box<Group>> groupListenable() => _groupBox.listenable();
  ValueListenable<Box<Prompt>> promptListenable() => _promptBox.listenable();

  void _invalidateCaches() {
    _childrenCache.clear();
    _pathGroupsCache.clear();
    _pathLabelCache.clear();
  }

  void _bumpOps() {
    _opsSinceCompact++;
    final now = DateTime.now();
    if (_opsSinceCompact >= 50 || now.difference(_lastCompactAt).inMinutes >= 10) {
      _opsSinceCompact = 0;
      _lastCompactAt = now;
      // 异步压缩以避免阻塞 UI
      Future(() async {
        try {
          await _groupBox.compact();
          await _promptBox.compact();
        } catch (_) {}
      });
    }
  }

  int get groupCount => _groupBox.length;
  int get promptCount => _promptBox.length;

  List<Group> get allGroups => _groupBox.values.toList();
  List<Prompt> get allPrompts => _promptBox.values.toList();

  // —— 自动保存设置 ——
  bool get autoSaveEnabled => (_settingsBox.get('autoSaveEnabled') as bool?) ?? false;
  int get autoSaveIntervalMinutes => (_settingsBox.get('autoSaveIntervalMinutes') as int?) ?? 10;
  int get autoSaveRetainCount => (_settingsBox.get('autoSaveRetainCount') as int?) ?? 20;
  String? get autoSaveDirPath => _settingsBox.get('autoSaveDirPath') as String?;
  String get manualSaveShortcut => (_settingsBox.get('manualSaveShortcut') as String?) ?? 'Ctrl+S';
  String get searchFocusShortcut => (_settingsBox.get('searchFocusShortcut') as String?) ?? 'Ctrl+K';

  Future<void> setAutoSaveEnabled(bool v) async => _settingsBox.put('autoSaveEnabled', v);
  Future<void> setAutoSaveIntervalMinutes(int m) async => _settingsBox.put('autoSaveIntervalMinutes', m);
  Future<void> setAutoSaveRetainCount(int n) async => _settingsBox.put('autoSaveRetainCount', n);
  Future<void> setAutoSaveDirPath(String path) async => _settingsBox.put('autoSaveDirPath', path);
  Future<void> setManualSaveShortcut(String s) async => _settingsBox.put('manualSaveShortcut', s);
  Future<void> setSearchFocusShortcut(String s) async => _settingsBox.put('searchFocusShortcut', s);

  Future<String> _defaultAutoSaveDirPath() async {
    final dir = await getApplicationSupportDirectory();
    final path = Path.join(dir.path, 'autosaves');
    await Directory(path).create(recursive: true);
    return path;
  }

  String _ts(DateTime dt) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    final y = dt.year.toString().padLeft(4, '0');
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    final ss = two(dt.second);
    return '${y}${m}${d}_${hh}${mm}${ss}';
  }

  Future<void> _enforceAutoSaveRetention(String dirPath) async {
    try {
      final ents = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json') &&
              f.uri.pathSegments.last.startsWith('ai_prompt_autosave_'))
          .toList();
      ents.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final keep = autoSaveRetainCount;
      if (ents.length > keep) {
        for (var i = keep; i < ents.length; i++) {
          try {
            ents[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // 执行自动保存快照（格式与导出 JSON 相同）
  Future<File?> saveAutoSnapshot({String? rootGroupId}) async {
    if (kIsWeb) return null; // Web 不写入本地文件
    final enabled = autoSaveEnabled;
    if (!enabled) return null;
    final dirPath = autoSaveDirPath ?? await _defaultAutoSaveDirPath();
    await Directory(dirPath).create(recursive: true);
    final name = 'ai_prompt_autosave_${_ts(DateTime.now())}.json';
    final file = File(Path.join(dirPath, name));
    final data = exportJson(rootGroupId: rootGroupId);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await _enforceAutoSaveRetention(dirPath);
    return file;
  }

  // 手动保存快照（不受开关影响），同样使用导出 JSON 格式
  Future<File?> saveManualSnapshot({String? rootGroupId}) async {
    if (kIsWeb) return null; // Web 不写入本地文件
    final dirPath = autoSaveDirPath ?? await _defaultAutoSaveDirPath();
    await Directory(dirPath).create(recursive: true);
    final name = 'ai_prompt_manual_${_ts(DateTime.now())}.json';
    final file = File(Path.join(dirPath, name));
    final data = exportJson(rootGroupId: rootGroupId);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  // 列出自动保存历史（包含路径与修改时间）
  Future<List<Map<String, dynamic>>> listAutoSaveHistory() async {
    if (kIsWeb) return [];
    final dirPath = autoSaveDirPath ?? await _defaultAutoSaveDirPath();
    try {
      final files = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('ai_prompt_autosave_') &&
              f.path.toLowerCase().endsWith('.json'))
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files
          .map((f) => {
                'path': f.path,
                'modified': f.lastModifiedSync(),
                'size': f.lengthSync(),
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Group> createGroup(String name, {String? parentId}) async {
    final uuid = const Uuid().v4();
    final level = parentId == null ? 1 : (getGroup(parentId)?.level ?? 0) + 1;
    if (level < 1 || level > 5) {
      throw StateError('分组层级必须在 1~5 范围');
    }
    final sortOrder = _calcNextSortOrder(parentId);
    final group = Group(
      id: uuid,
      name: name,
      level: level,
      parentId: parentId,
      sortOrder: sortOrder,
    );
    await _groupBox.put(group.id, group);
    _invalidateCaches();
    _bumpOps();
    return group;
  }

  Group? getGroup(String id) => _groupBox.get(id);

  Future<void> renameGroup(String id, String newName) async {
    final g = getGroup(id);
    if (g == null) return;
    final updated = Group(
      id: g.id,
      name: newName,
      level: g.level,
      parentId: g.parentId,
      sortOrder: g.sortOrder,
    );
    await _groupBox.put(id, updated);
    _invalidateCaches();
    _bumpOps();
  }

  Future<void> deleteGroup(String id) async {
    // 删除子树所有分组与提示词
    final parentId = getGroup(id)?.parentId;
    final descendants = _collectDescendantGroupIds(id);
    for (final gid in descendants) {
      // 删除该分组的所有提示词
      final prompts = _promptBox.values.where((p) => p.groupId == gid).toList();
      for (final p in prompts) {
        await _promptBox.delete(p.id);
      }
      await _groupBox.delete(gid);
    }
    // 先清理缓存，避免压实阶段读取到旧缓存
    _invalidateCaches();
    // 压实同级 sortOrder，保持连续
    await _compactSiblingSortOrders(parentId);
    _bumpOps();
  }

  /// 删除分组但保留其子分组：
  /// - 子分组提升到父级（保持相对顺序，追加到末尾）
  /// - 若该组自身存在提示词，则迁移到父级下的某叶子分组（不存在则新建）
  Future<void> deleteGroupKeepChildren(String id) async {
    final group = getGroup(id);
    if (group == null) return;
    final parentId = group.parentId;

    // 1) 处理该组自身的提示词：迁移到父级下的叶子分组
    final ownPrompts = getPromptsInGroup(group.id);
    if (ownPrompts.isNotEmpty) {
      final leafId = await ensureLeafUnder(parentId, defaultName: '未分类');
      for (final p in ownPrompts) {
        final updated = p.copyWith(
          groupId: leafId,
          sortOrder: _calcNextPromptSortOrder(leafId),
        );
        await _promptBox.put(p.id, updated);
      }
    }

    // 2) 提升子分组到父级：维持相对顺序并调整层级
    final children = getChildren(group.id)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    int baseOrder = _calcNextSortOrder(parentId);
    // 计算目标父深度用于层级校验
    final targetDepth = parentId == null ? 0 : buildPathGroups(parentId).length;
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      // 计算子树最大深度以校验不超过 5 层
      final depths = <String, int>{};
      void dfsDepth(String curId, int depth) {
        depths[curId] = depth;
        for (final c in getChildren(curId)) {
          dfsDepth(c.id, depth + 1);
        }
      }
      dfsDepth(child.id, 0);
      final newLevelRoot = targetDepth + 1; // 直接成为父级的子分组
      final maxNewLevel = depths.values.map((d) => newLevelRoot + d).fold<int>(1, (m, v) => v > m ? v : m);
      if (maxNewLevel > 5) {
        throw StateError('删除后子分组提升将导致层级超过 5 层，操作被拒绝');
      }

      // 更新子树：根节点 parentId 改为父级，sortOrder 追加；其余节点仅调整 level
      final updatedRoot = Group(
        id: child.id,
        name: child.name,
        level: newLevelRoot,
        parentId: parentId,
        sortOrder: baseOrder + i,
      );
      await _groupBox.put(child.id, updatedRoot);

      for (final entry in depths.entries) {
        final gid = entry.key;
        final depth = entry.value;
        if (gid == child.id) continue;
        final g = getGroup(gid)!;
        final updated = Group(
          id: g.id,
          name: g.name,
          level: newLevelRoot + depth,
          parentId: g.parentId,
          sortOrder: g.sortOrder,
        );
        await _groupBox.put(g.id, updated);
      }
    }

    // 3) 删除当前分组本身
    await _groupBox.delete(group.id);
    _invalidateCaches();
    await _compactSiblingSortOrders(parentId);
    _bumpOps();
  }

  /// 确保在指定父分组下存在一个叶子分组，若不存在则创建并返回其 id。
  Future<String> ensureLeafUnder(String? parentId, {String defaultName = '未分类'}) async {
    final children = getChildren(parentId);
    // 先尝试找到已有叶子分组
    for (final c in children) {
      final hasKids = getChildren(c.id).isNotEmpty;
      if (!hasKids) {
        return c.id;
      }
    }
    // 不存在则新建一个叶子分组
    final g = await createGroup(defaultName, parentId: parentId);
    return g.id;
  }

  /// 结构合并：将 source 的所有子分组迁移到 target 下；
  /// 如 removeSource 为 true，则删除 source 本身；source 的提示词会迁移到 target 下的叶子分组。
  Future<void> mergeGroupStructure(String sourceId, String targetId, {bool removeSource = true}) async {
    final source = getGroup(sourceId);
    final target = getGroup(targetId);
    if (source == null || target == null) return;
    if (sourceId == targetId) throw StateError('不能与自身合并');

    final targetDepth = buildPathGroups(targetId).length;
    // 按顺序迁移子分组
    final children = getChildren(sourceId)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    int baseOrder = _calcNextSortOrder(targetId);
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final depths = <String, int>{};
      void dfsDepth(String curId, int depth) {
        depths[curId] = depth;
        for (final c in getChildren(curId)) {
          dfsDepth(c.id, depth + 1);
        }
      }
      dfsDepth(child.id, 0);
      final newLevelRoot = targetDepth + 1;
      final maxNewLevel = depths.values.map((d) => newLevelRoot + d).fold<int>(1, (m, v) => v > m ? v : m);
      if (maxNewLevel > 5) {
        throw StateError('合并后层级超过 5 层，操作被拒绝');
      }
      // 根迁移到 target，保持追加顺序
      final updatedRoot = Group(
        id: child.id,
        name: child.name,
        level: newLevelRoot,
        parentId: targetId,
        sortOrder: baseOrder + i,
      );
      await _groupBox.put(child.id, updatedRoot);
      for (final entry in depths.entries) {
        final gid = entry.key;
        final depth = entry.value;
        if (gid == child.id) continue;
        final g = getGroup(gid)!;
        final updated = Group(
          id: g.id,
          name: g.name,
          level: newLevelRoot + depth,
          parentId: g.parentId,
          sortOrder: g.sortOrder,
        );
        await _groupBox.put(g.id, updated);
      }
    }

    // 迁移 source 自身的提示词到 target 下的一个叶子分组
    final ownPrompts = getPromptsInGroup(sourceId);
    if (ownPrompts.isNotEmpty) {
      final leafId = await ensureLeafUnder(targetId, defaultName: '未分类');
      for (final p in ownPrompts) {
        final updated = p.copyWith(
          groupId: leafId,
          sortOrder: _calcNextPromptSortOrder(leafId),
        );
        await _promptBox.put(p.id, updated);
      }
    }

    if (removeSource) {
      await _groupBox.delete(sourceId);
    }
    _invalidateCaches();
    await _compactSiblingSortOrders(targetId);
    _bumpOps();
  }

  /// 内容合并：将 source 子树下的所有提示词，迁移到目标叶子分组。
  Future<void> flattenPromptsUnderToLeaf(String sourceId, String targetLeafId, {bool deduplicate = false}) async {
    final targetLeaf = getGroup(targetLeafId);
    if (targetLeaf == null) throw StateError('目标分组不存在');
    final hasKids = getChildren(targetLeafId).isNotEmpty;
    if (hasKids) throw StateError('目标分组必须为叶子分组');

    final prompts = collectPromptsUnder(sourceId);
    // 目标已有的用于去重
    final existing = _promptBox.values.where((p) => p.groupId == targetLeafId).toList();
    for (final p in prompts) {
      if (deduplicate && existing.any((x) => x.title == p.title && x.content == p.content)) {
        continue;
      }
      final updated = p.copyWith(
        groupId: targetLeafId,
        sortOrder: _calcNextPromptSortOrder(targetLeafId),
      );
      await _promptBox.put(p.id, updated);
    }
    _bumpOps();
  }

  // 将分组移动到新的父分组（或根），并根据新位置调整子树的 level
  Future<void> moveGroup(String id, {String? newParentId}) async {
    final group = getGroup(id);
    if (group == null) return;
    if (newParentId == id) {
      throw StateError('不能将分组移动到自身');
    }
    final subtreeIds = _collectDescendantGroupIds(id);
    if (newParentId != null && subtreeIds.contains(newParentId)) {
      throw StateError('不能将分组移动到其子分组');
    }

    // 目标父分组路径深度
    final targetDepth = newParentId == null ? 0 : buildPathGroups(newParentId).length;
    final newLevelRoot = targetDepth + 1;

    // 计算子树深度映射
    final depths = <String, int>{};
    void dfsDepth(String curId, int depth) {
      depths[curId] = depth;
      for (final c in getChildren(curId)) {
        dfsDepth(c.id, depth + 1);
      }
    }
    dfsDepth(id, 0);

    // 检查最大层级不超过 5
    final maxNewLevel = depths.values.map((d) => newLevelRoot + d).fold<int>(1, (m, v) => v > m ? v : m);
    if (maxNewLevel > 5) {
      throw StateError('移动后分组层级超过 5 层，操作被拒绝');
    }

    // 更新根分组：parentId, level, sortOrder
    final updatedRoot = Group(
      id: group.id,
      name: group.name,
      level: newLevelRoot,
      parentId: newParentId,
      sortOrder: _calcNextSortOrder(newParentId),
    );
    await _groupBox.put(group.id, updatedRoot);

    // 更新子分组的 level（父链保持不变）
    for (final entry in depths.entries) {
      final gid = entry.key;
      final depth = entry.value;
      if (gid == id) continue;
      final g = getGroup(gid)!;
      final updated = Group(
        id: g.id,
        name: g.name,
        level: newLevelRoot + depth,
        parentId: g.parentId,
        sortOrder: g.sortOrder,
      );
      await _groupBox.put(g.id, updated);
    }
    _invalidateCaches();
    _bumpOps();
  }

  // 在同级内上移/下移分组顺序
  Future<void> reorderSibling(String id, {required bool moveUp}) async {
    final g = getGroup(id);
    if (g == null) return;
    final siblings = getChildren(g.parentId);
    siblings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final idx = siblings.indexWhere((x) => x.id == id);
    if (idx < 0) return;
    final swapIdx = moveUp ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= siblings.length) return;
    final a = siblings[idx];
    final b = siblings[swapIdx];
    final aNew = Group(id: a.id, name: a.name, level: a.level, parentId: a.parentId, sortOrder: b.sortOrder);
    final bNew = Group(id: b.id, name: b.name, level: b.level, parentId: b.parentId, sortOrder: a.sortOrder);
    await _groupBox.put(a.id, aNew);
    await _groupBox.put(b.id, bNew);
    // 排序更新后清理与通知，确保 UI 读取到最新顺序
    _invalidateCaches();
    _bumpOps();
  }

  Future<Prompt> createPrompt({
    required String title,
    required String content,
    required List<String> tags,
    String? description,
    required String groupId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool favorite = false,
    bool pinned = false,
    int usageCount = 0,
  }) async {
    final group = getGroup(groupId);
    if (group == null) throw StateError('分组不存在');
    // 必须属于叶子分组：该分组不可再有子分组
    final hasChildren = allGroups.any((g) => g.parentId == groupId);
    if (hasChildren) {
      throw StateError('提示词必须归属到叶子分组');
    }
    final prompt = Prompt(
      id: const Uuid().v4(),
      title: title,
      content: content,
      tags: tags,
      description: description,
      groupId: groupId,
      sortOrder: _calcNextPromptSortOrder(groupId),
      createdAt: createdAt,
      updatedAt: updatedAt,
      favorite: favorite,
      pinned: pinned,
      usageCount: usageCount,
    );
    await _promptBox.put(prompt.id, prompt);
    _bumpOps();
    return prompt;
  }

  Future<void> deletePrompt(String id) async {
    await _promptBox.delete(id);
    _bumpOps();
  }

  Future<void> updatePrompt(Prompt p) async {
    await _promptBox.put(p.id, p);
    _bumpOps();
  }

  Future<void> movePrompt(String id, String newGroupId) async {
    final p = _promptBox.get(id);
    if (p == null) return;
    final targetGroup = getGroup(newGroupId);
    if (targetGroup == null) throw StateError('目标分组不存在');
    final hasChildren = allGroups.any((g) => g.parentId == newGroupId);
    if (hasChildren) {
      throw StateError('提示词必须归属到叶子分组');
    }
    final updated = p.copyWith(
      groupId: newGroupId,
      sortOrder: _calcNextPromptSortOrder(newGroupId),
    );
    await _promptBox.put(id, updated);
    _bumpOps();
  }

  List<Group> getChildren(String? parentId) {
    final cached = _childrenCache[parentId];
    if (cached != null) return List<Group>.from(cached);
    final res = allGroups
        .where((g) => g.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _childrenCache[parentId] = res;
    return List<Group>.from(res);
  }

  List<String> _collectDescendantGroupIds(String rootId) {
    final ids = <String>[];
    void dfs(String id) {
      ids.add(id);
      final children = getChildren(id);
      for (final c in children) {
        dfs(c.id);
      }
    }
    dfs(rootId);
    return ids;
  }

  int _calcNextSortOrder(String? parentId) {
    final siblings = getChildren(parentId);
    if (siblings.isEmpty) return 1;
    return siblings.map((e) => e.sortOrder).fold<int>(1, (max, v) => v > max ? v : max) + 1;
  }

  // 在同级内将分组移动到指定索引（支持跨父级先移动再排序）
  Future<void> reorderSiblingToIndex(String id, int newIndex) async {
    final g = getGroup(id);
    if (g == null) return;
    final siblings = getChildren(g.parentId);
    siblings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final curIdx = siblings.indexWhere((x) => x.id == id);
    if (curIdx < 0) return;
    final moving = siblings.removeAt(curIdx);
    // 如果从前面拖到后面的间隙，移除后目标索引需要减 1 才能准确插入到期望位置
    int adjustedIndex = newIndex;
    if (newIndex > curIdx) {
      adjustedIndex = newIndex - 1;
    }
    final clampedIndex = adjustedIndex.clamp(0, siblings.length);
    siblings.insert(clampedIndex, moving);
    for (int i = 0; i < siblings.length; i++) {
      final s = siblings[i];
      final updated = Group(
        id: s.id,
        name: s.name,
        level: s.level,
        parentId: s.parentId,
        sortOrder: i + 1,
      );
      await _groupBox.put(s.id, updated);
    }
    // 排序更新后清理与通知，确保 UI 读取到最新顺序
    _invalidateCaches();
    _bumpOps();
  }

  // 删除后压实同级排序序号（保持 1..N 连续）
  Future<void> _compactSiblingSortOrders(String? parentId) async {
    // 直接从 box 读，避免缓存影响
    final siblings = _groupBox.values.where((g) => g.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (int i = 0; i < siblings.length; i++) {
      final s = siblings[i];
      if (s.sortOrder != i + 1) {
        final updated = Group(
          id: s.id,
          name: s.name,
          level: s.level,
          parentId: s.parentId,
          sortOrder: i + 1,
        );
        await _groupBox.put(s.id, updated);
      }
    }
  }

  // 获取某叶子分组下的提示词（按 sortOrder 排序）
  List<Prompt> getPromptsInGroup(String groupId) {
    final list = _promptBox.values.where((p) => p.groupId == groupId).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  int _calcNextPromptSortOrder(String groupId) {
    final prompts = getPromptsInGroup(groupId);
    if (prompts.isEmpty) return 1;
    return prompts.map((e) => e.sortOrder).fold<int>(1, (max, v) => v > max ? v : max) + 1;
  }

  // 在目标分组内将提示词移动/排序到指定索引
  Future<void> reorderPromptToIndex(String id, String targetGroupId, int newIndex) async {
    final p = _promptBox.get(id);
    if (p == null) return;
    final targetGroup = getGroup(targetGroupId);
    if (targetGroup == null) throw StateError('目标分组不存在');
    final hasChildren = allGroups.any((g) => g.parentId == targetGroupId);
    if (hasChildren) {
      throw StateError('提示词必须归属到叶子分组');
    }
    final list = getPromptsInGroup(targetGroupId);
    list.removeWhere((x) => x.id == id);
    final moving = p.copyWith(groupId: targetGroupId, sortOrder: 0);
    final clampedIndex = newIndex.clamp(0, list.length);
    list.insert(clampedIndex, moving);
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      final updated = item.copyWith(sortOrder: i + 1);
      await _promptBox.put(item.id, updated);
    }
  }

  // 递归收集并按分组顺序与分组内排序返回提示词
  List<Prompt> collectPromptsUnderSorted(String groupId) {
    final res = <Prompt>[];
    void dfs(String gid) {
      final kids = getChildren(gid);
      // 无论该分组是否为叶子，先收集其自身的提示词（兼容历史数据）。
      res.addAll(getPromptsInGroup(gid));
      // 再递归子分组以保持整体顺序
      for (final c in kids) {
        dfs(c.id);
      }
    }
    dfs(groupId);
    return res;
  }

  // 新增：收藏/置顶/使用次数操作
  Future<void> toggleFavorite(String id, bool favorite) async {
    final p = _promptBox.get(id);
    if (p == null) return;
    final updated = p.copyWith(favorite: favorite);
    await _promptBox.put(id, updated);
    _bumpOps();
  }

  Future<void> togglePinned(String id, bool pinned) async {
    final p = _promptBox.get(id);
    if (p == null) return;
    final updated = p.copyWith(pinned: pinned);
    await _promptBox.put(id, updated);
    _bumpOps();
  }

  Future<void> incrementUsageCount(String id) async {
    final p = _promptBox.get(id);
    if (p == null) return;
    final updated = p.copyWith(usageCount: p.usageCount + 1, updatedAt: DateTime.now());
    await _promptBox.put(id, updated);
    _bumpOps();
  }

  // 生成从根到当前分组的路径（名称列表）
  List<Group> buildPathGroups(String groupId) {
    final cached = _pathGroupsCache[groupId];
    if (cached != null) return List<Group>.from(cached);
    final path = <Group>[];
    Group? cur = getGroup(groupId);
    while (cur != null) {
      path.insert(0, cur);
      cur = cur.parentId == null ? null : getGroup(cur.parentId!);
    }
    _pathGroupsCache[groupId] = path;
    return List<Group>.from(path);
  }

  String buildPathLabel(String groupId) {
    final cached = _pathLabelCache[groupId];
    if (cached != null) return cached;
    final label = buildPathGroups(groupId).map((g) => g.name).join(' / ');
    _pathLabelCache[groupId] = label;
    return label;
  }

  // 递归收集某分组及其子分组下的所有提示词
  List<Prompt> collectPromptsUnder(String groupId) {
    final all = <Prompt>[];
    final ids = _collectDescendantGroupIds(groupId);
    for (final p in _promptBox.values) {
      if (ids.contains(p.groupId)) {
        all.add(p);
      }
    }
    return all;
  }

  // 全局搜索：支持前缀语法 tag:xxx / title:xxx / content:xxx / path:xxx
  // 匹配规则：将查询拆分为空格分隔的 token；
  // - 对于带前缀的 token，要求对应字段必须命中（AND）
  // - 对于无前缀的通用 token，要求每个 token 在任一字段命中（AND）
  List<Prompt> search(String query) {
    final parts = parseQuery(query);
    final hasAnyToken = parts["tag"]!.isNotEmpty || parts["title"]!.isNotEmpty || parts["content"]!.isNotEmpty || parts["path"]!.isNotEmpty || parts["general"]!.isNotEmpty;
    if (!hasAnyToken) return allPrompts;
    final matched = _promptBox.values.where((p) {
      final title = p.title.toLowerCase();
      final content = p.content.toLowerCase();
      final tagsLower = p.tags.map((e) => e.toLowerCase()).toList();
      final pathLabel = buildPathLabel(p.groupId).toLowerCase();

      bool matchAll(List<String> tokens, bool Function(String) checker) {
        for (final t in tokens) {
          if (t.isEmpty) continue;
          if (!checker(t)) return false;
        }
        return true;
      }

      final okTitle = matchAll(parts["title"]!, (t) => title.contains(t));
      final okContent = matchAll(parts["content"]!, (t) => content.contains(t));
      final okTag = matchAll(parts["tag"]!, (t) => tagsLower.any((x) => x.contains(t)));
      final okPath = matchAll(parts["path"]!, (t) => pathLabel.contains(t));

      if (!(okTitle && okContent && okTag && okPath)) return false;

      // 通用 token：每个 token 至少在一个字段命中
      bool okGeneral = matchAll(parts["general"]!, (t) => title.contains(t) || content.contains(t) || tagsLower.any((x) => x.contains(t)) || pathLabel.contains(t));
      return okGeneral;
    }).toList();

    // 计算权重得分并排序（标题>标签>内容>路径）
    int countOccur(String haystack, String needle) {
      if (needle.isEmpty) return 0;
      int count = 0;
      int idx = 0;
      while (true) {
        idx = haystack.indexOf(needle, idx);
        if (idx == -1) break;
        count++;
        idx += needle.length;
      }
      return count;
    }

    int scoreFor(Prompt p) {
      final title = p.title.toLowerCase();
      final content = p.content.toLowerCase();
      final tagsLower = p.tags.map((e) => e.toLowerCase()).toList();
      final pathLabel = buildPathLabel(p.groupId).toLowerCase();

      int titleScore = 0;
      for (final t in [...parts['title']!, ...parts['general']!]) {
        titleScore += countOccur(title, t);
      }

      int tagScore = 0;
      for (final t in [...parts['tag']!, ...parts['general']!]) {
        for (final tag in tagsLower) {
          tagScore += countOccur(tag, t);
        }
      }

      int contentScore = 0;
      for (final t in [...parts['content']!, ...parts['general']!]) {
        contentScore += countOccur(content, t);
      }

      int pathScore = 0;
      for (final t in [...parts['path']!, ...parts['general']!]) {
        pathScore += countOccur(pathLabel, t);
      }

      return titleScore * 4 + tagScore * 3 + contentScore * 2 + pathScore * 1;
    }

    matched.sort((a, b) {
      final sa = scoreFor(a);
      final sb = scoreFor(b);
      final cmp = sb.compareTo(sa);
      if (cmp != 0) return cmp;
      return a.title.compareTo(b.title);
    });
    return matched;
  }

  // 解析查询：返回各字段的 token（均为小写、去首尾空格）
  // 解析逻辑统一使用 utils/query_parser.dart 的 parseQuery

  // 导出为 JSON（整个分组树或选中分组子树）
  Map<String, dynamic> exportJson({String? rootGroupId}) {
    List<Map<String, dynamic>> buildNodes(String? parentId) {
      final children = getChildren(parentId);
      return children.map((g) {
        final node = <String, dynamic>{
          'name': g.name,
          'level': g.level,
        };
        final subgroups = getChildren(g.id);
        if (subgroups.isNotEmpty) {
          node['children'] = buildNodes(g.id);
        } else {
          // 叶子分组携带 prompts（按 sortOrder 排序）
          node['prompts'] = getPromptsInGroup(g.id)
              .map((p) => {
                    'title': p.title,
                    'content': p.content,
                    'tags': p.tags,
                    'description': p.description,
                    'createdAt': p.createdAt?.toIso8601String(),
                    'updatedAt': p.updatedAt?.toIso8601String(),
                    'favorite': p.favorite,
                    'pinned': p.pinned,
                    'usageCount': p.usageCount,
                  })
              .toList();
        }
        return node;
      }).toList();
    }

    final groupsJson = buildNodes(rootGroupId);
    return {'groups': groupsJson};
  }

  // 保存导出 JSON 到指定目录
  Future<File> saveExportJsonToDirectory(String dirPath, {String? rootGroupId}) async {
    final data = exportJson(rootGroupId: rootGroupId);
    final file = File(Path.join(dirPath, 'ai_prompt_export.json'));
    return file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // 导入 JSON（合并到现有库，最多 5 层）
  Future<void> importJson(Map<String, dynamic> json, {bool mergeDuplicates = true, void Function(int current, int total)? onProgress}) async {
    final groups = (json['groups'] as List?) ?? [];

    // 预统计提示词总数，用于进度展示
    int countPromptsInNode(Map<String, dynamic> node) {
      int total = 0;
      final children = node['children'] as List?;
      final prompts = node['prompts'] as List?;
      if (children != null && children.isNotEmpty) {
        for (final child in children.cast<Map<String, dynamic>>()) {
          total += countPromptsInNode(child);
        }
      } else if (prompts != null) {
        total += prompts.length;
      }
      return total;
    }
    int totalPrompts = 0;
    for (final node in groups.cast<Map<String, dynamic>>()) {
      totalPrompts += countPromptsInNode(node);
    }
    int processedPrompts = 0;
    onProgress?.call(processedPrompts, totalPrompts);

    Future<String> ensureGroupPath(List<String> names) async {
      String? parentId;
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        final level = i + 1;
        if (level > 5) {
          throw StateError('分组深度超过 5 层');
        }
        // 查找是否已有同名同父分组
        Group? existing = allGroups.firstWhere(
          (g) => g.name == name && g.parentId == parentId,
          orElse: () => Group(id: '', name: '', level: 0),
        );
        if (existing.id.isEmpty) {
          final created = await createGroup(name, parentId: parentId);
          parentId = created.id;
        } else {
          parentId = existing.id;
        }
      }
      return parentId!;
    }

    Future<void> walk(Map<String, dynamic> node, List<String> path) async {
      final name = node['name'] as String?;
      final children = node['children'] as List?;
      final prompts = node['prompts'] as List?;

      List<String> currentPath = path;
      if (name != null) {
        currentPath = [...path, name];
      }
      final groupId = await ensureGroupPath(currentPath);

      if (children != null && children.isNotEmpty) {
        for (final child in children.cast<Map<String, dynamic>>()) {
          await walk(child, currentPath);
        }
      } else if (prompts != null) {
        for (final p in prompts.cast<Map<String, dynamic>>()) {
          final title = p['title']?.toString() ?? '未命名';
          final content = p['content']?.toString() ?? '';
          final tags = (p['tags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          final description = p['description']?.toString();
          DateTime? createdAt;
          DateTime? updatedAt;
          bool favorite = false;
          bool pinned = false;
          int usageCount = 0;
          try {
            final ca = p['createdAt'] ?? p['created_at'];
            final ua = p['updatedAt'] ?? p['updated_at'];
            if (ca is String) createdAt = DateTime.tryParse(ca);
            if (ua is String) updatedAt = DateTime.tryParse(ua);
            if (ca is int) createdAt = DateTime.fromMillisecondsSinceEpoch(ca);
            if (ua is int) updatedAt = DateTime.fromMillisecondsSinceEpoch(ua);
            favorite = (p['favorite'] ?? false) == true;
            pinned = (p['pinned'] ?? false) == true;
            final uc = p['usageCount'];
            if (uc is int) usageCount = uc;
            if (uc is String) usageCount = int.tryParse(uc) ?? 0;
          } catch (_) {}

          // 可选：避免重复（同组同标题+内容）
          if (mergeDuplicates) {
            final exists = _promptBox.values.any((x) => x.groupId == groupId && x.title == title && x.content == content);
            processedPrompts++;
            onProgress?.call(processedPrompts, totalPrompts);
            if (exists) continue;
          }
          await createPrompt(
            title: title,
            content: content,
            tags: tags,
            description: description,
            groupId: groupId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            favorite: favorite,
            pinned: pinned,
            usageCount: usageCount,
          );
          processedPrompts++;
          onProgress?.call(processedPrompts, totalPrompts);
        }
      }
    }

    for (final node in groups.cast<Map<String, dynamic>>()) {
      await walk(node, []);
    }
  }
}

// 简易 Path 组合（避免引入 path 包）
class Path {
  static String join(String a, String b) {
    final sep = Platform.pathSeparator;
    final left = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
    final right = b.startsWith(sep) ? b.substring(1) : b;
    return '$left$sep$right';
  }
}