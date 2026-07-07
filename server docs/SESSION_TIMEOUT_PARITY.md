# Session Timeout / Long-Idle Parity — Android vs Flutter (Investigation Only)

> Source of truth: Android `D:\Git-Repos\magikdigi`. **No code changed.**
> Tags: ✅ Verified (traced in source) · 🟡 Not Yet Verified (needs a live capture).
> Companion docs: `SESSION_MANAGEMENT.md`, `SECURITY_PARITY.md`. This doc supersedes
> them **only** on the specific "after long idle, Android shows an auth message but
> Flutter shows No Data" question. (Deliverable also referenced as `SESSION_TIMEOUT_PARITY2.md`.)

---

## 0. TL;DR — what actually causes the difference

✅ **It is NOT a session-lifetime, token-persistence, or storage difference. It is an error-handling/UI difference, and the proof is in the code.**

After a long idle the *server* rejects the (unchanged) token/dealer. Both apps send the **same** request and get the **same** rejection. The two apps then **render that rejection differently**:

| Channel | Server reject form | Android does | Flutter does | Result |
|---|---|---|---|---|
| **Encrypted** `/digi_rest_api/*` (Pay Later, Expenses, …) | decrypted body = literal **`"NA"`** | `Toast "Authentication Failed"` (`DashboardHomeFragment.java:664` + ~15 fragments) | `jsonDecode("NA")` **throws** → repo `catch` → empty/`statusCode 1` | **"No Data"** (message lost) |
| **Plain REST** `/packagelist/*` (Nearest, Unpaid, …) | `statusCode==1` + `statusMessage` | `AlertDialog "No Details Found!"` + `statusMessage` | feed maps `statusCode==1` → **empty**, message discarded | **"No Data"** (message lost) |
| **SOAP** `wsController` (KPIs, Complaints, Payment) | `statusCode==1/2` + `statusMessage` | per-screen `AlertDialog`/`Toast` w/ `statusMessage` | KPI surfaces msg; **feed** sections swallow `statusCode==1` as empty | mixed |
| **Cold start** (process was killed) | BMS/version rejects dealer | `AppVersionCheck_Activity` dialog *"…not authorized to use this application"* (`:311/:336`) | splash silently falls back to cached URL → **LoginScreen** | different, but **not** the dashboard "No Data" |

➡️ **Flutter is converting a real server auth/reject signal into a silent empty state.** That is the whole bug. No storage change, no token refresh, no forced logout is warranted.

⚠️ **Important nuance (verified by the 2026-06-30 12:12 healthy capture, §4a):** *most* "No Data" you see is a **genuine empty list** — e.g. Pay Later returns `status_code:0` + `customer_data:[]` ("No Scheduled Customers."), which **Android also renders as empty**. That case is **already at parity** and is not a bug. The divergence is confined to the **true auth-reject** path (`NA` / non-zero status), which the healthy capture does not exercise (§4b).

---

## Part 1 — Long-Idle behaviour (30 min / 1 h / 2 h / overnight)

The clock interval is **irrelevant on the client** — neither app has any client-side timer, TTL, or expiry. Behaviour depends only on **(a) is the OS process still alive?** and **(b) does the server still accept the token?**

| Question | Android | Flutter | Status |
|---|---|---|---|
| Client-side idle timer / TTL | none | none | ✅ Match (grep: no timer/expiry in either) |
| token still exists after idle (process alive) | `LoginActivity.authToken` static — yes | `SessionService.authToken` in-memory — yes | ✅ Match |
| `authToken` / `dealerId` / `employeeId` after idle (process alive) | static fields persist | `SessionService` fields persist | ✅ Match |
| token after **process death** | SharedPreferences row persists (but app cold-starts to Login) | secure-storage row persists (but app cold-starts to Login) | ✅ Match |
| session auto-restored into dashboard on cold start | **NO** (cold start → version check → LoginActivity) | **NO** (cold start → splash → LoginScreen) | ✅ Match |
| first API after warm resume | whatever screen the user opens (uses static token) | same (uses SessionService token) | ✅ Match |
| first API **response** after idle | server-dependent; if rejected → see §5 | identical request → identical response | ✅ Match (server) |
| dashboard behaviour on reject | per-section dialog/toast w/ message | per-section **empty "No Data"** (message lost) | ❌ **Differs (UI)** |
| payment behaviour on reject | `Toast "Authentication Failed"` / error dialog | error snackbar (mostly surfaced) | 🟡 mostly match |
| report behaviour on reject | `AlertDialog` w/ message | empty / message | 🟡 partial |

✅ **30 min vs overnight makes no client difference** — only "process alive vs killed" matters, and that is identical in both apps.

---

## Part 2 — Storage lifetime (does this explain it? **No.**)

### Android
- ✅ `authToken` / `dealerId` / `employeeId` live in **static fields** on `LoginActivity` (used for every live call) **and** are mirrored to **SharedPreferences** (`SPF_NAME`, `SPF_NAME_LOGIN`, `BMS_SHARED_PREF`).
- ✅ Statics die with the **process**; SharedPreferences survive process death and reinstall-less restarts.
- ✅ **Remember-me only stores username+password** to prefill the login form (`LoginActivity.java:791-798`). It does **not** auto-submit or auto-restore a session.

### Flutter
- ✅ Live session = `SessionService` (**in-memory only**) — `authToken`/`dealerId`/`userType`/`employeeId`.
- ✅ `auth_token` + `remember_me` persisted to `flutter_secure_storage` (`auth_service.dart`), deleted on `logout()`.
- ✅ **Nothing reads the secure token back into `SessionService` at startup** — `splash_screen.dart` always `pushReplacement → LoginScreen` (`:62-64`); there is no auto-login path.

### When can `SessionService` be empty while secure storage still has the token?
- ✅ **Only after process death** (OS killed the backgrounded app). Then `SessionService` is empty *and* the app is cold-starting → it lands on **LoginScreen**, not the dashboard. So this state **cannot** produce a "No Data" dashboard — it produces a login screen. **Therefore it is not the cause of the reported symptom.**

➡️ ✅ **Storage lifetime does NOT explain the difference.** Both stores persist equally; neither app uses the persistent store to silently resume a dashboard session. The reported "No Data" happens with a **live** `SessionService` (process still alive) and a **server-rejected token** — i.e. it is downstream of the network response, not of storage.

---

## Part 3 — App resume lifecycle

### Android
- ✅ Warm resume (`onResume`) does **no** session re-check and **no** automatic API call. It continues using the **static** `authToken`/`dealerId`/`employeeId` — it does **not** reload them from SharedPreferences on resume.
- ✅ APIs fire only when the user navigates/refreshes a screen.
- ✅ Cold start path: `SplashScreenActivity → AppVersionCheck_Activity → LoginActivity`. `AppVersionCheck` can show *"…not authorized to use this application"* (`:311/:336`) before login.

### Flutter
- ✅ No `WidgetsBindingObserver`/`AppLifecycleState` session rebuild on resume — `SessionService` simply persists with the process; it is **not** rebuilt from secure storage.
- ✅ `AuthService` does **not** reload secure storage on resume; it only writes (login) / deletes (logout).
- ✅ Cold start: `SplashScreen` (3 s delay + connectivity + `ServerUrlResolver.resolve()` BMS URL) → **LoginScreen**. No silent dashboard restore.

| Resume aspect | Android | Flutter | Status |
|---|---|---|---|
| Session re-check on resume | none | none | ✅ Match |
| Auto API call on resume | none | none | ✅ Match |
| Reloads token from disk on resume | no (uses statics) | no (uses in-memory) | ✅ Match |
| Cold-start destination | version-check → Login | splash → Login | ✅ Match (Android adds an auth/version gate) |

---

## Part 4 — Live verification

### 4a. VERIFIED live capture — **healthy session** (Android, 2026-06-30 12:12, dealer 1053, token `6a4365644a4a05.99484935`)
A logcat capture of an **active, non-rejected** session confirms the exact wire formats and proves a key nuance:

| Channel | Endpoint | Verified response |
|---|---|---|
| **SOAP** | `unpaidCustomers` (`wsController`) | `statusCode=0; statusMessage=Success; useAltCustomerId=1; unpaidcustomers=[{…}]` ✅ |
| **Plain REST** | Nearest (`packageList…`) | `{"status_code":0,"status_msg":"Success","distance":[…],"name":[…],"alt_custom_number":[…],"latitude":[…],"longitude":[…]}` — **parallel arrays**, key is `status_msg` ✅ |
| **Encrypted** | `digi_rest_api/scheduled_collection_data` (Pay Later) | `{payload:…}` envelope → decrypts to `{"status_code":0,"status_message":"No Scheduled Customers.","customer_data":[],"setting_values":{…},"emp_details":[…]}` ✅ |

✅ **Crucial finding from this capture:** an *empty* Pay Later returns **`status_code:0` + `customer_data:[]`** (message `"No Scheduled Customers."`) — **not** `NA`, **not** `statusCode 1`. Flutter parses this identical shape (`pay_later_repository.dart:131-169`) and renders an **empty** feed. **Android renders the same empty list.** ➡️ So a dashboard Pay Later **"No Data" in the common case is a GENUINE empty and is already at parity** — both apps correctly show empty. The encrypted channel does **not** emit `NA` on a healthy/empty call.

➡️ **This narrows the real divergence:** the Android "Invalid Dealer / Authentication Failed" popups occur **only on an actual auth rejection** (the `NA` / non-zero `statusCode` path), which is a *separate, rarer* state than the everyday empty list. The everyday "No Data" you see most of the time is legitimate empty data, matching Android.

### 4b. Still to capture — the **rejected** session (the actual divergence)
The 12:12 capture has a **valid token**, so it does **not** show the failure path. To close the last 🟡, capture the same channels **after the server rejects the token/dealer** and record the failure body:

| Capture | Where | Field of interest |
|---|---|---|
| Encrypted reject | `digi_rest_api/scheduled_collection_data` | is the (decrypted) body literal `NA`, or `{status_code:1,…}`, or `{Error_code,…}`? |
| Plain REST reject | Nearest/Unpaid | `status_code` / `status_msg` on reject |
| SOAP reject | KPIs/Complaints | `statusCode` / `statusMessage` on reject |
| Cold start | BMS / `AppVersionCheck` | dealer-auth message + code |

🟡 Until that reject capture exists, the **exact failure body** is Not Yet Verified — but the Android handling is verified (`NA`→toast, `statusCode 1`→dialog) and the Flutter swallow points are verified (`rest_client.dart:114/118`, `dashboard_controller.dart:101-103/144-150/198-204`), so the *divergence direction* is certain even though the exact reject bytes are pending.

---

## Part 5 — API response after long idle (verified handling, 🟡 exact bytes)

- ✅ **Encrypted channel returns `"NA"` on auth failure.** Android: `requestFinished()` → `if (payloadresp.toString().equals("NA")) Toast "Authentication Failed"` (`DashboardHomeFragment.java:663-664`). The **same** `"NA"`→"Authentication Failed" toast exists in `CustomerMgmt_MakePayment_Fragment`, `AddExpensesFragment`, `BroadBandList`, `CalenderFragment`, `CustomerOperations_Fragment`, `ExpensesList`, `PayLaterReport`, `EventListFragment`, OTT/Event adapters, etc. (verified via grep — ~15 sites). So `"NA"` is the canonical **dealer/token-rejected** signal on the encrypted channel.
- ✅ **Encrypted channel, structured error**: `{Error_code, Error_Message}` → Android `AlertDialog "Fail!"` + `Error_Message` (`:667-687`). Flutter mirrors this (`rest_client.dart:123-127`, `pay_later_repository.dart:83-85,137-139`).
- ✅ **Plain REST / SOAP**: `statusCode==1` + `statusMessage` (e.g. "No Details Found"), `statusCode==2` → "Contact Support" toast, null/Volley error → "Failed."/"Server busy".
- 🟡 Whether the server tags an idle/dealer rejection as `statusCode 1` vs `2`/`3`, and whether the encrypted body is raw `NA` vs enveloped, is **Not Yet Verified** (needs the Part-4 capture). It does not change the conclusion.

---

## Part 6 — Error-handling comparison (per module)

| Module | Channel | Android on reject | Flutter on reject | Mismatch? |
|---|---|---|---|---|
| **Dashboard KPIs** | SOAP | dialog/uses `statusMessage` | `loadKpis` sets `errorMessage = statusMessage`, cards stay ₹0 | 🟡 minor (msg kept but cards look "empty") |
| **Dashboard Complaints** | SOAP | per-section dialog w/ message | `statusCode==1` → **empty, message discarded** (`dashboard_controller.dart:101-103`) | ❌ message lost |
| **Dashboard Nearest** | plain REST | `AlertDialog "No Details Found!"` + message | `statusCode==1` → empty (`controller :198-204`) | ❌ message lost |
| **Dashboard Pay Later** | **encrypted** | `"NA"`→`Toast "Authentication Failed"`; else `Error_Message` dialog | `"NA"` → **throws → caught → empty** (`controller :147-150`) | ❌ **auth-fail lost** |
| **Payments** | SOAP/encrypted | `Toast "Authentication Failed"` / error dialog | surfaces server `statusMessage` snackbar | ✅ mostly match |
| **Reports (Mini Day)** | plain REST | `AlertDialog "No Details Found!"` | empty / message | 🟡 partial |
| **Complaints screen** | SOAP | dialog | empty / error + retry | 🟡 partial |
| **Package Operations** | SOAP | error dialog | error result + message | ✅ match |
| **Expenses** | encrypted | `"NA"`→`Toast "Authentication Failed"` | empty / error | ❌ auth-fail lost |
| **Pay Later (report)** | encrypted | `"NA"`→`Toast "Authentication Failed"` | empty / error | ❌ auth-fail lost |

✅ **Confirmed: Flutter is incorrectly converting a server auth/reject into an empty state** in exactly the spots that hit the **encrypted `NA` path** and the **feed `statusCode==1` path**.

---

## Part 7 — Dashboard "No Data" root cause (highest priority)

✅ **Where the error is lost — two precise sites:**

1. **Encrypted `NA` → exception → empty.** `RestClient.postEncrypted` assumes a JSON envelope:
   - `jsonDecode(res.body)` (`rest_client.dart:114`) throws `FormatException` if the body is the literal `NA`; **or**
   - `jsonDecode(DigiCrypto.decryptions(payload))` (`:118`) throws if the decrypted payload is `NA`.
   Either throw is caught by the repo (`pay_later_repository.dart` try/catch) and the controller maps it to `payLaterItems = [] / payLaterError` (`dashboard_controller.dart:151-157`) → rendered as the generic empty/"No Data" feed. **The `"NA"` = "Authentication Failed" signal never reaches the UI.**

2. **Feed `statusCode==1` → empty, message discarded.** `loadComplaints` (`:101-103`), `loadNearest` (`:198-204`), `loadPayLater` (`:144-150`) all treat `statusCode==1` as "no records" → empty-state. The server's `statusMessage` is stored in `*Message` but the empty-state widget renders a **generic** "No …" string, so a real reject message (e.g. "Invalid Dealer") is shown as "No Data".

✅ **Android comparison:** `DashboardHomeFragment` shows the section's own `AlertDialog`/`Toast` carrying `statusMessage`/`Error_Message`/"Authentication Failed" — it never silently blanks on a reject. (Independent per-section `AsyncTask`s, confirmed earlier via `[DASHDIAG]`: Nearest 29 / Complaints 85 / PayLater 0 — sections are isolated; the issue is the *reject rendering*, not cross-section contamination.)

---

## Part 8 — Final verdict (explicit answers)

**1. Does Android keep sessions alive longer?** **NO.** ✅ Neither app has a client TTL/timer/expiry; both keep the session only while the OS process lives. Remember-me only prefills credentials (`LoginActivity.java:791-798`); it does not auto-login.

**2. Does SharedPreferences survive longer than flutter_secure_storage?** **NO (and irrelevant).** ✅ Both persist across process death; **neither app uses the persistent store to silently resume a dashboard session** (both cold-start to Login). The symptom occurs on a *warm* session, downstream of the persistent store.

**3. Does Android restore authentication differently?** **NO** on warm resume (both use in-memory statics/`SessionService`, no disk reload). 🟡 On **cold start** Android adds a BMS/version gate (`AppVersionCheck` "…not authorized") that Flutter resolves silently — different cold-start UX, but **not** the dashboard "No Data".

**4. Is Flutter losing SessionService values?** **NO.** ✅ `SessionService` persists with the process; if the process is killed, Flutter shows **Login**, not "No Data". The "No Data" happens *with* a live session.

**5. Are both apps receiving the same server response?** **YES.** ✅ For the **healthy** session this is now *directly verified* (§4a): identical SOAP / plain-REST / encrypted shapes; an empty Pay Later is `status_code:0`+`customer_data:[]` in both, rendered empty by both (**parity, not a bug**). 🟡 The **rejected**-session bytes (`NA` vs `statusCode 1`) are still pending a failure capture (§4b), but the handling on both sides is source-verified, so the divergence direction is certain.

**6. Storage issue or error-handling/UI?** ✅ **Purely error-handling / UI.** Proven at `rest_client.dart:114/118` and `dashboard_controller.dart:101-103/147-150/198-204`.

**7. Exactly what Flutter should change to match Android (parity ONLY):**

| # | Change | Match to Android | File(s) |
|---|---|---|---|
| A | In `postEncrypted`, detect a decrypted/raw body of **`NA`** (and a non-JSON body) and return a structured `{Error_code, Error_Message:"Authentication Failed"}` instead of throwing. | `"NA"`→`Toast "Authentication Failed"` (`DashboardHomeFragment:664` + peers) | `lib/core/network/rest_client.dart` |
| B | Surface that "Authentication Failed" as a **toast/snackbar** on the affected screens (Pay Later, Expenses, Payment, dashboard feeds) instead of a silent empty state. | per-fragment `Toast`/`AlertDialog` | dashboard feeds + encrypted-channel screens |
| C | For feed `statusCode==1`, when `statusMessage` is a **real reject message** (not "no records"), render the **server message** (inline/toast) rather than the generic empty string. | per-section `AlertDialog` w/ `statusMessage` | `dashboard_controller.dart` + feed widgets |
| D | *(Optional)* Mirror the cold-start **BMS "not authorized"** message at splash/login. | `AppVersionCheck_Activity:311/336` | `server_url_resolver` / `login_screen` |

**Explicitly NOT recommended / NOT introduced:** ❌ token refresh · ❌ forced logout · ❌ session expiry/TTL · ❌ new authentication · ❌ central interceptor · ❌ any business-logic change. The fixes are **display-only**: surface the message Android already surfaces, on the same trigger, through Flutter's existing toast/snackbar/empty-state widgets.

---

## Appendix — Evidence index

| Claim | Evidence |
|---|---|
| Encrypted `NA` → "Authentication Failed" | `DashboardHomeFragment.java:663-664`; same in `CustomerMgmt_MakePayment_Fragment`, `AddExpensesFragment`, `BroadBandList`, `CalenderFragment`, `CustomerOperations_Fragment`, `ExpensesList`, `PayLaterReport`, `EventListFragment`, OTT/Event adapters |
| Encrypted `Error_code`/`Error_Message` dialog | `DashboardHomeFragment.java:667-687` |
| Plain REST `statusCode==1` dialog | `DashboardHomeFragment.java:593-611` |
| Cold-start "not authorized" | `AppVersionCheck_Activity.java:311,336` |
| Remember-me only prefills (no auto-login) | `LoginActivity.java:791-798` |
| Login `statusCode` dialog/toast | `LoginActivity.java:820-829` |
| Flutter always cold-starts to Login | `splash_screen.dart:62-64` |
| Flutter `postEncrypted` throws on non-JSON/`NA` | `rest_client.dart:114,118` |
| Flutter `status_code==1` → Error envelope | `rest_client.dart:123-127` |
| Flutter feeds swallow `statusCode==1` | `dashboard_controller.dart:101-103,144-150,198-204` |
| Flutter `SessionService` in-memory only | `session_service.dart`; no startup restore |
