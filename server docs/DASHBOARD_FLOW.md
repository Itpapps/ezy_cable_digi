# Dashboard Flow — Existing Application Investigation & Flutter Parity Plan

Source of truth: the existing production Android app (read-only). This document
describes the dashboard end-to-end so the Flutter dashboard can mirror it while
being defensive and production-safe. **No implementation has been done yet.**

### Verification legend
- ✅ **Verified** — read directly from the existing application source code
  (file + line evidence below, or confirmed by me during this investigation).
- 🟡 **Not Yet Verified** — depends on live backend responses / runtime behavior
  on the real server, or on account/role/device configuration we have not
  exercised. Treated as an assumption until a live test confirms it.

Evidence is from `DashboardHomeFragment.java` (the active dashboard) unless noted.
No URLs, tokens, IMEIs, dealer ids, customer names, or receipt numbers are
recorded here (security rule).

---

## 1. Architecture Overview

- ✅ **Active dashboard:** `DashboardHomeFragment` with layout `dashboard_home_ui.xml`.
  Reached after login via the bottom-nav / drawer / initial `navigateTo` path.
- ✅ The dashboard is **populated by MULTIPLE independent APIs**, not one. The top
  KPI cards come from a single SOAP call; each list tab and the wallet come from
  their own call. Every call runs as an independent `AsyncTask` / Volley request —
  there is **no aggregation endpoint**.
- ✅ Calls are **fire-and-independent**: the KPI call and the complaints call are
  launched together on screen creation; the other tabs load **lazily on tab tap**.
- ✅ Transport: SOAP via `ksoap2` (`HttpTransportSE`, SOAP 1.1) for KPI / complaints
  / unpaid; REST form-POST via Volley for LCO wallet / nearest / pay-later.
- ✅ Auth is carried in every request as `authToken` + `imei` (SOAP) or
  `authtoken` + `imei` (+ `dealer_id`) (REST).
- ✅ User role (`DEALER`/`ADMIN`/`EMPLOYEE`/`SERVICE`) changes which cards/tabs show
  and which response field feeds "Collections".

### Components
| API | Method (config key) | Transport | Feeds | Loaded |
|-----|--------------------|-----------|-------|--------|
| 1. Dashboard KPIs | `dashBoardDetails` (`dbd`) | SOAP | Due, Month Billing, Onetime, Collections, complaints count | On screen create |
| 2. LCO Wallet | `getLCODepositAmount` (`glda`) | REST POST | LCO Wallet card | On screen create (DEALER/ADMIN, if `userLcoDeposit > 0`) |
| 3. Complaints | `getopencomplaintslist` (`gocl`) | SOAP | Complaints feed/tab | On create + on Complaints tab |
| 4. Unpaid customers | `unpaidCustomers` (`uc`) | SOAP | Unpaid feed/tab | On Unpaid tab |
| 5. Nearest customers | `NearestNextCustomer` (`nnc`) | REST POST | Nearest feed/tab | On Nearest tab |
| 6. Pay Later | `scheduled_collection_data` (`paylaterList`) | REST POST | Pay Later feed/tab | On Pay Later tab |

---

## 2. API Contract

### 2.1 Dashboard KPIs — `dashBoardDetails` (SOAP) ✅
- **Request** (complex type `dashBoard`, property name `dashInfo`):
  - `authToken` ✅
  - `imei` ✅
- **Timeout:** 70 000 ms when connected/connecting; 10 000 ms otherwise. ✅
- **Response** (string, `key=value;` pairs; parsed by `indexOf`):
  - `statusCode` (int) ✅ — always read first.
  - `statusMessage` (string) ✅.
  - When `statusCode == 0`, role-dependent fields:
    - DEALER/ADMIN: `outStandingAmount` (double), `employeeCollectionAmount`
      (double), `billAmount` (double), `collectionAmount` (double),
      `overDueAmount` (int), `complaints` (int), `deactivatedCustomers` (int),
      `onetimeChargeAmount` (double). ✅
    - EMPLOYEE: `outStandingAmount`, `employeeCollectionAmount`, `complaints`,
      `overDueAmount`. ✅
    - SERVICE: `complaints` only. ✅
  - 🟡 Exact server-side meaning of `collectionAmount` (today vs period) and
    `outStandingAmount` is **not verified** — labels are inferred from the UI.
- **Field parsing is individually try/caught** → a missing field is skipped and
  the rest still render. ✅

### 2.2 LCO Wallet — `getLCODepositAmount` (REST POST) ✅
- **Request form fields:** `dealer_id`, `imei`, `authtoken`. ✅
- **Timeout:** 100 000 ms (Volley `DefaultRetryPolicy`). ✅
- **Response (JSON):** `status_code` (int), `status_msg` (string),
  `lco_deposit_amount` (double, only when `status_code == 0`). ✅
- **Visibility gate:** only when role is DEALER/ADMIN and `userLcoDeposit > 0`. ✅

### 2.3 Complaints — `getopencomplaintslist` (SOAP) ✅ (per agent line-citations; 🟡 not line-reverified by me)
- **Request (complex type `OpenComplaintsInfo`):** `authToken`, `imei`,
  `dealer_id` (=0), `from_dashboard` ("1"). ✅
- **Timeout:** 700 000 ms. ✅
- **Response list `opencomplaintList`**, per item: `tkt_number`, `complaint_id`,
  `description`, `status`, `name`, `des`, `alt_custom_number`, `group_name`,
  `mobile_no`, `address1`, `crfno`, `date`, `alt_cust_id`, `customer_id`,
  `latitude?`, `longitude?`. ✅

### 2.4 Unpaid customers — `unpaidCustomers` (SOAP) ✅ (matches Flutter's existing repo)
- **Request (complex type `UnpaidcustomerInfo`):** `authToken`, `imei`,
  `biilmonth` ("M-YYYY"), `stbstatus` (-1), `customerstatus` (-1),
  `unpaidlist_type` (1), `group_id` (0), `from_dashboard` ("1"). ✅
- **Timeout:** 90 000 ms connected / 150 000 ms disconnected. ✅
- **Response list `unpaidcustomers`**, per item: `alt_cust_id`, `first_name`,
  `last_name`, `mobile_no`, `vc_number`, `total`, `box_number`, `amount`,
  `crfno`, `address1`, `customer_id`, `paid_on`, `customnumber`, `bill_month`,
  `nickname`, `broadband_user_id`, `customer_type` (int), `alt_custom_number`. ✅
- **Note:** the Flutter `UnpaidCustomersRepository` already calls this API and
  `Customer.fromJson` already maps these fields. ✅

### 2.5 Nearest customers — `NearestNextCustomer` (REST POST) ✅
- **Request form fields:** `dealer_id`, `lat`, `lang`, `imei`, `authtoken`,
  `distance_km` (default "2"), `from_dashboard` ("1"). ✅
- **Timeout:** 10 000 ms. ✅
- **Response (JSON, parallel arrays):** `status_code`, `status_msg`, `distance[]`,
  `name[]`, `alt_custom_number[]`, `latitude[]`, `longitude[]`. ✅
- **Needs device GPS**; if unavailable, lat/long sent as 0.0. ✅

### 2.6 Pay Later — `scheduled_collection_data` (REST POST) ✅
- **Request form fields:** `customer_id`, `customer_name`, `account_number`,
  `crf_number` (all empty from dashboard), `dealer_id`, `scheduled_start_date`,
  `scheduled_end_date` (both = current date), `status` (empty), `imei`,
  `authtoken`, `from_dashboard` ("1"). ✅
- **Response list `customer_data`**, per item: `customer_name`, `scheduled_date`
  (substring 0..10), `status`, `remarks`, `alt_custom_number`, `nickname`,
  `alt_cust_id`, `customnumber`, `customer_account_id`, `email`, `mobile_no`,
  `vc_number`, `total`, `box_number`, `amount`, `customer_id`, `paid_on`,
  `bill_month`, `crfno`, `address1`. ✅

---

## 3. Sequence Diagram (login → dashboard)

```
User → Login: submit credentials
Login → Backend: validateLogin (authToken, role, dealerId, flags)
Login → Dashboard: navigate (online) / OfflineDashboard (offline)

Dashboard.onCreate:
  ├─ DashboardDetails (dbd, SOAP)        ── KPI cards        [progress dialog]
  ├─ getopencomplaintslist (gocl, SOAP)  ── complaints       [progress dialog]
  └─ lcowallet (glda, REST)              ── wallet (cond.)   [progress dialog]

User taps a feed tab:
  ├─ "Unpaid"   → unpaidCustomers (uc, SOAP)
  ├─ "Nearest"  → NearestNextCustomer (nnc, REST)  (needs GPS)
  ├─ "Complaints" → getopencomplaintslist (gocl, SOAP)
  └─ "PayLater" → scheduled_collection_data (REST)

Each response:
  statusCode/ status_code == 0 → parse + render list/cards
                           == 1 → "No Details" (KPI: forces re-login)
                           == 2 → Toast "Contact Support"
  null/exception            → "Server busy/unreachable" (KPI: forces re-login)
```
✅ KPI + complaints fire together on create; tabs are lazy. 🟡 exact concurrency
ordering on the live device not re-tested.

---

## 4. Dashboard Item Map (every card / counter)

For each: source API field · type · null behavior · empty behavior · error
behavior · refresh · user-visible fallback. Android behavior is ✅; the Flutter
column is the **target** parity behavior.

| Item | API · field | Type | Android behavior | Flutter target fallback |
|------|-------------|------|------------------|-------------------------|
| **Due Amount** | dbd · `outStandingAmount` | double | try/catch; on parse fail value stays default; shown `₹%.2f` | `₹0.00` if null/missing |
| **Month Billing** | dbd · `billAmount` | double | try/catch; `₹%.2f` | `₹0.00` |
| **Onetime Charges** | dbd · `onetimeChargeAmount` | double | try/catch; `₹%.2f` | `₹0.00` |
| **Collections** | dbd · `collectionAmount` (DEALER) / `employeeCollectionAmount` (EMPLOYEE) | double | role-dependent; `₹%.2f` | `₹0.00` |
| **LCO Wallet** | glda · `lco_deposit_amount` | double | shown only if `status_code==0` & role gate; else hidden/0 | `₹0.00`; hide if not permitted |
| **Complaints (count)** | dbd · `complaints` | int | parsed; (count display currently commented out in Android) | `0` |
| **Overdue (count)** | dbd · `overDueAmount` | int | parsed but **not displayed** | not shown (parity) |
| **Deactivated (count)** | dbd · `deactivatedCustomers` | int | parsed but **not displayed** | not shown (parity) |
| **Unpaid Customers (list)** | uc · `unpaidcustomers[]` | array | `statusCode 1` → dialog + hide list; else render | empty-state, no crash |
| **Complaints (list)** | gocl · `opencomplaintList[]` | array | empty → "No Details Found" toast; else render | empty-state |
| **Nearest (list)** | nnc · parallel arrays | arrays | needs GPS; `NA` → "Authentication Failed" | empty-state / "enable location" |
| **Pay Later (list)** | paylaterList · `customer_data[]` | array | error_code → dialog; else render | empty-state |
| **Banners** | — | — | none found | none (parity) |
| **Business name** | login · `businessName` | string | header text | from session |

- 🟡 "Today's Collection" as a **separate** card does **not exist** — there is one
  "Collections" figure (`collectionAmount`). The Flutter subtitle says "today";
  whether the backend value is daily or period-to-date is **not verified**.
- ✅ Amount formatting: `RUPEES_SIGN + String.format("%.2f", value)`.
- ✅ Rounding mode from `amount_round`: `ACTUAL` (none) / `ROUND` (`Math.round`) /
  else `Math.ceil`. Applies to outstanding, billing, collection, overdue, onetime.

---

## 5. API → Widget Mapping (Android, verified)

| Response field | Android widget id | Label |
|----------------|-------------------|-------|
| `outStandingAmount` | `dashboard2_outstanding_tv` | Due Amount |
| `billAmount` | `dashboard2_monthbilling_tv` | Month Billing |
| `onetimeChargeAmount` | `dashboard2_onetimecharge_tv` | Onetime Charges |
| `collectionAmount` / `employeeCollectionAmount` | `dashboard2_collections_tv` | Collections |
| `lco_deposit_amount` | `tv_lcoaount` | LCO Wallet |
| `complaints` | (parsed → `int_complaints`; display commented out) | — |
| `overDueAmount`, `deactivatedCustomers` | parsed only; **no widget** | — |

---

## 6. Lifecycle

### 6.1 Loading ✅
- Each call shows a blocking `ProgressDialog` ("Getting Details…", "Loading…",
  "Loading data…", "Loading complaints…"), dismissed on response or error.
- No skeleton/shimmer; no per-card spinners.

### 6.2 Refresh ✅
- **No pull-to-refresh, no onResume re-fetch.** KPI/wallet load once on create.
- Tabs **re-fetch on every tab tap** (acts as the refresh mechanism for lists).

### 6.3 Error ✅ (KPI call — the strictest)
- `response == null` → `statusCode = 3` → AlertDialog "Server is busy or Un
  reachable!" / "Please login again after sometime" → OK → **return to Login**.
- `statusCode == 1` → AlertDialog "No Details Found!" + `statusMessage` → OK →
  **return to Login**.
- `statusCode == 2` → Toast `statusMessage + ": Contact Support"` (stays on screen).
- List/REST calls: softer — toasts ("Failed.", "Authentication Failed"), inline
  dialogs, hide the list (`setVisibility(GONE)`); some pop the back stack.

### 6.4 Retry ✅
- No manual retry button. REST uses Volley `DefaultRetryPolicy`. SOAP has no
  automatic retry — the user re-taps the tab or re-enters the screen.

### 6.5 Offline / timeout / session ✅
- Offline: connectivity state only adjusts the SOAP timeout; **no cached
  fallback**. The app expects to be online.
- Timeout: large per-API timeouts (10s–700s). On exception → "Server busy"
  dialog (KPI path forces re-login).
- Session expired / invalid token: **no explicit HTTP 401/403 check.** Detected
  indirectly via `statusCode`/`"NA"` body; the KPI path's `statusCode 1` / null
  response is what effectively logs the user out.
- Partial response: each field/section is independent — one failure does not
  break the others (except the KPI null/`1` path, which is global).

---

## 7. Flutter — Current State & Reuse Plan

### 7.1 Already built (reuse) ✅
- **UI shell:** `dashboard_screen.dart` with cards `_GradientSummaryCard`
  (Due, Month Billing, Onetime), `_LottieHighlightCard` (LCO Wallet, Collections),
  quick actions, feed chips (Complaints/Unpaid/Nearest/PayLater), `_TicketCard`.
- **Network:** `lib/core/network/soap_client.dart`, `rest_client.dart`,
  `server_url_resolver.dart` — production-parity SOAP/REST transport.
- **Session/config:** `session_service.dart` (`authToken`, `dealerId`, `userType`,
  `employeeId`, discount flags), `app_config.dart` (`namespace`, `deviceImei`).
- **Repos already wired to real APIs:** `UnpaidCustomersRepository` (uc),
  `PendingAmountRepository` (gpa), `SearchRepository` (sc),
  `DealerGroupsRepository`, `MakePaymentRepository` (mpay).
- **Model:** `Customer` with `fromJson` mapping the `uc` fields already.
- **Provider:** `CustomerListProvider` (ChangeNotifier) already calls
  `UnpaidCustomersRepository`.

### 7.2 Placeholder / hardcoded (must replace) ✅ (verified in source)
- Card amounts are **hardcoded strings**: Due `₹0.00`, subtitle `120 customers`;
  Month Billing `₹0.00`; Onetime `₹250.00`; LCO `₹0.0`; Collections `₹750.00`.
- Feed lists are **dummy** `_TicketItem` arrays (comment: "Dummy data — replace
  with real API / DB calls").

### 7.3 Missing (must build) ✅
- No repository/model for **dashBoardDetails** (KPI), **LCO wallet** (glda),
  **complaints list** (gocl), **nearest** (nnc), **pay later** (paylaterList).
- No dashboard controller/provider that aggregates KPI + wallet state.

### 7.4 Do NOT touch
- The hardcoded dummy data (will be removed, not extended).
- `analytics_screen.dart` test constants (separate screen).
- `OfflineDashboardScreen` (separate offline path).
- Working quick-action navigation and app bar.

---

## 8. Production Risks & required Flutter handling

| Risk | Android behavior | Flutter must |
|------|------------------|--------------|
| API returns null / malformed | KPI: "Server busy" → re-login | catch, show fallback `₹0.00` / empty-state; never crash |
| `statusCode == 1` (no details) | KPI: dialog → re-login | mirror for KPI; for lists show empty-state |
| `statusCode == 2` | Toast "Contact Support" | show non-fatal message |
| Missing JSON field | per-field try/catch, skip | null-safe parse, default value |
| Empty list | hide list / "No Details" | empty-state widget |
| Session expired / bad token | indirect (statusCode/NA) → re-login | detect, route to login gracefully |
| Slow network / timeout | long timeouts, then dialog | timeout + fallback, no ANR/freeze |
| Partial data (one API fails) | independent tasks, others survive | **each section isolated** — one failure ≠ whole dashboard fails |
| GPS unavailable (nearest) | lat/long 0.0 | prompt/empty-state, no crash |
| Backend renames a field | parse fails silently → 0/empty | defensive parse, default, log |
| Server maintenance | "Server busy" dialog | friendly retry message |

---

## 9. Backend Verification Checklist (🟡 — to confirm on the live/test server)
- [ ] 🟡 `dashBoardDetails` exact response keys & whether `collectionAmount` is
      today vs period; confirm role-specific field presence.
- [ ] 🟡 `getLCODepositAmount` response shape and the `userLcoDeposit` gate source.
- [ ] 🟡 `getopencomplaintslist` list key + item fields on the live server.
- [ ] 🟡 `NearestNextCustomer` array alignment (parallel arrays same length).
- [ ] 🟡 `scheduled_collection_data` `customer_data` shape.
- [ ] 🟡 Real status codes returned for expired token vs no-data vs error.
- [ ] 🟡 `amount_round` value supplied for this account.

## 10. Testing Checklist (per section, before marking done)
- [ ] Loads with real data (DEALER) — Due/Billing/Onetime/Collections/Wallet.
- [ ] EMPLOYEE role → Collections uses `employeeCollectionAmount`; gated cards hidden.
- [ ] Each feed tab loads its list; empty-state renders when list is empty.
- [ ] Airplane mode → graceful error, no crash.
- [ ] Forced bad token → graceful (re-login or message), no crash.
- [ ] One API forced to fail → other sections still render.
- [ ] `flutter analyze` clean after each section.

---

## 11. Definition of Done
- [ ] Each KPI card shows real `dashBoardDetails` data with `₹0.00` fallback.
- [ ] LCO wallet shows real `getLCODepositAmount`, gated by role/permission.
- [ ] Each feed tab (Unpaid/Complaints/Nearest/PayLater) shows real data with an
      empty-state and never crashes on null/empty/malformed/timeout/unauthorized.
- [ ] One section failing never crashes the whole dashboard.
- [ ] Role behavior (DEALER/EMPLOYEE/SERVICE) mirrors the existing app.
- [ ] `flutter analyze` clean.
- [ ] 🟡 User verifies each section live before it is marked complete.

---

## 12. Proposed incremental implementation order (NOT started — for approval)
1. **KPI cards** (`dashBoardDetails`): model + repository + dashboard controller;
   wire the 4 cards with `₹0.00` fallbacks and role logic. Verify.
2. **LCO Wallet** (`getLCODepositAmount`): REST repo + gate. Verify.
3. **Unpaid feed**: reuse `UnpaidCustomersRepository` + `CustomerListProvider`. Verify.
4. **Complaints feed** (`getopencomplaintslist`): new repo + model. Verify.
5. **Pay Later feed** (`scheduled_collection_data`): new REST repo + model. Verify.
6. **Nearest feed** (`NearestNextCustomer`): new REST repo + GPS. Verify.
7. Hardening: error/empty/offline states across all sections.

Each step: implement one section → `flutter analyze` → explain → **wait for
verification** before continuing. No refactors of unrelated code; no redesign.
