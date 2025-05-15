// Generated code - do not modify by hand

import 'package:hive/hive.dart';
import 'package:smart_expense_tracker/models/expense.dart';

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final typeId = 0;
  @override
  Expense read(BinaryReader reader) {
    return Expense(
      id: reader.readString(),
      date: reader.read() as DateTime,
      description: reader.readString(),
      amount: reader.readDouble(),
      category: reader.readString(),
      type: reader.readString(),
      currency: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer.writeString(obj.id);
    writer.write(obj.date);
    writer.writeString(obj.description);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.category);
    writer.writeString(obj.type);
    writer.writeString(obj.currency);
  }
}
