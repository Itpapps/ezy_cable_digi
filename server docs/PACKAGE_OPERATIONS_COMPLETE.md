# Package Operations — Complete Production Reference

**Module status: IN PROGRESS** (not complete until you verify). Investigation +
documentation only. **No Flutter code** until reviewed and approved.

Android (READ-ONLY reference): `D:\Git-Repos\magikdigi`.
Flutter (docs only): `D:\StudioProjects\ezy_cable_digi`.

### Verification legend
- ✅ **Verified** — read from the existing source this investigation (file:line).
- 🟡 **Not Yet Verified** — config key/flow exists but exact fields/values not
  read line-by-line, OR depends on a live backend response.
- 🔴 **Not verifiable from the client** — backend tables / stored procedures /
  billing math / report recalculation are server-side; confirm with backend team.

No URLs/tokens/IMEIs/dealer-ids/VC/serial/customer-names recorded — names & shapes only.

---

## 0. Two distinct package subsystems (critical) ✅

The app has **TWO separate package-operation systems** — do not conflate them:

| | A. Dealer Packages | B. Customer (per-box) Packages |
|--|--------------------|-------------------------------|
| Entry | "Package Operations" → `DigiPackage_Home` (Activate/Deactivate) | per-box: `Frag_act_Pack` / `Frag_Deactpack` (reached after box selection) |
| List API | `getDigiDealerPackages` (`gddp`) | `getCustomerpackages` (`gcp`) |
| Write API | `insertDigiDealerPackages` (`iddp`) | `Customerpackageoperations` (`cpo`) |
| Categories | flat list (`package_related_to`) | `is_base` / `is_add_on` / `is_al_a_carte` |
| Write fields | `packages,start_date,months,autorenewal,act_type` | `box_id,packages,service_type_val,month_val,act_type` |
| Reason on deactivate | not seen | **mandatory** (`cdr`) for STB; per-box uses cdr too |

**Two entry buttons exist in Customer Operations ✅:**
- **"Custom Packages"** (`custoper_btn_custompackages`, CustomerOperations:882) →
  `getCustomerBoxes` → on success opens **`Box_Selection_new`** (:2650) = the
  per-box **services hub** with **Active Packages / Add Services / Schedule
  Services / Reactivation** (`Box_Selection_new.java:182-208`). = **SYSTEM B**.
- **"Package"** (`custoper_btn_package`, :1673) → `DigiPackage_Home`
  (Activate / Deactivate dealer flow) = **SYSTEM A**.

✅ **The current Flutter `package_operations_screen.dart` (customer info → serial
dropdown → Active Packages / Add Services / Schedule Services / Reactivation)
EXACTLY mirrors Android `Box_Selection_new` (System B).** So the Flutter UI is
**not wrong** — it matches the per-box hub; it is just **100% hardcoded** (no API).

➡️ **Recommendation (architecture):** **keep the current Flutter UI** and wire
**System B** under it (gcp/cpo/gcpl/rbox + cdr reasons + STB deactivate). System A
(`DigiPackage_Home`) is a **separate** "Digi Package" feature — implement later
only if the business needs the dealer-package activation path too. **Your call**
(Phase 15) — but the evidence says the current Flutter screen already targets
the right Android screen.

---

## Phase 1 — Complete Functional Flow ✅ (core) / 🟡 (billing/reports/dash/db)

```
Customer Search ─▶ Customer Details ─▶ Customer Operations
  └─ "Package Operations" ─▶ DigiPackage_Home
        ├─ Activate  ─▶ CustomPackages_Activation ─ gddp(act_type=1)
        │                  └─ select ─▶ BillDetails_Act ─ iddp(act_type=1) [WRITE]
        └─ Deactivate─▶ CustomPackages_Deactivation ─ gddp(act_type=2)
                           └─ select ─▶ DigiPackages_deactivation ─ iddp(act_type=2) [WRITE]

  └─ per-box (after box selection):
        ├─ Frag_act_Pack    ─ gcp(act_type=1) → cpo(act_type=1)  [activate add/base/ala]
        ├─ Frag_Deactpack   ─ gcp(act_type=2) + cdr → cpo(act_type=2)  [deactivate + reason]
        ├─ ActivePackagesFragment ─ gcpl(status filter) [view active w/ expiry]
        └─ SchedulePackage_frag ─ gcp + cpo [scheduled]

  └─ STB ops (Customer Operations buttons):
        ├─ Deactivate STB ─▶ Deactivatestb_Frag_New ─ gcb + cdr + ds(deactivateSTB)
        ├─ Box ops ─▶ Box_Selection_new ─ db(deactivateBox, SOAP) / rbox(reactivateBox)
        ├─ Temp Activation ─▶ sta(stbTemporaryActivation)
        ├─ Renew ─▶ pr(packageRenew)
        ├─ Unpaid activation ─▶ uca(unpaidCustomerActivation)
        └─ Act-Deact Report ─▶ Act_Deact_Report ─ padr

Refresh: each list re-fetches on screen open; after a write the screen pops back
and the previous list re-fetches on re-entry. (No global push refresh seen ✅.)
Billing / Dashboard / Collections / DB impact = backend-side 🔴 (see Phases 9-11,14).
```

---

## Phase 2 — Screens ✅ (Android)

| Screen | Purpose | Prev → Next | APIs | Key request | Key response |
|--------|---------|-------------|------|-------------|--------------|
| `DigiPackage_Home` | Activate/Deactivate landing | CustomerOps → Activation/Deactivation | — | passes customerid,dealer_id,imei,authtoken,crf,lcocustomerid,custname | — |
| `CustomPackages_Activation` | pick dealer packages to activate | DigiPackage_Home → BillDetails_Act | `gddp` | dealer_id,customer_id,imei,authtoken,act_type=1 | digi_dealer_packages[] |
| `BillDetails_Act` | bill/confirm + WRITE | ← Activation | `iddp` | …,packages,start_date,months,autorenewal,act_type=1 | status_code,status_msg |
| `CustomPackages_Deactivation` | pick dealer packages to deactivate | DigiPackage_Home → DigiPackages_deactivation | `gddp` | …,act_type=2 | digi_dealer_packages[] |
| `DigiPackages_deactivation` | confirm + WRITE deact | ← Deactivation | `iddp` | …,packages,autorenewal,act_type=2 | status_code,status_msg |
| `Frag_act_Pack` | per-box activate (base/add/ala) | box sel → BillDetails | `gcp`→`cpo` | gcp:…,box_id,cas_id,act_type=1 · cpo:…,box_id,packages,service_type_val,month_val,act_type=1 | customer_packages{is_base,is_add_on,is_al_a_carte}; status_code |
| `Frag_Deactpack` | per-box deactivate + reason | box sel | `gcp`+`cdr`→`cpo` | gcp:…,box_id,cas_id,act_type=2 | same; reasons LOV |
| `ActivePackagesFragment` | view active packages (status filter) | box sel | `gcpl` | dealer_id,box_id,customerId,imei,authtoken,status | total_packages_list[]{name,start_date,end_date,status,serial_number,mac_vc_number,price} |
| `Deactivatestb_Frag_New` | deactivate STB (with reason) | CustomerOps | `gcb`+`cdr`+`ds` | ds:dealer_id,reasonId,imei,authtoken,serialNumber,lat,lang,box_id,customer_id | status_code,status_msg |
| `Box_Selection_new` | box deactivate/reactivate | CustomerOps | `db`(SOAP)/`rbox` | db:…,box_id,stock_id · rbox:…,box_id | status_code,status_msg |
| `Act_Deact_Report` | act/deact report | Reports | `padr` | 🟡 | 🟡 |

Loading: per-call `ProgressDialog` 🟡. Validation/error: see Phase 13.

---

## Phase 3 — API Catalogue (full)

### ✅ getCustomerBoxes (`gcb`, REST) — box/STB list & state
- Req: `dealer_id, customer_id, imei, authtoken` (CustomerOperations:2830-2834 / Deactivatestb:349-353).
- Resp: `status_code, status_msg, service_extension, customer_boxes[]{box_id, box_number, vc_number, customer_id, cas_server_id, status, box_status}` (CustomerOperations:2603-2641).

### ✅ getDigiDealerPackages (`gddp`, REST) — dealer packages list
- Req: `dealer_id, customer_id, imei, authtoken, act_type(1|2)`.
- Resp: `status_code, status_msg, digi_dealer_packages[]{package_id, name, price, package_related_to, start_date}` (CustomPackages_Activation:166-177).

### ✅ insertDigiDealerPackages (`iddp`, REST) — dealer package WRITE
- Activate req: `dealer_id, customer_id, imei, authtoken, packages(CSV), start_date(CSV), months(CSV), autorenewal, act_type=1` (BillDetails_Act:263-271).
- Deactivate req: `…, packages(CSV), autorenewal, act_type=2` (DigiPackages_deactivation:254-260).
- Resp: `status_code, status_msg`.

### ✅ getCustomerpackages (`gcp`, REST) — per-box current packages
- Req: `dealer_id, customer_id, imei, authtoken, box_id, cas_id, act_type(1|2)` (Frag_act_Pack:750-756).
- Resp: `status_code, status_msg, customer_packages{ is_base[], is_add_on[], is_al_a_carte[] }`; each item `{package_id, name, price, pricing_structure_type}` (Frag_act_Pack:592-669).

### ✅ Customerpackageoperations (`cpo`, REST) — per-box package WRITE
- Req: `dealer_id, customer_id, imei, authtoken, box_id, packages(CSV), service_type_val, month_val, act_type(1|2)` (Frag_act_Pack:844-852).
  - `customer_id` = lcoCustomerId (`getcustid`); `box_id` = selected box (`getbox`). **No `cas_id`** on cpo (only on gcp).
- Resp: `status_code, status_msg` (Frag_act_Pack:786-787). `0` → success dialog "Package Request!" then `popBackStack`; `1` → failed dialog.
- ✅ **deactivate (act_type=2) param resolved (VERIFIED, Frag_Deactpack:1223-1234):**
  `dealer_id, customer_id, imei, authtoken, box_id, packages(CSV), act_type="2",
  **`deact_reason`**=<reasonId>`. **No `service_type_val` / `month_val`** on the
  deactivate path (only `packages` + `deact_reason`). `packages` = same `package_id`
  CSV as activate (FilterTool.getCommonSeperatedString, Frag_Deactpack:578).

#### ✅ cpo/gcp SCHEDULE (act_type=7) — VERIFIED (SchedulePackage_frag)
Schedule Services is Add Services with a **future date** instead of qty/month:
- **List:** `gcp` with `act_type="7"` (`:749-755`) — `dealer_id, customer_id, imei,
  authtoken, box_id, cas_id, act_type="7"` → same `customer_packages{is_base,is_add_on,
  is_al_a_carte}` shape.
- **Write:** `cpo` with `act_type="7"` (`:846-853`) — `dealer_id, customer_id, imei,
  authtoken, box_id, packages(CSV), **schedule_start_date**, act_type="7"`. **No**
  `service_type_val` / `month_val` / `deact_reason`.
- **`schedule_start_date` format = `dd-MM-yyyy`** (`df3`, `:1152`). Must be a **strictly
  future** date — today and earlier are blocked (`:530-531` "must not be current date";
  `:1137-1144` "must not be lesser than current date"). Confirm copy: "Are you sure you
  want to schedule packages?" (`:536`).

#### ✅ cpo ACTIVATE (act_type=1) — exact CSV construction (VERIFIED)
The three CSV params are built from the selected packages (FilterTool:51-75, Frag_act_Pack:563-566,478-482):
| param | format | example |
|-------|--------|---------|
| `packages` | `package_id` joined by `,` | `101,102` |
| `service_type_val` | `package_id##ptype` joined by `,` | `101##1,102##1` |
| `month_val` | `package_id##month` joined by `,` | `101##1,102##1` |

- **Per-package defaults: `ptype="1"`, `month="1"`** — set when the catalogue list is built (Frag_act_Pack:614-615,643-644,674-675) and used as-is unless the quantity selector changes them.
- **Quantity/recurring selector (`ll_ptype`) appears ONLY when ALL three hold** (ActiveAdapter_listview.java:159):
  `pricing_structure_type == "2"` **AND** the row is checked **AND** `LoginActivity.qty_seletion_view == 1`.
  When shown: "Recurring" → `ptype=1, month=1` (months disabled); "Monthly" → `ptype=2, month=<1..12 chosen>` (ActiveAdapter:96-106,120-133; options `{"Recurring","Monthly"}`, months `1..12`).
- **`qty_seletion_view` source:** the `validateLogin` SOAP response property (LoginActivity:777-783, parsed off `envelope.getResponse().toString()`); default `0` if absent. It is **NOT** a separate API — it's already in the response Flutter's `AuthService.login()` receives.

> **🔵 LIVE-VERIFIED (2026-06-28, test dealer):** `qty_seletion_view = 0` for this dealer
> (probe read off the validateLogin response). Therefore the quantity selector is never
> shown and **every selected package is sent with `ptype="1"`, `month="1"`**. The Flutter
> **Add Services execution implements this default path only** — exact production parity for
> this dealer. If a dealer with `qty_seletion_view=1` is ever targeted, the Recurring/Monthly
> selector above must be investigated live and built before use (do not assume).

### ✅ getcustomerpackageslist (`gcpl`, REST) — active packages w/ expiry
- Req: `dealer_id, box_id, customerId, imei, authtoken, status` (ActivePackagesFragment:248-253).
- ✅ **`status` value is NUMERIC** (ActivePackagesFragment:118-125, LIVE-confirmed):
  **`"1"` = Active**, **`"0"` = Deactive** (the dropdown label maps to "1"/"0"; do
  NOT send the literal "Active"/"Deactive" — that returns `status_code 1
  "packages list not found"`).
- Resp: `status_code, status_msg, total_packages_list[]{name, start_date, end_date, status, serial_number, mac_vc_number, price}` (ActivePackagesFragment:165-183).
- `start_date`+`end_date` → expiry / remaining-days; `status` filter = "1"/"0".

### ✅ Customerdeactivereasons (`cdr`, REST) — deactivate reasons LOV
- Endpoint: `/packagelist/Customerdeactivereasons` (configg.properties `cdr`).
- ✅ **Per-box request fields resolved (VERIFIED, Frag_Deactpack:940-949):** **ONLY
  `imei, authtoken`** are sent — `dealer_id`/`customer_id`/`box_id`/`cas_id`/`act_type`
  are explicitly commented out. (The STB-deactivate screen may send more; per-box does not.)
- Resp: `status_code, status_msg, deactive_reasons[]{reasonId, reasonName}`
  (Frag_Deactpack:831-852). Client prepends a synthetic `{reasonId:0,"Select"}`.
- **Mandatory**: deactivation blocked until a reason is selected (Frag_Deactpack:504-505 "Select reason").

### ✅ STB Deactivation (Deactivatestb_Frag_New) — VERIFIED flow + the magic branch
Reached from Customer Operations (separate screen, not the per-box hub). Three steps:
- **Boxes:** `gcb` (getCustomerBoxes) → serial / `box_id` / `customer_id` (:235-292).
- **Reasons:** **`gdr` = `getDeactiveReasons` (SOAP)** — wrapper `reasonsInfo`/complex
  `DeactivateReasonsInfo`, fields `showforlco=0, authToken, imei`; response = repeated
  `reasonList` elements `{reasonId, reasonName}`, prepend "Choose Reason" (id 0)
  (:388-468). ⚠️ This is **`gdr` (SOAP)**, NOT the per-box `cdr` (REST).
- **GPS:** `lat`/`lang`, `0.0` fallback (:125-131). Validation: reason==0 / no box → toast.

**⚠️ Write path branches on a hardcoded reason id (:196-201):**
```java
if (reason_selected == 17) Deactivation_asyncTask (SOAP db);  else  Deactivatestbrest (REST ds);
```
> 🔵 **LIVE-VERIFIED (2026-06-28, test dealer) — `gdr` list:**
> `17=Unpaid Customer`, `21=Temporary Deactivation1`, `13=Others`, `16=On Vacation`,
> `31=On Hold`, `6=Deactivation Package Change`. So **`reasonId 17` = "Unpaid Customer"**
> → the **SOAP `db`** path; every other reason → **REST `ds`**. "Unpaid Customer" is a
> primary deactivation reason, so the `db` branch is **NOT skippable**. The literal `17`
> is dealer-config-specific, but production (magik) hardcodes it — exact parity = match `17`.

#### ✅ deactivateSTB (`ds`, REST) — non-17 reasons
- Endpoint `/packagelist/deactivateSTB`. Req: `dealer_id, reasonId, imei, authtoken,
  serialNumber, lat, lang, box_id, customer_id` (Deactivatestb_Frag_New:787-796).
- Resp: `status_code, status_msg` (:719).

#### ✅ deactivateBox (`db`, SOAP) — reasonId 17 ("Unpaid Customer")
- SOAP method `deactivateBox`; wrapper element `deactivateSTB_info`, complex
  `DeactivateSTB_Info`, fields `authToken, imei, reasonId, serialNumber, lat, lang,
  box_id, customer_id` (Deactivatestb_Frag_New:575-595). (No `stock_id` on this SOAP path.)
- Resp: `status_code, status_msg`.
- 🟡 exact response/post-success dialogs to re-read at implementation (:620-700).

### ✅ reactivateBox (`rbox`, REST) — VERIFIED & IMPLEMENTED
- Endpoint `/packagelist/reactivateBox` (configg.properties `rbox`).
- Req: `dealer_id, customer_id, imei, authtoken, box_id` (Box_Selection_new:513-523).
  **`customer_id` = the box's `customer_id`** (`CustomerBox.customerId`, set from
  `getCustomerBoxes…getCustomer_id()` :161) — NOT lcoCustomerId. Flutter falls back
  to lcoCustomerId only if the box field is empty.
- Resp: `status_code, status_msg`.
  - `0` → "Success!" dialog → OK → **`startActivity(MainActivity)` (home)** (:443-465).
  - `1` → "No Details Found!" dialog → OK → **also home** (:471-493).
  - transport error → Toast "Failed." (:503-509).
- **Flutter (exact parity):** confirm "Reactivate Box / Are you sure you want to
  Reactivate?" → `reactivateBox` → result dialog → OK → `Navigator.popUntil(isFirst)`
  (Dashboard) on BOTH 0 and 1; transport error → "Failed" dialog, stay. Double-submit
  guarded. 🔵 verify live.

### ✅ customerServicesExtendWithStock (`csews`, REST) — Service Extension — IMPLEMENTED
- Endpoint `/packagelist/customerServicesExtendWithStock` (configg.properties `csews`).
- **Gate:** hub tile shows only if **`box_wise_service_extension == "1"`** — a
  **validateLogin response property** (LoginActivity:562, default "0"), parsed into
  `SessionService.boxWiseServiceExtension`. NOT the `service_extension` role permission.
- Req (Box_Selection_new:408-413): `dealer_id, customer_id, imei, authtoken, box_id,
  **stock_id**`. `customer_id` = the box's `customer_id`; `stock_id` = the box's
  `stock_id` (added to `CustomerBox` — gcb returns it though §gcb list omitted it).
- Confirm: "Service Extension with Box / Are you sure you want to extend services with box?".
- Resp `status_code/status_msg`: `0`→"Success!"→home; `1`→"No Details Found!"→home;
  error→"Failed." (same home-on-both pattern as `rbox`, Box_Selection_new:335-385).
- **Flutter:** tile gated by `boxWiseServiceExtension`; confirm → `csews` → result dialog
  → `popUntil(isFirst)` on 0 and 1; double-submit guarded. analyze-clean. ⬜ live-verify
  pending (depends on this dealer's `box_wise_service_extension` value).

### 🟡 stbTemporaryActivation (`sta`, REST) — Phase 6
- Button `custoper_btn_tmpactivation` (CustomerOperations:1146,1210); `tmpact_url` (:203).
- Req: at least `dealer_id, customer_id, imei, authtoken`; **dates/duration Not Yet Verified**.
- Search response carries `tmp_activation` (int) flag (CustomerOperations:2375) = whether temp-activated.

### 🟡 packageRenew (`pr`), unpaidCustomerActivation (`uca`), serviceExtension (`serext`), customerServicesExtendWithStock (`csews`), packageslist (`packli`), packageActDeactReport (`padr`)
- Call sites located (Phase 0 grep) but request/response not read this pass — **Not Yet Verified**.

---

## Phase 4 — Active Package Flow ✅ (fields) / 🟡 (renewal/auto-renewal)
- Load via **`gcpl`** (status filter Active/Deactive) → `total_packages_list[]` with
  `name, start_date, end_date, status, serial_number, mac_vc_number, price`.
- **Expiry / remaining days** = derived from `end_date` (client computes) 🟡 (exact computation not read).
- **Auto-renewal** appears in the **activation write** model (`autorenewal` on iddp; default 0 on the dealer model). Per-package renewal via **`pr` (packageRenew)** 🟡.
- **Package category** = `is_base / is_add_on / is_al_a_carte` (gcp) or `pricing_structure_type`.
- **Pricing** = `price` per item; billing impact 🔴 backend.

---

## Phase 5 — STB Operations ✅ (apis) / 🔴 (cross-module side effects)
- `deactivateSTB` (`ds`): needs `serialNumber`, `box_id`, `reasonId` (from `cdr`), GPS `lat/lang`, `customer_id`.
- `deactivateBox` (`db`): box-level (SOAP + `reasonId`, or REST + `stock_id`).
- `reactivateBox` (`rbox`): `box_id` + standard ids.
- Connected to: box `status`/`box_status` (gcb), `vc_number`, `serial_number`,
  `cas_server_id`. Effect on **customer status / payments / dashboard / reports**
  is **backend-side 🔴** — no client push refresh seen beyond local re-fetch.

---

## Phase 6 — Temporary Activation ✅ (UX/flow) / 🟡 (sta params) / 🔴 (duration/billing)
- Entry `custoper_btn_tmpactivation` (CustomerOperations:1210-1261).
- **Access control ✅:** denied for `userType == "SERVICE"` OR `customerType ==
  "BroadBand"` → "Access denied" dialog (:1213-1229).
- **Flow ✅:** otherwise a single confirm dialog **"Temporary Activation — Are you
  sure you want to Activate?"** → **Yes** → `TemporaryActivation_stb()` (:1243).
  **There is NO duration / from-date / to-date input in the UI** — it is a
  one-tap activate.
- ➡️ Therefore **duration / expiry / billing are decided by the BACKEND** 🔴, not
  sent by the client.
- 🟡 Exact `sta` request fields (inside `TemporaryActivation_stb()`) and the
  response/status handling not read line-by-line; expected to be the standard
  `dealer_id, customer_id, imei, authtoken` (no dates). `tmp_activation` (int) on
  the customer (search response :2375) flags whether already temp-activated; the
  button is shown/hidden by `temp_act` (:1314).

---

## Phase 7 — Status Mapping ✅ (complete, evidence) — the client is BINARY

**KEY PRODUCTION FINDING:** the existing app represents box/package state as a
**binary Active / DeActive**, plus a separate temporary-activation flag. The
richer states (SUSPENDED / LOCKED / EXPIRED / PENDING / TEMP-DEACTIVE) **do NOT
exist as client-side labels** — searched the entire adapter layer; no `setText`
for them was found. **Flutter must NOT invent those states** (that would be
inventing behavior). They are, at most, backend-only concepts.

### Verified mappings ✅
- **`box_status` → label** (the only explicit mapping, `OTTAdapter.java:69-74`):
  - `box_status == "1"` → **"Active"**
  - else (incl. `"0"`) → **"DeActive"**
- **Temporary activation** is a **separate flag**, NOT a box_status value:
  - customer `tmp_activation` (int) — persisted flag (CustomerOperations:2375).
  - `temp_act == 0` → temp-activation available/shown (:1314).
- **`pricing_structure_type`** is a **package TYPE, not status**:
  `pricing_structure_type == "2"` → quantity-selectable package
  (`ActiveAdapter_listview.java:159`).
- **`package status` (gcpl)** is filtered via a `Select / Active / Deactive`
  dropdown (the `status` request param) → confirms the **binary Active/Deactive**
  model for packages too. No richer per-row status label found.

### ✅ LIVE-VERIFIED (test server, getCustomerBoxes)
- **Active box** (customer 927630): `status = "1"` AND `box_status = "1"` →
  **Active**. Confirms the `OTTAdapter` rule.
- **No boxes** (customer 1027021): `status_code = 1, "NO Boxes For this Customer"`
  → the empty state (handle as "no boxes", not an error).
- 🟡 **Deactivated box value not captured** (no deactivated box available during
  the probe) — the exact deactivated `box_status` ("0" vs "2") is still open.
  **FROZEN RULE for the status LABEL:** `box_status == "1"` → **Active**; anything
  else → **DeActive** (`OTTAdapter:69-74`). Confirm the deactivated value during
  testing (a one-line check), but do not block on it.

#### 🔵 LIVE-VERIFIED & CORRECTED — Reactivation visibility (2026-06-28)
**Earlier assumption ("gate Reactivation on DeActive") was WRONG.** The production
source is authoritative:
- `frag_box_selection.xml:331-339` — the Reactivation row has **no `visibility`
  attribute** → default **VISIBLE**.
- `Box_Selection_new.java:164-166` — the **only** code touching it sets it `GONE`
  **iff `box_status == "0"`**. It is **never** set back to VISIBLE in code.
- Reactivation is **NOT role-gated** (only Add Services→`package_activation`,
  Schedule→`schedule_service`, Remove Services→`package_deactivation` are; `:124-147`).

**VERIFIED RULE:** Reactivation is **shown when `box_status != "0"`** (including the
Active value `"1"`) and **hidden only when `box_status == "0"`**. Confirmed live for
customer with `box_status="1"` (flags `pa=pd=ss=se=true`): production shows it, so
Flutter must too. Flutter impl: `if (box.boxStatus.trim() != '0') …Reactivation`.
> ⚠️ Note the asymmetry: the status **label** treats only `"1"` as Active, but
> **Reactivation visibility** keys off `"0"` (not off the Active label). Do not
> conflate the two.

### Not represented in the client (do not build) 🔴
SUSPENDED, LOCKED, EXPIRED, PENDING, TEMP-DEACTIVE — no client mapping exists.
If the business needs them, they must come from a **backend-confirmed** field/value
(Not Yet Verified). Do not assume.

---

## Phase 8 — Deactivation Reasons ✅
- `Customerdeactivereasons` (`cdr`) → list of `{reasonId, reasonName}` → spinner
  (`DeactivateReasons_Adapter`).
- **Mandatory** before any deactivation (STB and per-box): selecting reasonId==0
  blocks with "Select reason" (Frag_Deactpack:504-505).
- `reasonId` is sent on `ds` (deactivateSTB) and the deactivate write.
- 🟡 exact `cdr` request fields + whether free-text "other" is allowed (an
  `ed_reason` EditText exists, Frag_Deactpack:487) Not fully read.

---

## Phase 9 — Reports Integration 🟡 / 🔴
- `packageActDeactReport` (`padr`) is a **read** report (Act_Deact_Report screen).
- Whether activation **immediately** updates Employee/Mini-Day/Collection reports,
  or the backend recalculates later, is **🔴 backend-side** — no client code makes
  reports refresh after a package write (only local list re-fetch). **Not Yet
  Verified**; confirm with backend.

---

## Phase 10 — Dashboard Integration 🟡 / 🔴
- No client code refreshes the dashboard (collection/due/unpaid/cards) after a
  package operation. The dashboard re-fetches only when re-opened (its own APIs).
- Whether package activation changes dashboard figures is **🔴 backend-side**
  (the dashboard KPIs come from `dashBoardDetails`). **Not Yet Verified.**

---

## Phase 11 — Billing Integration 🔴 (backend) — **Not Yet Verified**
- Package activation sends `start_date`, `months`, `autorenewal` (iddp) /
  `month_val` (cpo) → the backend computes billing. **Immediate vs next-month,
  pro-rata, partial month, renewal/expiry, outstanding, GPA interaction are ALL
  server-side and CANNOT be verified from the client.** Must be confirmed with the
  backend team before relying on any billing behavior. **Do not assume.**

---

## Phase 12 — Customer Refresh ✅ (verified) — refresh differs by operation
**Two different refresh behaviors (verified):**
- ✅ **Add / Remove Service (`cpo`)** — `Frag_act_Pack.java:788-805`: success
  dialog (`status_msg`) → OK → **`popBackStack()`** (returns to `Box_Selection_new`).
  Dashboard navigation is commented out (:798-799). **Local only.**
- ✅ **Reactivate (`rbox`)** — `Box_Selection_new.java:443-465`: success/`status 1`
  dialog → OK → **`startActivity(new Intent(context, MainActivity.class))`** —
  **restarts MainActivity (home) = a full refresh of everything.** (This is the
  "reactivate refreshes everything" behavior.)
- ✅ **STB deactivate (`ds`)** — 🟡 success handler not read line-by-line; expected
  similar (dialog → back/home).

➡️ **Flutter parity rule:**
- After **Add/Remove Service** success → pop back to the package hub AND re-fetch
  `getCustomerBoxes` + the package list (so the hub reflects the change).
- After **Reactivate** success → navigate to the **Dashboard/home**
  (`popUntil(isFirst)` / pushReplacement to dashboard) = full refresh.
- 🔴 Downstream billing/dashboard/reports recalculation is backend-side.
```
cpo (add/remove)  → dialog → popBackStack          → re-fetch hub (boxes+packages)
rbox (reactivate) → dialog → restart MainActivity  → full home refresh
Dashboard / GPA / Reports figures: recalculated by BACKEND, not pushed by client.
```

```
[write success] → success dialog → popBackStack → (on re-entry) list API re-fetch
   Dashboard / GPA / Reports: NOT pushed by the client (backend recalculates) 🔴
```

---

## Refresh Behavior Matrix (implementation reference) ✅/🟡

The Package Hub (Flutter `package_operations_screen.dart` = Android
`Box_Selection_new`) is the central screen. Every operation refreshes it
**differently** — getting this right is the difference between a correct dynamic
screen and a stale one. Rules below are the **Flutter spec**; ✅ = matches verified
Android behavior, 🟡 = inferred (confirm during testing).

| Operation | API | On success (Android) | Flutter refresh rule |
|-----------|-----|----------------------|----------------------|
| Open Hub | `getCustomerBoxes` (gcb) | boxes loaded into spinner | fetch on open; `status_code 1` → **empty state** "No Boxes"; show loading + retry |
| Active Packages (view) | `getcustomerpackageslist` (gcpl) | read-only list | fetch on open; re-fetch on status-filter change |
| Add Services | `Customerpackageoperations` (cpo, act_type=1) | dialog → `popBackStack` ✅ | pop to Hub **and re-fetch Hub** (boxes + packages) |
| Remove Services | cpo (act_type=2) + `cdr` reason | 🟡 dialog → back | pop to Hub **and re-fetch Hub** |
| Service Extension | `serext` / `csews` | 🟡 not read | re-fetch Hub (🟡 confirm) |
| Schedule Services | `gcp` + `cpo` | 🟡 dialog → back | pop to Hub + re-fetch (🟡) |
| **Reactivation** | `reactivateBox` (rbox) | dialog → **restart MainActivity (home)** ✅ | navigate **home / Dashboard** (`popUntil(isFirst)`), full refresh |
| STB Deactivation | `deactivateSTB` (ds) + `cdr` | 🟡 dialog → back/home | navigate home (🟡 confirm) |
| Dashboard / GPA / Reports | — | **NOT** pushed by client | do not push; backend recalculates 🔴 |

Key invariants:
- **Add/Remove/Extension/Schedule** → stay in the package area, refresh the **Hub**.
- **Reactivate (and likely STB deactivate)** → go **home** (full refresh).
- The Hub must always re-derive **Active/DeActive** from a fresh `getCustomerBoxes`
  after any state-changing op (never trust stale state).

## Phase 13 — Error Handling Matrix ✅ (verified for cpo) / 🟡 (other APIs)
✅ **`cpo` write (`Frag_act_Pack.java:786-838`):**
- `status_code == 0` → success dialog ("Package Request!", `status_msg`) → OK →
  `popBackStack()`.
- `status_code == 1` → "Failed!" dialog with `status_msg` (screen stays).
- Volley `onErrorResponse` (network/timeout/HTTP) → **"Failed." toast**; progress
  dialog dismissed; screen stays. Response parsed inside `try/catch` (malformed →
  caught, no crash).
- ⚠️ **No client-side double-submit guard** (button not disabled) → **Flutter MUST
  add one** (disable while in flight) — package writes are billing-critical.
- ✅ **Deactivation requires a reason** (client blocks reasonId==0).
🟡 Other APIs (iddp/ds/db/rbox/gddp/gcp/gcpl) follow the same 0/1(/2) +
`onErrorResponse`-toast pattern (e.g. Box_Selection_new:307-310, Deactivatestb
0/1/2 branches) but each branch's exact text was not read line-by-line.

| Case | Existing behavior | Status |
|------|-------------------|--------|
| Timeout / network | Volley error → toast; no auto-retry | 🟡 |
| HTTP error | Volley error path | 🟡 |
| Invalid auth | backend `status_code` ≠0 + msg | 🟡 |
| Empty/null/partial JSON | try/catch per field; list hidden | 🟡 |
| Duplicate / already active/inactive | backend `status_msg` (list pre-filtered by act_type) | 🟡/🔴 |
| Invalid STB/VC/serial | backend validation → msg | 🔴 |
| Deactivate without reason | **client blocks** ("Select reason") | ✅ |
| Concurrent / double submit | not guarded client-side (button) | 🟡 → Flutter MUST guard |
| Multiple selection | supported (CSV) | ✅ |

Flutter rule: never crash on null/empty/malformed/timeout/unauthorized; show
`status_msg`; keep screen on failure; **disable submit while in flight**.

---

## Phase 14 — Database Investigation 🔴 **Not Yet Verified**
- Tables, stored procedures, audit trail, logs, rollback, history, report
  recalculation are **server-side and not visible in the client**. **Explicitly
  Not Yet Verified — must be confirmed with the backend team.** Not guessed.
- Verifiable expectation only: a successful `iddp`/`cpo`/`ds`/`rbox` returns
  `status_code==0` and the subsequent `gcp`/`gcpl`/`gcb` reflects the change.

---

## Phase 15 — Flutter Gap Analysis ✅

`lib/features/complaints/package_operations_screen.dart` (current):
| Aspect | State |
|--------|-------|
| Customer info (name/lco/serial dropdown/vc) | ✅ real fields |
| Active Packages view | ✅ **DONE** — live `gcpl` with status filter (Active "1"/Deactive "0"), shows dates + price |
| Add Services (Base/Add-On/Alacarte tabs) | ✅ **DONE** — `gcp` catalogue + `cpo` activate (default path, confirm dialog, double-submit guard, hub refresh). 🔵 LIVE-VERIFIED 2026-06-28 (`status_code 0`, "Packages will be processed shortly") |
| Remove Services (deactivate) | ✅ **DONE** — `gcp` act_type=2 + `cdr` reasons (mandatory) + `cpo` act_type=2 (`deact_reason`); confirm dialog, double-submit guard, hub refresh. 🔵 LIVE-VERIFIED 2026-06-28 (`status_code 0`, reason=16) |
| Schedule Services | ✅ **DONE** — `gcp` act_type=7 + `cpo` act_type=7 (`schedule_start_date` dd-MM-yyyy, future-only date picker); confirm dialog, double-submit guard, hub refresh. 🔵 LIVE-VERIFIED 2026-06-28 (`status_code 0`, date 30-06-2026) |
| Reactivation | ❌ snackbar only; no `rbox` |
| Deactivate STB (`deactivate_stb_screen.dart`) | ✅ **DONE (⬜ live-verify pending)** — `gcb` boxes + `gdr` reasons (SOAP) + GPS; branch `reasonId==17`("Unpaid Customer")→`db` SOAP, else `ds` REST; validation, double-submit guard, per-path result handling. analyze-clean; not yet run live (test-server network was down) |
| Package model / repository / controller | ❌ **none exist** |
| Validation / refresh / error handling | ❌ none |
| Reports / Dashboard / Billing integration | ❌ none (and backend-driven 🔴) |

**Box hub services — Android vs Flutter ✅:** Android `Box_Selection_new:101-106`
exposes **6** services (each **role-gated** by `LoginActivity.package_activation`
/ `schedule_service` / `package_deactivation`): **Active Packages, Add Services,
Remove Services, Service Extension, Reactivation, Schedule Services**. The current
Flutter now has **5** (Active Packages, Add Services, **Remove Services ✅ done**,
Schedule Services, Reactivation, **Service Extension ✅**) — **all 6 hub services now
present**. Service Extension (`csews`) is gated by `box_wise_service_extension`
(config flag), NOT the role permission.
Boxes are loaded
via `getCustomerBoxes` (passed into the hub) and shown in a box spinner.

**Missing to build (after approval & after Phase 6/7 verified):**
1. Models: `CustomerBox`, `Package` (base/add-on/ala), `ActivePackage` (expiry).
2. Repository (REST, reuse `RestClient.postForm`): `getCustomerBoxes`,
   `getCustomerpackages`, `Customerpackageoperations`, `getcustomerpackageslist`,
   `Customerdeactivereasons`, `deactivateSTB`, `reactivateBox`, (and dealer
   `gddp`/`iddp` if system A is chosen).
3. Controller/state per screen; defensive parsing; **double-submit guard**.
4. Wire the screens; status mapping (Phase 7, frozen rule) before showing labels.
5. **Box spinner** (select box) + **role-gating** of services; add the missing
   **Remove Services** + **Service Extension**.
6. **Refresh (Phase 12):** re-fetch the hub after add/remove; go **home** after
   reactivate.
7. **Empty/error states:** `getCustomerBoxes status_code 1` = "NO Boxes".

---

## Architecture / Sequence / Navigation
See Phase 0-2 diagrams above. Navigation: Customer Details → Package Operations
(`DigiPackage_Home`) and the per-box screens; STB ops are separate Customer
Operations buttons.

## Testing Checklist (when implemented)
Single/multiple activation; deactivation (with mandatory reason); per-box
base/add-on/ala; active-list expiry; temp activation (after Phase 6); STB
deactivate/reactivate; invalid STB/VC/serial; timeout/network/server error;
concurrent/double-submit; dealer permission.

## Production Risks
Billing-critical (test only on local/test server, disposable customer); double
activation → must guard; idempotency 🔴 backend; status value mapping unverified
(don't display wrong state); billing/reports/dashboard recalculation 🔴 backend.

## Implementation Plan (🔒 FROZEN SPEC — foundation-first)

> **This document is FROZEN** as the implementation specification (status mapping
> live-verified). If implementation uncovers a contradiction: verify with live
> evidence → **update this doc first** → then update code. Do not re-investigate
> the module otherwise.

**Phase 1 — Foundation (NO UI changes):**
1. `CustomerBox` model (box_id, box_number, vc_number, customer_id,
   cas_server_id, status, box_status) + `isActive` getter (`box_status == "1"`).
2. `Package` model (package_id, name, price, pricing_structure_type; category =
   base/add-on/ala) + `ActivePackage` (name, start_date, end_date, status,
   serial_number, mac_vc_number, price).
3. `PackageOperationsRepository` (REST via `RestClient.postForm`):
   `getCustomerBoxes()`, `getCustomerPackages(boxId, actType)`,
   `getCustomerPackageList(boxId, status)`. Defensive parse; never throw.
   → **verify each against a real response** before UI.

**Phase 1.5 — Login Permissions (explicit pre-Phase-2 checkpoint):** ✅ verified-contract
- ⚠️ The flags come from a **SEPARATE API**, not the login response:
  **`getRolePermissions` (key `grp`, REST POST)** — request `dealer_id, imei,
  authtoken` (LoginActivity:1144-1147); response `status_code, status_msg,
  rolePermission` where **`rolePermission` is a JSON STRING** of
  `{ name: { permission: "1"/"0" } }` (LoginActivity:1054-1107).
- Package-relevant flags (each `{name}.permission`): **`package_activation`** (Add),
  **`package_deactivation`** (Remove), **`schedule_service`** (Schedule),
  **`service_extension`** (Service Extension). Others present: `renew`,
  `make_payment`, `unpaid_customer_activation`, `unpaid_customer_deactivation`,
  `onetime_charges`, `customer_discount`, `share_option`, `expenses` (not package-hub).
- **Answers (evidence):** type = **string `"1"`/`"0"`**; can be **missing** (some
  `try/catch` with defaults; whole block wrapped) → use **default `false` (deny)`**;
  **dealer/role-specific**; **session-only** (fetched once right after login);
  **never refreshed** post-login.
- **Flutter:** `validateLogin` did NOT fetch these → added `AuthService.
  _fetchRolePermissions()` (REST) after login; parses the 4 flags into
  `SessionService` as **bools** (`permission == "1"`), safe `false` on any failure.
- **Gate Phase 2 on this** — the Hub shows/hides actions on these flags.

**Phase 2 — Dynamic Package Hub** (replace the hardcoded screen):
- Live box selector (spinner) from `getCustomerBoxes`.
- Role-gated actions (LoginActivity flags `package_activation` / `schedule_service`
  / `package_deactivation` → need these captured at login 🟡).
- Correct **Active/DeActive** (frozen rule §7).
- Empty state ("No Boxes", `status_code 1`), loading, retry, error dialog,
  refresh-on-return.

**Phase 3 — Features (one at a time, each verified):**
Active Packages → Add Services → Remove Services → Service Extension →
Schedule Services → Reactivation → STB Deactivation.
Each: uses the repository (no API calls from UI); refreshes the Hub per the
**Refresh Behavior Matrix**; double-submit guard; never crashes on
null/empty/malformed/timeout.

🟡 **Pre-Phase-2 dependency:** role-permission flags (`package_activation`,
`schedule_service`, `package_deactivation`) are not captured at Flutter login yet —
add them to the login parse (or the action gating is incomplete).

## Definition of Done (12 items — module IN PROGRESS)
1. Existing impl investigated — core ✅; temp/status-mapping/pr/uca/serext/csews/packli/padr 🟡.
2. APIs verified — gcb/gddp/iddp/gcp/cpo/gcpl/ds/db/rbox/cdr ✅; sta/pr/uca/serext/csews/packli/padr 🟡.
3. Backend behavior — 🔴 backend team.
4. Database behavior — 🔴 backend team.
5. Documentation — this doc (core done; gaps flagged).
6-12. Flutter impl / analyze / testing / error handling / parity / backend verify /
   **your approval** — pending.

### Immediate next investigation (before any code)
1. Temp activation (`sta`) request/response (Phase 6) — read `custoper_btn_tmpactivation` onClick.
2. Status value→label mapping (Phase 7) — read box/active adapters.
3. `cdr` request shape + free-text reason rule (Phase 8).
4. `pr`/`uca`/`serext`/`csews`/`packli`/`padr` request/response.
5. Your decision: Flutter implements **system A (dealer)** or **system B (per-box)** — Phase 0/15.
