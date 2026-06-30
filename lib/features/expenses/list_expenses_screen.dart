import 'package:ezi_cable_digi/core/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'add_expenses_screen.dart';
import 'data/expense_models.dart';
import 'data/expenses_repository.dart';

/// Expenses list — Android parity (`ExpensesList`): date-range filtered
/// `expense_data`. FAB opens Add Expenses (`expense_data_create`) and refreshes on
/// return. Replaces the legacy in-memory `ExpenseStorage` placeholder.
class ListExpensesScreen extends StatefulWidget {
  const ListExpensesScreen({super.key});

  @override
  State<ListExpensesScreen> createState() => _ListExpensesScreenState();
}

class _ListExpensesScreenState extends State<ListExpensesScreen> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  bool _loading = false;
  bool _error = false;
  String _message = '';
  List<ExpenseListItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await ExpensesRepository.instance.getExpenseList(
      startDate: _fmt(_startDate),
      endDate: _fmt(_endDate),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.items;
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const [];
        _error = false; // no records
        _message = r.statusMessage;
      } else {
        _items = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => start ? _startDate = picked : _endDate = picked);
    }
  }

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddExpensesScreen()),
    );
    if (added == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context, 'list_expenses'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        backgroundColor: const Color(0xFF0D47A1),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFFF5F7FB),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                    child: _dateField('Start Date', _startDate, () => _pick(true))),
                const SizedBox(width: 10),
                Expanded(
                    child: _dateField('End Date', _endDate, () => _pick(false))),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('Search',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.black45, size: 44),
              const SizedBox(height: 12),
              Text(_message.isEmpty ? 'Could not load expenses' : _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(AppStrings.of(context, 'no_expenses_found')));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
      itemCount: _items.length,
      itemBuilder: (_, i) => _ExpenseCard(
        item: _items[i],
        onTap: () async {
          final edited = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => AddExpensesScreen(item: _items[i]),
            ),
          );
          if (edited == true && mounted) _load();
        },
      ),
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
            const SizedBox(height: 2),
            Text(_fmt(value),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final ExpenseListItem item;
  final VoidCallback onTap;
  const _ExpenseCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final amount =
        item.totalAmount.isNotEmpty ? item.totalAmount : item.baseAmount;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade200, width: 0.8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 3),
                      if (item.category.isNotEmpty)
                        Text(item.category,
                            style:
                                const TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text(item.date,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.black45)),
                      if (item.paymentMethod.isNotEmpty)
                        Text(item.paymentMethod,
                            style:
                                const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                ),
                Text('₹$amount',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF0D47A1))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
