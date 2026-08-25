import 'package:flutter/material.dart';
import 'data/expense_models.dart';
import 'data/expenses_repository.dart';

/// Android hardcodes tax-type as ₹ (absolute, id="2") / % (percentage, id="1").
/// The API `tax_types` field is ignored in Android (AddExpensesFragment:663-671
/// is commented out). We match that exactly.
const _kTaxTypes = ['₹', '%'];
const _kTaxTypeIds = {'₹': '2', '%': '1'};

/// Add Expenses — Android parity (`AddExpensesFragment`): category / payment-mode /
/// tax-type dropdowns load from `expense_dashboard` master data; create via
/// `expense_data_create`. Validation matches Android: name + valid amount required.
class AddExpensesScreen extends StatefulWidget {
  final bool isTab;
  final VoidCallback? onSuccess;
  final ExpenseListItem? item;
  const AddExpensesScreen({super.key, this.isTab = false, this.onSuccess, this.item});

  @override
  State<AddExpensesScreen> createState() => _AddExpensesScreenState();
}

class _AddExpensesScreenState extends State<AddExpensesScreen> {
  String selectedDate = DateTime.now().toString().split(' ')[0];
  final expenseController = TextEditingController();
  final amountController = TextEditingController();
  final taxValController = TextEditingController();
  final invoiceController = TextEditingController();
  final remarksController = TextEditingController();

  bool _loadingMaster = true;
  String _masterError = '';
  bool _submitting = false;

  List<ExpenseCategory> _categories = const [];
  List<String> _paymentModes = const [];

  ExpenseCategory? _category;
  String? _paymentMode;
  String _taxTypeLabel = '₹';  // Android default: ₹ (id="2")

  double get amountVal => double.tryParse(amountController.text) ?? 0.0;
  double get taxVal => double.tryParse(taxValController.text) ?? 0.0;
  double get totalAmount => amountVal + taxVal;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      expenseController.text = widget.item!.title;
      amountController.text = widget.item!.baseAmount;
      taxValController.text = widget.item!.taxAmount;
      invoiceController.text = widget.item!.invoiceNumber;
      remarksController.text = widget.item!.remarks;
      selectedDate = widget.item!.date;
    }
    _loadMaster();
  }

  @override
  void dispose() {
    expenseController.dispose();
    amountController.dispose();
    taxValController.dispose();
    invoiceController.dispose();
    remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadMaster() async {
    setState(() {
      _loadingMaster = true;
      _masterError = '';
    });
    final r = await ExpensesRepository.instance.getMasterData();
    if (!mounted) return;
    setState(() {
      _loadingMaster = false;
      if (r.statusCode == 0) {
        _categories = r.data.categories;
        _paymentModes = r.data.paymentModes;
        if (widget.item != null) {
          _category = _categories.isNotEmpty
              ? _categories.firstWhere(
                  (c) => c.name.toLowerCase() == widget.item!.category.toLowerCase(),
                  orElse: () => _categories.first,
                )
              : null;
          _paymentMode = _paymentModes.isNotEmpty
              ? _paymentModes.firstWhere(
                  (m) => m.toLowerCase() == widget.item!.paymentMethod.toLowerCase(),
                  orElse: () => _paymentModes.first,
                )
              : null;
          if (widget.item!.taxCategory.contains('%')) {
            _taxTypeLabel = '%';
          } else {
            _taxTypeLabel = '₹';
          }
        } else {
          _category = _categories.isNotEmpty ? _categories.first : null;
          _paymentMode = _paymentModes.isNotEmpty ? _paymentModes.first : null;
        }
      } else {
        _masterError = r.statusMessage.isEmpty
            ? 'Could not load expense options'
            : r.statusMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        title: Text(widget.item != null ? 'Edit Expense' : 'Add Expenses',
            style: const TextStyle(
                color: Colors.black54, fontWeight: FontWeight.w800, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black54),
      ),
      body: _loadingMaster
          ? const Center(child: CircularProgressIndicator())
          : _masterError.isNotEmpty
              ? _errorRetry()
              : _form(),
    );
  }

  Widget _errorRetry() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.black45, size: 44),
            const SizedBox(height: 12),
            Text(_masterError,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadMaster,
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

  Widget _form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                    label: 'Expenses *', controller: expenseController),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildObjDropdown<ExpenseCategory>(
                  label: 'Category Type *',
                  value: _category,
                  items: _categories,
                  itemLabel: (c) => c.name,
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'Date',
                  readOnly: true,
                  controller: TextEditingController(text: selectedDate),
                  suffixIcon: Icons.calendar_today_outlined,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() =>
                          selectedDate = picked.toString().split(' ')[0]);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStrDropdown(
                  label: 'Payment Mode',
                  value: _paymentMode,
                  items: _paymentModes,
                  onChanged: (v) => setState(() => _paymentMode = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'Amount *',
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _buildStrDropdown(
                      label: 'Tax Type',
                      value: _taxTypeLabel,
                      items: _kTaxTypes,
                      onChanged: (v) => setState(() => _taxTypeLabel = v ?? '₹'),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      label: 'Tax Amount',
                      hint: '0',
                      controller: taxValController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(label: 'Invoice Number', controller: invoiceController),
          const SizedBox(height: 16),
          _buildTextField(
              label: 'Remarks', controller: remarksController, maxLines: 3),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F3FB),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expenses Details',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.black54,
                        fontSize: 15)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _buildDetailField(
                            'Amount', '₹${amountVal.toStringAsFixed(1)}')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildDetailField(
                            'Tax (Rs)', '₹${taxVal.toStringAsFixed(1)}')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildDetailField(
                            'Total', '₹${totalAmount.toStringAsFixed(1)}')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Spacer(flex: 2),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _addExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : Text(widget.item != null ? 'Update' : 'Add',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC60000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  onPressed: _submitting ? null : _clearFields,
                  child: const Text('Clear',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _addExpense() async {
    if (_submitting) return;
    // Android validation: name + valid amount required (AddExpensesFragment:174-176).
    if (expenseController.text.trim().isEmpty) {
      _snack('Enter expenses name');
      return;
    }
    if (amountVal <= 0) {
      _snack('Enter Valid Amount');
      return;
    }
    if (_category == null) {
      _snack('Choose a category');
      return;
    }
    setState(() => _submitting = true);
    final r = await ExpensesRepository.instance.createExpense(
      title: expenseController.text.trim(),
      categoryId: _category!.id,
      date: selectedDate,
      baseAmount: amountVal.toString(),
      paymentMethod: _paymentMode ?? '',
      taxTypeId: _kTaxTypeIds[_taxTypeLabel] ?? '2',
      taxAmount: taxVal > 0 ? taxVal.toString() : '',
      invoiceNumber: invoiceController.text.trim(),
      remarks: remarksController.text.trim(),
      expenseId: widget.item?.expenseId ?? '',
      isEdited: widget.item != null ? '1' : '0',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    await _resultDialog(r.success, r.message);
    if (r.success && mounted) {
      _clearFields();
      if (widget.isTab) {
        widget.onSuccess?.call();
      } else {
        Navigator.pop(context, true); // signal the list to refresh
      }
    }
  }

  Future<void> _resultDialog(bool success, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(success ? 'Success' : 'Fail!'),
        content: Text(message.isEmpty ? (success ? 'Saved' : 'Failed') : message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _clearFields() {
    expenseController.clear();
    amountController.clear();
    taxValController.clear();
    invoiceController.clear();
    remarksController.clear();
    setState(() {});
  }

  Widget _buildTextField({
    required String label,
    TextEditingController? controller,
    String? hint,
    bool readOnly = false,
    IconData? suffixIcon,
    VoidCallback? onTap,
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            suffixIcon: suffixIcon != null
                ? Icon(suffixIcon, color: Colors.black54, size: 20)
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0D47A1))),
          ),
        ),
      ],
    );
  }

  Widget _buildStrDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return _dropdownShell(
      label: label,
      displayText: value ?? '',
      onTap: () async {
        final result = await _showDropdownDialog<String>(
          items: items,
          selected: value,
          itemLabel: (s) => s,
        );
        if (result != null) onChanged(result);
      },
    );
  }

  Widget _buildObjDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return _dropdownShell(
      label: label,
      displayText: value != null ? itemLabel(value) : '',
      onTap: () async {
        final result = await _showDropdownDialog<T>(
          items: items,
          selected: value,
          itemLabel: itemLabel,
        );
        if (result != null) onChanged(result);
      },
    );
  }

  Widget _dropdownShell({
    required String label,
    required String displayText,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black54)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(displayText,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.keyboard_arrow_down,
                    size: 20, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<T?> _showDropdownDialog<T>({
    required List<T> items,
    required T? selected,
    required String Function(T) itemLabel,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dropdown',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.85,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final isSelected = item == selected;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        color: isSelected
                            ? const Color(0xFF0D47A1).withValues(alpha: 0.06)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                itemLabel(item),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check,
                                  size: 20, color: Color(0xFF0D47A1)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.black54)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
