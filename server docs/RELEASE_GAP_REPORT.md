# Release Gap Report

Consolidated pre-release status. Android (`D:\Git-Repos\magikdigi`) = source of truth.
Investigation/cleanup only — **no feature implementation in this phase**. Deep contracts live
in: `PACKAGE_OPERATIONS_COMPLETE.md`, `OPERATIONAL_MODULES_PARITY.md`, `OFFLINE_MODE_COMPLETE.md`,
`COMPLAINTS_FLOW.md`.

Legend: ✅ Complete · 🟡 Existing-but-incomplete · 🔴 Missing · ⬜ Built, not live-verified.

---

## 1. The three modules investigated this phase

### Settings persistence — ✅ Complete
- **Android:** `PrinterSetting_Fragment` → `SharedPreferences("settings_Pref")`, keys
  `header1/header2/footer1/footer2` + `AMT_FILTER_PREF` (Float, default 500). Submit confirms
  ("Are you sure you want to submit?") → save → restart MainActivity. Clear wipes only the
  header/footer fields. Receipts read these (`DisplayPaymentDetails_Fragment:662-735`).
- **Flutter (done):** `SettingsStore` (SharedPreferences, same keys) persists all 5; screen
  loads on open, confirm-on-submit, Android-exact Clear; thermal receipt prints header1/2
  (above "PAYMENT RECEIPT") + footer1/2 (bottom), only when set.
- **Restart behavior:** Flutter needs no restart — receipts read settings fresh each build.
- **Error handling:** parse failure on amount → defaults 500; persistence is local, no network.
- **Gap:** `amt_filter` is persisted but **not consumed** (Android uses it for dashboard/search
  amount highlight). 🟡 low-risk follow-up, intentionally not wired.

### Expenses — ✅ Complete (implemented this phase)
- **Built:** `expenses/data/expense_models.dart` + `expenses_repository.dart` (3 REST APIs:
  `expense_dashboard` master, `expense_data` list, `expense_data_create` create/edit);
  **Add** screen wired to master-data LOVs (category/payment-mode/tax-type) + create +
  validation (name + valid amount, Android-exact) + Success/Fail dialog; **List** screen
  date-range filtered + FAB→Add + refresh-on-return + loading/empty/error/retry. File renamed
  `list_expenses-screen.dart` → `list_expenses_screen.dart` (snake_case lint). `flutter
  analyze` clean.
- **Not built (parity-correct):** **attachments** — Android's `document_expenses` upload is
  commented out (disabled), so omitted; **Delete** — Android has none. **No role-gating**
  (matches Android).
- **Legacy (unused, kept):** `core/data/expense.dart` + `expense_storage.dart`.
- _(original investigation below)_

### Expenses — investigation (Android source of truth)
- **Android end-to-end:** `ExpensesList` (list + date filters + master-data dropdowns) +
  `AddExpensesFragment` (create/edit). REST:
  - `expensesListmasterData` — categories, tax types, employees, payment modes
    (req `imei, authtoken, dealer_id, employee_id, request_from=FromDigiApp`).
  - `expensesListdata` — list (adds `expense_start_date`, `expense_end_date`).
  - `expensescreate` — create/edit (`is_edited, expense_title, expense_id, expense_category_id,
    expense_tax_type_id, expense_date, base_amount, payment_method, expense_invoice_number,
    remarks, dealer_id, employee_id, request_from, tax_type, tax_amount, imei`).
- **Validation:** required = expense name + valid amount (`:174-176`); date/invoice/remarks
  validations are commented out.
- **Attachments/images:** picker + `encodeFileToBase64` exist, **but `document_expenses`
  payload is COMMENTED OUT** (`:533`) and the storage-permission check is commented out →
  **attachments are captured but NOT uploaded in production** (effectively disabled). So
  Flutter does NOT need attachment upload for parity.
- **CRUD:** Create + Edit (`is_edited`) + Read (list). **No Delete.**
- **Role permissions:** none found (not role-gated).
- **Error handling:** "Authentication Failed" on bad auth; master-data/list failures → toast;
  create returns Error_code/Error_Message or status_message.
- **Flutter gaps:** screens exist but **local-only** — `ListExpensesScreen` reads in-memory
  `ExpenseStorage`; `AddExpensesScreen` has no repository/API. **Missing:** models, repository
  (3 endpoints), master-data dropdowns, date-filtered list, create/edit wiring, refresh.

### Employee Track — ✅ Complete (implemented this phase)
- **Built:** `employee_track/data/employee_collection.dart` + `employee_track_repository.dart`
  (SOAP `empCollection`, wrapper `collectInfo`/`checkCollectionInfo`, fields `authToken,
  fromDate, toDate(yyyy-MM-dd), imei`; response repeated `collectionResult` +
  `statusCode/statusMessage`) + `employee_track_screen.dart` (date-range → per-employee
  collections, total, loading/empty/error/retry). Drawer item `'employee_track'` (already
  existed, was a no-op) now wired. `flutter analyze` clean.
- **NOT GPS** — it's a collection report; location-sending stays in `LocationSyncService`.
- **Distinct from** Reports → "Employee Collections" (`eccd`, customer-level) which maps to
  the still-stub `SearchCollectionsScreen` — a **separate, deferred** feature (see §Deferred).
- 🟡 SOAP date is sent as the `yyyy-MM-dd` string (Android's value); verify live that the
  server accepts it (Android registers MarshalDate but the field is a String).
- _(original investigation below)_

### Employee Track — investigation
- **Exists in production?** **Yes** — `MainActivity:554-556` opens `EmployeeTrackFragment` for
  **non-POS devices** (the guard is only "Maps cannot be loaded In POS Machines"). Not gated by
  a dealer role/config flag.
- **What it actually is:** despite the name, it's an **employee *collection report*** — SOAP
  `empColl` + `checkCollectionInfo`, **date-range filter** → collection list
  (`EmployeeTrackFragment:109-110,308,366-382`). **No GoogleMap/Marker/GPS/background tracking**
  in this screen.
- **GPS/location:** handled separately by a location service; **Flutter already sends location**
  via `LocationSyncService` (so the "tracking" side is covered). The missing piece is the
  **report screen**.
- **Permissions/background/sync:** none specific to this screen (it's a read-only SOAP report).
- **Flutter:** no Employee Track screen, no drawer entry → **Missing**. 🟡 exact `empColl`
  request/response fields to read if/when built.

---

## 2. Module status overview

### ✅ Completed
| Module | Notes |
|--------|-------|
| Package Operations (hub, Active, Add, Remove, Schedule) | live-verified |
| Reactivation visibility | fixed (box_status != "0") |
| Settings (receipt header/footer persistence) | this phase |
| Collection Schedule / Pay Later (server-side) | this phase |
| Nearest Customer List | Flutter ≥ Android |
| Payments, Receipts, Dashboard, Customer Search/Details | prior work |
| Complaints (create / history / update / dashboard feed) | wired to real APIs (`complaints/*`) |
| **Expenses** (master + list + create) | this phase — `expense_dashboard`/`expense_data`/`expense_data_create` |
| **Employee Track** (collection report) | this phase — SOAP `empCollection`; drawer wired |

### ⬜ Built, not live-verified (Package Operations writes)
| Item | API | Why |
|------|-----|-----|
| Reactivation execution | `reactivateBox` (rbox) | test-server network was down |
| STB Deactivation | `deactivateSTB` (ds) + `deactivateBox` (db, SOAP, reason 17) | not run live |
| Service Extension | `customerServicesExtendWithStock` (csews) | depends on `box_wise_service_extension` flag |

### 🟡 Existing but incomplete
| Module | State |
|--------|-------|
| Offline Module | UI + local payment store; **placeholder sync, dummy cache, no download** (see OFFLINE_MODE_COMPLETE.md) — deferred milestone |
| Reports → "Employee Collections" (`eccd`) | `SearchCollectionsScreen` is a snackbar-only **stub** (separate from Employee Track) |
| Settings `amt_filter` consumer | persisted, not consumed |

### 🔴 Missing
| Module | Note |
|--------|------|
| _(none of the targeted release modules)_ | Offline is deferred by decision, not missing |

---

## 3. APIs not yet implemented in Flutter
| API | Module | Transport | Risk |
|-----|--------|-----------|------|
| `/GetRequest` (download data) | Offline | REST | 🔴 High (deferred) |
| `/GetCollectionData` (sync) | Offline | REST | 🔴 High (deferred) |
| `eccd` (Reports employee-collection details) | Reports | SOAP | 🟠 Med (stub) |
| `expense_dashboard`/`expense_data`/`expense_data_create` | Expenses | REST | ✅ DONE this phase |
| `empCollection` (employee collection report) | Employee Track | SOAP | ✅ DONE this phase |
| `reactivateBox` / `deactivateSTB` / `deactivateBox` / `csews` | Package Ops | REST/SOAP | 🟡 built, verify live |

## 4. Placeholders still in the codebase
| Placeholder | File | Impact |
|-------------|------|--------|
| Dummy sync (`markAllPaymentsSynced`, no HTTP) | `core/services/offline_sync_service.dart` | Offline payments never reach server |
| Dummy-seeded customer cache (`₹500`… rows) | `core/database/database_helper.dart:327-465` | Offline lists show fake data |
| Search Collections (snackbar-only) | `features/reports/search_collections_screen.dart` | Reports "Employee Collections" (`eccd`) not wired |
| Manual offline flag (not connectivity-driven) | `core/services/offline_mode_service.dart` | No auto offline/auto-sync |
| Legacy (kept, unused) `CollectionSchedule` + `DatabaseHelper.insert/searchCollectionSchedule` | by design | retained for Pay Later rollback only |
| Legacy (kept, unused) `Expense` + `ExpenseStorage` | by design | superseded by server Expenses; retained for low-risk |

## 5. Temporary debug logs
- **Removed this phase:** `[UC]`×2 (`unpaid_customers_repository`), `[MPAY]`
  (`make_payment_repository`), `[GPA]` (`payment_controller`) + their now-unused
  `foundation` imports.
- **Earlier session temp logs** (`[CPO]`, `[CPO-DEACT]`, `[CPO-SCHED]`, `[RBOX]`, `[DS]`,
  `[DB]`, `[CSEWS]`, `[HUBDIAG]`, `[GDR]`, `[QTYCFG]`, `[ROLEPERM]`, `[LOGIN]`) — already
  stripped. **Current grep for `print('[` / temp tags: none remain.**
- Remaining `debugPrint` (`LocalizationService` load-failure) is a legitimate error log, not
  a temp investigation log.

## 6. Known production differences (intentional, documented)
- **Pay Later** is now **online-only** (was local-offline) — matches Android; offline shows an
  error instead of silent local save.
- **Receipt** now prints printer-settings header/footer (blank default = unchanged).
- **Reactivation** visibility corrected to `box_status != "0"` (was inverted).
- **Nearest Customers**: Flutter uses device-GPS + local cache (Android plots a passed list) —
  Flutter is self-contained / arguably richer.

## 7. Risk-rated remaining work
| Item | Risk | Effort | Note |
|------|------|--------|------|
| Offline engine (download + sync + cache + auto-sync) | 🔴 High | Large | biggest blast radius; spec frozen |
| Live-verify Package Ops 3 writes | 🟡 Low | Tiny | needs test-server network |
| Expenses backend (3 APIs) | 🟠 Med | Medium | screens exist; no payments risk |
| Employee Track report (`empColl`) | 🟠 Med | Medium | read-only SOAP report |
| Settings `amt_filter` consumer | 🟡 Low | Small | dashboard/search highlight |

## 8. Intentional differences (Android-justified)
- **Pay Later** is now **online-only** (was local-offline) — matches Android; offline → error.
- **Receipt** prints printer-settings header/footer (blank default = unchanged).
- **Reactivation** visibility = `box_status != "0"` (was inverted).
- **Nearest Customers** uses device-GPS + local cache (Android plots a passed list).
- **Expenses**: no attachment upload (Android's `document_expenses` is disabled) and no Delete
  (Android has none).

## 9. Deferred features (by decision / out of this release)
| Feature | Why deferred |
|---------|--------------|
| **Offline engine** (`/GetRequest` download + `/GetCollectionData` sync + real cache + auto-sync) | 🔴 highest blast radius — dedicated milestone (spec frozen: OFFLINE_MODE_COMPLETE.md) |
| **Reports → "Employee Collections"** (`eccd`, `SearchCollectionsScreen` stub) | separate from Employee Track; not in this release's 3 modules |
| **Settings `amt_filter` consumer** (dashboard/search highlight) | low value; persisted but unused |
| **STB temporary activation** (`sta`) and other 🟡 in PACKAGE_OPERATIONS_COMPLETE.md | not requested this release |

## 10. Remaining risks before release
| Risk | Level | Mitigation |
|------|-------|-----------|
| Package-Ops writes (rbox/ds/db/csews) not yet run live | 🟡 | on-screen dialogs confirm; needs test-server device |
| Employee Track SOAP date sent as `yyyy-MM-dd` string (Android marshals a Date) | 🟡 | verify live the server accepts it |
| Expenses live behavior (master/list/create) not yet run live | 🟡 | verify on test server |
| Offline shipped only as UI+local until the milestone | 🟠 | document to users; no silent data loss (Pay Later now errors offline) |

## 11. Release-readiness checklist
- [x] Expenses + Employee Track implemented, Android-parity, `flutter analyze` clean (new files).
- [x] Temp investigation logs removed (`[UC]`/`[MPAY]`/`[GPA]` + earlier tags); none remain.
- [x] Full-project analyze: **57 pre-existing lints** in untouched files
      (`search_collections`, `app_drawer` Radio, `database_helper`, bluetooth…) — none from
      this work; down from 60 (fixed the expenses filename lint).
- [ ] Live-verify on test server: Package-Ops writes (rbox/ds/db/csews), Expenses, Employee Track.
- [ ] Decide: Offline this release vs next milestone.
