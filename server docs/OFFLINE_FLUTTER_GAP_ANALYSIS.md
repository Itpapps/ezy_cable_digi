# Offline Mode — Flutter Gap Analysis (Phase 2)

> Compares Flutter (`d:\StudioProjects\ezy_cable_digi`) to the verified Android behaviour in
> `OFFLINE_ANDROID_INVESTIGATION.md`. ✅ Complete · 🟡 Partial · 🔴 Missing/Divergent.
> No code changed. Implementation is Phase 3 (awaiting approval).

---

## Headline
Flutter's offline **engine** (download, parse, SQLite, payment commit, sync, clear) is a **faithful, near-1:1 port**. The gaps are concentrated in **two places**:
1. 🔴 **Offline-login gate** — Flutter is missing Android's **2-day staleness block** and field-disable.
2. 🟡 **Auto-sync** — Flutter **adds** connectivity-driven auto-sync that Android has **disabled** (commented out). This is *invented logic* relative to Android and is the main duplicate-sync/race risk.
Plus minor: duplicate sync wrappers, and immediate-sync-on-online-payment not mirrored.

---

## Module-by-module

### 1. Offline login gate — 🔴 DIVERGENT (highest priority)
- **Flutter now:** on a login attempt or splash with no network, it goes straight to `OfflineDashboardScreen` — **no date check, no prior-login requirement, no block, no field-disable**. `login_screen.dart:97-103` (`setOfflineMode(noNetwork)` → `OfflineDashboardScreen`); `splash_screen.dart:34-43` (no-network → `OfflineDashboardScreen`).
- **Android:** offline entry requires last **online**-login date ≤ 2 days (`LoginActivity.java:278`), else *"Please go online and sync previous offline collections data"* / *"Sync Previous data"* → **exit**; username/password disabled offline (`:248-251`).
- **Risk:** **High** — a device that has been offline/stale for >2 days (or never logged in) can still enter the offline dashboard and take payments against stale balances. Android explicitly forbids this past 2 days.
- **Files:** `login_screen.dart`, `splash_screen.dart`, `session_service.dart` (already has `serverCurrentDate`/`lastLogin`), `offline_mode_service.dart` (needs a persisted last-online-login date).
- **Dependency:** Flutter must **persist the server `current_date` at each successful online login** (it currently lives only in in-memory `SessionService.serverCurrentDate`, `auth_service.dart:97,117`) so the gate survives process death.

### 2. Dealer validation offline — ✅ COMPLETE (by matching Android = none)
- Android does no dealer validation offline (only the 2-day window). Flutter also does none. The only thing to add is the 2-day window itself (item 1). No credential/token/dealer comparison should be introduced (Android has none).

### 3. Fresh-install (A/B/C) — 🟡 PARTIAL
- **A (fresh, offline):** Android opens an **empty** offline dashboard (datediff side-effect). Flutter also opens the offline dashboard empty. **Coincidentally matches** — but for different reasons. Decide in Phase 3 whether to (a) replicate Android's empty-dashboard behaviour or (b) implement the *intended* block. Recommend matching the **2-day rule** (item 1); fresh install has no saved date → treat as stale → block. *(This is stricter than Android's literal buggy behaviour but matches Android's intent; needs your explicit call per "match Android exactly".)*
- **B (downloaded, ≤2 days):** Flutter ✅ works (dashboard + lists + pay + sync).
- **C (no download, ≤2 days):** Flutter ✅ opens empty lists (matches Android).

### 4. Offline-data requirement — ✅ COMPLETE
- Neither app requires a download to open the dashboard; both render empty if nothing downloaded. Flutter matches. `offline_dashboard_screen.dart:34-45`.

### 5. Offline dashboard modules — ✅ COMPLETE (with one extra)
| Module | Android | Flutter | Status |
|---|---|---|---|
| Search Customer | ✅ | ✅ `SearchCustomerScreen` | ✅ |
| Reports | ✅ MiniDay | ✅ `OfflineReportsScreen`/`miniday_report_screen` | ✅ |
| Unpaid customers | ✅ | ✅ `OfflineUnpaidListScreen` | ✅ |
| Paid list / per-payment sync | ✅ | 🟡 Flutter syncs via "Back to online" + bulk, **no per-row tap-to-sync dialog** | 🟡 |
| Nearest/Complaints/PayLater/Expenses/PkgOps/EmpTrack/Settings | 🔴 absent | 🔴 absent | ✅ match |
| Download Records | drawer (online) | drawer (`download_records_screen.dart`) | ✅ |

### 6. SQLite schema — ✅ COMPLETE (+ extra online-cache tables)
- Flutter `offline_customers` + `offline_payments` mirror Android `offline_data_4` + `offliendataafter_pay`, **same flag 0/1/2 semantics** (`database_helper.dart:627-688`, `753-903`).
- Flutter **adds** `customers` / `payments` / `collection_schedules` online-cache tables (Android has none). Not a gap; just extra. DB **version 7** with real `_onUpgrade` migrations (Android v4 drops+recreates) — Flutter is **better** here; keep.
- 🟡 Like Android, no unique index on `customer_id`. Matches Android (no change needed).

### 7. Offline payments — ✅ COMPLETE
- `OfflineDataService.commitPayment` (`offline_data_service.dart:158-208`): flag→1, receipt `tstamp+customerId` (`:178`), pay_mode R/B, sendSms 015/005, dup-guard `flag != 0` → *"Payment already made for this customer."* (`:170-171`). Receipt shown via `showOfflineReceipt` (`offline_payment_flow.dart:137-176`). **Matches Android**, and the explicit dup-guard is actually *stronger* than Android's (Android relies on list filtering).
- 🟡 **Gap:** Android auto-syncs the payment immediately if online at payment time (`Offline_unPaidCustomer_Fragment.java:646`); Flutter always just shows the receipt. Minor; decide in Phase 3.
- 🟡 **Validation parity:** verify Flutter's offline dialog enforces partial-pay rule (amount ≥ total when `partial_pay==1`) and bank-field mandatoriness with Android's exact texts (`offline_payment_dialog.dart`). Not yet line-verified.

### 8. Offline sync — 🟡 PARTIAL / DIVERGENT
- ✅ **Wire format matches** exactly: `:50` command, fixed-width Base64 buffer, `type=3`, ACK→flag2 / NAK→flag0 / else→retry (`offline_data_service.dart:234-309`). Endpoint `/GetCollectionData` (`:24`).
- ✅ Bulk sync `syncAllPending` (`:312-329`) mirrors `SyncData_Fragment` (Flutter does **not** batch in 25s — minor; Android batches 25, Flutter does all. Low risk).
- 🔴 **Auto-sync divergence:** `ConnectivityService._onChanged` auto-syncs on reconnect (`connectivity_service.dart:28-52`). **Android's auto-sync is commented out / disabled** (`NetworkChangeReceiver.java:60-105`). This is **logic Android does not run**. Risk: unexpected background sync, potential double-submit/race vs a manual sync (mitigated only by the in-process `_isSyncing` flag — not durable). **Recommend disabling to match Android** (Phase 3 decision).
- 🟡 **Duplicate sync services:** `OfflineSyncService.syncPendingToServer` (`offline_sync_service.dart:22-28`) wraps `OfflineDataService.syncAllPending` **and** also `markAllPaymentsSynced` on the legacy `payments` table. Two entry points doing overlapping work → violates "no duplicate logic". Consolidate in Phase 3.

### 9. Error handling — 🟡 PARTIAL
- Flutter surfaces sync/commit errors as **snackbars/exceptions**, not Android's dialogs/toasts, and **omits several Android messages**:
  - 🔴 Missing: the **"Sync Previous data"** block (item 1).
  - 🔴 Missing: per-row **"No Internet Connection."** on tap-to-sync.
  - 🟡 Different wording for ACK/NAK/error vs Android toasts (#6–#10 in the Android doc).
- The user requires **no silent failures** and Android-equivalent messages → Phase 3 should map Flutter strings to the verbatim Android texts (Android doc §9).

### 10. Offline security — ✅ COMPLETE (matches; Flutter token storage exceeds, keep)
- Both: plain SQLite, no DB encryption, no offline dealer binding. Match.
- Flutter keeps the auth token in `flutter_secure_storage` (online concern) — **keep**, does not affect offline parity.
- **Do not add** encryption/binding Android lacks.

---

## Risk-ranked gap summary
| # | Gap | Status | Risk | Files |
|---|---|---|---|---|
| 1 | No 2-day offline-login staleness block + no field-disable | 🔴 | **High** | `login_screen.dart`, `splash_screen.dart`, `offline_mode_service.dart`, `auth_service.dart` |
| 2 | Connectivity auto-sync that Android has disabled | 🔴 | Med (race/double-submit) | `connectivity_service.dart`, app init |
| 3 | Missing/oddly-worded offline error popups | 🟡 | Med (UX parity) | offline screens, `offline_data_service.dart` |
| 4 | Duplicate sync services | 🟡 | Low (maintainability) | `offline_sync_service.dart`, `connectivity_service.dart` |
| 5 | No per-row tap-to-sync dialog on dashboard | 🟡 | Low | `offline_dashboard_screen.dart` |
| 6 | No immediate-sync-on-online-payment | 🟡 | Low | `offline_payment_flow.dart` |
| 7 | Offline payment dialog validation parity (partial-pay/bank) not verified | 🟡 | Med (money) | `offline_payment_dialog.dart` |

**Everything else is ✅ at parity.** The engine is solid; the work is the login gate, the auto-sync decision, and error-message parity.
