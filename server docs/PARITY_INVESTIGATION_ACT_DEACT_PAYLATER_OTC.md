# Android Parity Investigation: Act/Deact Report, Pay Later, One Time Charges

> Generated from Android source: `D:\Git-Repos\magikdigi`  
> Date: 2026-06-29

---

## 1. ACT/DEACTIVATE REPORT

### Android Source Files
| File | Purpose |
|------|---------|
| `Fragments/Act_Deact_Report.java` | Fragment — fetches & displays report |
| `Adapters/ActdeactAdapter.java` | ListView adapter — renders rows |
| `complexclasses/ActdeactModel.java` | Data model |

### API Endpoint
- **URL**: `NAMESPACE + /packagelist/packageActDeactReport` (config key: `padr`)
- **Method**: POST (form-encoded, Volley StringRequest)
- **Timeout**: 100,000ms

### Request Parameters
```
dealer_id       → LoginActivity.dealerId (String)
employee_id     → LoginActivity.employeeId (String)
customer_id     → passed via Bundle (the server's internal customer_id)
imei            → LoginActivity.imeiNo
authtoken       → LoginActivity.authToken
```

### Response Structure
```json
{
  "status_code": 0,
  "status_msg": "...",
  "package_act_deact_report": "[{...}, {...}]"   // JSON array as string
}
```

### Response Fields (per item in `package_act_deact_report` array)
| JSON Key | Model Field | Display Label |
|----------|-------------|---------------|
| `name` | PackageName | Package Name |
| `box_number` | BoxNumber | Box Number |
| `operation_type` | OperationType | Operation Type |
| `created_on` | CreatedDate | Created Date |
| `error_msg` | ErrorMessage | Error Message |
| `created_name` | Createdby | Created By |

### UI Layout (Android `row_actdeact.xml`)
Each row shows 6 fields:
1. Package Name (`actdeact_itemlist_pname`)
2. Box Number (`actdeact_itemlist_boxnum`)
3. Operation Type (`actdeact_itemlist_opttype`)
4. Created Date (`actdeact_itemlist_crdate`)
5. Error Message (`actdeact_itemlist_errmsg`)
6. Created By (`actdeact_itemlist_crby`)

### Header
- Customer Name (`actdct_cname`)
- LCO Customer ID (`actdct_lcoid`)

### Error Handling
- `status_code == 1` → AlertDialog "No Details Found!" + pop back stack
- Volley error → Toast "Failed."
- Response may contain `<br>` tags — Android strips them before parsing

### Access Control
- Denied if `userType == "SERVICE"` or `customerType == "BroadBand"`

### Navigation (Android)
- Opened from `CustomerOperations_Fragment` → button `custoper_btn_actdeact`
- Receives Bundle: `customerid`, `lcocustid`, `crf`, `customername`

---

## 2. PAY LATER (Collection Schedule Report)

### Android Source Files
| File | Purpose |
|------|---------|
| `Fragments/PayLaterReport.java` | Full report screen with filters |
| `Adapters/PayLaterAdapter.java` | RecyclerView adapter |
| `complexclasses/PaylaterModel.java` | Data model |

### API Endpoint
- **URL**: `NAMESPACE + /digi_rest_api/scheduled_collection_data` (config key: `paylaterList`)
- **Method**: POST (form-encoded via `ApiCallRestClient`)
- **Caller tag**: `"scheduled_collection_data"`

### Request Parameters
```
customer_id             → "" (empty for report, specific for per-customer)
customer_name           → from filter EditText
account_number          → from filter EditText
crf_number              → from filter EditText
dealer_id               → LoginActivity.dealerId
scheduled_start_date    → selected date (yyyy-MM-dd), defaults to today
scheduled_end_date      → selected date (yyyy-MM-dd), defaults to today
status                  → from status Spinner selection
selected_employee_id    → from employee Spinner selection
imei                    → LoginActivity.imeiNo
authtoken               → LoginActivity.authToken
request_from            → "FromDigiApp"
is_list                 → "1"
from_dashboard          → "0" (report screen), "1" (dashboard card)
```

### Response Structure
```json
{
  "customer_data": "[{...}, {...}]",
  "setting_values": "{\"status_drop_down\": [\"Pending\", \"Collected\", ...]}",
  "emp_details": "[{\"employee_id\": \"1\", \"Name\": \"John\"}, ...]"
}
```
On error: `{"Error_code": 1, "Error_Message": "..."}`

### Response Fields (per item in `customer_data`)
| JSON Key | Displayed in Android |
|----------|---------------------|
| `customer_name` | **Customer Name** (tv_custname) |
| `crfno` | **CRF No** (tv_crf) — hidden if `use_caf != 1` |
| `status` | **Status** (tv_lastpaiddate) |
| `scheduled_date` | **Schedule Date** (tv_Amount) — `.substring(0, 10)` |
| `remarks` | stored but NOT displayed in list |
| `alt_custom_number` | stored |
| `nickname` | stored |
| `alt_cust_id` | stored |
| `customnumber` | stored |
| `customer_account_id` | stored |
| `email` | stored |
| `mobile_no` | stored |
| `vc_number` | stored |
| `total` | stored |
| `box_number` | stored |
| `amount` | stored |
| `customer_id` | stored |
| `paid_on` | stored |
| `bill_month` | stored |
| `address1` | stored |

### Android UI — List Item (row_unpaid_list_new.xml)
**Only 4 fields are DISPLAYED in the list row:**
1. **Customer Name** (`tv_custname`)
2. **CRF No** (`tv_crf`) — only if `LoginActivity.use_caf == 1`
3. **Status** (`tv_lastpaiddate`)
4. **Schedule Date** (`tv_Amount`)

Plus an arrow icon (`igv_arrow`) — visible when `from == 1` (report), invisible when `from == 0` (dashboard)

### Filter UI
- **Start Date** (DatePicker, default: today)
- **End Date** (DatePicker, default: today, min = start date)
- **Customer Name** (EditText)
- **CRF** (EditText) — only if `use_caf == 1`
- **Account Number** (EditText)
- **Status Spinner** (populated from `setting_values.status_drop_down`)
- **Employee Spinner** (populated from `emp_details`)
- **Submit Button** → re-fetches
- **Clear Button** → resets filters to defaults

### Error Handling
- `Error_code` present → AlertDialog "Fail!" + hide list + show no-records
- Otherwise parse `customer_data`

---

## 3. ONE TIME CHARGES

### Android Source Files
| File | Purpose |
|------|---------|
| `Fragments/OneTimeCharges_Frag.java` | Create new one-time charge |
| `Fragments/Onetime_history.java` | View charge history |
| `Fragments/DisplayOnetimeChrages.java` | Detail/print view after save |
| `Adapters/OnetimeHistory_Adapter.java` | History list adapter |
| `complexclasses/Onetimemodel.java` | History data model |

### 3A. CHARGE TYPES API (Dynamic Dropdown)
- **URL**: `NAMESPACE + /packagelist/chargeTypes` (config key: `ct`)
- **Method**: POST (form-encoded)

#### Request Parameters
```
dealer_id    → LoginActivity.dealerId
customer_id  → customer's internal id (NOTE: has trailing space in Android: "customer_id ")
imei         → LoginActivity.imeiNo
authtoken    → LoginActivity.authToken
```

#### Response
```json
{
  "status_code": 0,
  "status_msg": "...",
  "charge_types": "[{\"charge_type_id\": \"1\", \"charge_type_name\": \"Installation\"}, ...]"
}
```
- Populates Spinner (`onetime_spin_chargemodes`)
- `spinnerMap` maps position → `charge_type_id`
- Selected item provides `selestate` (name) and `selstateid` (id)

### 3B. SAVE ONE TIME CHARGE API
- **URL**: `NAMESPACE + /packagelist/saveOnetimeCharges` (config key: `sotc`)
- **Method**: POST (form-encoded)

#### Request Parameters
```
dealer_id           → LoginActivity.dealerId
customer_id         → customer's internal id
charge_type         → selstateid (int from spinnerMap)
amount              → entered amount (String, max 7 chars, 2 decimal)
chq_dd              → cheque/DD number
bank                → bank name
branch              → branch name
chq_dd_date         → cheque date (yyyy-MM-dd or "")
remarks             → remarks text
created_date        → selected date (yyyy-MM-dd)
check_paid_unpaid   → 1 (cheque) or 2 (cash/no instrument)
onetime_charge_id   → "0" (new)
ot_type             → "0"
imei                → LoginActivity.imeiNo
authtoken           → LoginActivity.authToken
```

#### Response
```json
{
  "status_code": 0,
  "status_msg": "Saved Successfully"
}
```
- Success → AlertDialog with "Print" and "OK" buttons
- Print → navigates to `DisplayOnetimeChrages` fragment

### 3C. ONE TIME CHARGES HISTORY API
- **URL**: `NAMESPACE + /packagelist/getOneTimeCharges` (config key: `gotc`)
- **Method**: POST (form-encoded)

#### Request Parameters
```
dealer_id    → LoginActivity.dealerId
customer_id  → customer's internal id
imei         → LoginActivity.imeiNo
authtoken    → LoginActivity.authToken
```

#### Response
```json
{
  "status_code": 0,
  "status_msg": "...",
  "onetime_charges": "[{...}, {...}]"
}
```

#### History Item Fields
| JSON Key | Model Field | Display |
|----------|-------------|---------|
| `onetime_charge_id` | onetime_charge_id | — |
| `charge_type_name` | createtype | Charge Type |
| `amount` | amount | Amount |
| `date` | createddate | Date |
| `bank_name` | bank | Bank |
| `branch_name` | branch | Branch |
| `cheque_dd_no` | chequeno | Cheque/DD No |
| `remarks` | remarks | Remarks |
| `paid_unpaid` | paid | Paid/Unpaid |
| `bill_no` | bill_no | Bill No |
| `receipt_no` | receipt_no | Receipt No |
| `cheque_date` | chequedate | Cheque Date |

#### History Header
- Customer Name, Address, Mobile (from `CustomerOperations_Fragment` static fields)
- Total Count label

#### Error Handling
- `status_code == 1` → AlertDialog "No Records Found!" + pop back stack
- Volley error → Toast "Failed."

### Access Control (Both Create & History)
- Denied if `userType == "SERVICE"` or `customerType == "BroadBand"`

### Create UI Fields
- Customer Name (display only)
- Charge Type (Spinner — **dynamically loaded from API**)
- Amount (EditText, max 7 chars, 2 decimal places)
- Created Date (DatePicker, must not be > today)
- Checkbox "Instrument Details" → shows/hides:
  - Instrument Date (DatePicker, must not be > today)
  - Cheque/DD No
  - Bank Name
  - Branch Name
- Remarks
- Save button

---

## 4. FLUTTER CURRENT STATE

### Act/Deact Report
- **DOES NOT EXIST** in Flutter codebase
- No screen, no repository, no model
- Needs to be built from scratch

### Pay Later
- **Repository EXISTS** (`pay_later_repository.dart`) — correctly calls `/digi_rest_api/scheduled_collection_data`
- **Model EXISTS** (`pay_later.dart`) — parses all fields from API
- **Dashboard card** works (via `DashboardController.loadPayLater`)
- **Standalone report screen** — NOT FOUND as separate screen
- **UI issue**: Flutter shows different fields than Android's 4-field list (Name, CRF, Status, Date)
- **Filter UI** — NOT implemented as standalone report

### One Time Charges
- **DOES NOT EXIST** in Flutter codebase
- No screen for creating charges
- No history screen
- No charge types API call
- No save charges API call
- Needs to be built from scratch

---

## 5. IMPLEMENTATION PLAN

### Phase 1: Act/Deact Report (New)
1. Create `lib/features/customer/data/act_deact_repository.dart`
   - POST to `NAMESPACE/packagelist/packageActDeactReport`
   - Params: dealer_id, employee_id, customer_id, imei, authtoken
   - Parse `package_act_deact_report` array
2. Create model `ActDeactItem` (packageName, boxNumber, operationType, createdDate, errorMessage, createdBy)
3. Create `lib/features/customer/act_deact_report_screen.dart`
   - Header: customer name + LCO ID
   - ListView with 6-field rows
   - Loading, empty, error states matching Android
4. Wire from Customer Details screen operations

### Phase 2: Pay Later Report (Fix UI)
1. Flutter repository is **already correct** — no changes needed
2. Create standalone `PayLaterReportScreen` with:
   - Filter bar: start date, end date, customer name, CRF (if use_caf), account number, status spinner, employee spinner
   - Submit + Clear buttons
   - List showing ONLY: Customer Name, CRF, Status, Schedule Date
3. Wire from drawer/navigation

### Phase 3: One Time Charges (New)
1. Create `lib/features/customer/data/onetime_charges_repository.dart`
   - `fetchChargeTypes()` → `/packagelist/chargeTypes`
   - `saveOnetimeCharge()` → `/packagelist/saveOnetimeCharges`
   - `fetchOnetimeHistory()` → `/packagelist/getOneTimeCharges`
2. Create models: `ChargeType(id, name)`, `OnetimeChargeItem(...12 fields)`
3. Create `lib/features/customer/onetime_charges_screen.dart` (create form)
4. Create `lib/features/customer/onetime_history_screen.dart` (history list)
5. Wire from Customer Details screen operations

---

## 6. INTERLINKS & DEPENDENCIES

```
CustomerDetailsScreen (Flutter) ← entry point for all 3 features
    ├── Act/Deact Report → needs customer_id, customername, lcocustid, crf
    ├── One Time Create  → needs customer_id, crf, custname, lcocustomerid
    ├── One Time History → needs customer_id, crf, custname, lcocustomerid
    └── Pay Later        → needs customer_id (for per-customer lookup)

All APIs share:
    - dealer_id (SessionService.instance.dealerId)
    - imei (AppConfig.deviceImei)
    - authtoken (SessionService.instance.authToken)
    - Base URL: ServerUrlResolver.instance.namespace

Pay Later Report (standalone) ← accessed from drawer/nav menu
    - Uses same repository as dashboard Pay Later card
    - Additional filters: date range, status, employee

Access Control:
    - SESSION userType == "SERVICE" → deny Act/Deact + OTC
    - Customer type == "BroadBand" → deny Act/Deact + OTC
    - use_caf == 1 → show CRF fields in Pay Later
```

---

## 7. KEY DIFFERENCES: Android URL Patterns

| Feature | URL Pattern | Encryption |
|---------|-------------|------------|
| Act/Deact Report | `/packagelist/packageActDeactReport` | None (plain POST) |
| Pay Later List | `/digi_rest_api/scheduled_collection_data` | Encrypted REST |
| Charge Types | `/packagelist/chargeTypes` | None (plain POST) |
| Save OTC | `/packagelist/saveOnetimeCharges` | None (plain POST) |
| OTC History | `/packagelist/getOneTimeCharges` | None (plain POST) |

**Note**: `/packagelist/` endpoints use plain `RestClient.postForm()`.  
`/digi_rest_api/` endpoints use `RestClient.postEncrypted()`.

---

## 8. SUMMARY OF ISSUES

| # | Issue | Severity |
|---|-------|----------|
| 1 | Act/Deact Report screen doesn't exist in Flutter | **Critical** |
| 2 | One Time Charges (create + history) doesn't exist | **Critical** |
| 3 | Pay Later report screen with filters doesn't exist | **High** |
| 4 | Pay Later dashboard card shows wrong fields vs Android | **Medium** |
| 5 | Charge Types hardcoded/missing (no dynamic API call) | **Critical** |
| 6 | No access control for SERVICE/BroadBand users | **Medium** |
