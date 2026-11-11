import 'package:flutter/material.dart';

import '../../core/widgets/premium_dialog.dart';
import 'data/search_repository.dart';

/// D-B6: Android's first Dealer dropdown item (id 0). For a common employee
/// the server then searches all of their mapped dealers (wsmodel searchCustomer).
const SearchDealer kSelectDealer = SearchDealer(0, '----Select Dealer----');

/// D-B6 / Android Getmappeddealersru (SearchCustomer_Fragment_Newdesign
/// :701-876, ScannerFrag :440-530), run when Search or Scan opens for a common
/// employee. Shows Android's non-cancellable "Getting Dealers list,   Please
/// wait..." loader, then:
///  • status 0 → "----Select Dealer----" followed by the mapped dealers;
///  • transport failure (Android's null response) → "Server is Un reachable!"
///    dialog, and OK closes the screen (Android popBackStack);
///  • status 1 → "{message}: Dealers not Loaded"; status 2 → "{message}:
///    Contact Support" (the dropdown keeps only "----Select Dealer----").
/// Returns the dropdown items, or null when nothing should change (the screen
/// was closed / left).
Future<List<SearchDealer>?> loadSearchDealers(BuildContext context) async {
  showPremiumLoading(context,
      message: 'Getting Dealers list,   Please wait...', canPop: false);
  final r = await SearchRepository.instance.fetchMappedDealers(); // never throws
  if (!context.mounted) return null;
  Navigator.of(context).pop(); // close the loader

  switch (r.statusCode) {
    case 0:
      return [kSelectDealer, ...r.dealers];
    case 1:
      showPremiumSnackBar(context, '${r.statusMessage}: Dealers not Loaded',
          isError: true);
      return null;
    case 2:
      showPremiumSnackBar(context, '${r.statusMessage}: Contact Support',
          isError: true);
      return null;
    default:
      final screen = Navigator.of(context);
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Server is Un reachable!'),
          content:
              const Text('Please check your Internet connection and try again.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                screen.pop(); // Android getFragmentManager().popBackStack()
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
  }
}
