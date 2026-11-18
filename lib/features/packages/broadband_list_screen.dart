import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/broadband_plan.dart';
import 'data/broadband_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Renew BroadBand — Android parity (`BroadBandList` fragment). Opens from the
/// Customer Operations "Renew BroadBand" tile: fetches the plan + expiry list
/// (`broadband_expiry_list`), shows the current plan, and renews
/// (`broadband_renew_customers`). On success Android pops back to the customer.
class BroadBandListScreen extends StatefulWidget {
  final Customer customer;
  const BroadBandListScreen({super.key, required this.customer});

  @override
  State<BroadBandListScreen> createState() => _BroadBandListScreenState();
}

class _BroadBandListScreenState extends State<BroadBandListScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  BroadbandExpiryResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await BroadbandRepository.instance
        .fetchExpiryList(widget.customer.broadbandUserId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _result = r;
      } else {
        _error = r.statusMessage.isEmpty ? 'Could not load plan.' : r.statusMessage;
      }
    });
  }

  Future<void> _renew() async {
    if (_busy) return;
    // Android confirm (BroadBandList:97).
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Renew!',
      body: 'Are you sure you want to renew the broadband plan?',
      confirmLabel: 'OK',
      cancelLabel: 'CANCEL',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    // Android uses the renewed-list broadband_user_id; fall back to the customer's.
    final bbId = (_result?.renewedList.isNotEmpty ?? false)
        ? _result!.renewedList.first.broadbandUserId
        : widget.customer.broadbandUserId;
    // Android BroadBandList :170 (ApiCallRestClient.callPostApi): a
    // non-cancellable "Fetching Details, Please wait" while the renewal runs.
    // It also keeps the header / bottom bar / drawer from opening another
    // screen meanwhile — the success pop below must close THIS screen.
    showPremiumLoading(context,
        message: 'Fetching Details, Please wait', canPop: false);
    final res = await BroadbandRepository.instance.renewBroadband(
      broadbandUserId: bbId.isEmpty ? widget.customer.broadbandUserId : bbId,
      customerId: widget.customer.lcoCustomerId,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _busy = false);
    if (res.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    // Android shows a bare "Fail!" for EVERY non-success renew response. But a
    // duplicate / already-in-progress rejection (RENEW tapped again while the
    // first renewal is still being processed by the backend) is NOT a true
    // failure. We keep the backend's own status_message as the source of truth
    // and only replace the alarming "Fail!" verdict with a neutral title, so an
    // "already in progress" response no longer reads as a lost/failed renewal.
    // Genuine backend errors still surface verbatim via the server message, and
    // we never claim success. Intentional, scoped divergence from Android's
    // "Fail!" title (renewal logic + navigation are unchanged).
    final renewOk = res.statusCode == 0;
    await showPremiumConfirm(
      context: context,
      title: renewOk ? 'Success' : 'Renewal Status',
      body: res.message.trim().isNotEmpty
          ? res.message
          : (renewOk
              ? 'Success'
              : "We couldn't confirm the renewal. If you just submitted one, it "
                  'may already be processing — please refresh before trying '
                  'again.'),
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
    if (renewOk && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('RENEW BROADBAND'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _errorView()
              : _content(),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _content() {
    final current =
        (_result?.renewedList.isNotEmpty ?? false) ? _result!.renewedList.first : null;
    final expiry = _result?.expiryList ?? const <BroadBandPlan>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.customer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  _row('Plan', current?.lastPurchasedPlanName ?? '—'),
                  _row('MRP', current?.mrp ?? '—'),
                  _row('Start', current?.startDate ?? '—'),
                  _row('Expiry', current?.endDate ?? '—'),
                ],
              ),
            ),
          ),
        ),
        if (expiry.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: expiry.length,
              itemBuilder: (context, i) {
                final p = expiry[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(p.lastPurchasedPlanName.isEmpty
                        ? p.subscriberName
                        : p.lastPurchasedPlanName),
                    subtitle: Text('₹${p.mrp} · ${p.startDate} → ${p.endDate}'),
                    trailing: Text(p.subscriberStatus),
                  ),
                );
              },
            ),
          )
        else
          const Expanded(child: SizedBox.shrink()),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _busy ? null : _renew,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('RENEW',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
