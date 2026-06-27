# API Migration Record — MagikDigi (Android → Flutter)

Source of truth: D:\Git-Repos\magikdigi. Server method names: `app/src/main/assets/configg.properties`.
Type = SOAP (ksoap2 via `/wsController`) or REST (`/packagelist/...`, `/digi_rest_api/...`).

| # | Feature | Config key | Type | Status | Doc |
|---|---|---|---|---|---|
| 1 | BMS Cloud Auth | — | SOAP | ✅ Implemented (registration/logo; does NOT set login URL) | AUTH_LOGIN.md |
| 2 | Login (validateLogin) | `LOGIN` | SOAP | ✅ Verified (authToken/dealerId/userType) | AUTH_LOGIN.md |
| 3 | Dealer Groups | `dg` | REST | 🟡 Implemented; error-UI parity + intermittent "Not a Valid Dealer" pending | DEALER_GROUPS.md |
| 4 | Customer List (unpaid) | `uc` | SOAP | 🟡 Implemented; display verified (1 customer). customerType→param mapping to confirm | — |
| 5 | Customer Search | `sc` | SOAP | ✅ **Complete — manually verified** | CUSTOMER_SEARCH.md |
| 6 | Get Pending Amount | `gpa` | SOAP | 🟡 Implemented; verified `statusCode=0`/`pendingAmount`. Pending: Android compare + zero-amount check + user approval | — |
| 7 | Make Payment | `mpay` | SOAP | ✅ **STB cash VERIFIED end-to-end** (positive-due customer): `statusCode=0`, server receipt, `acc_payment_details` row (`payment_flag=4`, amount + receipt + billingId match). 28-field parity request. Broadband / STB+BB / card·bank = follow-up (out of launch scope). | MAKE_PAYMENT.md · PAYMENT_FLOW_SPEC.md |
| 8 | Payment History | `payhist` | SOAP | ⬜ Pending | — |

> ✅ **Payment now calls the server (STB cash):** `PaymentController.pay()` → `MakePaymentRepository`
> posts real `makePayments` (`mpay`), uses the server receipt, and no longer writes a local dummy row.
> ⚠️ Pending **device verification** (test server + disposable customer + tiny amount) and user approval.
> Broadband / STB+Broadband / bank·card·upi are out of scope (not implemented).

## Conventions established
- **Env switching:** comment/uncomment `namespace` / `namespaceBms` in `app_config.dart` (mirrors `EzyCableDigiConstants`). No runtime toggle.
- **Login URL:** `NAMESPACE + "/wsController"` (production package path); BMS `ipAddress` is NOT used for login.
- **SOAP envelope:** ksoap2 VER11 — `<v:Envelope i:/d:/c:/v:>`, `<v:Header/>`, `<n0:method xmlns:n0>`, wrapper carries `i:type="n0:<TypeName>"`.
- **REST:** form-encoded POST, JSON response (some fields double-encoded JSON strings, e.g. `group_details`).
- **Auth on every call:** `authToken` (SOAP key `authToken`, REST key `authtoken`); list/payment calls also send `dealer_id`/`group_id`.
- **User-Agent:** `ksoap2-android/2.6.0+` on all calls (WAF gates on it → 403 otherwise).
- **Session:** in-memory `SessionService` (mirrors Android `LoginActivity` statics; not persisted).

## ⛔ PRODUCTION BLOCKERS — REQUIRED before any release APK/IPA is generated
These MUST be resolved before building a production release. Do not ship until all are ✅.

1. ⛔ **Replace `AppConfig.deviceImei` fallback with a real device identifier** (`device_info_plus` → ANDROID_ID).
   Release currently sends an **empty** `imei` by design; a real id must be wired. See `DEVICE_ID_STRATEGY.md`.
2. ⛔ **Implement + verify the SMS-Key device-registration screen** (the `CloudAuthentication` flow):
   a new Flutter install's ANDROID_ID is unregistered (per-app-signing-key differs from the Java app), so it
   must register via BMS `validateAuthentication` with `smsCode` (the dealer's backend-issued SMS Key) before
   login. See `DEVICE_ID_STRATEGY.md` → "Device-registration lifecycle". The dev hardcoded id bypasses this.
3. ⛔ **Verify the iOS device-identifier strategy** (no ANDROID_ID/IMEI on iOS — e.g. `identifierForVendor`)
   **and confirm the server accepts it.**
4. ⛔ **Remove all temporary debug logs** before release: `[GPA]`, `[SC]`, `[UC]`, `[DG]` (and any others).
5. ⛔ **Complete payment-flow verification end-to-end:** `gpa` → `mpay` → receipt → Bluetooth print,
   diffed against the Android app (money/receipt correctness). **Today payment is LOCAL DUMMY only** —
   `mpay` (server `makePayments`) is NOT implemented; pressing Pay only writes local SQLite.
6. ⛔ **Receipt PDF cannot render ₹** — the `pdf` package's default Helvetica font has no Unicode/₹ glyph
   ("Helvetica has no Unicode support"). Embed a Unicode TTF (e.g. NotoSans) in the receipt PDF, or fall back
   to `"Rs."`. (Android renders ₹ via the system font on-screen; thermal print is ESC/POS, printer-dependent.)

> Also pending (not release-blocking but track): `dg` error-UI parity + intermittent "Not a Valid Dealer";
> `uc` customerType→param mapping; switch `namespace`/`namespaceBms` to LIVE for production builds.
