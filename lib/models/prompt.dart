import 'package:hive/hive.dart';

class Prompt {
  Prompt({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    this.description,
    required this.groupId,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.favorite = false,
    this.pinned = false,
    this.usageCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String title;
  String content;
  List<String> tags;
  String? description;
  String groupId; // 叶子分组 id
  int sortOrder;
  DateTime? createdAt;
  DateTime? updatedAt;
  bool favorite;
  bool pinned;
  int usageCount;

  Prompt copyWith({
    String? title,
    String? content,
    List<String>? tags,
    String? description,
    String? groupId,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? favorite,
    bool? pinned,
    int? usageCount,
  }) {
    return Prompt(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      groupId: groupId ?? this.groupId,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      favorite: favorite ?? this.favorite,
      pinned: pinned ?? this.pinned,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'description': description,
        'groupId': groupId,
        'sortOrder': sortOrder,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'favorite': favorite,
        'pinned': pinned,
        'usageCount': usageCount,
      };

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      return DateTime.tryParse(v);
    }
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }

  static Prompt fromJson(Map<String, dynamic> json) => Prompt(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
        description: json['description'] as String?,
        groupId: json['groupId'] as String,
        sortOrder: (json['sortOrder'] ?? 0) as int,
        createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
        updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
        favorite: (json['favorite'] ?? false) as bool,
        pinned: (json['pinned'] ?? false) as bool,
        usageCount: (json['usageCount'] ?? 0) as int,
      );
}

class PromptAdapter extends TypeAdapter<Prompt> {
  @override
  final int typeId = 2;

  @override
  Prompt read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Prompt(
      id: fields[0] as String,
      title: fields[1] as String,
      content: fields[2] as String,
      tags: (fields[3] as List).cast<String>(),
      description: fields[4] as String?,
      groupId: fields[5] as String,
      sortOrder: (fields[6] ?? 0) as int,
      createdAt: fields[7] as DateTime?,
      updatedAt: fields[8] as DateTime?,
      favorite: (fields[9] ?? false) as bool,
      pinned: (fields[10] ?? false) as bool,
      usageCount: (fields[11] ?? 0) as int,
    );
  }

  @override
  void write(BinaryWriter writer, Prompt obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.tags)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.groupId)
      ..writeByte(6)
      ..write(obj.sortOrder)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.favorite)
      ..writeByte(10)
      ..write(obj.pinned)
      ..writeByte(11)
      ..write(obj.usageCount);
  }
}