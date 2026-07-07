# Operational Modules — Pre-Release Parity Report

Investigation-only (no implementation). **Android is the source of truth**
(`D:\Git-Repos\magikdigi`, READ ONLY). Flutter: `D:\StudioProjects\ezy_cable_digi`.
Every status below is backed by a file/line citation on both sides. No assumptions —
items not confirmed are marked 🟡.

Legend: ✅ Complete · 🟨 Partial · ❌ Missing · 🟡 Not Yet Verified.

---

## Executive summary (gap table)

| # | Module | Android (truth) | Flutter today | Status | Risk |
|---|--------|-----------------|---------------|--------|------|
| 1 | **Employee Track** | `EmployeeTrackFragment` (SOAP `empColl`) | **nothing** (no screen, no drawer entry) | ❌ **Missing** | Med |
| 2 | **Settings** (Printer/Receipt) | `PrinterSetting_Fragment` (SharedPreferences persist) | ✅ **DONE** — `SettingsStore` (SharedPreferences, keys match Android) persists header1/2/footer1/2/amt_filter; screen loads on open + confirm-on-submit + Android-exact Clear; receipt thermal lines now print header/footer (DisplayPaymentDetails:662-735). ⬜ amt_filter consumer (dashboard/search highlight) intentionally not wired (separate module). | ✅ **Complete (verify live)** | Low |
| 3 | **Nearest Customer List** | `NearestCustomersMapsFrag` (map of a **precomputed** `nextcustomers` list passed via intent) | `customers/nearest_customers_screen.dart` — GPS + local DB + list/map/distance filter | ✅ **Complete** (different, self-contained approach) | Low |
| 4 | **Expenses** | `ExpensesList` + `AddExpensesFragment` (REST CRUD + master data) | `expenses/*` — **local in-memory `ExpenseStorage` only**, no backend | 🟨 **Partial (local placeholder)** | High |
| 5 | **Collection Schedule** | drawer item → `PayLaterReport` (REST `paylaterList`) | ✅ **DONE** — server-side: list → `scheduled_collection_data` (real employee/status LOVs from the response, loading/empty/error/retry); Pay Later create (payment flow) → lookup (`gethitapipaylater`) → pre-filled dialog → `scheduled_collection_create` with server `customer_id`/`is_editable` → Success/Fail dialog. Legacy local `CollectionSchedule`/`DatabaseHelper` kept unused. | ✅ **Complete (verify live)** | Med-High |

**Production-ready as-is:** #3 Nearest Customer List (verify data source acceptable).
**Genuine gaps before release:** #1 Employee Track (missing), #2 Settings persistence,
#4 Expenses (no backend), #5 Collection Schedule (not wired to `paylaterList`).

---

## 1. Employee Track — ❌ Missing

**Phase 1 — Architecture**
- Android entry: nav drawer → `EmployeeTrackFragment` (`Fragments/EmployeeTrackFragment.java`),
  adapter `EmployeeTrackAdapter`, models `EmployeeTrackInfoModel` / `LiveTrackInfo`.
- Flutter entry: **none.** No screen, no `app_drawer.dart` item, no route.

**Phase 2 — API**
- SOAP, same `NAMESPACE`; method = `empColl` (`PropertyReader.getProperty("empColl")`,
  `EmployeeTrackFragment.java:109-110`); wrapper/complex `checkCollectionInfo`
  (`:328`); response parsed by iterating `getPropertyCount()` (`:362-382`).
- 🟡 exact request fields + the `LiveTrackInfo` map/location payload not fully read
  (only needed once we decide to build this).

**Phase 3 — Flutter coverage:** repository ❌ · model ❌ · controller ❌ · screen ❌ ·
widget ❌. Nothing to reuse except infra (`SoapClient`, `SessionService`, `Geolocator`).

**Phase 4 — Android behavior:** SOAP list parse in try/catch; standard ksoap2.
🟡 loading/empty/error specifics not read (no Flutter counterpart to compare).

**Phase 5 — Dependencies:** Authentication/Session (`authToken`, `dealerId`, `imei`),
Geolocation. Tied to the employee-collection subsystem (`empColl`).

**Required work (if in release scope):** model(s) + SOAP repository (`empColl`) +
controller + screen (likely list/map). **Decision needed: is Employee Track in the
release scope at all?** It is entirely absent today.

---

## 2. Settings (Printer/Receipt) — 🟨 Partial (save is a stub)

**Phase 1 — Architecture**
- Android: `Fragments/PrinterSetting_Fragment.java` — receipt header/footer config.
- Flutter: `lib/features/settings/printer_settings_screen.dart`; opened from
  `app_drawer.dart:937` (`PrinterSettingsScreen`). Title = "SETTINGS".

**Phase 2 — API:** none — **local config only** (both sides). Android persists to
`SharedPreferences` (`PrinterSetting_Fragment.java:41,58,90` `settingsPref`,
fields header1/header2/footer1/footer2).

**Phase 3 — Flutter coverage:** screen ✅ (UI: `header1/header2/footer1/footer2`
+ `amountFilter` default `500.0`, `printer_settings_screen.dart:16-20,102-108`).
**Persistence ❌** — the Submit handler **only shows a snackbar**
(`:163-167` `printer_settings_saved`); no `SharedPreferences`/`SecureStorage` write.
Clear is local only (`:182-187`).

**Phase 4 — Android behavior:** Save → write to `SharedPreferences`; values then used
in receipt printing (header/footer). Clear resets fields.

**Phase 5 — Dependencies:** Payments/receipt printing (BLE printer) consume the
header/footer; the `amountFilter` (500.0) overlaps dashboard/unpaid thresholds.
Reusable: `SecureStorageService` (already in app), the existing screen UI.

**Gap:** Flutter collects the fields but **never persists them and receipts don't read
them**. Required work: persist on Submit (SharedPreferences/SecureStorage) + load on
open + have the receipt builder read these values. Low-medium effort, screen already built.

---

## 3. Nearest Customer List — ✅ Complete (different approach)

**Phase 1 — Architecture**
- Android: `activities/NearestCustomersMapsFrag.java` — a **map** that renders a
  **precomputed** customer list received via intent
  (`getIntent().getParcelableArrayListExtra("nextcustomers")`, `:49`;
  `EmpCollection_ResponseModel`). The "nearest" computation happens upstream in the
  employee-collection flow; this screen only plots markers.
- Flutter: `lib/features/customers/nearest_customers_screen.dart`; opened from
  `app_drawer.dart:942`. Self-contained: gets device GPS
  (`Geolocator.getCurrentPosition`, `:46`), pulls customers with coordinates from the
  **local DB** (`DatabaseHelper.getCustomersWithLocation`, `:51`), computes distance
  (`Geolocator.distanceBetween`, `:53`), sorts, and offers **List + Map** views with a
  **distance (km) filter** and per-customer navigation (`CustomerMapScreen`).

**Phase 2 — API:** Android = none on this screen (data passed in). Flutter = none
(local DB + device GPS). No live endpoint either side here.

**Phase 3 — Flutter coverage:** screen ✅, map ✅, list ✅, filter ✅, loading dialog ✅
(`showPremiumLoading`), error ✅ ("enable GPS" snackbar). Reuses `DatabaseHelper`,
`Geolocator`, `google_maps_flutter`, `CustomerMapScreen`.

**Phase 4 — Behavior:** Flutter handles loading (premium loader), GPS failure
(snackbar + stops), empty ("No customers found" / "No customers in selected range"),
filter re-compute. **Equal or better than Android** (Android shows only a map of a
passed list; Flutter adds GPS-distance ranking + list + filter).

**Phase 5 — Dependencies:** Customer Search / local customer DB (locations),
Geolocation, Maps. No Session/API dependency.

**Verdict:** ✅ Complete. Only open question (🟡): confirm the **local DB has customer
lat/long populated** in production (depends on the sync that fills
`getCustomersWithLocation`). If locations are present, this module is production-ready.

---

## 4. Expenses — 🟨 Partial (UI only, local in-memory)

**Phase 1 — Architecture**
- Android: `Fragments/ExpensesList.java` (list + filters) + `Fragments/AddExpensesFragment.java`
  (create/edit), adapter `ExpensesListAdapter`, model `ExpensesListModel`.
- Flutter: `lib/features/expenses/list_expenses-screen.dart` (opened from
  `app_drawer.dart:952`) + `add_expenses_screen.dart`.

**Phase 2 — API (Android, REST):**
- **Master data** — `expensesListmasterData` (`ExpensesList.java:281`,
  `AddExpensesFragment.java:486`): returns categories, tax types, employees, payment
  modes. Payload: `imei, authtoken, dealer_id, employee_id, request_from=FromDigiApp`.
- **List** — `expensesListdata` (`ExpensesList.java:303`). Payload adds
  `expense_start_date, expense_end_date` (+ filters: category/tax/employee/paymode).
- **Create/Edit** — `expensescreate` (`AddExpensesFragment.java:508-535`). Payload:
  `is_edited, expense_title, expense_id, expense_category_id, expense_tax_type_id,
  expense_date(+" 00:00:00"), base_amount, payment_method, expense_invoice_number,
  remarks, dealer_id, employee_id, request_from, tax_type, tax_amount, imei`.

**Phase 3 — Flutter coverage:** screens ✅ (UI present) but **backend ❌**.
`list_expenses-screen.dart` renders `ExpenseStorage.expenses` (a local, in-memory list
from `core/data/expense_storage.dart`, `:10`). `add_expenses_screen.dart` has **no**
repository/`RestClient`/`DatabaseHelper`/`postForm` usage (grep: no matches) — it does
not call `expensescreate`. No category/tax/employee/paymode master-data load.
Repository ❌ · model ❌ · controller ❌.

**Phase 4 — Android behavior:** master-data load on open (`gethitapiexpensesMasterData(1)`,
`:99`); list on search with date range; create posts then refreshes list. 🟡 exact
loading/error dialogs not transcribed.

**Phase 5 — Dependencies:** Auth/Session (`dealer_id, employee_id, imei, authtoken`),
Reports (expenses feed financial reports backend-side). Reusable: `RestClient.postForm`,
`SessionService`, the existing list/add screen UIs.

**Gap:** This is effectively a **placeholder**. Required work: models
(`ExpenseListItem`, master-data LOVs), repository (`expensesListmasterData` /
`expensesListdata` / `expensescreate`), wire both screens (dynamic dropdowns, date
filter, create/edit, refresh-on-success). Highest-effort of the five.

---

## 5. Collection Schedule — 🟨 Partial (local DB, not wired to `paylaterList`)

**Phase 1 — Architecture**
- Android: nav-drawer item **"Collection Schedule"**
  (`res/menu/activity_main__navigation_drawer_drawer.xml`) → **`PayLaterReport`**
  fragment (`Fragments/PayLaterReport.java`, layout `fragment_pay_later_report.xml`).
- Flutter: `lib/features/collections/collection_schedule_screen.dart`; opened from
  `app_drawer.dart:958`.

**Phase 2 — API (Android, REST):** `paylaterList` (`PayLaterReport.java:257`). Payload:
`customer_id(""), customer_name, account_number, crf_number, dealer_id,
scheduled_start_date, scheduled_end_date, status, selected_employee_id, imei,
authtoken, request_from=FromDigiApp, is_list="1", from_dashboard="0"` (`:264-277`).
(Employee list + status values are server/LOV-driven.)

**Phase 3 — Flutter coverage:** screen ✅ with the right **filters** (start/end date,
employee, customer name, account, status) and result list — **but it queries the local
SQLite DB** (`DatabaseHelper.searchCollectionSchedules`, `:64`), not `paylaterList`.
Employee dropdown is **hardcoded** `['Choose','itp']` (`:147`); status hardcoded
`['Choose','Scheduled','Completed']` (`:163`). Model `core/data/collection_schedule.dart`
exists (local). Repository/API ❌.

**Phase 4 — Android behavior:** date-range + filters → `paylaterList`; renders the
returned schedule/pay-later rows; re-fetch on search. 🟡 exact loading/empty/error
dialogs not transcribed.

**Phase 5 — Dependencies:** Auth/Session, Reports/Collections, Employees LOV
(`selected_employee_id`), Customer Search (account/crf filters). Reusable:
`RestClient.postForm`, `SessionService`, the screen UI/filters already built.

**Gap:** UI matches but data source differs. Required work: repository for
`paylaterList`, model from its response, replace local-DB query, load a **real employee
LOV** and the real status values, wire loading/empty/error. 🟡 Confirm whether the local
DB path is an intentional offline mode (if so, document it as offline-only and still add
the online `paylaterList` path for parity).

---

## Collection Schedule / Pay Later — Option A blast-radius (pre-implementation)

**Decision:** full server parity (Android source of truth). Pay Later becomes server-side;
**no hybrid**. Legacy local code is **kept but unused** until production verification.

**Callers of `schedulePayLater`:** exactly ONE — `payment_options_screen.dart:326`
(`_handlePayLater`). No other caller in the codebase.

**Affected:**
- **API (new):** `scheduled_collection_create` (`/digi_rest_api/...`, create) +
  `scheduled_collection_data` (`/digi_rest_api/...`, list). REST form-POST.
- **Repository (new):** `collections/data/pay_later_repository.dart`.
- **Model (new):** `collections/data/pay_later.dart` (`PayLaterSchedule`, `PayLaterEmployee`).
- **Screens (edit):** `payment_controller.dart` (`schedulePayLater` → POST, new return),
  `payment_options_screen.dart` (`_handlePayLater` result handling),
  `collection_schedule_screen.dart` (local DB → API + real LOVs).
- **DB table (LEGACY, untouched):** `collection_schedules` +
  `DatabaseHelper.insertCollectionSchedule` / `searchCollectionSchedules` + the
  `CollectionSchedule` model — become **unused/dead** after this change; **left in place**
  per release instruction (documented legacy, removed only after production verification).
- **Offline dependency:** NONE — `lib/features/offline/*` has zero references to
  `CollectionSchedule`/`schedulePayLater`/`paylater`. So no offline-subsystem regression.

**Behavior change (accepted):** Pay Later is now **online-only** (Android has no offline
Pay Later). Offline → the POST fails and shows the error dialog (no silent local save).

**Request/response (verified):**
- create req: `customer_id, dealer_id, employee_id(=SessionService.employeeId),
  scheduled_date, status, is_edited="0", remarks, imei, authtoken`.
  resp: `Error_code`+`Error_Message` → "Fail!" dialog · else `status_message` → "Success"
  dialog (CustomerMgmt_MakePayment_Fragment:2767-2799).
- list req: `customer_id(""), customer_name, account_number, crf_number, dealer_id,
  scheduled_start_date, scheduled_end_date, status, selected_employee_id, imei, authtoken,
  request_from="FromDigiApp", is_list="1", from_dashboard="0"`.
  resp success: `customer_data[]` rows + `setting_values.status_drop_down` (status LOV) +
  `emp_details[]{employee_id,Name}` (employee LOV); `Error_code` → "Fail!" + no-records
  (PayLaterReport:285-428). All nested values are JSON strings (decode like package-ops).

**Validation flow (match Android):** create — `status` chosen, `scheduled_date` set
(dialog already enforces); list — filters optional, dates default to today.
**Loading:** "Fetching Details, Please wait" (list) / "Scheduling collection..." (create).
**Empty:** no-records view when `Error_code`/empty `customer_data`.
**Error:** server `Error_Message` in a dialog; transport → generic error + retry.
**Retry:** re-tap Search (list) / re-open dialog (create) — same as Android (no auto-retry).

**Rollback plan:** revert the 3 edited files (`payment_controller`, `payment_options_screen`,
`collection_schedule_screen`) to restore the local-DB path; the legacy `CollectionSchedule`
model + `DatabaseHelper` methods + table are still present, so rollback is a pure revert
with no schema/data migration. New files (`pay_later.dart`, `pay_later_repository.dart`) are
additive and can be left or deleted.

## Cross-cutting notes
- **Shared infra already available** (reuse, do not recreate): `RestClient.postForm`,
  `SoapClient` (+ `readField`/`readAll`), `ServerUrlResolver`, `SessionService`
  (`authToken/dealerId/employeeId/imei`), `SecureStorageService`, `DatabaseHelper`,
  `Geolocator`, `google_maps_flutter`, `LocationSyncService`.
- **`request_from=FromDigiApp`** is required by the expenses + paylater REST endpoints.
- Endpoint keys live in Android `assets/configg.properties`
  (`expensesListmasterData`, `expensesListdata`, `expensescreate`, `paylaterList`,
  `empColl`); the Flutter REST base is `ServerUrlResolver.namespace + <path>`.

## Definition of Done (per gap module)
- [ ] Repository + model created (reusing `RestClient`/`SoapClient`); defensive parse.
- [ ] Screen wired to the real API (no hardcoded LOVs); loading / empty / error+retry.
- [ ] Refresh after success; never crash on null/empty/malformed/timeout/unauthorized.
- [ ] Behaviour matches Android (verified file/line) or divergence documented.
- [ ] `flutter analyze` clean; verified live on the test server before marked complete.

## Recommended order (genuine gaps only)
1. **Settings persistence** (small, self-contained, screen exists).
2. **Collection Schedule → `paylaterList`** (screen + filters exist; swap data source + LOVs).
3. **Expenses** (3 endpoints + master data; screens exist; larger).
4. **Employee Track** (only if in release scope — full build) — **confirm scope first**.

(#3 Nearest Customer List needs no work beyond confirming the local DB has customer
coordinates in production.)
