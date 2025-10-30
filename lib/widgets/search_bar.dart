import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

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

    return SizedBox(
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
    );
  }
}