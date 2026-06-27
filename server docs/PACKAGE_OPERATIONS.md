# Package Operations — Investigation (Documentation First)

**Module status: IN PROGRESS.** This is investigation + documentation only. No
Package Operations code will be implemented until this document is complete and
you approve it.

Source of truth (READ-ONLY): `D:\Git-Repos\magikdigi`. Flutter target:
`D:\StudioProjects\ezy_cable_digi`.

### Verification legend
- ✅ **Verified** — read directly from the existing Android/Flutter source this
  pass (file + line cited).
- 🟡 **Not Yet Verified** — config key exists but the usage/fields were not read
  line-by-line this pass, OR depends on live backend responses.
- 🔴 **Cannot be verified from the client** — backend tables / stored procedures
  are not visible in the app source; must be confirmed with the backend team.

No URLs, tokens, IMEIs, dealer ids, VC numbers, serials, or customer names are
recorded — only field/method names and structure.

> Investigation note: parallel sub-agents were unavailable (session limit) during
> this pass, so coverage was done by direct reads. The **core flow (box state +
> activation + deactivation)** is fully evidenced; several adjacent sub-flows
> (temporary activation, STB deactivate, reactivation, deactivate-reasons) are
> marked 🟡 with exact files to read next.

---

## 1. High-Level Module Flow

### Entry & navigation ✅
- Customer Details → **Package Operations** opens **`DigiPackage_Home`**
  (`CustomerOperations_Fragment.java:905`).
- `DigiPackage_Home` is a **two-button landing** (`DigiPackage_Home.java:39-84`):
  - **Activate** (`digipack_act_btn`) → `CustomPackages_Activation`.
  - **Deactivate** (`digipack_deact_btn`) → `CustomPackages_Deactivation`.
- Identifiers passed to both (`:57-63` / `:74-80`): `customerid`, `dealer_id`
  (`LoginActivity.dealerId`), `imei`, `authtoken`, `crf`, `lcocustomerid`,
  `custname`. (Note: the **customer_id**, not alt_cust_id, is the key — same as
  the other package endpoints.)

### Sequence (activation — verified) ✅
```
CustomerDetails → "Package Operations" → DigiPackage_Home (Activate / Deactivate)

Activate:
  CustomPackages_Activation
    → getDigiDealerPackages (gddp, act_type=1)         [load available packages]
    → user multi-selects packages (adapter flags)
    → selectedpackages() builds CSV arrays
    → BillDetails_Act (bill / confirm)
       → insertDigiDealerPackages (iddp, act_type=1)   [WRITE: activate]
       → status_code 0 → success → back/refresh

Deactivate:
  CustomPackages_Deactivation
    → getDigiDealerPackages (gddp, act_type=2)          [load deactivatable pkgs]
    → user multi-selects
    → DigiPackages_deactivation (confirm)
       → insertDigiDealerPackages (iddp, act_type=2)    [WRITE: deactivate]
       → status_code 0 → success
```
- ✅ `act_type` distinguishes the operation everywhere: **1 = activation,
  2 = deactivation** (list AND write).
- 🟡 Temporary activation / temporary deactivation / reactivation / STB
  deactivate are **separate** flows (see §8) — not part of the
  `DigiPackage_Home` two-button path; not fully traced this pass.

### Box / STB state retrieval ✅
- `getCustomerBoxes` (key `gcb`) REST response (`CustomerOperations_Fragment.java
  :2603-2645`): `status_code`, `status_msg`, `service_extension`, and
  `customer_boxes[]` — each item: `box_id`, `box_number`, `vc_number`,
  `customer_id`, `cas_server_id`, `status`, `box_status`. (`stock_id` is present
  in the model but commented out in the parse.)
- ✅ The **STB/box state** is carried by `status` and `box_status`. The exact
  meaning of each `status`/`box_status` value (active/inactive/suspended/temp) is
  🟡 — needs the value→state mapping from the adapters / a live response.

---

## 2. Customer Dependency Graph

Package Operations depends on / connects to:
- **Customer Search → Customer Details** ✅ — the entry point; supplies
  `customer_id` (= `lcoCustomerId`), `crf`, name, and the box/VC data.
- **getCustomerBoxes** ✅ — supplies the box list (box_id / vc / status) the
  package operations act on.
- **Dealer** ✅ — every package call sends `dealer_id` + `authtoken` + `imei`.
- **Billing** ✅ — activation routes through `BillDetails_Act` (a bill/confirm
  screen) before the write.
- **Payments / Complaints / Reports / Collections** 🟡 — not directly invoked by
  the package write path; `packageActDeactReport` (`padr`) is a separate report
  ("Act-Deact Report" operation). Cross-module impact (e.g. billing recalencular)
  is backend-side 🔴.

```
Customer Search ─▶ Customer Details ─▶ Package Operations (DigiPackage_Home)
                                   │           │
                          getCustomerBoxes   ├─ Activate ─▶ gddp(1) ─▶ BillDetails_Act ─▶ iddp(1)
                          (box/vc/status)    └─ Deactivate ─▶ gddp(2) ─▶ Deactivation ─▶ iddp(2)
   Dealer (dealer_id/authtoken/imei) ── attached to every call
   Act-Deact Report (padr) ── separate read-only report
```

---

## 3. STB Investigation

- ✅ STB/box data comes from **`getCustomerBoxes` (gcb)** → `customer_boxes[]`
  with `status` + `box_status` per box (§1). A customer can have multiple boxes;
  the operations screen selects a box (by box_number/vc).
- 🟡 **Whether STB must be active before package operations** is **not yet
  verified** — the activation fragment loads dealer packages by `customer_id`
  (not by box state), so there is no obvious client-side STB-active gate in
  `CustomPackages_Activation`. Backend may enforce it 🔴.
- 🟡 State values: `status` / `box_status` ints/strings → active / inactive /
  suspended / temporary-active / temporary-deactive mapping is **not yet
  verified**. Next: read the box-selection adapter and `Box_Selection_new.java` /
  the `DigiselectedAdapter` / `DigideselectAdapter` for the value→label mapping.
- 🟡 STB deactivate uses a **separate** API `deactivateSTB` (`ds`) and screen
  `Deactivatestb_Frag_New.java` (the "Deactivate STB" customer operation, distinct
  from package deactivate) — not traced this pass.

---

## 4. Package Retrieval ✅ (available/dealer packages) · 🟡 (current packages)

### Available / dealer packages — `getDigiDealerPackages` (key `gddp`) ✅
- Transport: REST form-POST (Volley). Used by both activation
  (`CustomPackages_Activation.java:89,136-187,236-240`) and deactivation
  (`CustomPackages_Deactivation.java:80,235-239`).
- **Request fields:** `dealer_id`, `customer_id`, `imei`, `authtoken`,
  `act_type` (**"1"** for activation list, **"2"** for deactivation list).
- **Response:** `status_code` (int), `status_msg` (string), and
  `digi_dealer_packages` — a JSON-array string. Per item (`:166-177`):
  - `package_id` — package identifier.
  - `name` — package display name.
  - `price` — base price.
  - `package_related_to` — category/relation (e.g. base/add-on grouping). 🟡 exact semantics.
  - `start_date` — package start date.
  - (client-side defaults added to the model: `quantity` = "1", `autoRenewal` = 0.)
- 🟡 Other per-item fields (status, expiry, category id) were not present in this
  parse; confirm against a live response.

### Current / active customer packages — `getCustomerpackages` (key `gcp`) 🟡
- Config key exists (`gcp=/packagelist/getCustomerpackages`) but its request/
  response and call site were **not located this pass**. Likely backs an
  "active packages" view. Next: grep `getCustomerpackages` / `gcp` across
  Fragments + adapters (`ActivePackagesFragment.java`, `Frag_act_Pack.java`).

### `getcustomerpackageslist` (key `gcpl`) 🟡 — separate list endpoint, not traced.
### `packageslist` (key `packli`) 🟡 — master package list, not traced.

---

## 5. Package Selection Rules

- ✅ **Multiple packages** can be selected — the activation list uses a
  multi-select adapter (`GetCustomPackages_ActAdapter.getSelectedFlags()`,
  `CustomPackages_Activation.java:256`) and `selectedpackages()` builds arrays of
  the selected `package_id` / `name` / `price` / `quantity` / `start_date` /
  `autorenewal` (`:286-293`), then joins them into CSV strings sent as `packages`,
  `start_date`, `months`, `autorenewal` (§6).
- 🟡 **Duplicate / already-active / expired prevention:** not verified. The list
  comes pre-filtered by the backend per `act_type` (activation list vs
  deactivation list), which is the primary guard. Whether the adapter blocks
  re-selecting an already-active package client-side is **not yet verified** —
  read `GetCustomPackages_ActAdapter` / `DigiPackagesDeactAdapter`.
- 🔴 Backend duplicate/idempotency handling is server-side and not visible here.

---

## 6. Activation Flow ✅ (write verified)

- **Screen:** `CustomPackages_Activation` → `BillDetails_Act` (bill/confirm).
- **Write API:** `insertDigiDealerPackages` (key **`iddp`**), REST form-POST
  (`BillDetails_Act.java:72,263-271`).
- **Request fields** (`:263-271`):
  - `dealer_id` (`LoginActivity.dealerId`)
  - `customer_id`
  - `imei`
  - `authtoken`
  - `packages` — CSV of selected `package_id`s (`CustomPackages_Activation.totalstrs`)
  - `start_date` — CSV of per-package start dates (`totastatdates`)
  - `months` — CSV of durations (`totalval`)
  - `autorenewal` — auto-renewal flag(s) (`ttlautorenewal`)
  - `act_type` = **"1"**
- **Response:** `status_code`, `status_msg` (`:193-194`).
- 🟡 Full status-code branch handling (0/1/2/3 → dialogs/toasts) in
  `BillDetails_Act` not fully read; confirm next.

---

## 7. Deactivation Flow ✅ (package deactivate verified) · 🟡 (STB/suspend/reactivate)

- **Package deactivation:** `CustomPackages_Deactivation` → load via `gddp`
  (`act_type=2`) → multi-select → `DigiPackages_deactivation` → **write
  `insertDigiDealerPackages` (iddp)** with: `dealer_id`, `customer_id`, `imei`,
  `authtoken`, `packages` (CSV), `autorenewal`, `act_type` = **"2"**
  (`DigiPackages_deactivation.java:72,254-260`). Response `status_code`,
  `status_msg`. (Note: deactivation write does **not** send `start_date`/`months`.)
- 🟡 **Normal vs Temporary vs Permanent** deactivation, **package removal**,
  **suspension**, **reactivation** are distinct flows using other endpoints
  (`deactivateSTB` `ds`, `deactivateBox` `db`, `reactivateBox` `rbox`,
  `stbTemporaryActivation` `sta`) — see §8. Not traced this pass.
- 🟡 **Deactivate reasons** — `Customerdeactivereasons` (key `cdr`) supplies a
  reasons list (likely a dropdown on the deactivate/STB screen). Request/response
  not read this pass. Next: grep `cdr` / `Customerdeactivereasons` +
  `DeactivateReasons_Adapter.java`.

---

## 8. Temporary Activation / Deactivation 🟡 (dedicated follow-up needed)

- ✅ Endpoint exists: `stbTemporaryActivation` (key `sta` =
  `/packagelist/stbTemporaryActivation`).
- 🟡 Purpose, request fields (dates / duration / flags), response, the state it
  sets, billing impact, and reactivation flow are **Not Yet Verified**. Likely
  screens: `Frag_act_Pack.java` / `Frag_Deactpack.java` /
  `Box_Selection_new.java`. This section is explicitly incomplete and must be
  filled before implementing temp activation.
- 🔴 Backend flags/dates/expiry columns that drive temp state are server-side.

---

## 9. Backend Investigation

- ✅ **API endpoints (REST, `/packagelist/…`)** confirmed from
  `assets/configg.properties`: `gddp` (getDigiDealerPackages), `iddp`
  (insertDigiDealerPackages), `gcb` (getCustomerBoxes), `gcp`
  (getCustomerpackages), `gcpl` (getcustomerpackageslist), `cpo`
  (Customerpackageoperations), `cdr` (Customerdeactivereasons), `sta`
  (stbTemporaryActivation), `ds` (deactivateSTB), `db` (deactivateBox), `rbox`
  (reactivateBox), `pr` (packageRenew), `serext` (serviceExtension), `csews`
  (customerServicesExtendWithStock), `packli` (packageslist), `padr`
  (packageActDeactReport), `uca` (unpaidCustomerActivation).
- 🟡 `Customerpackageoperations` (`cpo`) — config key exists but **no call site
  found** in the activation/deactivation path this pass (that path uses `iddp`).
  It may be used elsewhere or legacy. Not Yet Verified.
- 🔴 **Database tables / stored procedures / backend validation logic: Not
  Verifiable from the client.** The app only sees REST endpoints + JSON. Table
  names, SPs, and server-side validation **must be confirmed with the backend
  team** — explicitly NOT guessed here.
- ✅ **Status codes (transport):** every package REST call returns
  `status_code` (int) + `status_msg` (string); `status_code == 0` = success
  (verified in gddp/iddp/gcb). Non-zero branch semantics 🟡.

---

## 10. Error Handling 🟡 (partially verified)

✅ verified: each package REST call parses `status_code`/`status_msg`; gddp/gcb
render the list only on `status_code == 0`. Detailed per-failure UX (dialog vs
toast, retry) was **not fully read** this pass and is **Not Yet Verified** for:
network timeout, SOAP fault (these are REST not SOAP — Volley `VolleyError`),
invalid STB/VC/serial, duplicate package, already active/inactive, backend
validation failure, dealer restriction, auth failure, package unavailable,
concurrent update, malformed/empty/partial responses.

**Flutter requirement (to apply when implementing):** never crash on null/empty/
malformed/timeout/unauthorized; show the server `status_msg`; keep the screen on
failure (don't claim success); one failing call must not crash the screen. (Same
defensive rule already used in the payment/complaints repos.)

---

## 11. UI Investigation

### Android ✅
- `DigiPackage_Home` (two buttons) → `CustomPackages_Activation` /
  `CustomPackages_Deactivation` (ListView multi-select) → `BillDetails_Act` /
  `DigiPackages_deactivation` (confirm) → success.
- Loading: per-call `ProgressDialog` (pattern consistent with other fragments) 🟡.
- Refresh: list re-fetched on screen open; after a write, returns back (re-fetch
  on re-enter) 🟡.

### Flutter — CURRENT STATE ✅ (entirely placeholder; structure differs)
`lib/features/complaints/package_operations_screen.dart` — **HARDCODED STUB**:
- Customer info card (name, LCO id, **Serial Number** dropdown from
  `serialNumber`/`boxNumber`, VC number) — real customer fields. ✅
- "Services" card with four tiles: **Active Packages**, **Add Services**,
  **Schedule Services**, **Reactivation** — this is a **different structure** than
  Android's Activation/Deactivation two-button flow.
- `ActivePackagesScreen` (:249-381) — **hardcoded** "GOLD Pack Postpaid ₹140 /
  Status: Active" placeholder; status dropdown `Select/Active/Deactive` does
  nothing.
- `_ServicesScreen` (Add/Schedule, :384-595) — **hardcoded** Base/Add-On/Alacarte
  tabs with placeholder packages (ECF, GOLD Pack, RTFC…); **SAVE only shows a
  snackbar** (no API).
- `Reactivation` (:23-48) — confirm dialog → **snackbar only** (no `reactivateBox`
  call).
- ❌ **No real package API anywhere; no package repository/model exists.**

➡️ **Decision needed:** keep the current Flutter structure (Active Packages / Add
/ Schedule / Reactivation) and wire it to the real APIs, OR rebuild to match
Android's Activation/Deactivation two-button flow. (My recommendation: match
Android, since `gddp`/`iddp` map cleanly to Activate/Deactivate; the current
Flutter "Add/Schedule Services" tabs don't correspond to a verified API.)

---

## 12. Data Model Investigation

### Verified (Android complex models) ✅
- **getCustomerBoxes**: `box_id, box_number, vc_number, customer_id,
  cas_server_id, status, box_status` (+ unused `stock_id`).
- **GetCustomPackages_ActModel** (dealer package): `package_id, name, price,
  package_related_to, start_date` (+ client `quantity`, `autoRenewal`).
- **Selected package (write)**: CSV of `package_id` (`packages`), `start_date`,
  `months`, `autorenewal`.

### Flutter ✅
- `Customer` (`lib/core/data/customer.dart`) carries the relevant ids:
  `lcoCustomerId` (= customer_id), `vcNumber`, `serialNumber`, `boxNumber`,
  `altCustomerId`, `customerType`, `broadbandUserId`.
- 🟡 No Flutter `Package` / `CustomerBox` model yet — to be created.

### Not Yet Verified 🟡
- Activation **response** package model (what `iddp` returns beyond
  status_code/msg), temporary-activation model, deactivate-reason model.

---

## 13. API Catalogue

| API (key) | Method | Purpose | Request (verified) | Response (verified) | Status |
|-----------|--------|---------|--------------------|--------------------|--------|
| `getCustomerBoxes` (`gcb`) | REST POST | List customer boxes/STBs + state | (caller-dependent) | `status_code, status_msg, service_extension, customer_boxes[]{box_id,box_number,vc_number,customer_id,cas_server_id,status,box_status}` | ✅ response |
| `getDigiDealerPackages` (`gddp`) | REST POST | List packages to activate/deactivate | `dealer_id, customer_id, imei, authtoken, act_type(1/2)` | `status_code, status_msg, digi_dealer_packages[]{package_id,name,price,package_related_to,start_date}` | ✅ |
| `insertDigiDealerPackages` (`iddp`) | REST POST | **Write** activate/deactivate | act: `dealer_id, customer_id, imei, authtoken, packages(CSV), start_date(CSV), months(CSV), autorenewal, act_type=1` · deact: same minus start_date/months, `act_type=2` | `status_code, status_msg` | ✅ |
| `getCustomerpackages` (`gcp`) | REST POST | Current/active packages | — | — | 🟡 |
| `Customerpackageoperations` (`cpo`) | REST POST | Package ops (legacy?/other) | — | — | 🟡 no call site found |
| `Customerdeactivereasons` (`cdr`) | REST POST | Deactivate reasons LOV | — | — | 🟡 |
| `stbTemporaryActivation` (`sta`) | REST POST | Temp activation | — | — | 🟡 |
| `deactivateSTB` (`ds`) | REST POST | Deactivate STB | — | — | 🟡 |
| `deactivateBox` (`db`) | REST POST | Deactivate box | — | — | 🟡 |
| `reactivateBox` (`rbox`) | REST POST | Reactivate box | — | — | 🟡 |
| `packageRenew` (`pr`) | REST POST | Renew package | — | — | 🟡 |
| `serviceExtension` (`serext`) | REST POST | Service extension | — | — | 🟡 |
| `packageActDeactReport` (`padr`) | REST POST | Act/Deact report | — | — | 🟡 (separate report) |

Related screens (Android): `DigiPackage_Home`, `CustomPackages_Activation`,
`CustomPackages_Deactivation`, `BillDetails_Act`, `DigiPackages_deactivation`,
`Deactivatestb_Frag_New`, `ActivePackagesFragment`, `Box_Selection_new`.

---

## 14. Testing Plan (to run once implemented)
- Single package activation (one selection → `iddp` act_type=1 → status 0).
- Multiple package activation (CSV of ids).
- Duplicate selection (ensure list/guard prevents it).
- Deactivation (act_type=2).
- Temporary activation / deactivation (after §8 verified).
- Activation after deactivation (round-trip).
- Invalid STB / VC / serial.
- Timeout / network loss / server error / unexpected response.
- Concurrent requests (double-submit guard).
- Dealer restriction (permission).

---

## 15. Production Risks
- **Money/billing-critical**: package activation changes the customer's bill →
  test ONLY on the local/test server with a disposable customer; never live.
- **Duplicate activation / double-submit** → must guard (disable button while in
  flight), as the payment flow does.
- **Idempotency** of `iddp` is backend-side 🔴 — confirm with backend before
  enabling retries.
- **Race conditions / concurrent box edits** 🔴 — backend.
- **Rollback/recovery**: on failure show `status_msg`, re-fetch the list; do not
  assume success.

---

## 16. Definition of Done (module = IN PROGRESS until all 12 complete)
1. ⬜ Existing implementation investigated — **partial** (core flow ✅; temp/STB/
   reactivate/reasons 🟡).
2. ⬜ APIs verified — gddp/iddp/gcb ✅; gcp/cpo/cdr/sta/ds/rbox 🟡.
3. ⬜ Backend behavior verified — 🔴 needs backend team.
4. ⬜ Database behavior verified — 🔴 needs backend team.
5. ⬜ Documentation completed — **this doc (core done; gaps flagged)**.
6. ⬜ Flutter implementation completed.
7. ⬜ Static analysis clean.
8. ⬜ Manual testing completed.
9. ⬜ Error handling verified.
10. ⬜ Compared with existing app behavior.
11. ⬜ Backend verification completed.
12. ⬜ Explicit user approval.

### Immediate next investigation steps (before any code)
1. Read `getCustomerpackages` (`gcp`) call site + response → the "active
   packages" view fields.
2. Read `Customerdeactivereasons` (`cdr`) + `DeactivateReasons_Adapter` → reasons LOV.
3. Read `stbTemporaryActivation` (`sta`) screen(s) → temp activation request/state.
4. Read `deactivateSTB` (`ds`) / `reactivateBox` (`rbox`) → STB deactivate/reactivate.
5. Map `status`/`box_status` values → state labels (box-selection adapter).
6. Decide the Flutter structure (match Android Activate/Deactivate vs current
   Active/Add/Schedule/Reactivate) — **needs your decision** (see §11).
