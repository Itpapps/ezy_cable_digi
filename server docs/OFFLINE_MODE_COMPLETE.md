# Offline Module — Complete Investigation & Implementation Spec

**Status: INVESTIGATION COMPLETE** (no code yet).
**Android = source of truth** (`D:\Git-Repos\magikdigi`, READ ONLY).
**Flutter:** `D:\StudioProjects\ezy_cable_digi`. Goal: production parity, reusing existing Flutter code.

✅ = line-verified | 🟡 = confirm at implementation

> ⚠️ Highest-risk module — touches payments, search, dashboard, sync, customer data.

---

## 1. Executive Summary

**Android** is a complete offline system:
1. **Download** the dealer's customers into SQLite (`/GetRequest` → `offline_data_4`)
2. **Collect payments offline** (stored in `offliendataafter_pay` with flag semantics)
3. **Sync** the queued collections to server (`/GetCollectionData`) — **manually** (`SyncData_Fragment`) and **automatically on reconnect** (`NetworkChangeReceiver`)

**Flutter** has the **UI shell + local payment storage + a manual offline flag**, but the
**core engine is placeholder/dummy**:
- ❌ **No real download** — `OfflineModeService.recordDownload` only stores a *count*; the `customers` cache in `DatabaseHelper` is **dummy-seeded**.
- ❌ **No real sync** — `OfflineSyncService.syncPendingToServer()` is a **placeholder** that calls `markAllPaymentsSynced()` (no HTTP POST).
- ✅ Offline **payment creation** stores locally (`offline_payment_flow.dart` → `db.insertPayment`).
- ✅ Offline mode is a **manual** SharedPreferences flag (`OfflineModeService`), not driven by connectivity.
- ❌ **Schema mismatch:** Flutter `customers/payments/collection_schedules` vs Android `offline_data_4 / offliendataafter_pay / bledevices` (far richer).

**Verdict:** the offline module is **Partial (UI + local store) with a missing engine** (download + sync + real cache). This is the bulk of the work.

---

## 2. Android Architecture (Verified)

### 2.1 Files
| File | Purpose |
|------|---------|
| `activities/Offline_Activity.java` | Offline host activity (holds fragments, date, partial_pay config) |
| `Fragments/Offline_Tabs_Fragment` | Tabbed offline home (paid/unpaid/search/reports) |
| `Fragments/Offline_Dashboard.java` | Dashboard: shows paid list (flag=1), sync per-item, navigate to search/reports |
| `Fragments/OfflineDataDownload_Fragment.java` | **Download** customers → SQLite (two-step: count then fetch) |
| `Fragments/SyncData_Fragment.java` | **Batch sync** all flag=1 rows → server; clear data |
| `Fragments/Offline_unPaidCustomer_Fragment.java` | **Unpaid list** + payment dialog + immediate sync attempt |
| `Fragments/Offline_paidCustomer_Fragment` | Paid customers list |
| `Fragments/Offline_Search_Fragment` / `Offline_searchItemList_Fragment` | Offline search (by name/CRF/LCO ID/mobile) + payment from search |
| `Fragments/Offline_Reports_*` / `Offline_MiniDay_Report_Fragment` | Offline reports (date range, mini day) |
| `Utils/DB_Helper.java` | **SQLite** (SQLiteOpenHelper) — 1199 lines |
| `Offline_Models/Offline_Data_Model.java` | Row model (Parcelable, 36 fields) |
| `Utils/EzyCableDigiConstants.java` | API paths, prefs keys, utility functions |
| `Utils/NetworkChangeReceiver.java` | **BroadcastReceiver** — auto-sync on reconnect |
| `Adapters/Offline_searchdata_Adapter.java` | RecyclerView adapter for offline lists |

### 2.2 API Endpoints (Verified)
```
Base URL = login_serverUrl.replace("/wsController", "")
         = NAMESPACE (e.g. "http://192.168.1.16/testing/ezycabledigi_v2_H8_cloud_live/app/index.php")

Download: POST  {baseUrl}/GetRequest
Sync:     POST  {baseUrl}/GetCollectionData
```

In Flutter terms:
```dart
final baseUrl = ServerUrlResolver.instance.namespace; // = AppConfig.namespace
final downloadUrl = '$baseUrl/GetRequest';
final syncUrl = '$baseUrl/GetCollectionData';
```

---

## 3. Download Flow (✅ Fully Verified)

### 3.1 Two-Step Protocol
`OfflineDataDownload_Fragment` performs a **two-step** download:

**Step 1 — Get record count** (`downloadData_getLengthrequest`):
```
POST {baseUrl}/GetRequest
Content-Type: application/x-www-form-urlencoded

Params:
  ScrNo = machineID(11) + version(3:"019") + command(3:":70") + startcount(3:"   ") + endcount(5:"00000")

Response (raw string):
  First 9 chars = status code (e.g. "@:71 5372")
  - Contains "@:71" → success; chars [4..9] = row_count (trimmed)
  - Otherwise → no records found
```

**Step 2 — Download all records** (`downloadData_request`):
```
POST {baseUrl}/GetRequest
Content-Type: application/x-www-form-urlencoded

Params:
  ScrNo = machineID(11) + version(3:"019") + command(3:":70") + startcount(4:"    ") + endcount(5:zero-padded row_count)

Response (raw string):
  First 9 chars = status code (must contain "@:71")
  Chars [9..end] = customer records (with "#" replaced by "")
  Records are split every 332 characters
```

### 3.2 Record Parsing (332 chars per customer — ✅ verified)
| Offset | Length | Field |
|--------|--------|-------|
| 0-12 | 13 | `LCOid_CRFno` (CRF No, may be empty) |
| 13-25 | 13 | `account_num` (LCO Customer ID) |
| 26-49 | 24 | `name` |
| 50-73 | 24 | `address` |
| 74-86 | 13 | `bill_amount` |
| 87-99 | 13 | `tax_amount` |
| 100-112 | 13 | `pending_amount` |
| 113-125 | 13 | `total_amount` |
| 126-133 | 8 | `month` (billing month) |
| 134-145 | 12 | `mobile_number` |
| 146-158 | 13 | `last_paid_amount` |
| 159-168 | 10 | `last_paid_date` |
| 169-193 | 25 | `businessname` (employee/agent) |
| 194-206 | 13 | `customer_id` |
| 207-219 | 13 | `crf_number` |
| 220-232 | 13 | `lco_cust_id` |
| 233-235 | 3 | `payment_flag` ("000" = current month unpaid) |
| 236-248 | 13 | `discount_amount` |
| 249-261 | 13 | `total_payment_after_discount` |
| 262-271 | 10 | `discount_start_date` |
| 272-281 | 10 | `discount_end_date` |
| 282-294 | 13 | `penalty_amount` |
| 295-307 | 13 | `total_payment_after_penalty` |
| 308-317 | 10 | `penalty_start_date` |
| 318-327 | 10 | `penalty_end_date` |
| 328-331 | 4 | `discount_penalty_flag` (e.g. "0000", "DM00", "DA00", "00PM", "00PA") |

### 3.3 DB Insert After Download
Each parsed record → `db.addContact(new Offline_Data_Model(...))` with:
- `amount` = "0.00" (no payment yet)
- `flag` = 0 (downloaded, unpaid)
- All payment/bank/sync fields = empty strings

### 3.4 SharedPreferences After Download
```java
edit.putInt(OFFLINEFLAG, 0);           // 0 = data inserted (download complete)
edit.putString("total_length", total_records);
edit.putString(USERCODE, LoginActivity.offline_user_code);
edit.putString(MACHINE_ID, LoginActivity.machineNumber);
```

### 3.5 Pre-conditions
- `flag == 1` in SharedPrefs (OFFLINEFLAG) — means previous data is synced/cleared
- Memory check: available > 100MB
- WiFi check: warns if on mobile data, allows "Download Anyway"

---

## 4. Offline Payment Flow (✅ Fully Verified)

### 4.1 Entry Points
Payments can be made from:
1. **Unpaid customer list** (`Offline_unPaidCustomer_Fragment`) — paginated (25/page)
2. **Search results** (`Offline_searchItemList_Fragment`) — by name/CRF/LCO ID/mobile

### 4.2 Payment Dialog (`alertChangeAmountDialog`)
Shows:
- **Cash** (RadioButton "R") or **Bank** (RadioButton "B")
- **Amount** EditText (pre-filled with `total_amount` or discount/penalty-adjusted amount)
- **Send SMS** checkbox ("015" with SMS, "005" without)
- **Discount/Penalty** checkbox (logic based on `discount_penalty_flag` 4-char code)
- **Bank details** (if bank): cheque number, bank name, branch name, instrument date

### 4.3 Discount/Penalty Logic (✅ verified)
`discount_penalty_flag` is a 4-character string: `[disc_flag][disc_auto][penalty_flag][penalty_auto]`
- `disc_flag`: "D" = discount applies, "0" = no discount
- `disc_auto`: "M" = manual (user can check/uncheck), "A" = auto (pre-applied, locked)
- `penalty_flag`: "P" = penalty applies, "0" = no penalty
- `penalty_auto`: "M" = manual, "A" = auto

Date-range check: discount/penalty only applies if `currentDate` is between start/end dates.

### 4.4 Payment Commit (on "Done and Pay")
```java
// Validation
- Amount > 0
- If partial_pay == 1: amount must be >= total_amount
- If bank: all bank fields mandatory

// Set fields on the model
offline_data_model.setFlag(1);                    // PAID (pending sync)
offline_data_model.setAmount(amt);                // paid amount
offline_data_model.setPaymentDate(timeStamp);     // "dd-MM-yyyy HH:mm:ss"
offline_data_model.setLast_paid_date(timestamp2); // "dd-MM-yyyy"
offline_data_model.setLast_paid_amount(amt);
offline_data_model.setPay_mode("R" or "B");       // Cash or Bank
offline_data_model.setSendSMS("005" or "015");    // SMS flag
// Bank only:
offline_data_model.setChequenumber(...)
offline_data_model.setBankname(...)
offline_data_model.setBranchname(...)
offline_data_model.setInsdate(act_CheqDate)       // YYYYMMDD format
// Discount/penalty:
offline_data_model.setDiscount_penalty_flag("DM00"/"00PM"/"0000"/etc.)

// DB Operations (TWO writes):
db_helper.insertContact_afterpayment_aftersync_flag(offline_data_model);
  // → INSERT into offliendataafter_pay (payment queue)
db_helper.updateContact_afterpayment_aftersync_flag(offline_data_model);
  // → UPDATE offline_data_4 SET flag=1, amount=amt, paymentDate=... WHERE customer_id=?
```

### 4.5 Post-Payment Behavior
```java
if (internet available) {
    syncData(offline_data_model);  // Immediate sync attempt
} else {
    navigatetoDisplayCustomerDetails(offline_data_model);  // Show receipt
}
```

### 4.6 Outstanding Amount Calculation
```java
if (discount_penalty_flag contains "D") {
    outstandingAmt = total_payment_after_discount - paidAmount;
} else if (discount_penalty_flag contains "P") {
    outstandingAmt = total_payment_after_penalty - paidAmount;
} else {
    outstandingAmt = total_amount - paidAmount;
}
// Then: db_helper.updateContact_afterpayment_aftersync_flag2(...) updates offline_data_4.total_amount
```

### 4.7 `offliendataafter_pay` Insert (✅ verified — `insertContact_afterpayment_aftersync_flag`)
Writes these columns:
```
customer_id, amount, flag(=1), paymentDate, last_paid_date, last_paid_amount,
bill_amount, pending_amount, name, lco_cust_id, crf_number, total_amount,
tax_amount, address, mobile_num, chequenumber, bankname, branchname, insdate,
sendSMS, pay_mode, discount_penalty_flag
```

---

## 5. Sync Engine (✅ Fully Verified)

### 5.1 Sync Endpoint
```
POST {baseUrl}/GetCollectionData
Content-Type: application/x-www-form-urlencoded
```

### 5.2 Request Parameters
```
type         = "3"
payment_flag = sendSMS value ("005" = no SMS, "015" = with SMS)
buffer       = Base64( request_string )
```

### 5.3 Request String Construction (✅ verified — fixed-length concatenation)
**For Cash (pay_mode = "R"):**
```
machineID(11) + version(3:"019") + command(3:":50") + customer_number(13) +
paid_amount(13) + pay_mode(1:"R") + alt_receiptnumber(25) +
hhtPaidDate(19) + discount_penalty_flag(4)
```

**For Bank (pay_mode = "B"):**
```
machineID(11) + version(3:"019") + command(3:":50") + customer_number(13) +
paid_amount(13) + pay_mode(1:"B") + alt_receiptnumber(25) +
chequenumber(6) + bankname(19) + branchname(19) + insdate(8) +
hhtPaidDate(19) + discount_penalty_flag(4)
```

Where:
- `machineID` = `LoginActivity.machineNumber` (padded to 11)
- `alt_receiptnumber` = `timestamp(ddMMyyyyHHmmss) + customer_id` (padded to 25)
- `hhtPaidDate` = `paymentDate` field (padded to 19)
- All fields right-padded with spaces to fixed length via `fixedLengthString`

### 5.4 Response Handling
```
"ACK" → SUCCESS:
  - Set flag = 2 (synced)
  - db.updateContact_afterpayment_aftersync_flag(model)   → UPDATE offline_data_4
  - db.updateContact_afterpayment_aftersync_flagpay(model) → UPDATE offliendataafter_pay
    (matched by customer_id AND paymentDate)

"NAK" → FAILURE:
  - Set flag = 0 (reset to unpaid — allows retry)
  - Same two update calls
  - Toast: "Not synced"

Other → ERROR:
  - Toast: "Some error occurred"
  - Row remains at flag=1 (will retry)
```

### 5.5 Sync Locations (3 places sync can happen)
1. **SyncData_Fragment** — "Sync" button syncs ALL flag=1 rows in a loop
2. **Offline_Dashboard** — tap a paid item → sync single item (if internet)
3. **Offline_unPaidCustomer_Fragment** — immediate sync after payment (if internet)
4. **NetworkChangeReceiver** — auto-sync on reconnect (per-row)

### 5.6 Clear Data Flow
- Only available when `totalpaid_custs == 0` (all payments synced)
- `db.deleteAllContacts()` → deletes from BOTH `offline_data_4` AND `offliendataafter_pay`
- Resets SharedPreferences: `OFFLINEFLAG = 1`, `total_length = "0"`, `MACHINE_ID = "0"`
- Navigates to LoginActivity (forces re-login for new machine ID)

### 5.7 Batch Sync Logic (SyncData_Fragment)
```java
paid_custList = db.getAllFlagContacts("1");  // from offliendataafter_pay WHERE flag=1
total_paid_sync_custs = paid_custList.size();

// On "Sync" button click:
for (int i = 0; i < paid_custList.size(); i++) {
    if (paid_custList.get(i).getFlag() == 1) {
        syncData(paid_custList.get(i));  // POST each row
    }
}

// After each ACK: recount and update UI
if (total_paid_sync_custs == totalsynced_custs) {
    alertForSuccessSync();  // → navigate to MainActivity
}
```

---

## 6. Database Schema (✅ Fully Verified)

### 6.1 Android `offline_data_4` (customer cache) — 37 columns
| # | Column | Type | Purpose |
|---|--------|------|---------|
| 0 | `id` | INTEGER PK AUTO | Row ID |
| 1 | `lco_crf_no` | TEXT | CRF number (from download) |
| 2 | `account_num` | TEXT | LCO customer ID |
| 3 | `name` | TEXT | Customer name |
| 4 | `address` | TEXT | Address |
| 5 | `bill_amount` | TEXT | Bill amount |
| 6 | `tax_amount` | TEXT | Tax amount |
| 7 | `pending_amount` | TEXT | Pending amount |
| 8 | `total_amount` | TEXT | Total due |
| 9 | `amount` | TEXT | Paid amount (0.00 if unpaid) |
| 10 | `month` | TEXT | Billing month |
| 11 | `mobile_num` | TEXT | Mobile number |
| 12 | `last_paid_amount` | TEXT | Last paid amount |
| 13 | `last_paid_date` | TEXT | Last paid date |
| 14 | `businessname` | TEXT | Business/employee name |
| 15 | `customer_id` | TEXT | Unique customer ID |
| 16 | `crf_number` | TEXT | CRF number |
| 17 | `lco_cust_id` | TEXT | LCO customer ID |
| 18 | `payment_flag` | TEXT | "000" = current month |
| 19 | `flag` | INTEGER | 0=downloaded, 1=paid, 2=synced |
| 20 | `paymentDate` | TEXT | Payment timestamp |
| 21 | `syncpaymentDate` | TEXT | Sync timestamp |
| 22 | `chequenumber` | TEXT | Cheque/DD number |
| 23 | `bankname` | TEXT | Bank name |
| 24 | `branchname` | TEXT | Branch name |
| 25 | `insdate` | TEXT | Instrument date |
| 26 | `sendSMS` | TEXT | "005"/"015" |
| 27 | `pay_mode` | TEXT | "R"=cash, "B"=bank |
| 28 | `discount_amount` | TEXT | Discount amount |
| 29 | `total_after_discount` | TEXT | Total after discount |
| 30 | `discount_start_date` | TEXT | Discount period start |
| 31 | `discount_end_date` | TEXT | Discount period end |
| 32 | `penalty_amount` | TEXT | Penalty amount |
| 33 | `total_after_penalty` | TEXT | Total after penalty |
| 34 | `penalty_start_date` | TEXT | Penalty period start |
| 35 | `penalty_end_date` | TEXT | Penalty period end |
| 36 | `discount_penalty_flag` | TEXT | 4-char flag |

### 6.2 Android `offliendataafter_pay` (payment queue) — same schema
Identical columns to `offline_data_4`. Rows inserted on payment, updated on sync.

### 6.3 Android `bledevices` — 2 columns
`device_name TEXT, device_address TEXT`

### 6.4 Android DB Operations Summary
| Method | Table | Purpose |
|--------|-------|---------|
| `addContact(model)` | offline_data_4 | Insert downloaded customer |
| `getAllContacts()` | offline_data_4 | Get all customers |
| `getAllFlagContacts(flag)` | offliendataafter_pay | Get payments by flag (1=paid, 2=synced) |
| `getAll_paid_Sync_FlagContacts()` | offliendataafter_pay | Get flag IN (1,2) |
| `getTodays_paid_Sync_FlagContacts(date)` | offliendataafter_pay | Today's payments |
| `getAllBetweenDates(start, end)` | offliendataafter_pay | Date range report |
| `getAllspecificContactsByName(filter)` | offline_data_4 | Search by name (LIKE) |
| `getAllspecificContactsByCRFNo(filter)` | offline_data_4 | Search by CRF (exact, NOCASE) |
| `getAllspecificContactsByLcoId(filter)` | offline_data_4 | Search by LCO ID (exact, NOCASE) |
| `getAllspecificContactsByMobile(filter)` | offline_data_4 | Search by mobile (LIKE) |
| `getspecificContactsByCustid(filter)` | offline_data_4 | Get by customer_id (exact) |
| `getAllspecificContactsByLcoId_Prev/Next(id)` | offline_data_4 | Navigate prev/next by row ID |
| `insertContact_afterpayment_aftersync_flag(model)` | offliendataafter_pay | Insert payment record |
| `updateContact_afterpayment_aftersync_flag(model)` | offline_data_4 | Update main table (flag, amount, date) |
| `updateContact_afterpayment_aftersync_flagpay(model)` | offliendataafter_pay | Update payment table (by customer_id AND paymentDate) |
| `updateContact_afterpayment_aftersync_flag1/2(model, id)` | offline_data_4 | Update outstanding amount |
| `getContactsCount()` | offline_data_4 | Total count |
| `deleteAllContacts()` | BOTH tables | Clear all data |
| `deleteContact(model)` | offline_data_4 | Delete single |

### 6.5 Flutter `DatabaseHelper` Current Tables
| Table | Status | Notes |
|-------|--------|-------|
| `customers` | 🟨 dummy-seeded | Has some relevant fields but missing discount/penalty/flag/payment columns |
| `payments` | 🟨 partial | Has sync flag but no queue semantics (005/015, receipt#, bank details) |
| `collection_schedules` | legacy | No longer needed |

### 6.6 Schema Gap
Flutter must gain:
1. A real **customer cache table** matching Android's `offline_data_4` (all 36 data columns)
2. An **offline-payment queue table** matching `offliendataafter_pay` (or extend `payments` with full flag/bank/discount semantics)

---

## 7. Offline Dashboard (✅ Verified)

### 7.1 `Offline_Dashboard.java`
- Shows **paid customers** (flag=1) from `offliendataafter_pay` in a RecyclerView
- Displays count: "Total - {paid_count}"
- **Tap item** → if internet → offer sync dialog → sync single item
- **"Search Customer"** → navigate to `Offline_Search_Fragment`
- **"Reports"** → navigate to `Offline_Reports_Home_Fragment`
- **"View All" / "No payments"** → navigate to `Offline_Tabs_Fragment` (paid/unpaid tabs)

### 7.2 Unpaid List Filtering
- Default: `flag == 0` (not paid)
- **Current month checkbox**: additionally filter `payment_flag == "000"`
  - Checked: current month unpaid only
  - Unchecked: all unpaid (flag==0 AND payment_flag != "000" → previous months)
- Pagination: 25 items per page with Prev/Next buttons

### 7.3 Offline Search
4 search types (by name LIKE, CRF exact NOCASE, LCO ID exact NOCASE, mobile LIKE):
- `getAllspecificContactsByName`, `getAllspecificContactsByCRFNo`, `getAllspecificContactsByLcoId`, `getAllspecificContactsByMobile`
- Results shown in `Offline_searchItemList_Fragment` with Prev/Next record navigation

---

## 8. Connectivity & Auto-Sync (✅ Verified)

### 8.1 Android
- `NetworkChangeReceiver extends BroadcastReceiver` — registered for `CONNECTIVITY_ACTION`
- On reconnect: queries all flag=1 rows, POSTs each to `/GetCollectionData`
- Per-row sync (same `syncData` method as manual sync)

### 8.2 Flutter Current State
- `connectivity_plus` used in dashboard/login/splash/app_drawer for **detection** only
- Manual offline-mode toggle via `OfflineModeService`
- **No auto-sync listener exists**

---

## 9. Error Handling (✅ Verified from code)

| Scenario | Android Behavior | Flutter Must Replicate |
|----------|-----------------|----------------------|
| No internet during download | Toast "No data downloaded, please try again" | Same |
| PHP error in response | Alert dialog with error message | Same |
| No records found | Alert "No records found to download" | Same |
| Download on mobile data | Warn "may charge", offer "Download Anyway" or "Settings" | Same |
| Memory < 100MB | Toast "not enough memory" | Same |
| Sync returns "ACK" | Set flag=2, update both tables | Same |
| Sync returns "NAK" | Set flag=0 (reset), toast "Not synced" | Same |
| Sync network error | Toast "Data not synced, please try again", row stays flag=1 | Same |
| Sync other error | Toast "Some error occurred" | Same |
| Amount <= 0 | Toast "Due amount is 0.00 or less" | Same |
| Amount empty | Toast "Amount cannot be 0.00 or empty" | Same |
| Partial pay violation | Alert "Entered amount should be >= pending" | Same |
| Bank fields empty | Toast "All fields mandatory" | Same |
| Already paid (flag 1/2) | Toast "Payment already made" | Same |
| All synced successfully | Alert "All payments successfully synced" → MainActivity | Same (go online) |
| Clear data with pending | Toast "Please sync all paid customer first" | Same |
| App restart mid-sync | Unsynced rows remain at flag=1, re-synced on next attempt | Same |

---

## 10. Flutter Investigation — Reuse Classification

| Component | File | Classification |
|-----------|------|---------------|
| Offline mode flag | `core/services/offline_mode_service.dart` | ✅ **REUSE** — extend with machine ID, user code |
| Sync service | `core/services/offline_sync_service.dart` | 🔴 **REPLACE** — dummy → real sync engine |
| SQLite helper | `core/database/database_helper.dart` | 🟨 **EXTEND** — add real cache + queue tables |
| Customer model | `core/data/customer.dart` | 🟨 **EXTEND** — add missing Android fields |
| Payment model | `core/data/payment.dart` | 🟨 **EXTEND** — add bank/discount/flag fields |
| Payment flow | `features/offline/offline_payment_flow.dart` | 🟨 **EXTEND** — add queue semantics, bank, discount |
| Payment dialog | `features/offline/widgets/offline_payment_dialog.dart` | 🟨 **EXTEND** — add bank/SMS/discount UI |
| Unpaid list | `features/offline/offline_unpaid_list_screen.dart` | 🟨 **EXTEND** — bind to real cache, pagination |
| Dashboard | `features/offline/offline_dashboard_screen.dart` | 🟨 **EXTEND** — bind to real paid list |
| Download screen | `features/offline/download_records_screen.dart` | 🟨 **EXTEND** — real download API |
| Mini day report | `features/offline/miniday_report_screen.dart` | 🟨 **EXTEND** — bind to real payment queue |
| REST client | `core/network/rest_client.dart` | ✅ **REUSE** — add raw string POST (non-JSON) |
| Session service | `core/services/session_service.dart` | ✅ **REUSE** — add machineNumber field |
| Server URL resolver | `core/network/server_url_resolver.dart` | ✅ **REUSE** — namespace already exposed |
| Connectivity | `connectivity_plus` package | ✅ **REUSE** — wire to auto-sync |

---

## 11. Gap Analysis

| Android Feature | Flutter Status | Risk | Work Required |
|----------------|---------------|------|---------------|
| Download customers (`/GetRequest`) | ❌ Missing | **High** | Real download + parse 332-char records |
| Customer cache (`offline_data_4`) | ❌ Missing (dummy) | **High** | New table with 36 columns |
| Payment queue (`offliendataafter_pay`) | ❌ Missing | **High** | New table or extend `payments` |
| Sync engine (`/GetCollectionData`) | ❌ Missing (placeholder) | **High** | Real POST + Base64 buffer + reconcile |
| Auto-sync on reconnect | ❌ Missing | **High** | `connectivity_plus` listener |
| Flag semantics (0/1/2) | ❌ Missing | **High** | Column + lifecycle logic |
| Payment dialog (bank/SMS/discount) | 🟨 Partial | **Med** | Extend dialog UI |
| Offline search (4 types) | 🟨 Partial | **Med** | Bind to real cache + queries |
| Pagination (25/page) | ❌ Missing | **Low** | Add pagination to list |
| Discount/penalty logic | ❌ Missing | **Med** | 4-char flag parse + date range check |
| Duplicate prevention | ❌ Missing | **Med** | Flag guards + customer_id+paymentDate key |
| Clear data flow | ❌ Missing | **Low** | Delete + prefs reset + re-login |
| Memory check before download | ❌ Missing | **Low** | Check available storage |
| Receipt from offline payment | ✅ Exists | **Low** | Verify data binding |
| Machine ID in session | ❌ Missing | **Med** | Add to SessionService + login flow |
| Connectivity detection | ✅ Exists | **Low** | Wire to auto-sync |
| Manual offline toggle | ✅ Exists | **Low** | Keep |

---

## 12. Implementation Plan

### Phase A — Foundation (Est: 1 day)
**Goal:** Online/offline switch working; infrastructure ready.
- Add `machineNumber` to `SessionService` (populated from login response)
- Extend `OfflineModeService` with `userCode`, `machineId`, `totalLength`, `offlineFlag` prefs
- Add `postRaw()` to `RestClient` (returns raw string, not JSON) for `/GetRequest` + `/GetCollectionData`
- Wire `connectivity_plus` stream to a central connectivity notifier
- **DoD:** prefs store offline state; RestClient can POST and receive raw strings

### Phase B — SQLite Schema (Est: 1 day)
**Goal:** Real tables exist, no dummy data.
- Add `offline_customers` table (37 columns matching Android `offline_data_4`)
- Add `offline_payments` table (matching Android `offliendataafter_pay` — 22 relevant columns)
- Additive migration (keep existing tables for backward compat)
- Remove dummy-seed code from offline paths
- **DoD:** Tables created on app start; no dummy data; `flutter analyze` clean

### Phase C — Customer Download (Est: 2 days)
**Goal:** Real `/GetRequest` download populates cache.
- Implement two-step download: count request → data request
- Parse 332-char records into `offline_customers` table
- Update `download_records_screen.dart` to trigger real download
- Bind unpaid list + search to `offline_customers` table
- Pre-conditions: memory check, WiFi check, flag check
- **DoD:** Downloaded customers appear in offline list; search works against real data

### Phase D — Offline Payments (Est: 2 days)
**Goal:** Payment creates a proper queue entry with full semantics.
- Extend payment dialog: cash/bank radio, SMS checkbox, bank fields, discount/penalty logic
- On payment: INSERT into `offline_payments` (flag=1) + UPDATE `offline_customers` (flag=1)
- Receipt generation from local payment data
- Duplicate guard: check flag before allowing payment
- Outstanding amount calculation (discount/penalty aware)
- **DoD:** Payment persists locally; receipt prints; duplicate blocked; pagination works

### Phase E — Sync Engine (Est: 2 days)
**Goal:** Real sync replaces placeholder.
- Build sync request string (fixed-length fields + Base64 encoding)
- POST to `/GetCollectionData` with `type=3`, `payment_flag`, `buffer`
- Handle "ACK" → flag=2 on both tables
- Handle "NAK" → flag=0 (reset for retry)
- Handle error → keep flag=1, show toast
- Per-row sync (not batch — matches Android)
- **DoD:** Queued payments reach server exactly once; flags update correctly

### Phase F — Auto-Sync & Dashboard (Est: 1 day)
**Goal:** Reconnect triggers sync; dashboard shows correct counts.
- `connectivity_plus` stream listener → on reconnect, query flag=1 rows, sync each
- Dashboard: show paid count, sync individual items, navigate to lists/reports
- SyncData screen: show paid/synced/total counts, "Sync All" button
- Clear data flow: only if no pending payments; delete both tables; reset prefs
- **DoD:** Reconnect auto-syncs; dashboard counts are accurate; clear data works

### Phase G — Search & Reports (Est: 1 day)
**Goal:** Full offline search and reporting parity.
- 4 search types: name (LIKE), CRF (exact NOCASE), LCO ID (exact NOCASE), mobile (LIKE)
- Prev/Next record navigation
- Reports: today's payments, date range, mini day report
- **DoD:** All search types return correct results; reports match paid data

### Phase H — Hardening (Est: 1 day)
**Goal:** Error handling, edge cases, robustness.
- All error scenarios from §9 implemented
- App restart safety: unsynced rows survive
- Partial sync safety: per-row marking
- Idempotent sync (Base64 receipt number is unique per payment)
- `flutter analyze` clean
- Test against live server
- **DoD:** No payment ever lost; all Android error behaviors replicated

---

## 13. Cross-Cutting / Reuse Rules

- **Endpoints:** `ServerUrlResolver.instance.namespace + "/GetRequest"` and `+ "/GetCollectionData"`
- **Reuse:** `RestClient`, `SessionService`, `ServerUrlResolver`, `DatabaseHelper`, `OfflineModeService`, `connectivity_plus`
- **Do NOT duplicate** — extend existing code
- **Fixed-length padding:** Flutter equivalent of `String.format("%1$Ns", str)` → `str.padLeft(N)` or `str.padRight(N)`
- **Base64:** `dart:convert` → `base64Encode(utf8.encode(requestString))`

---

## 14. Definition of Done (Module)

- [ ] Real download populates a real cache; offline reads come from it
- [ ] Offline payments queue with Android flag semantics (0/1/2); receipts print
- [ ] Real sync POSTs to `/GetCollectionData`; only server-confirmed rows cleared; idempotent
- [ ] Auto-sync on reconnect; manual sync available
- [ ] No payment ever lost (restart/interrupt/duplicate safe)
- [ ] All 4 search types work against real cache
- [ ] Discount/penalty logic matches Android behavior
- [ ] Dashboard counts accurate (paid/synced/total)
- [ ] Clear data only after all synced; resets state
- [ ] `flutter analyze` clean; verified live on test server

---

## 15. Key Constants Reference

```dart
// API commands (from EzyCableDigiConstants.java)
const downloadCommand = ':70';  // GET_REQUEST_DOWNLOADDATA
const syncCommand = ':50';      // GETCOLLECTIONDATA_SYNCDATA
const version = '019';

// Fixed lengths for request construction
// machineID: 11, version: 3, command: 3, customer_number: 13
// paid_amount: 13, pay_mode: 1, alt_receiptnumber: 25
// chequenumber: 6, bankname: 19, branchname: 19, insdate: 8
// hhtPaidDate: 19, discount_penalty_flag: 4
// Download: startcount: 4, endcount: 5

// Flag values
const flagDownloaded = 0;  // Downloaded, unpaid
const flagPaid = 1;        // Payment made, pending sync
const flagSynced = 2;      // Synced to server

// SMS flags (sendSMS / payment_flag for sync)
const smsNo = '005';   // Offline payment WITHOUT SMS
const smsYes = '015';  // Offline payment WITH SMS

// Payment mode
const payModeCash = 'R';
const payModeBank = 'B';

// SharedPreferences keys
const offlinePref = 'offlinedata_pref';
const offlineFlag = 'offlinedataflag';  // 0=data present, 1=cleared/synced
const machineIdKey = 'machineNumber';
const userCodeKey = 'usercode';
const totalLengthKey = 'total_length';

// Record parsing
const recordLength = 332;  // chars per customer record in download response
```

---

## 16. Login Response Fields for Offline (✅ Verified — LoginActivity.java:607-776)

All from the `validateLogin` SOAP response:
| Field | Variable | Purpose |
|-------|----------|---------|
| `machineNumber` | `LoginActivity.machineNumber` | Device machine ID for sync requests (11 chars) |
| `offline_user_code` | `LoginActivity.offline_user_code` | Stored in SharedPrefs for offline identity |
| `offlineStatus` | `LoginActivity.offlineStatus` | 1 = offline feature enabled for this user |
| `lovvalue_restrict_partial_payment` | `LoginActivity.lovValue_restrict_partial_payment` | 1 = amount must be >= total_amount |
| `hhtoption` | `LoginActivity.hhtoption_search` | Search option config |
| `current_date` | `LoginActivity.current_date` | Server date for discount/penalty range checks |

**Flutter action:** Add these to `SessionService` from the existing `validateLogin` response parsing in `AuthService.login()`.

---

## 17. Open Items (minimal)

- 🟡 Exact `NetworkChangeReceiver` registration (manifest vs dynamic) — implementation detail for Flutter (use `connectivity_plus` stream instead)
- 🟡 Whether offline entry requires explicit user action (Android: user manually navigates to `Offline_Activity` after download; not automatic)
- ✅ All API protocols, DB schemas, payment flows, sync flows, and login fields are now fully verified
