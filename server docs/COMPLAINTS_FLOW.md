# Complaints Flow — End-to-End Investigation & Flutter Parity Plan

The complaints feature is **interlinked** across three places:
1. **Dashboard "Complaints" feed** — the open-complaints list (already wired).
2. **Customer Details → "Create Complaints"** — raise a new complaint.
3. **Customer Details → "Complaint History"** — that customer's complaints.

A complaint **created** from customer details is stored on the backend and then
**appears** both in that customer's history and (while still open) in the
dashboard open-complaints feed. **Updating** a complaint's status ("close
complaint") changes its status everywhere. So these screens share one backend
set of complaint records — they must be wired to the real APIs to behave
correctly. **No implementation yet — this is investigation + documentation.**

### Verification legend
- ✅ **Verified** — read directly from the existing app source during this
  investigation (file + line confirmed).
- 🟡 **Not Yet Verified** — reported by the sub-agent with line citations but not
  personally re-read line-by-line, OR depends on live backend responses. Treat as
  an assumption to confirm before/while implementing that sub-section.

No URLs, tokens, IMEIs, dealer ids, customer names, or ticket numbers are recorded.
All complaint methods use the **same** `NAMESPACE` (✅ confirmed: `CLOSE_NAMESPACE`,
`COMP_NAMESPACE`, etc. are all aliases of `EzyCableDigiConstants.NAMESPACE`), so
the existing `SoapClient` + `ServerUrlResolver.namespace` + `loginServerUrl` work
for every one of them.

---

## 1. The root cause you saw ("status is not updating")

✅ Flutter `complaint_details_screen.dart` `_update()` (line 55) is a **stub**:
it only shows a snackbar "Status updated to …" and pops — it calls **no API**.
Also:
- ✅ Its status dropdown is **hardcoded** (`Select/ASSIGNED/INPROCESS/ONHOLD/
  RESOLVED/CLOSED`) instead of the real `complaintTypes` list.
- ✅ It only receives `complaintId`, `customerName`, `complaint`, `currentStatus`
  — it does **not** receive `altCustomerId` or `ticketNumber`, both of which the
  real `closeComplaint` API requires. So even the inputs are insufficient today.

Likewise `create_complaint_screen.dart` and `complaints_history_screen.dart` are
**stubs** (see §4).

---

## 2. API Contract (all complaint endpoints)

All SOAP (ksoap2, VER11), same namespace, `statusCode`/`statusMessage` envelope.

### 2.1 Open complaints list — `getopencomplaintslist` (key `gocl`) ✅ DONE
- Request: `authToken`, `imei`, `dealer_id` (0), `from_dashboard` ("1").
- Response: `opencomplaintList` (JSON-array string) — items: `tkt_number`,
  `complaint_id`, `description`, `status`, `name`, `des`, `alt_custom_number`,
  `group_name`, `mobile_no`, `address1`, `crfno`, `date`, `alt_cust_id`,
  `customer_id`, `latitude?`, `longitude?`.
- ✅ Already implemented in Flutter (`complaints_repository.dart`, dashboard feed).

### 2.2 Status list (LOV for update) — `complaintTypes` (key `compty`) ✅ method/wrapper verified
- Wrapper `getComplaintStatusInfo`; request: `authToken`, `imei`. ✅
- Response: repeated `complaintStatuses` → item field `statusName`; plus a
  hardcoded "Select" default. 🟡 (exact item field name `statusName` agent-cited).
- Timeout 70s online.

### 2.3 Update / close complaint — `closeComplaint` (key `clscomp`) ✅ VERIFIED
- Wrapper element `closeCompInfo`, i:type `closeComplaintInfo`. ✅
- Request fields: `altCustomerId` (int), `authToken`, `complaintId` (int),
  `comment` (the remark), `status` (the chosen status name), `ticketNumber`,
  `imei`. ✅
- Response: `statusCode` (0 success / 1 "enter valid details" / 2 contact
  support), `statusMessage`. Null → "Server busy/Unreachable" dialog. ✅
- Success: shows a "Complaint Updated Successfully" dialog (id, comment, status),
  then pops back. ✅ Timeout 70s online / 10s offline.

### 2.4 Categories (for create) — `complaintCategories` (key `comcat`) 🟡
- Wrapper `getComplaintCategoriesInfo`; request `authToken`, `imei`.
- Response: `complaintCategories` → items `categoryId` (int), `categoryName`. 🟡

### 2.5 Errors (for create) — `complaintErrors` (key `comperr`) 🟡
- Wrapper `getComplaintErrorsInfo`; request `authToken`, `imei`.
- Response: `complaintErrors` → items `errorId`, `errorCode`, `errorDescription`. 🟡

### 2.6 Assigned employees (for create) — `assignedemployeedetails` (key `aed`) 🟡
- Wrapper `getassignedinfo`; request `authToken`, `imei`, `customerId` (int).
- Response: `assignedemployee_details` → items `employee_id` (int), `employee_name`. 🟡

### 2.7 Create complaint — `createComplaint` (key `crecomp`) ✅ VERIFIED
- Wrapper element `newCompInfo`, i:type `createComplaintInfo`. ✅
- Request fields: `customerId` (int = altCustId), `authToken`, `complaint` (text),
  `category` (categoryId int), `error` (errorId int), `imei`, `latitude` (string),
  `longitude` (string), `assigned_to` (employee id int), `lat` (string),
  `lang` (string). ✅
- Response: `statusCode` (0 success / 1 validation / ≥2 error), `statusMessage`. ✅
- Timeout 100s online / 200s offline. Needs device GPS (lat/long; 0.0 if absent). ✅

### 2.8 Complaint history (per customer) — `getCustomerComplaintList` (key `gccl`) 🟡
- Wrapper `getCustomerComplaintList`; request `altCustomerId` (int), `authToken`,
  `imei`. 🟡
- Response: `customerComplaintList` → items `customer_id`, `alt_cust_id`,
  `customnumber`, `name`, `group_name`, `complaint_id`, `tkt_number`,
  `description`, `complaintTime`, `status`. 🟡

---

## 3. Interlink (how the screens connect) ✅
- **Create** (`createComplaint`) writes a complaint for `customerId`/`altCustId`.
- It then surfaces in **History** (`getCustomerComplaintList` for that customer)
  and, while open, in the **dashboard feed** (`getopencomplaintslist`, dealer-scoped).
- **Update** (`closeComplaint`) changes the `status`; closed/resolved statuses
  drop out of the open feed (backend-filtered). 🟡 exact "open" filter is backend-side.
- Consequence: after create/update, the relevant lists must be **re-fetched** to
  reflect the change (Android does not auto-refresh; the user re-opens the list —
  ✅). The dashboard feed already refetches on chip tap.

---

## 4. Flutter current state (inventory)

| Screen | File | State | Gap |
|--------|------|-------|-----|
| Dashboard complaints feed | `dashboard/data/complaints_repository.dart` + controller | ✅ **REAL** (done) | — |
| Complaint details / **update status** | `complaints/complaint_details_screen.dart` | ❌ **STUB** — snackbar only, hardcoded status list, missing altCustomerId/ticketNumber | wire `complaintTypes` + `closeComplaint`; pass altCustId + ticketNumber from the feed item |
| **Create complaint** | `complaints/create_complaint_screen.dart` | ❌ **STUB** — hardcoded categories+employees, no error list, snackbar only | wire `complaintCategories` + `complaintErrors` + `assignedemployeedetails` + `createComplaint` |
| **Complaint history** | `complaints/complaints_history_screen.dart` | ❌ **STUB** — `_complaints` returns `[]` | wire `getCustomerComplaintList` |
| Complaints tab (bottom-nav) | `complaints/complaints_screen.dart` | 🟡 placeholder (`const []` items) | clarify purpose; likely reuse dashboard feed or remove |
| Customer Details links | `customer/customer_details_screen.dart` | ✅ navigates to Create (`CreateComplaintScreen`) + History (`ComplaintHistoryScreen`) with `customer` | reuse — pass the right ids |

Reusable infra (✅): `SoapClient`, `ServerUrlResolver`, `SessionService`
(`authToken`, `dealerId`, `userType`), `AppConfig.deviceImei`, the
`open_complaint.dart` model, and the dashboard `OpenComplaint` shape.

Data the update screen needs that the feed already has: the dashboard
`OpenComplaint` carries `alt_cust_id`/`customer_id` and `tkt_number` — so the
"Update Status" navigation can pass `altCustomerId` + `ticketNumber` + the real
`complaintId`. ✅ (Currently `_TicketCard` only forwards ticketId/name/desc/status.)

---

## 5. Production risks & required handling
| Risk | Existing-app behavior | Flutter must |
|------|----------------------|--------------|
| Status LOV API fails | spinner shows only "Select" | fall back to a safe default list or disable update with a message; never crash |
| Update returns 1/2 | toast "Enter valid details" / "Contact support" | show message, keep screen, don't claim success |
| Update returns null | "Server busy" dialog | show error, do NOT pop as success |
| Create category/employee API fails | dropdowns empty | block submit with a message; never crash |
| Create returns validation error | toast | show server message, keep form |
| GPS unavailable on create | lat/long 0.0 | send 0.0, no crash |
| History empty / no records | "No records" | empty-state |
| Any list malformed | per-field try/catch | defensive parse, default '' |
| Stale list after create/update | manual re-open | re-fetch the affected list on return |

The Flutter rule (all sections): never crash on null / missing fields / empty
arrays / malformed responses / network / timeout / unauthorized; show graceful
fallback; one failing call must not crash the screen.

---

## 6. Incremental implementation plan (NOT started — for approval)
Each step: implement → `flutter analyze` → explain → **wait for verification**.

1. **Update status (closeComplaint)** — the reported bug.
   - Pass `altCustomerId` + `ticketNumber` + real `complaintId` from the feed
     item into `ComplaintDetailsScreen` (extend `_TicketItem`/navigation).
   - Load the real status LOV (`complaintTypes`); fallback list if it fails.
   - Wire `_update()` to `closeComplaint`; handle 0/1/2/null exactly like Android;
     on success refresh the dashboard feed.
2. **Complaint history (getCustomerComplaintList)** — wire `ComplaintHistoryScreen`.
3. **Create complaint (createComplaint)** — wire categories + errors + assigned
   employees + GPS + submit; refresh history/feed on success.
4. Hardening + the bottom-nav `complaints_screen.dart` decision.

Before coding steps 2–3, quickly line-verify the 🟡 response field names
(`complaintCategories`, `complaintErrors`, `assignedemployeedetails`,
`getCustomerComplaintList`, `complaintStatuses`) against the Android source.

---

## 7. Definition of Done (per section)
- [ ] Update status actually calls `closeComplaint` and reflects server result
      (success/failure), with the real status LOV, passing altCustId+ticketNumber.
- [ ] Create complaint calls `createComplaint` with real category/error/employee
      lists; validates; shows server result.
- [ ] History shows real `getCustomerComplaintList` data with empty/error states.
- [ ] No crash on null/empty/malformed/timeout/unauthorized in any flow.
- [ ] Created/updated complaints reflect across history + dashboard feed on refetch.
- [ ] `flutter analyze` clean.
- [ ] 🟡 User verifies each section live before it is marked complete.

---

## 8. CREATE COMPLAINT — verified end-to-end (Android source of truth)

All code references below are READ-ONLY from
`Fragments/Complaint_NewComplaint_Fragment.java` unless noted. This is how the
existing app builds the create screen **dynamically** (no hardcoded categories or
employees) and submits robustly.

### 8.1 Two modes — `complaintType` (from login) ✅
- `complaintType = LoginActivity.complaintType` (:141). It is a **login flag**.
- Branch (:170–188):
  - **SIMPLE** layout → loads **Categories** (`ComplaintCategoriesList`) +
    **Assigned employees** (`ComplaintAssigned`). No error list. `error` sent as 0.
  - **ADV** (else) → loads **Errors** (`ComplaintErrorList`). (assigned commented out.)
- ✅ The current Flutter create UI (Category + Assign-To + Employee + Description)
  matches **SIMPLE**. So we implement SIMPLE first; ADV (error list) is a 🟡 follow-up
  gated on the tenant's `complaintType` (not yet captured at login).

### 8.2 The three dynamic dropdowns (LOV APIs) — all SOAP, same namespace

**A. Categories — `complaintCategories` (key `comcat`)** ✅
- Wrapper element `categoriesinfo`/complex `getComplaintCategoriesInfo`; request
  `authToken` + `imei`. Timeout 60s/30s.
- Response: repeated `complaintCategories` items → `categoryId` (int) +
  `categoryName` (string), parsed at :402–433; a `Select` (id 0) is prepended.
- Selecting a row sets `CategoriesIdValue = categoryId` (the submit `category`).

**B. Assigned employees — `assignedemployeedetails` (key `aed`)** ✅
- Wrapper element `assignedinfo` (i:type `assignedEmployeeInfo`); request
  `authToken` + `imei` + `customerId` (= `altCustId` = **customer_id**, :616).
  Timeout 60s/30s.
- Response: repeated `assignedemployee_details` items → `employee_id` (int) +
  `employee_name` (string), parsed at :668–694; a `Select` (id 0) is prepended.
- Selecting a row sets `Assignednames = employee_name` and
  `assignedvalue = employee_id` (:771–773) — `employee_id` becomes the submit
  `assigned_to`.
- ⚠️ The **"Employee / Service" dropdown is cosmetic** — a hardcoded
  `{"Employee","Service"}` array (:257) whose selection handler is **commented
  out** (:266–276). It does **not** filter the list or affect the request. The
  real people come from this one API. (So the Flutter hardcoded employee names are
  wrong on two counts: hardcoded, and the Employee/Service split is meaningless.)

**C. Errors (ADV only) — `complaintErrors` (key `comperr`)** 🟡
- Wrapper `getComplaintErrorsInfo`; request `authToken` + `imei`. Items
  `errorId` / `errorCode` / `errorDescription` (parse ~:872–900). Only used in ADV
  mode; `ErrorId` feeds the submit `error`. Not needed for SIMPLE.

### 8.3 Submit — `createComplaint` (key `crecomp`) ✅
- Wrapper element `newCompInfo`, i:type `createComplaintInfo` (:1108–1120).
- Fields (:1088–1106): `customerId` (= altCustId = **customer_id**), `authToken`,
  `complaint` (the typed text), `category` (categoryId), `error` (errorId, 0 in
  SIMPLE), `imei`, `latitude` (string), `longitude` (string),
  `assigned_to` (employee_id), `lat` (string), `lang` (string). Timeout 100s/200s.
- ✅ `customerId` here is the **customer_id** — the same id `getCustomerComplaintList`
  uses (CustomerOperations_Fragment.java:2460 sets `altCustId = getCustomerId()`),
  i.e. our `Customer.lcoCustomerId`. (Verified live: history with `lcoCustomerId`
  returns the right records; with the alphanumeric account number it returns none.)

### 8.4 Validation & robustness (how Android avoids errors/crashes) ✅
- Register button (:228–233): blocks submit unless **category selected**
  (`CategoriesIdValue != 0`) **and** an **employee selected**
  (`Assignednames != "Select"`), else Toast "Select Complaint /employee".
- **Signal check** before submit (:228, `getSignaStrength`): weak signal → dialog,
  no call. (Flutter: a plain network check is enough; the Wi-Fi RSSI logic is
  Android-specific and optional.)
- **GPS optional** (:191–199): if location unavailable, `latitude=longitude=0.0`.
  Never blocks submit.
- Every LOV parse is in try/catch; on failure the spinner just keeps its `Select`
  default. LOV failures Toast "… not Loaded" / "Contact Support" (statusCode 1/2),
  null → "Server is Unreachable" dialog. None crash the screen.
- Submit response (:1158–1240): `0` → "New Complaint Registered Successfully"
  dialog (date, category, description, assignee) → `popBackStack`; `1` → "Enter
  Valid Details" dialog; `2` → "Contact Support"; null → "Server busy" dialog.

### 8.5 Interlink (create → history → dashboard) ✅
- `createComplaint` writes a record keyed on **customer_id** + `assigned_to`.
- It then appears in **History** (`getCustomerComplaintList` by customer_id —
  already wired ✅) and, while open, in the **dashboard open feed**
  (`getopencomplaintslist`, dealer-scoped — already wired ✅).
- No auto-refresh in Android; lists re-fetch when reopened. Our history + both
  complaint lists already re-fetch (history on open, feeds on tab tap / after
  update). After a successful create we should pop back and let those re-fetch.

### 8.6 Flutter current state vs target (create) ✅
- `create_complaint_screen.dart` is a **stub**: categories hardcoded (:18–22),
  employees hardcoded (:26–30), **no** category/employee API, `_register()` only
  shows a snackbar (:38–49). The Employee/Service dropdown copies Android's
  cosmetic one.
- **To build (SIMPLE mode):**
  1. Repo: `fetchComplaintCategories()` → `[(id,name)]` with `Select`.
  2. Repo: `fetchAssignedEmployees(customerId)` → `[(id,name)]` with `Select`.
  3. Repo: `createComplaint(customerId, complaint, category, error=0, assignedTo, lat, long)`
     → `ComplaintActionResult`.
  4. Screen: load both LOVs on open (using `customer.lcoCustomerId`), populate real
     dropdowns, GPS (0.0 fallback), validate (category≠Select & employee≠Select &
     description non-empty), submit, handle 0/1/2/null, pop on success.
  5. Keep the Employee/Service dropdown **cosmetic** (parity) OR omit it — it has no
     backend effect; recommend omitting to avoid confusion. (Decision needed.)
- Defensive everywhere: LOV failure → keep `Select`, show a soft message, never
  crash; submit failure → message, keep form.

### 8.7 Code file index (read-only Android)
- Create screen / modes / validation / GPS / submit:
  `Fragments/Complaint_NewComplaint_Fragment.java`
  (:141 mode, :170–188 branch, :191–199 GPS, :228–233 validate,
  :330–545 categories, :598–795 assigned employees, :799–1020 errors,
  :1058–1240 createComplaint).
- History id source: `Fragments/CustomerOperations_Fragment.java:2460` & `:1797`.
- Update/status: `Fragments/ComplaintHistory_Others_Fragment.java`
  (:228–313 status LOV, :450–621 closeComplaint).
- Open list: `Fragments/DashboardHomeFragment.java` (:760–978) /
  `Fragments/OpenComplaints_Fragment.java`.
