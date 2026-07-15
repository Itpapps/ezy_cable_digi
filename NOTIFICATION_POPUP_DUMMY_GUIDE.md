# Login Notification Popup — Dummy Build Guide (Demo Only)

**Status:** DUMMY prototype for a demo video. No API yet. Hardcoded data.
**Goal:** After login → Dashboard appears → a modal popup shows ("Notifications" title,
long scrollable body, single blue OK). OK closes it, Dashboard stays. Nothing else.

**Design rule:** dummy → API must change only ONE method later (the repository).

---

## Architecture (3 new files + 1 edit)

```
lib/
  core/widgets/premium_dialog.dart          ← REUSE (already exists: showPremiumDialog)
  features/
    dashboard/dashboard_screen.dart         ← EDIT (add the trigger in initState)
    notifications/
      data/
        login_notification.dart             ← NEW  (model = the data shape)
        notification_repository.dart         ← NEW  (data source: dummy now, API later)
      login_notification_dialog.dart         ← NEW  (the popup UI)
```

Responsibilities:
- **Model** = the shape of the data (title + body). Shared by dummy and API.
- **Repository** = WHERE the data comes from. The ONLY file that changes for the API.
- **Dialog** = HOW it looks. Doesn't care if data is dummy or API.
- **Dashboard edit** = WHEN it shows (after the first frame, once).

---

## STEP 1 — Model  `lib/features/notifications/data/login_notification.dart`

```dart
/// The data shape of a login notification.
/// DUMMY today; later the API JSON is parsed into this SAME class,
/// so the dialog and the dashboard trigger never change.
class LoginNotification {
  final String title;
  final String body;

  const LoginNotification({
    required this.title,
    required this.body,
  });
}
```
Why: one shared "shape" so dummy and API are interchangeable.

---

## STEP 2 — Repository  `lib/features/notifications/data/notification_repository.dart`

```dart
import 'login_notification.dart';

/// The ONE seam between dummy data and the future API.
/// Today: returns a hardcoded LoginNotification.
/// Later: replace ONLY the body of fetchLoginNotification() with the API call.
class NotificationRepository {
  NotificationRepository._();
  static final NotificationRepository instance = NotificationRepository._();

  Future<LoginNotification?> fetchLoginNotification() async {
    // ── DUMMY DATA (paste your long text between the triple quotes) ──
    return const LoginNotification(
      title: 'Notifications',
      body: '''Dear LCOs,

Bill deletion requests will be accepted only until the evening of the 26th of
every month. Any requests submitted after this will be processed next month.

Magikdigi-ൽ broadband customer unmapping option available ആയിട്ടുണ്ട്.
Path : Broadband > Customer Operation > Unmap customer.

Note :- Broadband payment ചെയ്യുമ്പോൾ ശ്രദ്ധിച്ചു മാത്രം ചെയ്യുക.

Magik-Digi support land phone number : 0480-2080005

(Add many more lines here to test scrolling.)''',
    );

    // To show NO popup, return null instead:
    // return null;
  }
}
```
Why: the dashboard always calls this method. Swapping to the API = editing only
inside this method. Singleton pattern matches the app's other services.

---

## STEP 3 — Dialog UI  `lib/features/notifications/login_notification_dialog.dart`

```dart
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'data/login_notification.dart';

/// The login-notification popup card (matches the web: blue title bar,
/// scrollable body, single blue OK). Overflow-proof by construction.
class LoginNotificationDialog extends StatelessWidget {
  final LoginNotification notification;
  const LoginNotificationDialog({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    // Cap the height so a very long notice can never grow past the screen.
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,             // card only as tall as needed
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Title bar (blue) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: AppColors.primary,
              child: Text(
                notification.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // ── Scrollable body (the long text) ──
            Flexible(                                   // takes leftover space only
              child: SingleChildScrollView(             // long text SCROLLS, no overflow
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  notification.body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),

            // ── Single blue OK button (closes the popup only) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```
Why each part:
- `ConstrainedBox(maxHeight)` → card can never exceed 70% of screen.
- `Column(mainAxisSize.min)` → card hugs its content up to that cap.
- `Flexible` → gives the scroll area the *leftover* height so OK is never pushed off.
- `SingleChildScrollView` → long body scrolls instead of overflowing (no RenderFlex).
- OK → `Navigator.of(context).pop()` closes ONLY the dialog; Dashboard stays.

---

## STEP 4 — Trigger  EDIT  `lib/features/dashboard/dashboard_screen.dart`

### 4a. Add imports at the top (with the other imports)
```dart
import '../../core/widgets/premium_dialog.dart';
import '../notifications/data/notification_repository.dart';
import '../notifications/login_notification_dialog.dart';
```

### 4b. Add a guard field in the State class (near the other fields)
```dart
bool _notificationShown = false;
```

### 4c. In initState (currently ~line 154), add ONE line at the END of the method
Existing initState looks like:
```dart
  void initState() {
    super.initState();
    LocationSyncService.instance.onScreenOpened(TrackingScreen.dashboard);
    _dash.addListener(_onDash);
    _dash.loadKpis();
    _dash.loadWallet();
    _dash.loadComplaints();
    // ADD THIS LINE:
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showLoginNotification());
  }
```

### 4d. Add this method inside the State class (anywhere among the methods)
```dart
  // ── DUMMY login notification popup (demo only). Comment out the
  // addPostFrameCallback line in initState to disable until the API is ready. ──
  Future<void> _showLoginNotification() async {
    if (_notificationShown || !mounted) return;   // show once, and only if alive
    _notificationShown = true;

    final n = await NotificationRepository.instance.fetchLoginNotification();
    if (n == null || !mounted) return;             // no notice, or screen gone → stop

    await showPremiumDialog<void>(
      context: context,
      barrierDismissible: false,                    // must press OK (no tap-outside)
      child: LoginNotificationDialog(notification: n),
    );
  }
```
Why:
- `addPostFrameCallback` → runs AFTER the first frame, so the Dashboard is painted
  behind the popup and the dialog has a valid overlay.
- `_notificationShown` flag → shows exactly once per login (no duplicates).
- `if (!mounted)` before/after the `await` → the screen could be disposed during the
  async wait; using a dead context would crash. This guards it.
- `showPremiumDialog` (reused) → the app's standard animated, dimmed dialog wrapper.
- `barrierDismissible: false` → only OK closes it (matches the web).

---

## STEP 5 — Run & test

1. `flutter analyze`  → must be clean.
2. Run the app, log in.
3. Dashboard appears → popup appears.
4. Body scrolls smoothly (paste a very long body in STEP 2 to verify).
5. Tap OK → popup closes → Dashboard stays. Done.

Test on: small phone, large phone, tablet, landscape, and 2.0× font
(Settings → Display → Font size). The body should scroll; nothing overflows.

---

## To DISABLE later (until the API is ready)
Comment out the ONE line in STEP 4c (the `addPostFrameCallback`). The three new
files can stay unused. Nothing else to touch.

## To go LIVE with the API later
Edit ONLY `NotificationRepository.fetchLoginNotification()` (STEP 2): call the
server (RestClient/SoapClient), parse JSON into a `LoginNotification`, return it
(or `null` when there's no active notice). The model, dialog, and trigger stay
exactly the same.

---

## Progress checklist
- [x] STEP 1 — model created (`login_notification.dart`)
- [x] STEP 2 — repository created (dummy) (`notification_repository.dart`)
- [x] STEP 3 — dialog widget created (`login_notification_dialog.dart`)
- [x] STEP 4 — dashboard trigger added (`dashboard_screen.dart` initState)
- [ ] STEP 5 — YOU test: log in → popup → scroll → OK → dashboard stays
