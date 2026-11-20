import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/customer_box.dart';
import 'data/ott_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// OTT — Android parity (`OTTFragment` + `OTTAdapter`). Lists the customer's OTT
/// boxes; tapping one opens a change-credentials dialog (UserName / Password)
/// that calls `ott_change_username` / `ott_change_password`.
class OttScreen extends StatefulWidget {
  final Customer customer;
  final List<CustomerBox> ottBoxes;
  const OttScreen({super.key, required this.customer, required this.ottBoxes});

  @override
  State<OttScreen> createState() => _OttScreenState();
}

class _OttScreenState extends State<OttScreen> {
  bool _busy = false;

  // Owned by the State, NOT by _showChangeDialog. showPremiumDialog has a 260ms
  // exit transition, so the TextFields stay mounted after Navigator.pop returns.
  // A controller disposed inside the method is therefore used after disposal.
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _valueCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _showChangeDialog(CustomerBox box) async {
    var mode = 'UserName'; // Android spinner: UserName | Password
    _valueCtrl.clear();
    _confirmCtrl.clear();
    final submitted = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: StatefulBuilder(
            builder: (ctx, setDlg) {
              final isUser = mode == 'UserName';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OTT · Box ${box.boxNumber}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Change',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'UserName', child: Text('UserName')),
                      DropdownMenuItem(value: 'Password', child: Text('Password')),
                    ],
                    onChanged: (v) => setDlg(() {
                      mode = v ?? 'UserName';
                      _valueCtrl.clear();
                      _confirmCtrl.clear();
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _valueCtrl,
                    obscureText: !isUser,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: isUser ? 'UserName' : 'Password',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: !isUser,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: isUser ? 'Confirm UserName' : 'Confirm Password',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            // Android validation: len >= 4 and value == confirm.
                            final v = _valueCtrl.text;
                            final c = _confirmCtrl.text;
                            final noun = isUser ? 'UserName' : 'Password';
                            if (v.length < 4) {
                              showPremiumSnackBar(
                                  ctx, 'Please enter valid $noun',
                                  isError: true);
                              return;
                            }
                            if (c.length < 4) {
                              showPremiumSnackBar(
                                  ctx, 'Please enter valid Confirm $noun',
                                  isError: true);
                              return;
                            }
                            if (v != c) {
                              showPremiumSnackBar(ctx,
                                  '$noun & Confirm $noun should be same',
                                  isError: true);
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('SUBMIT'),
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
    );

    final value = _valueCtrl.text;
    final isUser = mode == 'UserName';
    if (submitted != true || !mounted) return;

    setState(() => _busy = true);
    final res = isUser
        ? await OttRepository.instance
            .changeUsername(boxId: box.boxId, username: value)
        : await OttRepository.instance
            .changePassword(boxId: box.boxId, password: value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    await showPremiumConfirm(
      context: context,
      title: res.statusCode == 0 ? 'Success' : 'Fail!',
      body: res.message.trim().isEmpty
          ? (res.statusCode == 0 ? 'Success' : 'Failed')
          : res.message,
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    // Theme-aware page: Theme 1 keeps the same blue page + white text.
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 40, // compact, same as Customer / Payment Details
        title: const Text('OTT',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(widget.customer.name,
                style: TextStyle(
                    color: t.headingText,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,),),
          ),
          Expanded(
            child: widget.ottBoxes.isEmpty
                ? Center(
                    child: Text('No OTT boxes.',
                        style: TextStyle(
                            color: t.isLight
                                ? t.subtitleText
                                : Colors.white70)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: widget.ottBoxes.length,
                    itemBuilder: (context, i) {
                      final b = widget.ottBoxes[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('Box: ${b.boxNumber}'),
                          subtitle: Text('VC: ${b.vcNumber}'),
                          trailing: Text(b.stateLabel,
                              style: TextStyle(
                                  color: b.isActive
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w700)),
                          onTap: _busy ? null : () => _showChangeDialog(b),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
