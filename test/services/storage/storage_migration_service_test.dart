import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:smart_expense_tracker/models/expense.dart';
import 'package:smart_expense_tracker/services/storage/storage_interface.dart';
import 'package:smart_expense_tracker/services/storage/storage_migration_service.dart';

@GenerateMocks([StorageInterface])
class MockSourceStorage extends Mock implements StorageInterface {}

class MockDestinationStorage extends Mock implements StorageInterface {}

void main() {
  late MockSourceStorage mockSourceStorage;
  late MockDestinationStorage mockDestinationStorage;

  setUp(() {
    mockSourceStorage = MockSourceStorage();
    mockDestinationStorage = MockDestinationStorage();
  });

  group('StorageMigrationService Tests', () {
    final testExpense = Expense(
        id: 'test',
        amount: 0,
        description: 'test',
        date: DateTime.now(),
        category: 'test',
        type: 'Expense',
        currency: 'USD');

    test('successfully migrates data between storages', () async {
      // Arrange
      final expenses = [
        Expense(
            id: '1',
            amount: 100,
            description: 'Test 1',
            date: DateTime.now(),
            category: 'Food',
            type: 'Expense',
            currency: 'USD'),
        Expense(
            id: '2',
            amount: 200,
            description: 'Test 2',
            date: DateTime.now(),
            category: 'Transport',
            type: 'Expense',
            currency: 'USD'),
      ];

      when(mockSourceStorage.getExpenses()).thenAnswer((_) async => expenses);

      // Act
      await StorageMigrationService.migrateData(
          mockSourceStorage, mockDestinationStorage);

      // Assert
      verify(mockSourceStorage.getExpenses()).called(1);
      for (var expense in expenses) {
        verify(mockDestinationStorage.saveExpense(expense)).called(1);
      }
    });

    test('handles empty source storage', () async {
      // Arrange
      when(mockSourceStorage.getExpenses()).thenAnswer((_) async => []);

      // Act
      await StorageMigrationService.migrateData(
          mockSourceStorage, mockDestinationStorage);

      // Assert
      verify(mockSourceStorage.getExpenses()).called(1);
      verifyNever(() => mockDestinationStorage.saveExpense(testExpense));
    });

    test('handles errors during migration', () async {
      // Arrange
      when(mockSourceStorage.getExpenses())
          .thenThrow(Exception('Failed to get expenses'));

      // Act & Assert
      expect(
        () => StorageMigrationService.migrateData(
            mockSourceStorage, mockDestinationStorage),
        throwsException,
      );
    });
  });
}
