# Offline Login + Remember-Me — Parity Investigation (NO CODE)

> Source of truth: Android `D:\Git-Repos\magikdigi` (READ-ONLY). Every claim cites file:line.
> Tags: ✅ Verified in source · 🟡 Not Yet Verified. Scope: login credential persistence,
> Remember-Me, disabled fields, offline-entry conditions, routing, logout, splash, fresh-install.
> Companion: `OFFLINE_ANDROID_INVESTIGATION.md` (broader offline). This doc drills into login/Remember-Me.

---

# PHASE 1 — Android (verified)

## 1. Where username/password are saved
✅ **SharedPreferences file `"vidslogin"`** (`LoginActivity.java:121` `SPF_NAME = "vidslogin"`), keys **`username`** / **`password`** (`:122-123`). **Plaintext** (`MODE_PRIVATE`).
- **Written:** only on a **successful online login**, and only inside `if (chkRememberMe.isChecked())` → `putString(USERNAME, …)` + `putString(PASSWORD, …)` (`:791-794`).
- **Read (restored into the fields):** **unconditionally** on every `LoginActivity.onCreate` — `userName.setText(getString(USERNAME,""))` + `userPassword.setText(getString(PASSWORD,""))` (`:226-227`), and again in the permission/network paths (`:469-473`). The restore is **not** gated by Remember-Me; it just shows whatever was last saved (empty string if never saved / last login cleared it).

## 2. How Remember-Me works
✅ Checkbox `cb_rememberMe` (`:224`). On successful online login (`:791-798`):
- **Checked** → save `username` + `password` to `vidslogin`.
- **Unchecked** → `loginPreferences.edit().clear().commit()` → **wipes** saved credentials (`:796-797`).
✅ **The checkbox is NOT pre-restored** — there is no `chkRememberMe.setChecked(...)` from prefs anywhere; it **defaults unchecked** on every launch (grep confirmed). So the box appears unchecked even when credentials are pre-filled.
✅ **Passwords are stored plaintext.** No hashing/encryption.

## 3. How fields are disabled offline
✅ In `onCreate`, when offline:
```
248  if (!EzyCableDigiConstants.isNetworkAvailable(LoginActivity.this)) {
249      userName.setEnabled(false);
250      userPassword.setEnabled(false);
251  }
```
✅ **Only `setEnabled(false)`** — *not* `focusable`, `clickable`, or `inputType` changes. The fields still show the restored text (from §1) but cannot be edited/focused. (`isNetworkAvailable` = `getActiveNetworkInfo() != null`, `EzyCableDigiConstants`.)

## 4. Conditions that allow Offline Login
✅ The **only mandatory condition** is the **2-day freshness window** on the last *online*-login date:
```
271  if (activeNetworkInfo == null) {                         // no network
275      current_days_login = settingsPref.getString(current_dates_login, "");  // SPF_NAME_LOGIN
277      datediff(current_days_login, formattedDate);          // → dayDifference
278      if (dayDifference <= 2) { open Offline_Activity } else { "Sync Previous data" → exit }
```
| Candidate condition | Required for offline ENTRY? |
|---|---|
| Previous **online** login (a saved `current_dates_login` ≤ 2 days) | ✅ **Effectively yes** (the date is only written on online login, `:812`) |
| Remember-Me checked | ❌ No (not referenced in the offline branch) |
| Offline flag / business url / user code / machine no / dealer id | ❌ No (used later for download/sync, not for entry) |
🟡 Fresh-install nuance: `datediff("")` throws → `dayDifference` stays default `0` → `0<=2` true → offline dashboard opens **empty** (side-effect, see §10 Case A).

## 5. Login button pressed offline — is anything compared?
✅ **No.** The offline branch (`:271-305`) never reads `username`/`password` and never compares them. Username is **not** validated, password is **not** compared. Android simply **trusts** the device (date window) and opens the offline dashboard. The restored credentials are **cosmetic only**.

## 6. Where LoginActivity decides: Offline Dashboard / popup / exit
✅ All in the login-button handler (`:270-305`, duplicated for SDK<23 at `:328-362`):
- `activeNetworkInfo == null` **and** `dayDifference <= 2` → `startActivity(Offline_Activity)` + `finish()` (`:279-293`).
- `activeNetworkInfo == null` **and** `dayDifference > 2` → AlertDialog **"Please go online and sync previous offline collections data"** / title **"Sync Previous data"** → OK → `finish(); System.exit(0)` (**exit app**, `:294-305`).
- network present + empty fields → "UserName and Password should not be Empty" / "Empty Fields!" (`:306-312`).
- network present + fields filled → `BMS_login`/`login` (online) (`:313-318`).

## 7. Every SharedPreference used for offline login
| Pref file (constant) | Key | Purpose | Written | Read | Cleared |
|---|---|---|---|---|---|
| `vidslogin` (`SPF_NAME`) | `username`, `password` | Remember-Me credential prefill (cosmetic) | online login if RM checked (`:793-794`) | every onCreate (`:226-227`) | online login if RM **unchecked** (`:796-797`). **Not** on logout |
| `LOGIN_VALUES` (`SPF_NAME_LOGIN`) | `current_dates_login` | **Offline gate date** (server date) | online login (`:812`) | offline branch (`:276`) | never (overwritten next online login) |
| `LOGIN_VALUES` | `app_theme_login`, `crfno_login`, `hhtoption_login`, `amtroun_login`, `formats`, `customer_dic`, `enable_cust_disc` | offline dashboard settings (intent extras) | online login (`:808-817`) | offline branch (`:280-289`) | never |
| `LOGIN_url` (`SPF_NAME_LOGIN123`) | `loginUrl` | data-server URL | BMS/login | onCreate (`:168-171`) | never |
| `OFFLINEPREF` | `USERCODE`, `MACHINE_ID`, `total_length`, `USECAF` | download/sync metadata | login/download | offline/download/sync | on clear-data |
| `partial_pay` | `partial_pay` | partial-payment rule | login (`:776`) | offline (`:290`) | never |
🟡 BMS prefs (`BMS_SHARED_PREF`) hold app logo path; not used for the offline gate.

## 8. Logout — what is cleared
✅ Both logout paths (`MainActivity.java:238-240`, `DashboardHomeFragment.java:188-190`): just `Intent(LoginActivity)` + `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK`. Confirmation text: **"Are you sure you want to logout? \n Click 'Yes' to Logout!"**
- ❌ Does **NOT** clear remembered username/password (`vidslogin` survives).
- ❌ Does **NOT** clear offline user code, dealer id, machine number, or the **offline SQLite database**.
- It only clears the **activity back-stack**. Static fields (authToken/dealerId) die only if the process dies.
➡️ After logout, the next LoginActivity still pre-fills the remembered credentials, and the offline DB is intact.

## 9. SplashScreen
✅ `SplashScreenActivity` (`:43-67`): network present → `AppVersionCheck_Activity`; no network → `LoginActivity`. It does **NOT** preload username/password and does **NOT** auto-submit/auto-login. Credential prefill happens in `LoginActivity.onCreate` (§1). There is **no auto-login** anywhere — the user must press Login.

## 10. Fresh-install scenarios
| Case | Setup | Android behaviour | Evidence |
|---|---|---|---|
| **A** | Never logged in online; offline launch | Fields disabled & empty (no saved creds); press Login → `datediff("")` exception → `dayDifference=0` → **opens empty Offline Dashboard** (Unpaid 0 / Paid 0 / Search empty). No block. 🟡 side-effect, not an explicit allow | `:226-227,1046-1051,278`; `Offline_Activity.java:94` |
| **B** | Online login once, **Remember-Me ON**, then offline | Fields disabled, **pre-filled** with saved creds; press Login → date ≤2 → **Offline Dashboard** (with downloaded data if any) | `:226-227,793-794,279-293` |
| **C** | Online login once, **Remember-Me OFF**, then offline | Creds were cleared at that login (`:796-797`) → fields disabled & **empty**; press Login → date ≤2 → **Offline Dashboard** | `:796-797,279-293` |

➡️ Remember-Me only affects **whether the fields are pre-filled** — it does **not** affect whether offline login is allowed (the 2-day date does).

---

# PHASE 2 — Flutter comparison

| Area | Android | Flutter | Status |
|---|---|---|---|
| **Credential persistence** | username+password plaintext in `vidslogin` | **Not stored.** Only `auth_token` + `remember_me` flag in `flutter_secure_storage` (`auth_service.dart:16-17,180-182`) | 🔴 **Missing** (no username/password persistence) |
| **Field pre-fill on open** | always restores username+password (`:226-227`) | **No restore** — `_userController`/`_passwordController` start empty (`login_screen.dart:28`) | 🔴 Missing |
| **Remember-Me semantics** | checked→save creds, unchecked→**clear** creds; box defaults unchecked | `_rememberMe` toggles writing the `remember_me` flag only; no cred save/clear; box defaults false (`:30,268-277`) | 🟡 Different (token-flag vs credential prefill) |
| **Disabled fields offline** | `setEnabled(false)` on both fields when offline (`:248-251`) | Fields **always editable** (no offline disable) (`_GlassTextField`, `:402`) | 🔴 Missing |
| **Offline-entry gate** | 2-day window on `current_dates_login`, else "Sync Previous data" → exit | **No gate** — no network → `OfflineDashboardScreen` directly (`login_screen.dart:94-103`, `splash_screen.dart:34-43`) | 🔴 Missing |
| **Offline login compares creds?** | No (pure trust) | No (also goes straight to offline dashboard) | ✅ Match (neither compares) |
| **Offline dashboard opens empty if no data** | yes | yes (`offline_dashboard_screen.dart:34-45`) | ✅ Match |
| **Routing decision location** | `LoginActivity` button handler | split between `splash_screen` + `login_screen` | 🟡 Different location, similar effect (but missing the gate) |
| **Logout clearing** | clears nothing (creds + offline DB survive) | clears SessionService + `auth_token` + `remember_me`; offline DB survives (`auth_service.dart:202-205`) | 🟡 Flutter clears **more** (its token/flag); offline DB parity ✅ |
| **Splash auto-login** | none | none | ✅ Match |
| **Credential storage security** | plaintext SharedPreferences | secure storage (token only) | 🟡 Flutter more secure; keep |

**Net:** Flutter matches on "no credential comparison", "empty offline dashboard", and "no auto-login", but is **missing**: credential prefill, offline field-disable, the 2-day offline gate + block dialog, and the exact Remember-Me save/clear semantics.

---

# PHASE 3 — Implementation plan (NO CODE; for approval)

> Reproduce Android behaviour exactly. No new auth, no JWT refresh, no new business rules.
> **Keep credentials in `flutter_secure_storage`** (encrypted) instead of plaintext prefs — same
> behaviour, no security reduction. Each step ends `flutter analyze` clean, no temp logs.

### Decisions needed first
- **D1 — Password prefill:** Android pre-fills the *password* field (plaintext) and it's cosmetic only (never compared offline). Options: (a) **match exactly** — persist username+password in secure storage and prefill both; (b) prefill **username only**, leave password blank (slightly safer, minor visual diff). *Recommend (a) for exact parity, stored in secure storage.*
- **D2 — Fresh-install offline (Case A):** match Android's literal "opens empty dashboard", or block when there's no prior online login? *Recommend block (Android's intent); confirm.*

### Step 1 — Persist Remember-Me credentials (secure storage)
- On **successful online login**: if Remember-Me checked → write `username` (+ `password` per D1) to `flutter_secure_storage`; if unchecked → **delete** them (mirror Android's `clear()` at `:796-797`). Reuse existing `SecureStorageService`; add keys `remember_username` / `remember_password`.
- **Risk:** none. **Test:** toggle RM, relaunch, inspect.

### Step 2 — Prefill fields on Login screen open
- In `login_screen.dart initState`, read the stored credentials and set the controllers (mirror `:226-227`). Checkbox **defaults unchecked** (match Android — do not auto-check).
- **Risk:** none. **Test:** Cases B (prefilled) and C (empty).

### Step 3 — Disable fields when offline
- When `connectivity == none`, set the two `_GlassTextField`s to `enabled: false` (mirror `setEnabled(false)`; do not change focus/inputType). Re-enable when online.
- **Risk:** low. **Test:** airplane-mode open → fields read-only, still show prefilled text.

### Step 4 — Offline-entry 2-day gate + block dialog (depends on the broader offline plan Step 1-2)
- Persist server `current_date` at online login (already noted in `OFFLINE_IMPLEMENTATION_PLAN.md` Step 1). On offline Login press: compute day-difference; `≤2` → `OfflineDashboardScreen`; `>2` (or none per D2) → dialog **"Please go online and sync previous offline collections data"** / title **"Sync Previous data"** → OK → exit (`SystemNavigator.pop()`). Also apply the same gate in `splash_screen` no-network path.
- **Risk:** Med (entry). **Test:** Cases A/B/C + stale >2-day.

### Step 5 — Logout parity
- Keep Flutter's current logout (clears session + token + RM flag). **Do not** clear remembered username/password unless RM was unchecked (Android keeps them). **Do not** wipe the offline DB (Android doesn't). Confirm offline DB and remembered creds survive logout.
- **Risk:** low. **Test:** logout → re-open login → creds still prefilled; offline DB intact.

### Cross-cutting requirements
- No silent failures: the >2-day case shows the exact dialog; offline field-disable is visible; prefill failures fall back to empty (never crash).
- Proper loading/dialog states; no crashes; no new packages.
- Verbatim Android strings: "Please go online and sync previous offline collections data" / "Sync Previous data"; "Are you sure you want to logout? \n Click 'Yes' to Logout!".

### Explicitly NOT doing
JWT refresh · new authentication · password comparison offline · new business rules · reducing security (credentials go to secure storage, not plaintext prefs) · wiping offline DB on logout · auto-login on splash (Android has none).

### Order
1 → 2 → 3 → 5 (independent), then 4 (needs the persisted online-login date). Verify each on RMX3842 before the next.
