import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // 局部 Shortcuts：优先级高于默认 TextEditingShortcuts，保证 Ctrl+K 始终被捕捉
    final LogicalKeySet? searchKeySet = (() {
      final s = app.searchFocusShortcut.trim().toLowerCase();
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

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (searchKeySet != null) searchKeySet: const SearchBarRefocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SearchBarRefocusIntent: CallbackAction<SearchBarRefocusIntent>(
            onInvoke: (intent) {
              // 保持焦点，并打印日志，防止被 TextField 默认快捷键吞掉
              debugPrint('SearchBar captured: Ctrl+K');
              FocusScope.of(context).requestFocus(_focusNode);
              app.showSnack(context, '已捕获 Ctrl+K（搜索框仍保持焦点）');
              return null;
            },
          ),
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