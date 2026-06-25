import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/sms_service.dart';

class SmsFilterScreen extends StatefulWidget {
  const SmsFilterScreen({super.key});

  @override
  _SmsFilterScreenState createState() => _SmsFilterScreenState();
}

class _SmsFilterScreenState extends State<SmsFilterScreen> {
  final SmsService _smsService = SmsService();
  DateTime? selectedDate;
  DateTimeRange? selectedDateRange;
  DateTime? selectedMonthYear;
  bool isLoading = false;

  void _fetchSms(String fetchType, DateTime referenceDate, {DateTime? rangeEnd}) async {
    print("Fetching SMS: fetchType=$fetchType, referenceDate=$referenceDate, rangeEnd=$rangeEnd");

    setState(() {
      isLoading = true;
    });

    try {
      final result = await _smsService.fetchTransactions(
        fetchType,
        referenceDate,
        rangeEnd: rangeEnd,
      );
      if (result['parsed']! > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetched ${result['parsed']} SMS transactions successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching SMS found for this date'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print("Error fetching SMS: $e");
      if (e.toString().contains('NO_KEYWORDS_SET')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set keywords in Settings first'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch SMS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _selectDay(BuildContext context) async {
    final DateTime now = DateTime.now();
    // Restrict selectable dates to the last 6 months only
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 180)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedDateRange = null;
        selectedMonthYear = null;
      });
      _fetchSms('day', picked);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTime now = DateTime.now();
    // Restrict the range picker to dates within the last 6 months
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 180)),
      lastDate: now,
      initialDateRange: selectedDateRange,
    );
    if (picked != null) {
      setState(() {
        selectedDateRange = picked;
        selectedDate = null;
        selectedMonthYear = null;
      });
      _fetchSms('range', picked.start, rangeEnd: picked.end);
    }
  }

  void _showMonthYearPicker(BuildContext context) {
    final DateTime now = DateTime.now();
    // Generate allowed month-year options for the last 6 months
    List<DateTime> allowedMonths = [];
    DateTime currentMonth = DateTime(now.year, now.month, 1);
    // Determine the earliest allowed month by subtracting 180 days and normalizing to the first day of that month
    DateTime earliestAllowed = DateTime(now.year, now.month, 1).subtract(const Duration(days: 180));
    earliestAllowed = DateTime(earliestAllowed.year, earliestAllowed.month, 1);

    while (!currentMonth.isBefore(earliestAllowed)) {
      allowedMonths.add(currentMonth);
      // Move to the previous month:
      currentMonth = DateTime(currentMonth.year, currentMonth.month, 1).subtract(const Duration(days: 1));
      currentMonth = DateTime(currentMonth.year, currentMonth.month, 1);
    }
    allowedMonths = allowedMonths.reversed.toList();

    DateTime? tempSelectedMonth = allowedMonths.last; // default selection is the latest month

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Select Month and Year'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(Icons.calendar_month, color: Colors.orange, size: 36),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<DateTime>(
                  value: tempSelectedMonth,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: allowedMonths.map((date) {
                    return DropdownMenuItem<DateTime>(
                      value: date,
                      child: Text(DateFormat('MMMM yyyy').format(date)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      tempSelectedMonth = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                onPressed: () {
                  if (tempSelectedMonth != null) {
                    Navigator.pop(context);
                    setState(() {
                      selectedMonthYear = tempSelectedMonth;
                      selectedDate = null;
                      selectedDateRange = null;
                    });
                    _fetchSms('month', tempSelectedMonth!);
                  }
                },
                label: const Text('Fetch'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt, size: 24),
            SizedBox(width: 8),
            Text("SMS Filter Options"),
          ],
        ),
        centerTitle: true,
        elevation: 2,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Select a time period to fetch SMS transactions",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.calendar_today, color: Colors.white),
                ),
                title: const Text("Select Day"),
                subtitle: const Text("Fetch transactions for a specific day"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectDay(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.date_range, color: Colors.white),
                ),
                title: const Text("Select Date Range"),
                subtitle: const Text("Fetch transactions between two dates"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectDateRange(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.calendar_month, color: Colors.white),
                ),
                title: const Text("Select Month"),
                subtitle: const Text("Fetch transactions for an entire month"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showMonthYearPicker(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (selectedDate != null || selectedDateRange != null || selectedMonthYear != null)
            Card(
              margin: const EdgeInsets.all(16.0),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Current Selection",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (selectedDate != null)
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            "Selected Day: ${DateFormat('dd MMM yyyy').format(selectedDate!)}",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    if (selectedDateRange != null)
                      Row(
                        children: [
                          const Icon(Icons.date_range, size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Selected Range: ${DateFormat('dd MMM yyyy').format(selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(selectedDateRange!.end)}",
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    if (selectedMonthYear != null)
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            "Selected Month: ${DateFormat('MMMM yyyy').format(selectedMonthYear!)}",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (isLoading)
            Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 16),
                  Text(
                    "Fetching SMS transactions...",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
