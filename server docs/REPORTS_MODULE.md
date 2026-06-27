# Reports Module Investigation

Status: documentation-only investigation, no implementation changes.

## Scope
This note consolidates what is currently verified about the Reports module from two sources:
- the production Android app source at `D:\Git-Repos\magikdigi`
- the Flutter workspace at `D:\StudioProjects\ezy_cable_digi`

## Executive summary
- ✅ The production Android app has a real Reports home flow with two clearly implemented report entry points: Employee Collections and Mini Day Report.
- ✅ The Mini Day Report flow has a verified backend contract and a verified print route into the Bluetooth print flow.
- ✅ The Flutter app has reports screens and navigation entry points, but the current implementation is mostly UI-only or placeholder behavior.
- 🟡 There is no verified production contract for a separate “monthly report” or “month-wise report” flow in the Android source reviewed here. The only evidence found was class names in build output, not a live source implementation or route.

## Verified findings from the Android app

### 1) Reports home entry points
- ✅ Verified in `app/src/main/java/itp/com/magikdigi/Fragments/ReportsHome_Fragment.java`.
- The reports home screen offers:
  - Employee Collections
  - Mini Day Report
- Each entry opens a dedicated fragment through `MainActivity.changeFragment(...)`.

### 2) Employee Collections flow
- ✅ Verified in `app/src/main/java/itp/com/magikdigi/Fragments/Report_EmpCollect_Fragment.java`.
- The screen uses a date range picker and a Search button.
- On search, it calls a SOAP request using the config key `empColl` from `app/src/main/assets/configg.properties`.
- The request payload is a complex type named `checkCollectionInfo` with these fields:
  - `authToken`
  - `fromDate`
  - `toDate`
  - `imei`
- The request is sent by `ksoap2` over the SOAP endpoint defined by `LoginActivity.login_serverUrl`.
- The response is parsed into a list of `collectionResult` objects.

### 3) Employee Collection details flow
- ✅ Verified in `app/src/main/java/itp/com/magikdigi/Fragments/Reports_Emp_Collection_List_Fragment.java` and `app/src/main/java/itp/com/magikdigi/Fragments/Employee_Collection_Details_Fragment.java`.
- The Android app has a second-step flow for viewing employee collection results and their details.
- The request object for the detail path uses the complex class `empCustomerCollectionDetails` with:
  - `authToken`
  - `fromDate`
  - `toDate`
  - `employeeId`
  - `imei`
- The config key used for this flow is `eccd` from `configg.properties`.

### 4) Mini Day Report flow
- ✅ Verified in `app/src/main/java/itp/com/magikdigi/Fragments/MiniDayReport_Fragment.java`.
- The screen uses a REST POST request to the endpoint mapped by the config key `minidayreport`.
- The config value resolves to `/packagelist/miniDayCollections`.
- The request body uses these form fields:
  - `imei`
  - `authtoken`
  - `request_from=FromDigiApp`
- The response is parsed as JSON and expects:
  - `status_code`
  - `status_message`
  - `casData` for STB-style collection summary
  - `broadbandData` when broadband values are present
- The screen renders cash/bank count and amount values and enables print when the report is successfully generated.

### 5) Mini Day Report print route
- ✅ Verified in `app/src/main/java/itp/com/magikdigi/Fragments/MiniDayReport_Fragment.java` and `app/src/main/java/itp/com/magikdigi/Fragments/Bluetooth_Fragment.java`.
- When the user taps Print, the app:
  - checks Bluetooth availability
  - passes the report data into a Bluetooth fragment
  - sends a bundle with `offline_report = 3` to indicate the mini-day report print path
- This confirms that the Android production app has a real print integration path for mini-day reports.

## Verified findings from the Flutter app

### 1) Reports screens exist in Flutter
- ✅ Verified in the Flutter workspace:
  - `lib/features/reports/mini_day_report_screen.dart`
  - `lib/features/reports/search_collections_screen.dart`
- These screens are also reachable through navigation from the app drawer and dashboard.

### 2) The Flutter mini-day report screen is currently placeholder UI
- ✅ Verified in `lib/features/reports/mini_day_report_screen.dart`.
- The screen shows a print row and a summary card, but the values are hardcoded to zero.
- There is no backend repository, no API call, and no real report data source attached to this screen.

### 3) The Flutter employee collections screen is also placeholder UI
- ✅ Verified in `lib/features/reports/search_collections_screen.dart`.
- The screen shows date pickers and a Search button.
- The Search button currently only shows a snackbar and does not call any API or repository layer.

### 4) Flutter has an offline mini-day report implementation
- ✅ Verified in `lib/features/offline/miniday_report_screen.dart` and `lib/core/database/database_helper.dart`.
- This implementation reads payment records from local SQLite via `getTodayCollectionSummary()`.
- It generates a PDF for print and uses the local database rather than the production Android report API.
- This is useful as a local/offline reference, but it is not the same as the production Android report flow.

## What is not yet verified

### 1) Separate monthly report flow
- 🟡 Not yet verified.
- The investigation did not find a source-backed monthly report fragment or endpoint in the Android source reviewed here.
- The only evidence found was class names in build output and drawable resources, which is not enough to treat a monthly report flow as implemented.

### 2) Flutter parity with the Android production API contract
- 🟡 Not yet verified.
- The Flutter screens are present, but no verified repository/service layer has been wired to the Android report endpoints.
- No endpoint contract has been implemented in Flutter based on the Android code reviewed here.

### 3) Full print formatting details for report printing
- 🟡 Not yet verified.
- The Android app clearly routes mini-day report printing through Bluetooth, but the exact thermal/receipt formatting details were not fully validated in this investigation.

## Practical conclusion
If implementation is planned, the safest first target is the mini-day report because:
- it has a verified Android contract,
- it has a verified print path,
- and it is already partially represented in Flutter.

The employee collections flow is the next logical target because it also has a verified Android contract and a clear date-range input pattern.

The monthly report path should not be assumed to exist until a concrete source file, fragment, endpoint, or UI route is found in the Android app source.
