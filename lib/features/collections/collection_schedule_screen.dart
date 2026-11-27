import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/constants/app_colors.dart';
import 'data/pay_later.dart';
import 'data/pay_later_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Collection Schedule (Pay Later report) — server-side, Android parity with
/// `PayLaterReport` (`scheduled_collection_data`). The single list response also
/// carries the employee + status LOVs. The legacy local-DB path
/// (`DatabaseHelper.searchCollectionSchedules` / `CollectionSchedule`) is retained
/// elsewhere but no longer used here. See OPERATIONAL_MODULES_PARITY.md.
class CollectionScheduleScreen extends StatefulWidget {
  const CollectionScheduleScreen({super.key});

  @override
  State<CollectionScheduleScreen> createState() =>
      _CollectionScheduleScreenState();
}

class _CollectionScheduleScreenState extends State<CollectionScheduleScreen> {
  _SchedulePalette get p => _SchedulePalette.of(context);

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _employeeId = ''; // '' = Choose (no filter)
  String _status = ''; // '' = Choose (no filter)
  final _customerNameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _crfCtrl = TextEditingController();

  bool _loading = false;
  bool _error = false;
  String _message = '';
  List<PayLaterSchedule> _results = const [];
  List<PayLaterEmployee> _employees = const [];
  List<String> _statuses = const [];

  @override
  void initState() {
    super.initState();
    _search(); // initial load (also fills the employee + status LOVs)
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _accountCtrl.dispose();
    _crfCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _openDateSheet({
    required String title,
    required DateTime initial,
    required DateTime first,
  }) {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DateSheet(
        title: title,
        initial: initial.isBefore(first) ? first : initial,
        first: first,
        last: DateTime(2100),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await _openDateSheet(
      title: 'Start date',
      initial: _startDate,
      first: DateTime(2020),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      // Keep the range valid: end date never before start date.
      if (_endDate.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _openDateSheet(
      title: 'End date',
      initial: _endDate,
      first: DateUtils.dateOnly(_startDate),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await PayLaterRepository.instance.getPayLaterList(
      customerName: _customerNameCtrl.text.trim(),
      accountNumber: _accountCtrl.text.trim(),
      crfNumber: _crfCtrl.text.trim(),
      scheduledStartDate: _fmt(_startDate),
      scheduledEndDate: _fmt(_endDate),
      status: _status,
      employeeId: _employeeId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Keep the LOVs once the server has provided them.
      if (r.employees.isNotEmpty) _employees = r.employees;
      if (r.statuses.isNotEmpty) _statuses = r.statuses;
      if (r.statusCode == 0) {
        _results = r.schedules;
        _error = false;
      } else if (r.statusCode == 1) {
        _results = const []; // no records (Android shows the no-records view)
        _error = false;
        _message = r.statusMessage;
      } else {
        _results = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  void _clear() {
    setState(() {
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _employeeId = '';
      _status = '';
      _customerNameCtrl.clear();
      _accountCtrl.clear();
      _crfCtrl.clear();
    });
    _search();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => MainFrame(
    dark: _SchedulePalette.of(context).isDark,
    child: _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final p = _SchedulePalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // ↓ Shrinks the body when the keyboard appears so nothing overflows.
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: p.pageGradient),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleRow(context, p),
              // ↓ The filter card scrolls when the keyboard opens, preventing
              //   the "bottom overflowed" error on any screen size. Its height
              //   is capped so the results header and at least ~70 px of
              //   results stay visible on small phones.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(0.0, box.maxHeight - 190),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  child: _filterCard(p),
                ),
              ),
              _resultsHeader(p),
              Expanded(child: _resultArea(p)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Page title (back + title + subtitle) ─────────────────────────────────
  Widget _titleRow(BuildContext context, _SchedulePalette p) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          if (canPop) ...[
            Material(
              color: p.backBg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: p.titleText,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Collection schedule',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: p.titleText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Scheduled and pay-later collections',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: p.subtitleText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filters card ─────────────────────────────────────────────────────────
  Widget _filterCard(_SchedulePalette p) {
    const gap = SizedBox(height: 12);
    const hGap = SizedBox(width: 10);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: p.cardBorder,
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Filters',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateField('Start date', _fmt(_startDate), _pickStart),
              ),
              hGap,
              Expanded(child: _dateField('End date', _fmt(_endDate), _pickEnd)),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(child: _employeeDropdown()),
              hGap,
              Expanded(child: _statusDropdown()),
            ],
          ),
          gap,
          _textField(
            'Customer name',
            _customerNameCtrl,
            hint: 'Search by name',
            icon: Icons.account_circle_outlined,
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: _textField(
                  'Account number',
                  _accountCtrl,
                  hint: 'Optional',
                  icon: Icons.credit_card_outlined,
                ),
              ),
              hGap,
              Expanded(
                child: _textField(
                  'CRF number',
                  _crfCtrl,
                  hint: 'Optional',
                  icon: Icons.description_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _searchButton()),
              hGap,
              Expanded(child: _clearButton()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchButton() {
    final enabled = !_loading;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? _search : null,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Search',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _clearButton() {
    final red = p.clearText;
    return Opacity(
      opacity: _loading ? 0.6 : 1,
      child: Material(
        color: p.clearBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _loading ? null : _clear,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restart_alt_rounded, color: red, size: 20),
                SizedBox(width: 6),
                Text(
                  'Clear',
                  style: TextStyle(
                    color: red,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Results header + list ────────────────────────────────────────────────
  Widget _resultsHeader(_SchedulePalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Results',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: p.titleText,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p.pillBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Total ${_results.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: p.pillText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultArea(_SchedulePalette p) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: p.titleText));
    }
    if (_error) {
      // Scrolls instead of overflowing on small phones (MainFrame bars).
      return CenterOrScroll(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: p.subtitleText,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _message.isEmpty ? 'Could not load schedules' : _message,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.titleText, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.isLight ? AppColors.primary : Colors.white,
                  foregroundColor: p.isLight ? Colors.white : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No schedules found',
          style: TextStyle(color: p.subtitleText, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _results.length,
      itemBuilder: (_, i) => _ScheduleCard(schedule: _results[i], palette: p),
    );
  }

  // ── Form fields ──────────────────────────────────────────────────────────
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: p.labelText,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  BoxDecoration get _fieldBox => BoxDecoration(
    color: p.fieldBg,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: p.fieldBorder),
  );

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Ink(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: _fieldBox,
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: p.iconColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A field that looks like the other inputs and opens a bottom sheet to
  /// pick one option (replaces the old dropdown).
  Widget _pickerField({
    required String label,
    required IconData icon,
    required String sheetTitle,
    required String value,
    required List<_PickOption> options,
    required ValueChanged<String> onChanged,
  }) {
    final selected = options.firstWhere(
      (o) => o.value == value,
      orElse: () => options.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              FocusScope.of(context).unfocus();
              final picked = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _PickerSheet(
                  title: sheetTitle,
                  icon: icon,
                  options: options,
                  selected: selected.value,
                ),
              );
              if (picked != null && mounted) onChanged(picked);
            },
            child: Ink(
              height: 46,
              padding: const EdgeInsets.only(left: 10, right: 8),
              decoration: _fieldBox,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: p.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: p.iconColor),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusDropdown() {
    // Keep the selection valid if the server's list changes.
    final value = _status.isEmpty || _statuses.contains(_status) ? _status : '';
    return _pickerField(
      label: 'Status',
      icon: Icons.sync_rounded,
      sheetTitle: 'Select status',
      value: value,
      options: [
        const _PickOption('', 'All statuses'),
        ..._statuses
            .where((s) => s.isNotEmpty)
            .toSet()
            .map((s) => _PickOption(s, s)),
      ],
      onChanged: (v) => setState(() => _status = v),
    );
  }

  Widget _employeeDropdown() {
    final value =
        _employeeId.isEmpty || _employees.any((e) => e.id == _employeeId)
        ? _employeeId
        : '';
    return _pickerField(
      label: 'Employee',
      icon: Icons.person_outline_rounded,
      sheetTitle: 'Select employee',
      value: value,
      options: [
        const _PickOption('', 'All employees'),
        ..._employees.map((e) => _PickOption(e.id, e.name)),
      ],
      onChanged: (v) => setState(() => _employeeId = v),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    required String hint,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        SizedBox(
          height: 46,
          child: TextField(
            controller: ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loading ? null : _search(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: p.hintText,
              ),
              prefixIcon: Icon(icon, size: 18, color: p.iconColor),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 20,
              ),
              filled: true,
              fillColor: p.fieldBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
              isDense: true,
              border: border(p.fieldBorder),
              enabledBorder: border(p.fieldBorder),
              focusedBorder: border(AppColors.secondary, 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Theme-aware colours for this screen ──────────────────────────────────────
// Theme 1 (Default Blue): blue gradient page, white text on the page.
// Theme 2 (Premium Light): pearl page, navy text on the page.
// The filter and result cards are white in both themes.
class _SchedulePalette {
  /// Theme 2 (Premium Light) look. False in Theme 1 and in dark mode.
  final bool isLight;

  /// Phone is in dark mode (this screen only; the rest of the app is unchanged).
  final bool isDark;
  const _SchedulePalette._(this.isLight, this.isDark);

  factory _SchedulePalette.of(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return _SchedulePalette._(!dark && AppThemeConst.of(context).isLight, dark);
  }

  static const Color navy = Color(0xFF1A3C6E);

  // ── Text / icons on cards and fields ──
  Color get ink => isDark ? const Color(0xFFE8EEFA) : const Color(0xFF0F2350);
  Color get labelText =>
      isDark ? const Color(0xFFA9B6D3) : const Color(0xFF3B4A6B);
  Color get hintText =>
      isDark ? const Color(0xFF6F7E9E) : const Color(0xFF94A0B8);
  Color get iconColor =>
      isDark ? const Color(0xFF8E9CBC) : const Color(0xFF5B6B8C);

  // ── Surfaces ──
  Color get surface => isDark ? const Color(0xFF16213A) : Colors.white;
  Color get fieldBg =>
      isDark ? const Color(0xFF1E2A45) : const Color(0xFFF3F6FC);
  Color get fieldBorder =>
      isDark ? const Color(0xFF2A3856) : const Color(0xFFE2E8F4);
  Color get handle =>
      isDark ? const Color(0xFF33415F) : const Color(0xFFD6DCE8);

  /// Blue for amounts / selected items (lighter on dark so it stays readable).
  Color get accent => isDark ? const Color(0xFF7DB2FF) : AppColors.primary;

  // ── Clear button ──
  // Dark mode: white button with red text/icon.
  Color get clearBg => isDark ? Colors.white : const Color(0xFFFDECEC);
  Color get clearText => const Color(0xFFC62828);

  // ── Page ──
  Gradient get pageGradient {
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0B1426), Color(0xFF101C36)],
      );
    }
    return isLight
        ? const LinearGradient(colors: [Color(0xFFF5F7FF), Color(0xFFF5F7FF)])
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.secondary],
          );
  }

  Color get titleText => isLight ? navy : Colors.white;
  Color get subtitleText =>
      isLight ? AppColors.textSecondary : Colors.white.withValues(alpha: 0.72);
  Color get backBg => isLight
      ? navy.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: isDark ? 0.10 : 0.16);
  Color get pillBg => isLight
      ? navy.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: isDark ? 0.12 : 0.20);
  Color get pillText => isLight ? navy : Colors.white;
  Color get shadow => isLight
      ? navy.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: isDark ? 0.35 : 0.14);
  Border? get cardBorder {
    if (isDark) return Border.all(color: const Color(0xFF24314F));
    return isLight ? Border.all(color: const Color(0xFFDDE3F5)) : null;
  }
}

class _ScheduleCard extends StatelessWidget {
  final PayLaterSchedule schedule;
  final _SchedulePalette palette;
  const _ScheduleCard({required this.schedule, required this.palette});

  static final NumberFormat _money = NumberFormat('#,##,##0.00', 'en_IN');

  String get _initials {
    final words = schedule.customerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  String get _amount {
    final raw = schedule.amount.trim();
    final v = double.tryParse(raw.replaceAll(',', ''));
    return v == null ? raw : _money.format(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final name = schedule.customerName.trim().isEmpty
        ? 'NA'
        : schedule.customerName.trim();
    final status = schedule.status.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: palette.cardBorder,
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: p.ink,
                  ),
                ),
                if (schedule.altCustomNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    schedule.altCustomNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.labelText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _StatusChip(status: status),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (schedule.amount.trim().isNotEmpty)
                Text(
                  '₹$_amount',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: p.accent,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 14,
                    color: p.iconColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    schedule.scheduledDate,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: p.labelText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color fg;
    final IconData icon;
    if (s.contains('collect') || s.contains('paid') || s.contains('complete')) {
      fg = const Color(0xFF16A34A);
      icon = Icons.check_circle_rounded;
    } else if (s.contains('cancel') ||
        s.contains('fail') ||
        s.contains('reject')) {
      fg = const Color(0xFFDC2626);
      icon = Icons.cancel_rounded;
    } else if (s.contains('pend') || s.contains('schedul')) {
      fg = const Color(0xFFEA580C);
      icon = Icons.schedule_rounded;
    } else {
      fg = const Color(0xFF475569);
      icon = Icons.circle_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom-sheet picker (Employee / Status) ──────────────────────────────────
class _PickOption {
  final String value;
  final String label;
  const _PickOption(this.value, this.label);
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<_PickOption> options;
  final String selected;
  const _PickerSheet({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  _SchedulePalette get p => _SchedulePalette.of(context);

  /// Lists longer than this get a search box.
  static const int _searchFrom = 8;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final showSearch = widget.options.length > _searchFrom;
    final q = _query.trim().toLowerCase();
    // The current choice is pinned above the list (stays visible while the
    // list scrolls) and left out of the list below. "All …" is not pinned.
    _PickOption? pinned;
    if (widget.selected.isNotEmpty) {
      for (final o in widget.options) {
        if (o.value == widget.selected) {
          pinned = o;
          break;
        }
      }
    }
    final items = widget.options
        .where((o) => o != pinned)
        .where((o) => q.isEmpty || o.label.toLowerCase().contains(q))
        .toList();
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
              // Title centred on the sheet; close button on the right.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      widget.title,
                      // Long titles wrap onto the next line (below the X)
                      // instead of being cut off.
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: p.iconColor),
                    ),
                  ),
                ],
              ),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(color: p.hintText),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: p.iconColor,
                      ),
                      filled: true,
                      fillColor: p.fieldBg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.fieldBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.fieldBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.secondary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (pinned != null) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text(
                  'SELECTED',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: p.labelText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _optionTile(pinned),
              ),
              Divider(
                height: 12,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: p.fieldBorder,
              ),
            ],
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No matches',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.labelText),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        16 + media.padding.bottom,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _optionTile(items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(_PickOption o) {
    final isSelected = o.value == widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? p.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).pop(o.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : p.fieldBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: isSelected ? Colors.white : p.iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    o.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected ? p.accent : p.ink,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: p.accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom-sheet calendar (Start / End date) ─────────────────────────────────
class _DateSheet extends StatefulWidget {
  final String title;
  final DateTime initial;
  final DateTime first;
  final DateTime last;
  const _DateSheet({
    required this.title,
    required this.initial,
    required this.first,
    required this.last,
  });

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  _SchedulePalette get p => _SchedulePalette.of(context);

  late DateTime _selected = DateUtils.dateOnly(widget.initial);
  int _calendarKey = 0; // bump to jump the calendar to a new month

  static final DateFormat _nice = DateFormat('EEE, d MMM yyyy');

  void _jumpTo(DateTime d) => setState(() {
    _selected = DateUtils.dateOnly(d);
    _calendarKey++;
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final todayAllowed =
        !today.isBefore(DateUtils.dateOnly(widget.first)) &&
        !today.isAfter(widget.last);

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: 12 + media.padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _nice.format(_selected),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: p.iconColor),
                  ),
                ],
              ),
            ),
            if (todayAllowed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    _quickChip('Today', today),
                    const SizedBox(width: 8),
                    if (!today
                        .subtract(const Duration(days: 1))
                        .isBefore(DateUtils.dateOnly(widget.first)))
                      _quickChip(
                        'Yesterday',
                        today.subtract(const Duration(days: 1)),
                      ),
                  ],
                ),
              ),
            Container(
              height: 216,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                color: p.fieldBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  primaryColor: AppColors.primary,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: ValueKey(_calendarKey),
                  mode: CupertinoDatePickerMode.date,
                  dateOrder: DatePickerDateOrder.dmy,
                  initialDateTime: _selected,
                  minimumDate: DateUtils.dateOnly(widget.first),
                  maximumDate: widget.last,
                  onDateTimeChanged: (d) =>
                      setState(() => _selected = DateUtils.dateOnly(d)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SizedBox(
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(_selected),
                      child: const Center(
                        child: Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(String label, DateTime date) {
    final on = DateUtils.isSameDay(_selected, date);
    return Material(
      color: on ? AppColors.primary : p.fieldBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _jumpTo(date),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : p.labelText,
            ),
          ),
        ),
      ),
    );
  }
}
