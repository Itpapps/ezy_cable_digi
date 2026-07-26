import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/settings_store.dart';
import '../../core/theme/theme_constants.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _header1      = TextEditingController();
  final _header2      = TextEditingController();
  final _footer1      = TextEditingController();
  final _footer2      = TextEditingController();
  final _amountFilter = TextEditingController(text: '500.0');

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    await SettingsStore.instance.load();
    if (!mounted) return;
    final s = SettingsStore.instance;
    setState(() {
      _header1.text = s.header1;
      _header2.text = s.header2;
      _footer1.text = s.footer1;
      _footer2.text = s.footer2;
      _amountFilter.text = s.amtFilter.toString();
    });
  }

  // Persist all five (Android PrinterSetting_Fragment Submit → settings_Pref +
  // restart). Flutter reads them fresh when building each receipt, so no restart.
  Future<void> _save() async {
    final amt = double.tryParse(_amountFilter.text.trim()) ?? 500.0;
    await SettingsStore.instance.save(
      header1: _header1.text.trim(),
      header2: _header2.text.trim(),
      footer1: _footer1.text.trim(),
      footer2: _footer2.text.trim(),
      amtFilter: amt,
    );
    if (!mounted) return;
    _amountFilter.text = amt.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Printer settings saved')),
    );
  }

  void _confirmSave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Are you sure you want to submit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _save();
            },
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _header1.dispose();
    _header2.dispose();
    _footer1.dispose();
    _footer2.dispose();
    _amountFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SETTINGS',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.2, color: t.appBarFg),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        child: Column(
          children: [
            // ── Settings card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: t.cardBorderRadius,
                boxShadow: [
                  BoxShadow(
                    color: t.cardShadowColor,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title
                  Row(
                    children: [
                      Container(
                        width: 4, height: 18,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PRINTER SETTINGS',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: t.cardHeadingText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.paddingL),
                  _textField(context, 'Header 1', _header1, t),
                  const SizedBox(height: AppSizes.paddingS),
                  _textField(context, 'Header 2', _header2, t),
                  const SizedBox(height: AppSizes.paddingS),
                  _textField(context, 'Footer 1', _footer1, t),
                  const SizedBox(height: AppSizes.paddingS),
                  _textField(context, 'Footer 2', _footer2, t),
                ],
              ),
            ),

            const SizedBox(height: AppSizes.paddingM),

            // ── Amount filter card ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: t.cardBorderRadius,
                boxShadow: [
                  BoxShadow(color: t.cardShadowColor, blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4, height: 18,
                        decoration: BoxDecoration(
                          color: t.accent, borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'AMOUNT FILTER SETTINGS',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, color: t.cardHeadingText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  _textField(
                    context,
                    'Enter Amount to set filter',
                    _amountFilter, t,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSizes.paddingL),

            // ── Action buttons ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('SUBMIT',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: AppSizes.paddingS),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Android Clear wipes only the header/footer fields
                      // (PrinterSetting_Fragment:125-128) — not the amount, not prefs.
                      _header1.clear();
                      _header2.clear();
                      _footer1.clear();
                      _footer2.clear();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Clear',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(BuildContext context, String label, TextEditingController controller,
      AppThemeConst t, {TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.cardSubtitleText)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: t.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.inputBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.inputBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
