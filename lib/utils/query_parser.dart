Map<String, List<String>> parseQuery(String query) {
  final res = {
    'tag': <String>[],
    'title': <String>[],
    'content': <String>[],
    'path': <String>[],
    'general': <String>[],
  };
  final q = query.trim();
  if (q.isEmpty) return res;
  final tokens = q.split(RegExp(r'\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
  for (final tokRaw in tokens) {
    final tok = tokRaw.toLowerCase();
    if (tok.startsWith('tag:')) {
      final v = tok.substring(4).trim();
      if (v.isNotEmpty) res['tag']!.add(v);
    } else if (tok.startsWith('title:')) {
      final v = tok.substring(6).trim();
      if (v.isNotEmpty) res['title']!.add(v);
    } else if (tok.startsWith('content:')) {
      final v = tok.substring(8).trim();
      if (v.isNotEmpty) res['content']!.add(v);
    } else if (tok.startsWith('path:')) {
      final v = tok.substring(5).trim();
      if (v.isNotEmpty) res['path']!.add(v);
    } else {
      res['general']!.add(tok);
    }
  }
  return res;
}