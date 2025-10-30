import 'package:hive/hive.dart';

class Group {
  Group({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
    this.sortOrder = 0,
  });

  final String id;
  String name;
  final int level; // 1..5
  final String? parentId; // null 表示根分组
  int sortOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level,
        'parentId': parentId,
        'sortOrder': sortOrder,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        level: json['level'] as int,
        parentId: json['parentId'] as String?,
        sortOrder: (json['sortOrder'] ?? 0) as int,
      );
}

class GroupAdapter extends TypeAdapter<Group> {
  @override
  final int typeId = 1;

  @override
  Group read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Group(
      id: fields[0] as String,
      name: fields[1] as String,
      level: fields[2] as int,
      parentId: fields[3] as String?,
      sortOrder: (fields[4] ?? 0) as int,
    );
  }

  @override
  void write(BinaryWriter writer, Group obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.level)
      ..writeByte(3)
      ..write(obj.parentId)
      ..writeByte(4)
      ..write(obj.sortOrder);
  }
}