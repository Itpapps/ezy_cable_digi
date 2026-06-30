// Expenses models — Android parity (`expense_dashboard` / `expense_data` /
// `expense_data_create`). Defensive parse — never throws.

/// Category LOV item (`category_types[]{expense_category_id, expense_category}`).
class ExpenseCategory {
  final String id;
  final String name;
  const ExpenseCategory(this.id, this.name);

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
        (j['expense_category_id'] ?? '').toString().trim(),
        (j['expense_category'] ?? '').toString().trim(),
      );
}

/// Tax-type LOV item
/// (`tax_types[]{expense_tax_category_id, expense_tax_category, expense_tax_value}`).
class ExpenseTaxType {
  final String id;
  final String name;
  final String value;
  const ExpenseTaxType(this.id, this.name, this.value);

  factory ExpenseTaxType.fromJson(Map<String, dynamic> j) => ExpenseTaxType(
        (j['expense_tax_category_id'] ?? '').toString().trim(),
        (j['expense_tax_category'] ?? '').toString().trim(),
        (j['expense_tax_value'] ?? '').toString().trim(),
      );
}

/// Master data from `expense_dashboard` → `create_required_data_fields`.
class ExpenseMasterData {
  final List<String> paymentModes;
  final List<ExpenseCategory> categories;
  final List<ExpenseTaxType> taxTypes;
  const ExpenseMasterData({
    this.paymentModes = const [],
    this.categories = const [],
    this.taxTypes = const [],
  });
}

/// One expense row from `expense_data` → `expenses_list[]`.
class ExpenseListItem {
  final String expenseId;
  final String title;
  final String date; // yyyy-MM-dd (server returns datetime; first 10)
  final String totalAmount;
  final String baseAmount;
  final String taxAmount;
  final String paymentMethod;
  final String taxCategory;
  final String category;
  final String invoiceNumber;
  final String remarks;

  const ExpenseListItem({
    this.expenseId = '',
    this.title = '',
    this.date = '',
    this.totalAmount = '',
    this.baseAmount = '',
    this.taxAmount = '',
    this.paymentMethod = '',
    this.taxCategory = '',
    this.category = '',
    this.invoiceNumber = '',
    this.remarks = '',
  });

  factory ExpenseListItem.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    final d = s('expense_date');
    return ExpenseListItem(
      expenseId: s('expense_id'),
      title: s('expense_title'),
      date: d.length >= 10 ? d.substring(0, 10) : d,
      totalAmount: s('total_amount'),
      baseAmount: s('base_amount'),
      taxAmount: s('tax_amount'),
      paymentMethod: s('payment_method'),
      taxCategory: s('expense_tax_category'),
      category: s('expense_category'),
      invoiceNumber: s('expense_invoice_number'),
      remarks: s('remarks'),
    );
  }
}
