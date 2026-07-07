# Offline Mode — Android Investigation (Phase 1, NO CODE)

> Source of truth: Android `D:\Git-Repos\magikdigi` (READ-ONLY). Every claim cites a file:line.
> Tags: ✅ Verified in source · 🟡 Not Yet Verified (needs runtime/server).
> Scope: offline login, dealer validation, fresh-install, data requirement, dashboard, SQLite, payments, sync, errors, security.

---

## 0. Files traced
| File | Role |
|---|---|
| `activities/LoginActivity.java` | online + **offline login gate** (the 2-day window) |
| `activities/Offline_Activity.java` | offline container activity (hosts dashboard) |
| `Fragments/Offline_Dashboard.java` | offline home (paid list + per-payment sync) |
| `Fragments/Offline_unPaidCustomer_Fragment.java` | offline **payment creation** |
| `Fragments/OfflineDataDownload_Fragment.java` | **download** (`:70`, fixed-width parse) |
| `Fragments/SyncData_Fragment.java` | **bulk sync** button (batches of 25) |
| `Utils/NetworkChangeReceiver.java` | connectivity receiver (**auto-sync commented out**) |
| `Utils/DB_Helper.java` | SQLite (3 tables, v4) |
| `Utils/EzyCableDigiConstants.java` | `isNetworkAvailable`, prefs keys, endpoints |

---

## 1. Offline Login — exact flow

✅ **Android REQUIRES a prior successful online login**, and gates offline entry on a **2-day freshness window** of the last online-login date. No credentials are entered or verified offline.

**Evidence — `LoginActivity.java`:**
- `onCreate`: when offline, the **username & password fields are disabled** so you cannot type credentials:
  ```
  248  if (!EzyCableDigiConstants.isNetworkAvailable(LoginActivity.this)) {
  249      userName.setEnabled(false);
  250      userPassword.setEnabled(false);
  ```
- On **Login tap**, after `isNetworkAvailable()`, if there is **no network** (`activeNetworkInfo == null`, line 271/329):
  ```
  275  current_days_login = settingsPref.getString(current_dates_login, "");   // saved at last ONLINE login
  277  datediff(current_days_login, formattedDate);                            // → dayDifference
  278  if (dayDifference <= 2) {  → start Offline_Activity (offline dashboard)  // lines 279-293
       } else {                  → AlertDialog "Please go online and sync previous offline collections data"
                                    title "Sync Previous data" → OK → finish() + System.exit(0)   // 294-305
  ```
- `current_dates_login` is written **only on a successful online login** (`LoginActivity.java:812` `.putString(current_dates_login, current_date)`), where `current_date` is the **server's** date from the login response.

✅ **What is stored after a successful online login** (all **plaintext SharedPreferences**; nothing in SQLite):
| Value | Where (SharedPreferences file) | Key |
|---|---|---|
| Username, Password (if Remember-Me) | `SPF_NAME` | `USERNAME`, `PASSWORD` (`LoginActivity.java:792-794`) |
| Server login date | `SPF_NAME_LOGIN` | `current_dates_login` (`:812`) |
| App theme, CRF no, hht option, amt-round, format, customer-discount, enable-cust-disc | `SPF_NAME_LOGIN` | `app_theme_login`, `crfno_login`, `hhtoption_login`, `amtroun_login`, `formats`, `customer_dic`, `enable_cust_disc` (`:808-817`) |
| Business name, offline_user_code, machine no, offlineStatus | static fields + `OFFLINEPREF` | `businessName` (`:640`), `USERCODE` (`:708`), `MACHINE_ID` |
| authToken, dealerId, employeeId | **static fields** `LoginActivity.authToken/dealerId/employeeId` (+ BMS prefs) | — |
| Partial-pay flag | `partial_pay` prefs | `partial_pay` |

- **Auth token / dealer id / employee id are NOT read or used during offline entry.** They live in static fields that die with the process; offline login never references them.
- Storage is **plain text** (`Context.MODE_PRIVATE` SharedPreferences). No encryption. (§10.)

---

## 2. Dealer Validation when offline — **THE key finding**

✅ **Android performs NO dealer validation offline.** It does **not** compare username, dealer_id, authToken, dealer URL, business name, or any password hash. The *entire* offline gate is:

> **"Is the last *online*-login date ≤ 2 days old?"** (`LoginActivity.java:278`)

- If yes → it **trusts** the locally-stored login settings + downloaded SQLite data and opens `Offline_Activity`.
- If no → "Sync Previous data" dialog → app exits.

There is no other check. The dealer is implicitly "valid" because the device logged in online within the last 2 days. ✅ (verified: the offline branch at `LoginActivity.java:270-305` references only `current_dates_login` and `dayDifference`.)

---

## 3. Fresh-install scenarios (A / B / C)

✅ **`datediff` swallows a bad/empty date** and leaves `dayDifference` at its **default `0`** (`LoginActivity.java:1039-1052` — `parse("")` throws → caught → field unchanged → `0`). Combined with `Offline_Activity` performing **no data-presence check** (`Offline_Activity.java:94-95` just loads `getAllContacts()`), the three cases are:

| Case | State | What Android does | Evidence |
|---|---|---|---|
| **A. Fresh install, never logged in, offline** | `current_dates_login=""` | `datediff("")`→ exception → `dayDifference=0` → `0<=2` **true** → opens **Offline_Activity with EMPTY data** (no crash, no block) | `LoginActivity.java:1046-1051`, `278`; `Offline_Activity.java:94` |
| **B. Logged in once, downloaded data, offline ≤2 days** | date fresh, `offline_data_4` populated | Opens Offline_Activity → Offline_Dashboard with downloaded customers; can pay, view reports, sync | `LoginActivity.java:279-293` |
| **C. Logged in once, NEVER downloaded data, offline ≤2 days** | date fresh, `offline_data_4` empty | Opens Offline_Activity → dashboard shows **empty** lists (unpaid empty; "No payments"). No block. Cannot pay (no customers to select). | `Offline_Activity.java:94-95`; `Offline_Dashboard.java:88-111` |
| **(>2 days, any data)** | stale date | **BLOCKED**: "Please go online and sync previous offline collections data" → exit | `LoginActivity.java:294-305` |

🟡 *Runtime note:* Case A's "fresh install enters empty offline dashboard" is a **side-effect of the `datediff` exception** (not an explicit allow). It is the literal verified behavior, but is almost certainly unintended. Flag for the parity decision in Phase 3 — Android does **not** cleanly block fresh-install offline; it shows an empty offline dashboard.

---

## 4. Offline-data requirement

✅ **The offline dashboard does NOT require a prior download to open.** `Offline_Activity` opens regardless and simply renders whatever is in `offline_data_4` (empty → empty lists). There is **no "you must download data first" gate** anywhere in the offline-entry path.
- Download is a **separate, optional, online action** (`OfflineDataDownload_Fragment`, reached from the drawer while online).
- Offline modules that depend on data (unpaid list, payments, reports) are simply **empty** if nothing was downloaded.
- `OFFLINEPREF.USECAF` ("1 if data is not inserted", `Offline_Activity.java:62`) is read but **not used to block** entry.

---

## 5. Offline Dashboard — module matrix

✅ The offline dashboard is **intentionally minimal**. Only three actions exist (`Offline_Dashboard.java`): **Search Customer**, **Reports**, and the **paid-payment list + per-payment Sync**. All online-only modules are simply **absent** (not hidden/disabled — they were never added to the offline UI).

| Module | Offline behaviour | Evidence |
|---|---|---|
| Dashboard (home) | ✅ Works — shows paid-pending list (flag=1), "Total - N", or "No payments" | `Offline_Dashboard.java:88-111` |
| Search Customer | ✅ Works — local SQLite search (`Offline_Search_Fragment`) | `:113-121` |
| Unpaid customers (tabs) | ✅ Works — `Offline_Tabs_Fragment` (paid/unpaid from SQLite) | `:160-181` |
| Payments | ✅ Works — `Offline_unPaidCustomer_Fragment` (commit to SQLite) | §7 |
| Reports | ✅ Works (offline) — `Offline_Reports_Home_Fragment` → MiniDay collections from local paid rows | `:123-134`, `Offline_MiniDay_Report_Fragment.java` |
| Per-payment Sync | ✅ Works (online only) — tap a flag=1 row → "Do you want to sync this payment?" | `:144-251` |
| Nearest customers | 🔴 **Absent** offline (online-only) | not referenced in offline fragments |
| Complaints | 🔴 Absent offline | — |
| Collection Schedule (Pay Later) | 🔴 Absent offline | — |
| Employee Track | 🔴 Absent offline | — |
| Expenses | 🔴 Absent offline | — |
| Package Operations | 🔴 Absent offline | — |
| Settings | 🔴 Absent offline | — |
| Bluetooth printer | 🟡 Hidden on offline toolbar (`img_bluetooth.setVisibility(GONE)`, `Offline_Activity.java:66`) but receipt print still works via the receipt screen | `Offline_Activity.java:65-74` |
| Back button | ✅ "Press 'Exit' to close the application." / "Are you sure?" → Exit/Cancel | `Offline_Dashboard.java:199-218` |

---

## 6. SQLite — full schema

✅ **DB**: name `offline_database_4`, **version 4** (`DB_Helper.java:28-31`). **3 tables.** `onUpgrade` = **DROP all + recreate** (no migration; offline data is lost on a version bump — `:176-184`).

| Table | Purpose | PK | Notable cols |
|---|---|---|---|
| `offline_data_4` | **Downloaded customers** (master) | `_id INTEGER PRIMARY KEY` | `customer_id TEXT NOT NULL`, `flag INTEGER`, `payment_flag TEXT`, 37 cols incl. discount/penalty | 
| `offliendataafter_pay` | **Offline payment queue** (one row per payment) | `_id INTEGER PRIMARY KEY` | same 37 cols (carries payment snapshot) |
| `bledevices` | Saved BLE printer | *(none)* | `devicename`, `devaddress` |

✅ **`flag` semantics** (the sync state machine), verified across fragments:
| flag | meaning | set where |
|---|---|---|
| `0` | unpaid / freshly downloaded (also: NAK reset) | download (`_parseRecord` flag 0); NAK (`Offline_Dashboard.java:293`) |
| `1` | **paid offline, pending sync** | `Offline_unPaidCustomer_Fragment.java:611,685` |
| `2` | **synced to server** (ACK) | `Offline_Dashboard.java:266`, `SyncData_Fragment.java:187` |

- **Keys/Indexes/FKs**: only the `_id` primary keys above. **No foreign keys, no indexes, no unique constraints.** `customer_id` is `NOT NULL` but **not unique** (duplicates possible in the pay queue).
- **Deletes**: `deleteAllContacts()` wipes `offline_data_4` (used before a fresh download / on clear). 
- **Updates**: `updateContact_afterpayment_aftersync_flag` (master) + `...flagpay` (queue) flip `flag`/`syncpaymentDate`.
- **Conflict handling / dedupe**: **none at the DB level** — dedupe is purely UI (the unpaid tab only lists flag=0; once paid the row becomes flag=1 and leaves the unpaid list). 🟡

---

## 7. Offline Payments — full flow

✅ **Creation** (`Offline_unPaidCustomer_Fragment.java`, cash `:655-` / bank `:573-`):
1. Validate amount: not empty, `>= 1`; if `Offline_Activity.partial_pay == 1`, amount **must be ≥ total_amount** else dialog *"Entered payable amount should be greater than or equal to your pending amount"* / *"Invalid Amount!"* (`:586-605`).
2. Bank mode requires cheque/bank/branch/date else *"All fields are mandatory. Please fill bank details."* (`:574-579`).
3. Set on the model: `flag=1`, `amount`, `paymentDate = timeStamp(ddMMyyyyHHmmss)`, `pay_mode` = `"B"`(bank)/`"R"`(cash), `sendSMS` = `"015"`(sms)/`"005"`(no-sms), cheque/bank/branch/insdate for bank (`:611-639`, `:685-`).
4. Persist: `updateContact_afterpayment_aftersync_flag` (master row → flag 1) **and** `insertContact_afterpayment_aftersync_flag` (insert into pay queue) (`:640-641`).
5. Toast *"Payment accepted for - <name>"* (`:642`).
6. **If online → immediately `syncData(model)`** (`:644-646`); **if offline → `navigatetoDisplayCustomerDetails` (print receipt)** (`:649`).

✅ **Receipt number** = `timeStamp + customer_id` (ddMMyyyyHHmmss + custid), generated at sync (`Offline_Dashboard.java:326`) — same formula used for the printed receipt.
✅ **Duplicate prevention**: a paid row becomes flag=1 → it **leaves the unpaid (flag=0) tab**, so it cannot be selected again. (The explicit `if(flag==1||flag==2)` guards at `Offline_unPaidCustomer_Fragment.java:180,233` are **commented out** — dedupe relies on list filtering, not a hard guard.) 🟡
✅ **Customer balance**: updated implicitly via the paid row leaving unpaid; the master row keeps the snapshot. No separate ledger.
🟡 **Rollback**: on sync **NAK**, the row is reset to **flag=0** (`Offline_Dashboard.java:293`) — i.e. the payment is undone and the customer returns to unpaid.

---

## 8. Offline Sync

✅ **Sync is MANUAL.** There are exactly **three** triggers; there is **no connectivity-driven auto-sync** (the `NetworkChangeReceiver.onReceive` auto-sync block is **entirely commented out**, `NetworkChangeReceiver.java:60-105`):
1. **At payment time, if online** → auto-sync that one payment (`Offline_unPaidCustomer_Fragment.java:646`).
2. **Per-payment** → tap a flag=1 row on the offline dashboard (online) → "Do you want to sync this payment?" → Sync (`Offline_Dashboard.java:144-251`).
3. **Bulk** → "Sync Data" button (`SyncData_Fragment.java:129-156`) — iterates flag=1 in **batches of 25** (`:109,143-152`).

✅ **Wire format** (`Offline_Dashboard.java:316-350`, identical in SyncData): endpoint `loginServerUrl(without /wsController) + GETCOLLECTIONDATA_SYNCDATA`. Fixed-width **Base64** buffer:
`machineID(11)+version("019",3)+command(":50",3)+customer_number(13)+paid_amount(13)+pay_mode(1)+alt_receiptnumber(25)` then, **bank only**, `+cheque(6)+bank(19)+branch(19)+insdate(8)`, then `+hhtPaidDate(19)+discount_penalty_flag(4)`. Params: `type=3`, `payment_flag=sendSMS`, `buffer=<base64>`. Retry policy **200 s** timeout (`:362`).

✅ **Response handling** (`Offline_Dashboard.java:265-303`):
| Response | Action | Toast |
|---|---|---|
| `ACK` | flag→2, set `syncpaymentDate`, update both tables | "Successfully updated " |
| `NAK` | flag→0 (revert to unpaid) | "Not synced - " + response |
| other | no change | "Some error occurred." + response |
| Volley error | no change (stays flag=1) | "Error - Data not synced, please try again." |
| Exception | no change | "Error syncing data. Please contact Customer Care" |

🟡 Partial success (bulk): each payment is independent; failures stay flag=1 for retry. No transaction across the batch. Timeout/drop → stays flag=1 (safe).

---

## 9. Error popups — exact text (verbatim, do NOT summarize)

| # | Text (message / title) | Trigger | File:line |
|---|---|---|---|
| 1 | "Please go online and sync previous  offline collections data " / "Sync Previous data" | offline, last login >2 days → then **exit app** | `LoginActivity.java:296-300` |
| 2 | "UserName and Password should not be Empty" / "Empty Fields!" | online login, empty fields | `LoginActivity.java:308-309` |
| 3 | "No Internet Connection." | tap a paid row to sync while offline | `Offline_Dashboard.java:149` |
| 4 | "Do you want to sync this payment?." / "Are you sure?" | tap flag=1 row online | `Offline_Dashboard.java:233-234` |
| 5 | "Payment accepted for - <name>" | offline payment committed | `Offline_unPaidCustomer_Fragment.java:642` |
| 6 | "Successfully updated " | sync ACK | `Offline_Dashboard.java:270` |
| 7 | "Not synced - <response>" | sync NAK | `Offline_Dashboard.java:296` |
| 8 | "Some error occurred.<response>" | unknown sync response | `Offline_Dashboard.java:298` |
| 9 | "Error - Data not synced, please try again." | Volley error on sync | `Offline_Dashboard.java:311` |
| 10 | "Error syncing data. Please contact Customer Care" | exception during sync | `Offline_Dashboard.java:302` |
| 11 | "All fields are mandatory. Please fill bank details." | bank payment missing fields | `Offline_unPaidCustomer_Fragment.java:579` |
| 12 | "Entered payable amount should be greater than or equal to your pending amount" / "Invalid Amount!" | partial_pay=1 and amount < total | `Offline_unPaidCustomer_Fragment.java:592-593` |
| 13 | "Amount cannot be 0.00 or empty." | zero/empty amount | `Offline_unPaidCustomer_Fragment.java:584,658` |
| 14 | "No payments has been made (or) Check your internet connection." | bulk sync with nothing pending / offline | `SyncData_Fragment.java:156` |
| 15 | "Please sync all paid customer before you clear offline data." | clear-data with pending flag=1 | `SyncData_Fragment.java:167` |
| 16 | "Press 'Exit' to close the application." / "Are you sure?" | back press on offline dashboard | `Offline_Dashboard.java:201-202` |
| 17 | "Incomplete data, please re-download the data." | DB count ≠ saved total | `NetworkChangeReceiver.java:100` **(commented out — inactive)** |

---

## 10. Offline Security

| Aspect | Android | Evidence |
|---|---|---|
| SQLite encryption | ❌ **None** (plain SQLite, no SQLCipher) | `DB_Helper.java` (no cipher import) |
| SharedPreferences encryption | ❌ **None** (`MODE_PRIVATE`, plaintext) | throughout |
| Password storage | **Plaintext** in `SPF_NAME` (Remember-Me) | `LoginActivity.java:792-794` |
| Auth token offline | **Not used** offline (no token check) | §2 |
| Dealer verification offline | ❌ **None** — only the 2-day date window | §2 |
| Offline payment protection | dedupe by list filtering; NAK reverts | §7 |
| Prevent another dealer using same data | ❌ **None** — data is on-device, no per-dealer lock; reuse gated only by the 2-day window | §2 |
| Prevent copied database | ❌ **None** — no integrity/HMAC check | — |

➡️ Per the directive, **introduce nothing Android lacks**. Offline security is "trust the device + 2-day recency." Flutter must not add encryption/binding that Android doesn't have, and must not *remove* protections it already has (e.g., Flutter already keeps the auth token in secure storage — keep that, it doesn't affect offline).
