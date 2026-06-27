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
