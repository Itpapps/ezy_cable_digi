# Dashboard / Nearest Customer / Location — Android Parity Investigation

Investigation-only (no code). **Android = source of truth** (`D:\Git-Repos\magikdigi`,
READ ONLY). Goal: make the Flutter Dashboard + Nearest + Location match Android 1:1.
Items not line-verified are 🟡. **Financial safety:** this is dashboard/location only —
payments, collections, receipts, sync, offline-payment, customer data are NOT in scope.

> Architecture note: this Android app uses **Fragments + Volley (REST) + ksoap2 (SOAP) +
> SQLite + AsyncTask/per-call callbacks** — there is **no Retrofit/ViewModel/Presenter**.
> The migration maps to that reality (controllers/repositories already exist in Flutter).

---

## 1. Dashboard — call flow (Android `DashboardHomeFragment`)
```
DashboardHomeFragment.onCreateView
  ├─ GPSTracker gps = new GPSTracker(activity)         // LocationManager service
  ├─ lat/lng = gps.getLatitude()/getLongitude()
  ├─ dashBoardDetails (dbd, SOAP)   → summary cards    (independent call)
  ├─ getLCODepositAmount (glda, REST) → LCO wallet     (independent call)
  ├─ getopencomplaintslist (gocl, SOAP) → Complaints tab
  ├─ unpaidCustomers (uc, SOAP) → Unpaid tab
  ├─ NearestNextCustomer (nnc, REST, needs lat/lng) → Nearest tab
  └─ paylaterList (REST, /digi_rest_api ENCRYPTED) → PayLater tab
        ↓ each callback updates ITS OWN section (RelativeLayout/RecyclerView)
```
Each API has its **own** `SOAP_ACTION/METHOD_NAME` + callback (`DashboardHomeFragment:218-225`);
sections update **independently** as each response arrives (no single "load all then render").

## 2. Dashboard APIs
| Card / section | Key | Endpoint | Transport | Encrypted? |
|----------------|-----|----------|-----------|-----------|
| Summary (Due/Month Billing/Onetime/Collections) | `dbd` | `dashBoardDetails` | SOAP (wsController) | no |
| LCO Wallet | `glda` | `/packagelist/getLCODepositAmount` | REST | no |
| Complaints tab | `gocl` | `getopencomplaintslist` | SOAP | no |
| Unpaid tab | `uc` | `unpaidCustomers` | SOAP | no |
| **Nearest tab** | `nnc` | `/packagelist/NearestNextCustomer` | REST | no |
| PayLater tab | `paylaterList` | `/digi_rest_api/scheduled_collection_data` | REST | **YES** (DigiCrypto) |
| Location update | `ucl` | `updateCustomerlocation` | SOAP | no |
🟡 exact request/response fields for `dbd`, `glda`, `nnc` to be line-read at implementation
(request params at minimum: authToken/imei/dealer_id; `nnc` adds lat/lng).

## 3. Loading behaviour
**Independent per section.** Each call is fired separately and renders on its own callback.
Android shows a **ProgressDialog** ("Loading…Please wait") per blocking call (the common
pattern across fragments). 🟡 confirm whether the dashboard uses a per-section ProgressBar or
the modal ProgressDialog — but the model is: section appears when its call returns; failures
leave that section empty/with a message, **without blocking the others**.

## 4. Loading states (Flutter gap)
- **Android:** ProgressDialog/section spinner while a call is in flight.
- **Flutter today:** cards render from the controller; tabs show empty/error directly; the
  page leaves a **large blank area** below the content (screenshot). **Gap:** add per-section
  loading indicators + fill/again-on-refresh; avoid the tall blank region (size the body /
  show a placeholder).

## 5. Empty states (per tab)
| Tab | Empty / no-data | Null / error | Offline |
|-----|-----------------|--------------|---------|
| Complaints | "No complaints" (✅ Flutter shows this) | message | — |
| Unpaid | "No unpaid customers" (✅) | message | — |
| Nearest | list empty → "none in range" | **Flutter shows "Could not load nearest customers"** (current bug, see §8) | needs GPS |
| PayLater | no-records | "Fail!" message | — |
🟡 Android's exact empty copy per tab to confirm; Flutter already has empty/error placeholders
(good) — the issue is Nearest erroring + the overall blank space.

## 6. Error-handling matrix (Android)
| Condition | Android behaviour |
|-----------|-------------------|
| No internet | "Please turn on Wifi or Data Network" dialog (make-payment pattern) |
| Timeout / 5xx / Volley error | per-call `onErrorResponse` → Toast "Failed." ; section left empty |
| SOAP null response | "Server is busy or Un-reachable!" dialog |
| Empty/malformed JSON | try/catch per field; section hidden/empty (no crash) |
| `status_code`/`statusCode` ≠ 0 | show `statusMessage` |
🟡 exact HTTP-code branches (401/403/404) not individually handled — Volley funnels to a
generic error toast. Flutter should mirror: **per-section** error + retry, never crash the page.

## 7. Dashboard refresh triggers (Android)
Re-created/re-fetched on: **login**, fragment **re-entry** (drawer return / back to dashboard),
after **payment success** (returns to dashboard which re-queries), after **complaint update**
(list re-opened). 🟡 no explicit pull-to-refresh seen; no auto network-reconnect refresh.
Flutter: refresh on login + on return to dashboard; (optional) add pull-to-refresh.

## 8. Nearest Customer — flows
**A. Dashboard Nearest tab (`nnc`):**
```
GPSTracker.getLatitude()/getLongitude()  (LocationManager, last-known)
  → POST /packagelist/NearestNextCustomer {auth, lat, lng}
  → list rendered in the Nearest tab
```
**B. Drawer "Nearest Customer" (`NearestCustomersMapsFrag`):** a MAP that receives a
**precomputed** `nextcustomers` list via intent (from the employee-collection flow) — NOT a
fresh `nnc` call. (Different from the dashboard tab.)
**C. Flutter today:** the **drawer** Nearest screen (`nearest_customers_screen.dart`) uses
**device GPS (Geolocator) + the local customer cache** + on-device distance/sort + list/map
— self-contained, *different approach* from Android. The **dashboard** Nearest tab shows
"Could not load nearest customers" → likely it isn't wired to `nnc` (or GPS/local-data path
fails). 🟡 confirm what the Flutter dashboard Nearest tab calls.

## 9. Location APIs
| Purpose | Key | Endpoint |
|---------|-----|----------|
| Nearest customers (dashboard) | `nnc` | `/packagelist/NearestNextCustomer` |
| Update customer/agent location | `ucl` | `updateCustomerlocation` (SOAP) |
🟡 attendance/live-track/background-sync location endpoints: none found beyond `ucl` +
the employee-collection (`empCollection`) report. Location *sending* in Flutter already exists
(`LocationSyncService`).

## 10. Android GPS architecture
- **`GPSTracker`** (`Utils/GPSTracker.java`) extends `Service implements LocationListener`.
- Uses **`LocationManager`** (NOT FusedLocationProvider): tries **NETWORK_PROVIDER** then
  **GPS_PROVIDER**; `getLastKnownLocation` + `requestLocationUpdates`; `canGetLocation` flag
  (`:40-91,123,148`). No WorkManager/AlarmManager/foreground-service for nearest.
- **Flutter equivalent:** `geolocator` (FusedLocation) — functionally newer; acceptable, but
  behaviour differs (FusedLocation vs last-known LocationManager).

## 11. Location permission flow (Android)
`GPSTracker.canGetLocation` gates use; if no provider enabled → `showSettingsAlert` (prompt to
enable GPS). Denied/GPS-off → can't get location → nearest not loaded (graceful). 🟡 exact
dialogs. Flutter (`geolocator`) must mirror: permission denied / GPS off → friendly message +
fall back (don't crash); the nearest screen already shows "enable GPS" on failure.

## 12–15. (Dashboard nearest sequence / drawer / customer-details / offline)
- **Dashboard nearest sequence:** §8.A.
- **Drawer:** §8.B (map of a passed list; different from dashboard).
- **Customer Details location:** `customer_map_screen.dart` + Geolocator already exist in
  Flutter (navigate/map). 🟡 confirm Android's customer-details "navigate" = Google Maps intent.
- **Offline:** nearest/dashboard are **online** in Android (live calls); offline mode is the
  separate downloaded-cache subsystem (see OFFLINE_MODE_COMPLETE.md). Flutter's drawer-nearest
  reads the local cache (which is currently dummy-seeded — see RELEASE_GAP_REPORT.md).

## 16. Production UI comparison (Android vs Flutter)
| Aspect | Android | Flutter today |
|--------|---------|---------------|
| Section loading | ProgressDialog/spinner per call | none (blank, then content) |
| Empty state | per-tab message | ✅ has messages (Complaints/Unpaid) |
| Nearest | `nnc` list (or map of passed list) | dashboard tab **errors**; drawer uses GPS+local |
| Blank space | content fills / scrolls | **large blank blue/white area** below cards |
| Retry | re-enter/re-call | none on the dashboard tabs |
| Tablet layout | RelativeLayouts | needs review (screenshot is a tablet) |

## 17. Performance
Android fires each dashboard call **independently** (Volley enqueue / per-call AsyncTask) →
effectively concurrent; sections paint as they arrive. Flutter should fetch sections
concurrently (Future.wait or independent futures) and render each as it resolves — **not** one
blocking sequence.

## 18. Error recovery (partial failure)
Android: a failed section (e.g., Nearest) only affects **that** section — the others still
render. **Flutter must do the same** (per-section try/catch + state), never fail the whole
dashboard because one call failed.

## 19. Flutter implementation plan (architecture only — no code yet)
- **Reuse:** `dashboard_controller` + `dashboard_repository`, `connectivity_plus`,
  `geolocator`, `RestClient` (+ new `postEncrypted` for paylater), `SoapClient`,
  `DatabaseHelper`, the existing empty/error widgets, `NearestCustomersScreen`/`CustomerMapScreen`.
- **Per-section state:** each card/tab gets `loading | data | empty | error` (the controller
  exposes independent states); render a spinner while loading, message on empty, message+Retry
  on error.
- **Concurrent load:** fire summary/wallet/complaints/unpaid/nearest/paylater independently;
  update each on resolve.
- **Nearest (dashboard):** wire to `nnc` (`/packagelist/NearestNextCustomer`) with
  Geolocator lat/lng; handle GPS-off/denied gracefully (message, no crash). Decide: dashboard
  Nearest = live `nnc` (Android) vs the local-GPS approach used by the drawer screen.
- **Layout:** remove the tall blank region (size the scroll body / placeholder); ensure
  tablet layout looks right.
- **Refresh:** on login + return-to-dashboard; optional pull-to-refresh.
- **Location:** keep `geolocator`; permission/GPS-off → friendly fallback (match §11).

## 20. Financial safety
No changes to payment/collection/receipt/transaction/sync/offline-payment/customer-write
paths. Dashboard + location/nearest read paths only.

## Risk assessment
| Item | Risk | Note |
|------|------|------|
| PayLater dashboard tab (encrypted) | 🟡 | now uses `postEncrypted` (just wired) — verify live |
| Nearest dashboard wiring to `nnc` | 🟠 | new live call; GPS dependency; verify lat/lng + response |
| Per-section loading/empty/error refactor | 🟡 | UI-only; reuse existing widgets |
| Layout/blank-space fix | 🟢 | cosmetic |
| Location provider diff (Geolocator vs LocationManager) | 🟡 | behaviourally close; verify on device |
| 🔵 No payment-path changes | ✅ | enforced |

## 🟡 To line-verify before implementing
`dbd`/`glda`/`nnc` exact request+response fields; the dashboard loading widget (ProgressDialog
vs section spinner); what the Flutter dashboard Nearest tab currently calls; Android
customer-details navigate (Maps intent); exact per-tab empty copy.
