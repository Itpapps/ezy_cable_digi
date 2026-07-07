# Session Management — Android vs Flutter (Investigation Only)

> Source of truth: Android `D:\Git-Repos\magikdigi`. No code changed.
> Tags: ✅ Verified · 🟡 Not Yet Verified.

---

## Headline finding (important)
✅ **Android has NO session-expiry mechanism.** There is **no central interceptor, no token-expiry detection, no "session expired" dialog, and no forced logout/re-login** anywhere in the Android source.
- `DetectSession.java` is **not** a session interceptor — despite the name it only holds **print/share/selection listener callbacks** (verified: full class read; only `PrintInvoiceClickListener`/`ShareInvoiceClickListener`/`SelectedOrNot`).
- The **only** logout is the **manual** drawer button (`MainActivity` / `DashboardHomeFragment`: *"Are you sure you want to logout?"* → `LoginActivity` with `FLAG_ACTIVITY_CLEAR_TASK`).
- Grep for `session expired`, `invalid token`, `re-login`, `forceLogout`, `sessionExpired` across the whole Android module → **no matches** (only the manual logout strings).

➡️ **Therefore the premise "Android shows a session-expired popup while Flutter shows No Data" is not accurate.** Android does **not** show a session-expired popup. On a failed/empty/expired response, **Android shows per-screen dialogs/toasts** keyed on `statusCode`, and **Flutter shows per-section empty/error states** — these are architecturally the **same model**.

---

## 1. Session Lifecycle
| Stage | Android | Flutter | Status |
|---|---|---|---|
| Login | BMS auth → validateLogin; static fields + SharedPreferences | validateLogin → SessionService (in-memory) + secure-storage token | ✅ Match (Flutter persists token securely) |
| API usage | `authToken`/`imei` on every call | same | ✅ Match |
| Background → Foreground | no session re-check | no session re-check | ✅ Match |
| Timeout | **none** (no client expiry) | **none** | ✅ Match |
| Logout | manual button → LoginActivity (CLEAR_TASK) | `AuthService.logout()` → `SessionService.clear()` + delete secure token/remember | 🟡 Flutter clears more |
| Re-login | from LoginActivity | from LoginScreen | ✅ Match |

---

## 2. Session Expiry
- ✅ **Android: not detected.** No API response is interpreted as "session expired." Each screen's `AsyncTask.onPostExecute` interprets `statusCode`:
  - `0` → success
  - `1` → per-screen dialog ("No Records Found!", "Failed", "No Details Found", etc.)
  - `2`/`3` (or null response) → per-screen error dialog/toast ("Server is busy or Un reachable!", "Please contact support", "Failed.")
- ✅ **Flutter: not detected either.** Each repository returns `statusCode` (0 ok · 1 no-records → empty · ≥2/3 → error) and the screen renders **loading / empty / error** independently (dashboard now also has **Retry** buttons + skeletons).
- 🟡 Whether the **server** ever returns a distinct "expired token" code/message is **Not Yet Verified** (no live evidence; no client code keys off one).

| Aspect | Android | Flutter |
|---|---|---|
| Timeout detection | none | none |
| Which API returns expiry | none specific | none specific |
| Response code / message | generic statusCode 1/2/3 | generic statusCode 1/3 |
| Popup / dialog | per-screen error dialog | per-section inline error/empty (+Retry) |
| Forced logout | none | none |
| Session/DB/back-stack clear on expiry | none | none |

---

## 3. Dashboard Behaviour (the observed issue)
- ✅ **Verified via live `[DASHDIAG]` logs**: each dashboard section loads **independently** and one failing does **not** blank the others — Nearest `count=29`, Complaints `count=85`, PayLater `count=0` (all `status=0`).
- ✅ **Root cause of the "No Data" you saw** = a section's API returned **empty** (e.g., PayLater `count=0`) or errored — **not** a session expiry and **not** cross-widget contamination.
- ✅ Android's dashboard (`DashboardHomeFragment`) behaves the same: independent `AsyncTask`s per section (`DashboardDetails`, `getopencomplaintslist`, `getunpaiddata`, `nnc`, `gethitapipaylaterlist`); a failure shows that section's own empty/error, no global logout.
- 🔵 Not a bug — Flutter and Android match. (The PayLater `count=0` was separately addressed by matching the dashboard request params to Android.)

---

## 4. Global Error Handling
- ✅ **Android: no common handler.** Each `AsyncTask.onPostExecute` does its own `statusCode` checks + its own `AlertDialog`/`Toast`. There is **no base activity / interceptor / network layer** that centrally detects invalid token / unauthorized dealer / maintenance / forced logout.
- ✅ **Flutter**: `ErrorHandlerService` records uncaught/handled errors (non-fatal, for logging) but does **not** intercept or force logout; each repo's `try/catch` returns a safe result. No central session interception (parity with Android).

| Detect | Android | Flutter |
|---|---|---|
| invalid token | not detected (generic error) | not detected (generic error) |
| session expired | not detected | not detected |
| unauthorized dealer | server message in per-screen dialog | server message in per-section error |
| invalid employee | same | same |
| maintenance | same | same |
| forced logout | none | none |

---

## 5. Flutter module audit
| Module | Detects expiry? | On failure |
|---|---|---|
| `RestClient` / `SoapClient` | no | throws `RestException`/`SoapException` (caught by repos) |
| `AuthService` | no | returns `LoginResult(false, message)` |
| `SessionService` | no | in-memory holder; `clear()` only |
| Dashboard (KPI/Complaints/Nearest/PayLater) | no | per-section error/empty + Retry |
| Unpaid (`CustomerListProvider`) | no | `statusCode 3` → error state |
| Payments | no | surfaces server `statusMessage`; never fabricates receipt |
| Reports / Pay Later / Package Ops / Complaints / Expenses / OTC | no | per-screen empty/error |
| Offline | no | local SQLite; no network session |

- ✅ No module force-logs-out. ✅ No module crashes (defensive try/catch). 🟡 "Silent" cases = a genuine empty list rendered as an empty state (matches Android's "No Records").

---

## 6. Session Matrix (Android vs Flutter on failure/expiry)
| Module | Android on failure | Flutter on failure | Match? |
|---|---|---|---|
| Dashboard | per-section empty / "Server busy" dialog | per-section empty/error + Retry | ✅ (Flutter adds Retry) |
| Payments | error dialog (server message) | error snackbar (server message) | ✅ |
| Search | "No records" dialog | empty/error | ✅ |
| Complaints | empty / error dialog | empty/error + Retry | ✅ |
| Package Operations | error dialog | error result + message | ✅ |
| Reports (Mini Day) | "No Details Found" dialog | empty / message | ✅ |
| Expenses | error dialog | error snackbar | ✅ |
| Pay Later | error dialog | empty/error | ✅ |
| Nearest | empty | empty / error + Retry | ✅ |
| Employee Collection | empty/error | empty/error | ✅ |
| Settings | n/a (local) | n/a (local) | ✅ |
| Offline | local only | local only | ✅ |

➡️ **No module relies on session-expiry handling in Android, so none is "missing" in Flutter.** The only stylistic difference: Android uses **modal dialogs**, Flutter uses **inline empty/error states** (now with Retry).

---

## 7. Error Dialog Catalogue (Android, per-screen — verified samples)
| Screen | Title | Trigger |
|---|---|---|
| Payment History | "Failed!" / "Server is busy or Un reachable!" | statusCode 1 / null |
| Invoice History | "No Records Found!" / "Server connectivity error!" | statusCode 1 / null |
| Mini Day Report | "No Details Found!" | statusCode 1 |
| Generic AsyncTasks | "Server is busy or Un reachable!" + OK | null/error |
- ✅ These are **per-screen `AlertDialog.Builder`** instances — **not** a common dialog/helper/interceptor/base-activity. (No shared session dialog exists.)

---

## 8. Gap Report
| Item | Android | Flutter | Status | Risk | Parity recommendation (no new rules) |
|---|---|---|---|---|---|
| Session-expiry detection | none | none | ✅ Match | — | none needed |
| Central interceptor | none | none | ✅ Match | — | none needed |
| Forced logout on expiry | none | none | ✅ Match | — | none needed |
| Token refresh | none | none | ✅ Match | — | none needed |
| Per-screen failure UX | modal dialog | inline empty/error (+Retry) | 🟡 Partial (style) | Low | optional: match dialog style if desired |
| Dashboard isolation | independent AsyncTasks | independent controllers | ✅ Match | — | none needed |
| Logout clearing | navigate (statics persist) | clears session + secure token | 🟡 Flutter clears more | Low | keep |
| Token at rest | plaintext prefs | secure storage | 🟡 Flutter exceeds | Low | keep (do not downgrade) |

**Conclusion:** Session handling is **already at parity** with Android — neither app has session-expiry/forced-logout; both surface failures per-screen. The only optional parity tweak is **cosmetic** (dialog vs inline). No authentication redesign, no new security, no new business rules required.
