# Security Parity — Android vs Flutter (Investigation Only)

> Source of truth: Android `D:\Git-Repos\magikdigi`. No code changed.
> Tags: ✅ Verified (traced in source) · 🟡 Not Yet Verified (needs live/server confirmation).

---

## 1. Login Flow

### Android (`LoginActivity.java`)
- ✅ **Two-step**: `BMS_login` (SOAP `validateUserAuthentication` on `BMS_NAMESPACE` = `ezybms.itpworld.com`) resolves the data-server URL + app logo; then `login` (SOAP `validateLogin`, config key `LOGIN`) on `NAMESPACE/wsController`.
- ✅ Login is **SOAP** (ksoap2 `VER11`), wrapper `validateLoginInfo`. Request fields: `UserName`, `PassWord`, `imei`, `appTypeId`, `appTypeAutoId`, `lat`, `lang`.
- ✅ Response parsed from `envelope.getResponse().toString()` via substring: `statusCode`, `employeeId`, `dealerId`, `authToken` (+ `send_sms`, `swipe_scan`, `machineNumber`, `enable_payment_discount`, `max_discount_percent_allowed`, `box_wise_service_extension`).
- ✅ `statusCode==0` → success; stored in **static fields** (`LoginActivity.authToken/dealerId/employeeId`) **and SharedPreferences** (`SPF_NAME`, `SPF_NAME_LOGIN`, `BMS_SHARED_PREF`).

### Flutter (`AuthService.login`)
- ✅ **SOAP `validateLogin`** (wrapper `userInfo`/`validateLoginInfo`), same fields: `UserName`, `PassWord`, `imei`, `appTypeId=0`, `appTypeAutoId=0`, `lat='0.0'`, `lang='0.0'`.
- ✅ Reads `statusCode`/`statusMessage` + `authToken`/`dealerId`/`userType`/`employeeId` + `enable_payment_discount`/`max_discount_percent_allowed`/`box_wise_service_extension`/`machineNumber` → `SessionService` (in-memory).
- ✅ BMS resolution is done separately (`ServerUrlResolver.resolve()` in `LoginScreen.initState`), not as a button-press step — functionally equivalent, sequencing differs. 🟡 exact BMS field parity not line-checked.
- ✅ **IMEI guard** (added this cycle): if `AppConfig.deviceImei` is empty, `initDeviceImei()` is awaited before the request, so login never sends an empty IMEI.

| Item | Android | Flutter | Status |
|---|---|---|---|
| Login transport | SOAP validateLogin | SOAP validateLogin | ✅ Match |
| BMS pre-auth | `validateUserAuthentication` at login | `ServerUrlResolver.resolve()` on screen open | 🟡 Partial (same effect, different timing) |
| Fields sent | UserName/PassWord/imei/appType*/lat/lang | same | ✅ Match |
| Response fields | statusCode/employeeId/dealerId/authToken/… | same | ✅ Match |

---

## 2. Credentials
- ✅ **Password is sent plaintext** inside the SOAP body (`PassWord`) in **both** Android and Flutter. No hashing/encryption of the password by the client.
- ✅ **Android stores** login state in **plaintext SharedPreferences** (remember-me credentials, authToken, dealer/employee).
- ✅ **Flutter stores** `auth_token` + `remember_me` in **`flutter_secure_storage`** (OS-encrypted) — `AuthService` writes them on success (`auth_service.dart:180-182`), deletes on `logout()`. `SessionService` itself is **in-memory only**.

| Item | Android | Flutter | Status | Risk |
|---|---|---|---|---|
| Password hashing (client) | None (plaintext in SOAP) | None (plaintext in SOAP) | ✅ Match | — |
| Token at rest | SharedPreferences (plaintext) | flutter_secure_storage (encrypted) | 🟡 Flutter exceeds Android | Low (do not downgrade) |
| Remembered credentials | username+password in SharedPreferences | only token + remember flag (no password stored) | 🟡 Partial (Flutter stores less) | Low |

---

## 3. Tokens
- ✅ Android: `authToken` set at login, kept in static fields + SharedPreferences. **No expiry, no refresh, no client-side invalidation, no duplicate-login handling.**
- ✅ Flutter: `authToken` in `SessionService` (in-memory) + secure storage. **No expiry, no refresh.** `logout()` clears both.
- ✅ Token is sent on every request (SOAP wrapper `authToken`; REST form `authtoken`).

| Item | Android | Flutter | Status |
|---|---|---|---|
| Expiry / refresh | None | None | ✅ Match |
| Invalidation on logout | navigate to Login (statics persist until process death) | `SessionService.clear()` + secure-storage delete | 🟡 Flutter clears more thoroughly |
| Duplicate-login handling | None (client) | None (client) | ✅ Match |

---

## 4. Device Security
- ✅ **IMEI/Device ID**: both use `TelephonyManager.getDeviceId()` (API ≤ 28) / `Settings.Secure.ANDROID_ID` (API ≥ 29). Android requests `READ_PHONE_STATE`; Flutter uses a native channel.
- 🟡 **"SMS key"**: the login response carries `send_sms` (a 0/1 flag), used to gate SMS-on-payment — not a cryptographic key. No separate SMS key/device-registration handshake found.
- 🟡 **Dealer-device binding**: the IMEI is sent in every request; any binding/validation is **server-side** (cannot verify from client).
- ✅ **Multiple-device / unauthorized-device**: no client-side handling in either.
- ✅ **Root detection**: Android imports `RootBeer` in `SplashScreenActivity` but it is **commented out / not active**. Flutter: none. → effectively **none** in both.
- ✅ **Emulator / debug detection**: none in either.

| Item | Android | Flutter | Status |
|---|---|---|---|
| Device id source | getDeviceId / ANDROID_ID | ANDROID_ID (native) | ✅ Match |
| Root/emulator/debug detection | None (RootBeer disabled) | None | ✅ Match |
| Device binding | server-side only | server-side only | 🟡 Not Yet Verified (server) |

---

## 5. API Security (endpoint map)
- ✅ **SOAP** (`NAMESPACE/wsController`, ksoap2 VER11): `validateLogin`, `searchCustomer`, `getPendingAmount`, `makePayments`, `InvoiceService`, `empCollection`, package ops (`gcb`/`cpo`/`cdr`/`gdr`/`rbox`/`csews`), etc. Auth = `authToken` field in the wrapper + `imei`.
- ✅ **Plain REST** (`/packagelist/...`, form POST): `getCustomerBoxes`, `getPaymentHistorylist`, `miniDayCollections`, `packageActDeactReport`, `chargeTypes`, `saveOnetimeCharges`, `getOneTimeCharges`. Auth = form params `dealer_id`, `imei`, `authtoken`.
- ✅ **Encrypted REST** (`/digi_rest_api/...`): `scheduled_collection_data`/`scheduled_collection_create` (Pay Later), `expense_*`. Body `{payload, env_key, hash}` (hex-obfuscation via `DigiCrypto`) **plus** an `apitoken` **JWT** header (HS256, secret `"fd4f564545"`, claims `method_name`+`request_time`).
- ✅ **Offline**: `GetRequest` (download), `GetCollectionData`/payment sync — plain form POST/raw.
- ✅ Common params: `dealer_id` / `imei` / `authtoken` (REST); `authToken` + `imei` (SOAP). Flutter mirrors all of these (`RestClient.postForm`/`postEncrypted`, `SoapClient`, `DigiCrypto`).

| Channel | Android | Flutter | Status |
|---|---|---|---|
| SOAP wsController | ✅ | `SoapClient` | ✅ Match |
| Plain `/packagelist` | ✅ | `RestClient.postForm` | ✅ Match |
| Encrypted `/digi_rest_api` (envelope + JWT) | ✅ | `RestClient.postEncrypted` + `DigiCrypto` | ✅ Match |
| Offline download/sync | ✅ | `RestClient.postRaw` | ✅ Match |

---

## 6. Payment Security
- ✅ **Duplicate / double-submit**: Flutter `PaymentController._isStoring` guard (returns early on re-tap); offline `commitPayment` rejects when `flag != 0` ("Payment already made"). Android blocks via a modal `ProgressDialog` during the call + the offline paid-flag check. → equivalent intent.
- ✅ **Receipt validation / transaction IDs**: online receipt number is **server-issued** (never fabricated client-side); offline receipt number is **locally generated** (`timestamp + customer_id`) in **both** (Android `tstamp+customer_id`, Flutter `commitPayment`).
- 🟡 **Replay protection**: none client-side in either (relies on server + `billingId`). Not Yet Verified server-side.
- ✅ **Validation before payment**: amount required; broadband split (cable vs broadcaster) mirrors Android; STB-only `restrict_partial_payment` gating present.
- ✅ **Backend acknowledgement**: `statusCode==0` → success; receipt built from the response.

| Flow | Duplicate guard | Receipt source | Status |
|---|---|---|---|
| STB / Broadband / Combined | _isStoring + server | server receiptNumber | ✅ Match |
| Offline payment | flag!=0 reject | local tstamp+custId | ✅ Match |
| Package Ops / Expenses / Pay Later | per-call (no double-submit observed issues) | n/a | 🟡 Partial (not stress-tested) |

---

## 7. Storage
| Store | Android | Flutter | Status |
|---|---|---|---|
| Session/token | static fields + SharedPreferences (plaintext) | SessionService (in-memory) + secure storage (token) | 🟡 Flutter exceeds |
| Settings (header/footer/amt_filter) | SharedPreferences `settings_Pref` | `SettingsStore` (SharedPreferences) | ✅ Match |
| Saved printer | SQLite `bledevices` | SharedPreferences (`printer_mac/name`) | 🟡 Partial (different store, same effect) |
| Offline customers/payments | SQLite `offline_data_4` | SQLite `offline_customers`/`offline_payments` | ✅ Match (parsing offsets identical) |
| Cached permissions/dashboard/reports | not persisted (fetched live) | not persisted (fetched live) | ✅ Match |

---

## 8. Network Security
- ✅ **Cleartext HTTP** in both (`NAMESPACE = http://digi.kccl.tv`, BMS `http://ezybms…`); Flutter manifest sets `android:usesCleartextTraffic="true"` (Android original same).
- ✅ **No SSL pinning / no custom cert validation** in either (default platform trust; cleartext anyway).
- ✅ **Timeouts**: Android per-call (70s–700s). Flutter: SOAP 60s, REST 60s, offline raw 200s, gpa/mpay/box 70s.
- ✅ **Retry**: Android Volley `DefaultRetryPolicy` on some REST calls; Flutter has no auto-retry (manual Retry buttons on dashboard). 🟡 Partial.
- ✅ **Error handling**: Flutter is **defensive** (try/catch → safe result, never crashes); Android shows per-screen dialogs/toasts.

| Item | Android | Flutter | Status |
|---|---|---|---|
| HTTPS / pinning | cleartext, no pinning | cleartext, no pinning | ✅ Match |
| Timeouts | per-call | per-call | ✅ Match |
| Auto-retry | Volley retry on some REST | none (manual Retry) | 🟡 Partial |

---

## 9. Security Gap Summary
| Area | Status | Note |
|---|---|---|
| Login transport + fields | ✅ Match | SOAP validateLogin, identical fields |
| Password handling | ✅ Match | plaintext in SOAP (both) |
| Token lifecycle | ✅ Match | no expiry/refresh in either |
| Token at rest | 🟡 Flutter exceeds | secure storage vs plaintext prefs — **do not downgrade** |
| IMEI / device id | ✅ Match | ANDROID_ID |
| Root/emulator/debug | ✅ Match | none active in either |
| Device binding | 🟡 server-side | cannot verify from client |
| Endpoint channels (SOAP/REST/encrypted/offline) | ✅ Match | full parity incl. JWT envelope |
| Payment duplicate/receipt | ✅ Match | server receipt / offline local receipt |
| Replay protection | 🟡 server-side | none client-side either |
| Cleartext HTTP / no pinning | ✅ Match | identical |
| Auto-retry | 🟡 Partial | Android Volley retry vs Flutter manual |

**No new security recommended.** Only parity documented.
