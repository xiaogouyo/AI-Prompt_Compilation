import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class SearchBarRefocusIntent extends Intent {
  const SearchBarRefocusIntent();
}

class GlobalSearchBar extends StatefulWidget {
  const GlobalSearchBar({super.key, this.focusNode});
  final FocusNode? focusNode;

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    // 初始化为当前查询，避免首次构建丢失文本
    final app = context.read<AppState>();
    _controller.text = app.searchQuery;
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // 当外部搜索词发生变化且当前未聚焦时，同步到输入框
    if (app.searchQuery != _controller.text && !_focusNode.hasFocus) {
      _controller.text = app.searchQuery;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
    // 局部 Shortcuts：使用 SingleActivator 提升可靠性，避免与默认文本编辑快捷键冲突
    final ShortcutActivator? searchActivator = (() {
      final s = app.searchFocusShortcut.trim().toLowerCase();
      if (s.isEmpty || s == 'none') return null;
      if (s == 'ctrl+shift+k' || s == 'control+shift+k') {
        return const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true);
      }
      if (s == 'ctrl+alt+k' || s == 'control+alt+k') {
        return const SingleActivator(LogicalKeyboardKey.keyK, control: true, alt: true);
      }
      return const SingleActivator(LogicalKeyboardKey.keyK, control: true);
    })();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (searchActivator != null) searchActivator: const SearchBarRefocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          // 处理 Ctrl+K：始终保持搜索框焦点
          SearchBarRefocusIntent: CallbackAction<SearchBarRefocusIntent>(
            onInvoke: (intent) {
              debugPrint('SearchBar captured: Ctrl+K');
              FocusScope.of(context).requestFocus(_focusNode);
              return null;
            },
          ),
          // 注意：部分平台默认可能将 Ctrl+K 映射为编辑命令。
          // 这里通过本地 Shortcuts 捕获后保持焦点，通常即可覆盖默认行为。
        },
        child: SizedBox(
          height: 40,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: app.setSearchQuery,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '全局搜索：标题 / 内容 / 标签 / 分组',
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }
}