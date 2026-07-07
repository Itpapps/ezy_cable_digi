# Offline Mode — Incremental Implementation Plan (Phase 3)

> **Do not start until the investigation + this plan are approved.** Incremental, no big-bang.
> Each step ends: `flutter analyze` clean · no warnings · no TODO · no temp logs/debug prints ·
> no commented code · no duplicate logic · repository pattern · reuse existing architecture.
> Steps are ordered by risk and dependency. Each is independently shippable and testable on device.

---

## Decisions needed from you BEFORE coding
1. **Fresh-install offline policy** — match Android's *literal* behaviour (opens empty offline dashboard) **or** Android's *intent* (block when no prior online login)? *(Recommend: block — treat "no saved date" as stale.)*
2. **Auto-sync** — disable `ConnectivityService` to match Android (auto-sync is commented out there)? *(Recommend: disable, keep manual sync.)* Or keep as an approved enhancement?
3. **Error UX style** — Android uses modal dialogs + toasts. Match dialogs exactly, or keep Flutter snackbars with Android's verbatim text? *(Recommend: dialog for the login block; snackbar with Android text elsewhere.)*

---

## Step 1 — Persist last-online-login date (foundation, no behaviour change)
- **Goal:** store the server `current_date` at each successful online login so the offline gate survives process death (Android `current_dates_login`).
- **Change:** in `auth_service.dart` success path, write `serverCurrentDate` to `OfflineModeService` prefs (new key e.g. `offline_last_online_login`). Add getter to `OfflineModeService`.
- **Risk:** none (write-only). **Test:** login online, inspect prefs.
- **Depends on:** nothing.

## Step 2 — Offline-login 2-day gate + field disable (gap #1, HIGH)
- **Goal:** mirror `LoginActivity.java:248-305`.
- **Change:**
  - `login_screen.dart` / `splash_screen.dart`: before routing to `OfflineDashboardScreen`, read the Step-1 date; compute day-difference; `≤2` → offline dashboard; `>2` (or none, per Decision #1) → dialog **"Please go online and sync previous offline collections data"** / title **"Sync Previous data"** → on OK exit the app (`SystemNavigator.pop()`); disable username/password fields when offline.
  - Reuse existing navigation; no new packages.
- **Risk:** Med (changes entry). **Test:** Cases A/B/C + the >2-day stale case on device.
- **Depends on:** Step 1.

## Step 3 — Disable connectivity auto-sync (gap #2)
- **Goal:** match Android (auto-sync disabled).
- **Change:** stop calling `ConnectivityService.startListening()` at app init (and/or make `_onChanged` a no-op). Keep the class for the manual `hasNetwork` utility if used. Remove the `print()` debug line.
- **Risk:** Low. **Test:** reconnect with pending payments → confirm **no** auto-sync; manual sync still works.
- **Depends on:** none. *(Skip if Decision #2 keeps auto-sync.)*

## Step 4 — Consolidate sync services (gap #4, no duplicate logic)
- **Goal:** one sync path.
- **Change:** fold `OfflineSyncService.syncPendingToServer` logic into `OfflineDataService` (single `syncAllPending` + legacy-table marking), update the 4 call sites (`offline_dashboard_screen.dart:64`, `download_records_screen.dart:82`, `miniday_report_screen.dart:83`, `app_drawer.dart:529`) to the one method; delete the wrapper.
- **Risk:** Low-Med (call-site churn). **Test:** sync from each entry point.
- **Depends on:** Step 3 (so only manual paths remain).

## Step 5 — Error-message parity (gap #3, #9)
- **Goal:** verbatim Android texts, no silent failures.
- **Change:** map offline sync/commit results to Android strings (Android doc §9): ACK "Successfully updated ", NAK "Not synced - …", error "Error - Data not synced, please try again." / "Error syncing data. Please contact Customer Care", per-row offline "No Internet Connection.", bulk-empty "No payments has been made (or) Check your internet connection.", clear-guard "Please sync all paid customer before you clear offline data." Ensure every offline screen renders Loading/Success/Empty/Error/Retry explicitly.
- **Risk:** Low. **Test:** force each branch (airplane mode, bad token, empty queue).
- **Depends on:** Step 4.

## Step 6 — Payment-dialog validation parity (gap #7, money-critical)
- **Goal:** confirm/fix partial-pay rule + bank-field mandatoriness with Android texts.
- **Change:** in `offline_payment_dialog.dart`, enforce: amount ≥ total when partial-pay flag set ("Entered payable amount should be greater than or equal to your pending amount" / "Invalid Amount!"); bank mode requires cheque/bank/branch/date ("All fields are mandatory. Please fill bank details."); amount > 0 ("Amount cannot be 0.00 or empty.").
- **Risk:** Med (money). **Test:** cash + bank, partial vs full, on device.
- **Depends on:** none (can parallel Step 5).

## Step 7 — (Optional, Decision-dependent) per-row tap-to-sync + immediate-online-sync (gaps #5, #6)
- **Goal:** match Android's tap-a-paid-row "Do you want to sync this payment?" dialog, and auto-sync a payment taken while online.
- **Risk:** Low. **Test:** pay while online (syncs), tap paid row online (sync dialog).
- **Depends on:** Step 4. *(Lowest priority; confirm if wanted.)*

---

## Stability acceptance (every step)
No crashes / null-derefs · no duplicate sync · no duplicate/lost payment · no SQLite corruption · no infinite retries · no race (single sync path + guard) · no UI freeze (DB/network off the main isolate via sqflite/async) · all repos return Result-style objects · all screens handle Loading/Success/Empty/Error/Retry/Timeout/Offline explicitly.

## Out of scope (Android doesn't have it — do NOT add)
SQLite/prefs encryption · offline dealer/device binding · token refresh/expiry · copied-DB protection · any new business rule. Keep Flutter's existing secure-token storage and DB migrations.

## Suggested order
1 → 2 → (3) → 4 → 5 → 6 → (7). Ship/verify each on RMX3842 before the next.
