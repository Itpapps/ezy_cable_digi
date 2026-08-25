import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/pay_later_repository.dart';

/// Per-customer Pay Later (Android `gethitapipaylater` dialog) — shared by the
/// payment screen and Customer Details. Looks up the customer's schedule
/// (`scheduled_collection_data`), shows the Schedule-Collection create/edit
/// dialog (status LOV + date + remarks), then submits
/// (`scheduled_collection_create`). Reuses [PayLaterRepository] — no new APIs.
Future<void> showPayLaterScheduleDialog(
    BuildContext context, Customer customer) async {
  // Android sends the SYSTEM customer id (altCustId/custid = JSON customer_id =
  // Flutter lcoCustomerId), NOT alt_cust_id — the server rejects a non-integer
  // id with "customer id is not a integer or not valid". Guard empty up front.
  final cid = customer.lcoCustomerId.trim();
  if (cid.isEmpty) {
    showPremiumSnackBar(
        context, 'Customer id not available for Pay Later.', isError: true);
    return;
  }
  showPremiumLoading(context, message: 'Fetching Details, Please wait');
  final lookup = await PayLaterRepository.instance.getPayLaterList(
    customerId: cid,
    scheduledStartDate: '',
    scheduledEndDate: '',
  );
  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss loading

  if (lookup.statusCode == 3) {
    showPremiumSnackBar(context, lookup.statusMessage, isError: true);
    return;
  }
  final record = lookup.schedules.isNotEmpty ? lookup.schedules.first : null;
  if (record == null) {
    showPremiumSnackBar(
        context,
        lookup.statusMessage.isEmpty
            ? 'No schedule details found'
            : lookup.statusMessage,
        isError: true);
    return;
  }
  final statuses =
      lookup.statuses.isNotEmpty ? lookup.statuses : const ['Scheduled'];

  final remarksCtrl = TextEditingController(text: record.remarks);
  DateTime scheduleDate = _parseYmd(record.scheduledDate) ?? DateTime.now();
  String status =
      statuses.contains(record.status) ? record.status : statuses.first;

  final ok = await showPremiumDialog<bool>(
    context: context,
    child: PremiumDialogShell(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: StatefulBuilder(
            builder: (ctx, setD) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Iconsax.clock,
                          color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text('Schedule Collection',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.user,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        items: statuses
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setD(() => status = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: scheduleDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setD(() => scheduleDate = picked);
                        },
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month,
                                  size: 15, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                '${scheduleDate.day.toString().padLeft(2, '0')}-'
                                '${scheduleDate.month.toString().padLeft(2, '0')}-'
                                '${scheduleDate.year}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarksCtrl,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Remarks (optional)',
                    hintStyle:
                        TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(ctx, false);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('CANCEL',
                            style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(ctx, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(record.isEditable == '1' ? 'UPDATE' : 'SUBMIT',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      ),
    ),
  );

  if (ok != true || !context.mounted) return;

  showPremiumLoading(context, message: 'Scheduling collection...');
  final res = await PayLaterRepository.instance.submitPayLater(
    customerId: record.customerId,
    scheduledDate:
        '${scheduleDate.year}-${scheduleDate.month.toString().padLeft(2, '0')}-'
        '${scheduleDate.day.toString().padLeft(2, '0')}',
    status: status,
    remarks: remarksCtrl.text.trim(),
    isEdited: record.isEditable,
  );
  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss loading
  await _resultDialog(context, res.success, res.message);
}

DateTime? _parseYmd(String s) {
  final p = s.split('-');
  if (p.length < 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2].length > 2 ? p[2].substring(0, 2) : p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

Future<void> _resultDialog(BuildContext context, bool success, String message) {
  return showPremiumDialog<void>(
    context: context,
    child: PremiumDialogShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red, size: 44),
            const SizedBox(height: 12),
            Text(success ? 'Success' : 'Fail!',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(message.isEmpty ? (success ? 'Scheduled' : 'Failed') : message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('OK',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
