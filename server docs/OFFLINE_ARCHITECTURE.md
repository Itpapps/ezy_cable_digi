# Offline Mode — Architecture (Current Flutter, Android-aligned)

> Describes the **existing** Flutter offline architecture and the **target** (Android-parity) state.
> No redesign — this documents the layering already in place and the minimal additions needed.

---

## Layering (repository pattern, already in place)
```
UI (screens/dialogs)
  ├─ splash_screen / login_screen        → offline entry decision
  ├─ offline_dashboard_screen            → Search / Reports / Unpaid / Sync-back
  ├─ offline_unpaid_list_screen          → unpaid list (flag=0), tap → pay
  ├─ offline_payment_flow + offline_payment_dialog → commit + receipt
  └─ offline_reports / miniday_report    → local paid-rows report
        │
Service layer
  ├─ OfflineDataService   (core engine: download :70, commit, sync :50, clear)
  ├─ OfflineSyncService   (wrapper — TO BE CONSOLIDATED into the engine)
  ├─ ConnectivityService  (auto-sync listener — TO BE DISABLED for Android parity)
  ├─ OfflineModeService   (prefs: is_offline_mode, downloaded count, last download, offlineFlag)
  └─ SessionService       (in-memory: serverCurrentDate, lastLogin, machineNumber, offlineUserCode)
        │
Data layer
  ├─ DatabaseHelper (sqflite)
  │    ├─ offline_customers  (≙ Android offline_data_4, flag 0/1/2)
  │    ├─ offline_payments   (≙ Android offliendataafter_pay)
  │    └─ customers / payments / collection_schedules (online cache — Flutter-only extra)
  ├─ RestClient.postRaw → /GetRequest (download), /GetCollectionData (sync)
  └─ OfflineCustomer model (332-char fixed-width parse, offsets match Android)
```

## Data model — `offline_customers` (≙ `offline_data_4`)
- 332-char download record → fixed-width parse (`offline_data_service.dart:119-150`), offsets **identical** to Android (`OfflineDataDownload_Fragment.java:297-328`).
- `flag`: `0` unpaid/downloaded · `1` paid pending sync · `2` synced (+ NAK resets to `0`).
- Receipt number: `ddMMyyyyHHmmss + customerId`.

## Sync state machine (matches Android)
```
download → flag 0
  └─ commitPayment → flag 1  (offline_payments row inserted; master row updated)
        └─ sync (:50):
             ACK → flag 2 (synced; syncPaymentDate = ddMMyyyy)
             NAK → flag 0 (reverted to unpaid)
             other/timeout → stays flag 1 (retry)
clear → only when no flag=1 remain
```

## Offline-entry decision (TARGET — add the Android 2-day gate)
```
no network at login/splash
  └─ read persisted lastOnlineLoginDate (server current_date saved at last online login)
       ├─ none (never logged in)         → Android-intent: block ("Sync Previous data") *
       ├─ (today - date) <= 2 days        → OfflineDashboardScreen
       └─ > 2 days                        → dialog "Please go online and sync previous
                                            offline collections data" / "Sync Previous data" → exit
  * fresh-install policy is a Phase-3 decision (Android's literal behaviour opens empty;
    Android's intent blocks). Recommend block; confirm before implementing.
```
- **New persistence needed:** store the server `current_date` (from `auth_service.dart:97`) into `OfflineModeService` prefs on each successful online login (survives process death). Mirror Android's `current_dates_login`.

## What stays Flutter-only (do NOT remove)
- DB migrations (`_onUpgrade`) — safer than Android's drop+recreate; keep.
- Auth token in secure storage — online concern; keep.
- Explicit `flag != 0` payment dup-guard — stronger than Android list-filtering; keep.

## What to change for parity (summary; detail in the plan)
- ➕ Add 2-day offline-login gate + field-disable + verbatim block dialog.
- ➖ Disable connectivity auto-sync (Android's is commented out).
- 🔁 Consolidate `OfflineSyncService` into `OfflineDataService` (one sync path).
- 🔤 Map offline error strings to the verbatim Android texts.
