# Saved Bluetooth Printer Flow — Investigation (NO CODE)

Investigation-only. **Android = source of truth** (`D:\Git-Repos\magikdigi`).
Flutter working app = **`D:\StudioProjects\ezy_cable_digi`** (the prompt's
`D:\html\flutter_ezybill_new` is stale — ignore it). **Do NOT break the existing direct
printer-selection / print flow.** Goal: support BOTH Flow 1 (pick-then-print, current) and
Flow 2 (saved printer → auto-connect → print).

---

## 1. BLE AppBar icon
- **Android:** the AppBar Bluetooth icon opens **`Bluetooth_Fragment`** (classic BT SPP, uses
  `BluetoothChatService`). 🟡 exact click→navigation in the host activity to confirm.
- **Flutter:** the dashboard AppBar **already shows a Bluetooth icon** (visible in screenshots).
  🟡 confirm what it currently does (likely opens a connect screen using `RealBluetoothService`).

## 2. Saved-printer screen (Android `Bluetooth_Fragment`)
- Lists **paired devices**; `REQUEST_CONNECT_DEVICE` flow → `connectDevice(intent)` reads the
  **device MAC** → `mChatService.connect(device)` (`:552-560`). States via a Handler
  (`STATE_CONNECTING/CONNECTED/NONE`, `:493-524`). Print blocked if not connected
  ("You are not connected to any device to print", `:571-626`).

## 3. Where the printer is saved
- **SQLite `bledevices` table** (`DB_Helper`): `TABLE_BLE_DEVICES="bledevices"`,
  column `devicename` (+ address); `addBleDevice` = `db.insert(TABLE_BLE_DEVICES,…)` (`:190`),
  read = `select * from bledevices` (`:341`). **So the saved printer = name + MAC in SQLite.**
- (SharedPreferences `settings_Pref` is for receipt header/footer — `PrinterSetting_Fragment` —
  NOT the saved printer.)

## 4. Auto-connection (Android)
- On a receipt/print screen: read the saved device (MAC) → `BluetoothChatService.connect(MAC)`
  → wait for `STATE_CONNECTED` → write the receipt bytes. If not connected → blocked dialog.
  🟡 exact auto-vs-prompt branch per screen to confirm.

## 5. Print entry points (Android)
`Bluetooth_Fragment` + `DisplayPaymentDetails_Fragment` (payment receipt) + history/onetime
receipt screens build the receipt and write via `BluetoothChatService`. They all funnel through
the same chat-service connection (saved/last-connected device).

## 6. Existing Flutter printing (REUSE — do not modify the core)
- **`core/services/real_bluetooth_service.dart`** (`print_bluetooth_thermal`):
  `requestPermissions()`, `getDevices()` → `List<BluetoothInfo>` (paired), `connectPrinter(mac)`,
  `disconnectPrinter()`, `ensureConnected(mac)` (reconnect-if-needed), `_formatMacAddress()`.
  **This is the reusable BT core.**
- **`features/payment/receipt_preview_screen.dart`**: the current **direct-selection** print
  flow (pick a device → connect → print) + the thermal line builder (now reads header/footer).
  **Flow 1 lives here — must stay working.**

## 7. Gap analysis
| Android | Flutter today | Missing | Safe add |
|---------|---------------|---------|----------|
| Saved printer in `bledevices` (name+MAC) | none | **persistence of the chosen printer** | a small store (SharedPreferences via `SettingsStore`, or a `printers` table) |
| BLE icon → save-printer screen | AppBar BT icon (behaviour 🟡) | a **"Saved Printer" screen** (list paired → select → save) | new screen reusing `RealBluetoothService.getDevices()` |
| Auto-connect on print | direct-select each time | **auto-connect to saved + Print button** | extend `receipt_preview_screen`: if saved → `ensureConnected(savedMac)` → print; else current picker |
| Connect-fail handling | blocked dialog | fallback to manual pick | on connect fail → open the existing picker |

## 8. Architecture (no duplicate BT stacks)
- **Reuse `RealBluetoothService`** for ALL BT (permissions/scan/connect/print). Do NOT add a
  second BT plugin or manager.
- **Add a tiny persistence** for the saved printer (recommend `SettingsStore` keys
  `printer_mac` + `printer_name` — same SharedPreferences pattern already used; avoids a new
  table). Android uses SQLite `bledevices`; SharedPreferences is the lighter Flutter-idiomatic
  equivalent and doesn't touch the offline DB schema.
- **One save-printer screen** (reuses `getDevices()`), **one** auto-connect helper on the
  receipt flow.

## 9. Final recommendation
**Android architecture:** classic BT SPP (`BluetoothChatService`); saved printer = `bledevices`
SQLite row (name+MAC); receipt screens connect to it before writing.
**Flutter architecture:** `print_bluetooth_thermal` via `RealBluetoothService`; current flow =
pick→connect→print in `receipt_preview_screen`.
**Missing pieces:** (1) persist chosen printer; (2) BLE-icon save screen; (3) auto-connect path
on print with manual fallback.
**Safest plan (when approved):**
1. `SettingsStore`: add `printer_mac`/`printer_name` (load/save) — additive.
2. New `SavedPrinterScreen`: `RealBluetoothService.getDevices()` → tap to save (MAC+name).
   Wire the AppBar BT icon to it (reuse the existing icon).
3. `receipt_preview_screen`: BEFORE the existing picker — if a printer is saved, show **Print**
   → loading → `ensureConnected(savedMac)` → print; **on failure fall back to the current
   picker**. If nothing saved → **unchanged** current flow.
**Files to MODIFY (later):** `settings_store.dart` (add keys), AppBar host (wire icon),
`receipt_preview_screen.dart` (saved-printer branch only — keep Flow 1), + new
`saved_printer_screen.dart`.
**Files NOT to touch:** `real_bluetooth_service.dart` (reuse as-is), the receipt **line
builder**, the payment/collection/transaction/offline-payment paths.
**Risk:** Low if additive — the saved branch wraps the existing flow; Flow 1 is the fallback,
so it can't regress. 🔵 No payment-logic changes.

## 🟡 To verify before implementing
What the existing Flutter AppBar BT icon does today; exact Android auto-connect-vs-prompt per
receipt screen; whether to persist via SharedPreferences (recommended) vs a `printers` table.
