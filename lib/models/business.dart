import 'package:hive/hive.dart';

/// A business/ledger the user tracks: a name plus the keyword(s) that identify
/// its incoming payments in an SMS (e.g. a paybill account, till name, or any
/// distinctive token like "ANNE-577715").
class Business {
  final String id;
  final String name;
  final List<String> keywords;

  Business({required this.id, required this.name, required this.keywords});

  /// Lowercase + whitespace-stripped, so "ANNE - 577715", "anne-577715" and
  /// "ANNE-577715" all compare equal, and substring matching is tolerant.
  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  List<String> get keywordKeys =>
      keywords.map(normalize).where((k) => k.isNotEmpty).toList();

  Business copyWith({String? name, List<String>? keywords}) => Business(
        id: id,
        name: name ?? this.name,
        keywords: keywords ?? this.keywords,
      );
}

/// Hand-written Hive adapter (typeId 12).
class BusinessAdapter extends TypeAdapter<Business> {
  @override
  final int typeId = 12;

  @override
  Business read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Business(
      id: fields[0] as String,
      name: fields[1] as String,
      keywords: (fields[2] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Business obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.keywords);
  }
}
