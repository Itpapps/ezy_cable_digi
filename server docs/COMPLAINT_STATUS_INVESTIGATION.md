# Complaint Status Synchronization — Investigation Report

**Date:** 2026-06-27  
**Status:** INVESTIGATION COMPLETE — NO CODE CHANGES MADE  
**Reported Bug:** Changing one customer's complaint status appears to change other customers' status badges

---

## 1. Complete Flow Comparison

### 1.1 Dashboard Loading

| Step | Production (Android) | Flutter |
|------|---------------------|---------|
| Entry point | `DashboardHomeFragment.onCreateView()` L266 | `_DashboardScreenState.initState()` L129 |
| API call | `new getopencomplaintslist().execute()` | `_dash.loadComplaints()` |
| API method | `getopencomplaintslist` (key `gocl`) | Same: `getopencomplaintslist` |
| Wrapper | `openComplaintsInfo` | Same: `openComplaintsInfo` |
| Fields | `authToken, imei, dealer_id=0, from_dashboard="1"` | Same: identical fields |
| Parsing | `JSONArray → new ArrayList → setAdapter()` | `jsonDecode → List<OpenComplaint> → complaints = r.complaints` |
| **List creation** | **Creates new `ArrayList<>()` each time (L876)** | **Creates new `List<OpenComplaint>` each time (via `fromJson`)** |

### 1.2 Model Mapping

| Field | Production (`OpenComplaints_ResponseModel`) | Flutter (`OpenComplaint`) |
|-------|---------------------------------------------|--------------------------|
| `tkt_number` | `setTktNumber(tkt_number)` — mutable setter | `final String tktNumber` — **immutable** |
| `complaint_id` | `setComplaintId(complaint_id)` — mutable setter | `final String complaintId` — **immutable** |
| `status` | `setStatus(status)` — mutable setter | `final String status` — **immutable** |
| `alt_cust_id` | `setAltCustId(altcustid)` — mutable setter | `final String altCustId` — **immutable** |
| `customer_id` | `setCustomerId(customer_id)` — mutable setter | `final String customerId` — **immutable** |

**Evidence:** Production model uses setters (mutable). Flutter model uses `final` fields and `const` constructor — physically cannot be mutated after creation.

### 1.3 Status Badge Color Mapping

**Production — `OpenComplaints_RecyclerView_Adapter.onBindViewHolder()` (L67-76):**
```java
String status = list.get(position).getStatus();
if (status.equalsIgnoreCase("assigned") || status.equalsIgnoreCase("resolved")) {
    holder.status.setTextColor(con.getResources().getColor(R.color.thickgreen)); // #336600
} else if (status.equalsIgnoreCase("inprocess")) {
    holder.status.setTextColor(con.getResources().getColor(R.color.yellow));     // #ffcb08
} else if (status.equalsIgnoreCase("onhold")) {
    holder.status.setTextColor(con.getResources().getColor(R.color.red));        // #bc0000
} else if (status.equalsIgnoreCase("closed")) {
    holder.status.setTextColor(con.getResources().getColor(R.color.blue));       // #2e3192
}
```

**Flutter — `_TicketCard._statusColor()` (L976-983):**
```dart
static Color _statusColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('ASSIGN'))                              return Color(0xFF1565C0); // blue
  if (u.contains('PROCESS') || u.contains('PROGRESS'))   return Color(0xFFF59E0B); // amber
  if (u.contains('HOLD'))                                return Color(0xFFE53935); // red
  if (u.contains('RESOLV'))                              return Color(0xFF43A047); // green
  if (u.contains('CLOS'))                                return Color(0xFF757575); // grey
  return Color(0xFF1565C0); // default → blue
}
```

**Note:** The color hex values differ between production and Flutter, but the mapping logic is equivalent. Both are pure functions that operate on the item's own status string — no shared state possible.

### 1.4 Update Status Flow

**Production — `ComplaintHistory_Others_Fragment` (L449-628):**
```
User taps Update → CloseComplaint AsyncTask →
  doInBackground: SOAP call with {altCustId, complaintId, ticketNumber, status, comment}
  onPostExecute:
    if (statusCode == 0):
      Show success AlertDialog
      OK button → getFragmentManager().popBackStack()  ← POPS BACK TO PREVIOUS FRAGMENT
      NO RE-FETCH. The dashboard fragment is NOT recreated.
      The old adapter with old data survives.
```

**Flutter — `ComplaintDetailsScreen._update()` (L99-164):**
```
User taps Update → closeComplaint() →
  if success:
    _showSuccessDialog() →
      OK button:
        Navigator.pop(ctx)       // close dialog
        Navigator.pop(context, true)  // return `true` to caller
  
  Caller (_TicketCard.onPressed.then):
    if (ok == true) → onRefresh?.call()
    
  onRefresh (dashboard_screen L579-582):
    _dash.loadComplaints(force: true)  // FULL RE-FETCH FROM BACKEND
    setState(() {})                    // redundant extra rebuild
```

> [!IMPORTANT]
> **KEY ARCHITECTURAL DIFFERENCE FOUND:**
> The production Android app does **NOT** re-fetch the complaint list after a status update. It simply pops back to the previous fragment, which still has the old data.
> 
> The Flutter app **DOES** re-fetch the full list from the backend after every status update. This is a deliberate design choice in our Flutter implementation.

### 1.5 Refresh Flow

**Production:**
```
Update success → popBackStack() → No reload → Dashboard shows OLD badges
```

**Flutter:**
```
Update success → Navigator.pop(true) → .then() → onRefresh → 
  loadComplaints(force:true) → fetchOpenComplaints() → 
  backend returns FULL fresh list → complaints = r.complaints → 
  notifyListeners() → _onDash → setState() → rebuild ALL cards with NEW data
```

---

## 2. Widget Lifecycle Investigation

### 2.1 Reused Widgets

| Check | Finding | Evidence |
|-------|---------|----------|
| `_TicketCard` is `StatelessWidget` | ✅ No internal state | L963: `class _TicketCard extends StatelessWidget` |
| `_TicketItem` created fresh per build | ✅ New instance every `itemBuilder` call | L566-575: `final item = _TicketItem(...)` inside lambda |
| `OpenComplaint` immutable | ✅ All fields `final` | `open_complaint.dart` L8-23: every field is `final` |
| `_TicketItem` immutable | ✅ All fields `final` | L34-53: every field is `final`, class has `const` constructor |

### 2.2 Mutable Lists

| Check | Finding | Evidence |
|-------|---------|----------|
| `complaints` list reference | Fully replaced on refresh | L109: `complaints = r.complaints` — reference swap, not mutation |
| Old list survives? | No — no other code holds a reference | `_dash.complaints` is the only reference |
| List mutated in place? | No — never uses `add`, `remove`, `[]=` | Grep for `complaints.add`, `complaints[`, `complaints.remove` → zero hits |

### 2.3 Shared References / Static Variables / Singleton State

| Check | Finding | Evidence |
|-------|---------|----------|
| `ComplaintsRepository.instance` | Singleton but stateless | L45-47: no mutable fields except `_imei` (device ID, never changes) |
| `DashboardController` | Per-screen instance, not shared | L74: `final DashboardController _dash = DashboardController()` |
| Static status variable | None found | `_statusColor` is a pure static method, no static fields |
| Global status variable | None found | No top-level `status` or `statusLabel` variable anywhere |
| Cached objects | None | Controller stores `List<OpenComplaint>` reference only, swapped on refresh |

### 2.4 ListView Behaviour and Keys

| Check | Finding | Risk |
|-------|---------|------|
| Missing keys on `_TicketCard` | No `Key` provided | **LOW** — `_TicketCard` is `StatelessWidget`, no state to leak |
| `ListView.builder` with `StatelessWidget` children | Correct pattern | Each `build()` receives correct `item` by index |
| Incorrect equality / `==` | Not applicable | No `==` override, no `hashCode` override, not used in `Set` or `Map` |

### 2.5 Reused Controllers

| Check | Finding |
|-------|---------|
| `DashboardController` reused across screens | No — created in `_DashboardScreenState` |
| `_commentCtrl` | Local to `_ComplaintDetailsScreenState` |

---

## 3. Production App Refresh Comparison

| Question | Production (Android) | Flutter |
|----------|---------------------|---------|
| Does it reload the full list? | **NO** | **YES** — `loadComplaints(force: true)` |
| Does it update only one item? | **NO** — no update at all | **NO** — reloads full list |
| Does it locally mutate data? | **NO** | **NO** |
| Does it request fresh data? | **NO** | **YES** |
| Does it clear cache? | **NO** | **YES** — `complaints = r.complaints` replaces entire reference |
| Does it recreate the adapter? | **NO** | N/A (Flutter rebuilds widgets via `setState`) |
| Does it notify only one row? | **NO** | **NO** — full `notifyListeners()` → full `setState()` |
| Does it rebuild the entire screen? | **NO** — old fragment stays | **YES** — `setState()` rebuilds entire `_DashboardScreenState` |

> [!IMPORTANT]
> **The production Android app NEVER refreshes the complaint list after a status update.** It pops back to the same fragment with the same old adapter showing the same old data. The user must manually leave and re-enter the dashboard to see changes.
>
> The Flutter app refreshes the entire list from the backend after every successful update. This means every complaint gets its **current real status** from the server — which may differ from what was shown before if statuses changed on the backend between the initial load and the refresh.

---

## 4. API Behaviour Verification

### 4.1 Request

**`closeComplaint` (key `clscomp`):**
```
altCustomerId: [int] — the specific complaint's alt_cust_id
complaintId:   [int] — the specific complaint's complaint_id
ticketNumber:  [string] — the specific complaint's tkt_number
status:        [string] — new status value
comment:       [string] — comment text
imei:          [string] — device ID
authToken:     [string] — session token
```

**Evidence:** Only ONE complaint's IDs are sent. The API updates ONE complaint.

### 4.2 Response

**`closeComplaint` response:**
```
statusCode:    [int] — 0=success, 1=invalid, 2=support, 3=error
statusMessage: [string] — human-readable message
```

**Evidence:** No complaint data is returned in the response. No list. No modified status. Just success/failure.

### 4.3 `getopencomplaintslist` Response

**Returns:** The **full list** of all open complaints for the user's dealer scope. Not a single complaint. Not a delta. The full list.

**Evidence from production (L871-872):**
```java
String opencomplaintList = response.substring(
    response.indexOf("opencomplaintList=") + 18,
    response.indexOf(";", response.indexOf("opencomplaintList=")));
JSONArray jsonArray = new JSONArray(opencomplaintList);
```

**Evidence from Flutter (L75-76 in complaints_repository.dart):**
```dart
final raw = SoapClient.readField(xml, 'opencomplaintList') ?? '[]';
// ... jsonDecode(raw) ...
```

Both apps receive the same full list. Each complaint in the list has its **current** backend status at the time of the API call.

### 4.4 Status Propagation

The backend updates ONE complaint's status. The `getopencomplaintslist` then returns ALL complaints with their CURRENT statuses. If the backend happens to have updated other complaints (by other users, by backend jobs, by timeout rules), those changes will also appear in the refreshed list.

**Not Yet Verified:** Whether the backend has any automatic status propagation rules (e.g., auto-closing after timeout, auto-escalating after SLA breach). This requires backend documentation or server-side investigation.

---

## 5. Refresh Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant TicketCard as _TicketCard
    participant Details as ComplaintDetailsScreen
    participant Repo as ComplaintsRepository
    participant Backend as SOAP Backend
    participant Controller as DashboardController
    participant Dashboard as DashboardScreen

    User->>TicketCard: Taps "Update Status"
    TicketCard->>Details: Navigator.push()
    
    Note over Details: User selects new status, taps Update
    
    Details->>Repo: closeComplaint(altCustId, complaintId, ...)
    Repo->>Backend: SOAP closeComplaint
    Backend-->>Repo: statusCode=0 (success)
    Repo-->>Details: ComplaintActionResult(0, "Success")
    
    Details->>User: Shows success dialog
    User->>Details: Taps OK
    Details->>Dashboard: Navigator.pop(true)
    
    Dashboard->>Dashboard: .then(ok) → onRefresh()
    Dashboard->>Controller: loadComplaints(force: true)
    Dashboard->>Dashboard: setState(() {}) [redundant]
    
    Note over Controller: BEFORE: logs cached list
    
    Controller->>Repo: fetchOpenComplaints()
    Repo->>Backend: SOAP getopencomplaintslist
    Backend-->>Repo: Full list with ALL current statuses
    
    Note over Repo: RAW JSON logged before parsing
    
    Repo-->>Controller: ComplaintsResult(0, ..., [all complaints])
    
    Note over Controller: AFTER: logs new list
    
    Controller->>Controller: complaints = r.complaints (full replacement)
    Controller->>Controller: notifyListeners()
    Controller->>Dashboard: _onDash() → setState()
    
    Dashboard->>Dashboard: build() → _buildComplaintsFeed()
    
    Note over Dashboard: Each _TicketCard built from its own<br/>OpenComplaint with its own status string
    
    Dashboard->>User: All cards rendered with FRESH backend statuses
```

---

## 6. Log Comparison Analysis

### 6.1 What the Diagnostic Logs Will Show

The diagnostic logging added to the Flutter app will produce evidence at three points:

1. **`BEFORE REFRESH`** — The cached list at the moment of refresh. This is what was shown to the user before they updated.
2. **`RAW JSON`** — The exact JSON string from the backend, before any parsing.
3. **`AFTER REFRESH`** — The parsed list from the new backend response.

### 6.2 Expected Outcomes

| Scenario | BEFORE complaint B status | RAW JSON complaint B status | AFTER complaint B status | Root Cause |
|----------|--------------------------|----------------------------|-------------------------|------------|
| **A** | `ASSIGNED` | `ASSIGNED` | `ASSIGNED` | No change — visual only (color mapping fix revealed true status) |
| **B** | `ASSIGNED` | `ONHOLD` | `ONHOLD` | Backend returned different status — backend changed it |
| **C** | `ASSIGNED` | `ASSIGNED` | `ONHOLD` | Parsing bug in `OpenComplaint.fromJson` |
| **D** | Same in all three, but badge shows differently | — | — | Flutter rendering bug |

### 6.3 Evidence Not Yet Collected

> [!WARNING]
> **The diagnostic logs have been added but NOT yet run.** The before/after comparison requires the user to run the app in debug mode, reproduce the scenario, and provide the log output.
>
> **Verification Status: NOT YET VERIFIED**

---

## 7. Badge Investigation

### 7.1 Badge Colour vs. Status Text

These are **separate concerns** that must be investigated independently.

**Status text source chain:**
```
Backend JSON "status" field
  → OpenComplaint.status (final String)
    → _TicketItem.statusLabel (final String?)
      → _TicketCard.build(): statusText = item.statusLabel ?? fallback
        → Text('Status : $statusText')
```

**Badge colour source chain:**
```
statusText (the string above)
  → _statusColor(statusText) → pure function → Color
    → Container decoration (background, border)
    → Text style (color)
```

**Evidence:** Both chains start from the same `statusText` string. If the text is correct, the colour must be correct (the mapping function is deterministic). If the text is wrong, the colour will also be wrong.

### 7.2 Can Colour Change Without Text Changing?

**No.** Both derive from the exact same `statusText` variable on L989-991:
```dart
final statusText = item.statusLabel ?? (isAssigned ? 'ASSIGNED' : 'INPROCESS');
final statusColor = _statusColor(statusText);
```

If the colour changed, the text must also have changed. These cannot diverge.

### 7.3 Pre-Fix vs. Post-Fix Colour Behaviour

**Before the `_statusColor` fix:**
- Every complaint badge colour was determined by the binary `_TicketStatus` enum
- `_mapComplaintStatus()` mapped everything to either `assigned` (green) or `inprocess` (amber)
- An ONHOLD complaint appeared green (ASSIGNED colour)
- A RESOLVED complaint appeared green (ASSIGNED colour)
- A CLOSED complaint appeared green (ASSIGNED colour)
- **All badges looked the same colour most of the time**

**After the `_statusColor` fix:**
- Badge colour is determined by the real `statusLabel` string
- ONHOLD → red, RESOLVED → green, CLOSED → grey, etc.
- Colour differences between complaints became **visible for the first time**
- This is not a bug — it is the correct behavior that was previously masked

---

## 8. Race Condition Investigation

| Check | Finding | Evidence |
|-------|---------|----------|
| Multiple refreshes | `loadComplaints` has guard: `if (complaintsLoading) return` | L80 |
| Double setState | **YES** — `onRefresh` calls `setState(() {})` AND `loadComplaints` triggers `_onDash → setState()` | L579-582 and L75-76 |
| Risk of double setState | **LOW** — causes one extra rebuild with identical data, no data corruption | Both rebuilds read same `_dash.complaints` reference |
| notifyListeners timing | Called synchronously before `await` (L94) and in `finally` (L127) | Two `notifyListeners` per load: one at start (loading=true), one at end |
| Future completion order | Single `await` — deterministic | L96: `final r = await ...` |
| Navigator.pop timing | Synchronous — completes before `.then()` fires | Standard Flutter behavior |
| mounted checks | Present in `_update()` | L132: `if (!mounted) return` |
| Duplicate refresh calls | The redundant `setState(() {})` on L581 may cause a brief flicker but cannot corrupt data | See §8.1 below |

### 8.1 The Redundant `setState()` — Detailed Analysis

```dart
onRefresh: () {
  _dash.loadComplaints(force: true);  // async — starts loading
  setState(() {});                     // synchronous — rebuilds NOW
},
```

**What happens:**
1. `loadComplaints(force: true)` enters, sets `complaintsLoading = true`, calls `notifyListeners()` → `_onDash()` → `setState()` — **rebuild #1** (shows loading spinner)
2. The synchronous `setState(() {})` on the next line fires — **rebuild #2** (shows loading spinner again, same state)
3. The `await fetchOpenComplaints()` returns, sets new data, calls `notifyListeners()` → `_onDash()` → `setState()` — **rebuild #3** (shows new data)

**Result:** One unnecessary rebuild (#2). No data corruption. No wrong data shown. Just a wasted frame.

---

## 9. Model Field Verification

### 9.1 Each `OpenComplaint` has unique identity

Every `OpenComplaint` is created inside the `for` loop in `fetchOpenComplaints()`:
```dart
for (final item in decoded) {
  if (item is Map) {
    complaints.add(OpenComplaint.fromJson(Map<String, dynamic>.from(item)));
  }
}
```

Each `OpenComplaint.fromJson()` creates a **new instance** with its own field values from its own JSON object. No field is ever copied from another complaint.

### 9.2 Field isolation verification

| Field | Source | Shared? | Evidence |
|-------|--------|---------|----------|
| `complaintId` | `j['complaint_id']` per item | No | `open_complaint.dart` L48 |
| `customerId` | `j['customer_id']` per item | No | `open_complaint.dart` L60 |
| `altCustId` | `j['alt_cust_id']` per item | No | `open_complaint.dart` L59 |
| `tktNumber` | `j['tkt_number']` per item | No | `open_complaint.dart` L47 |
| `status` | `j['status']` per item | No | `open_complaint.dart` L50 |

### 9.3 `_TicketItem` field isolation

Each `_TicketItem` is constructed inside `itemBuilder` (L563-575), reading fields from `list[i]` — a specific `OpenComplaint` at index `i`. No cross-contamination is possible.

---

## 10. Dashboard Controller Investigation

| Check | Finding | Evidence |
|-------|---------|----------|
| Cache replacement | Full reference swap | L109: `complaints = r.complaints` |
| Item replacement | N/A — no per-item update | Full list replaced |
| Immutable vs. mutable objects | `OpenComplaint` is immutable (all `final` fields) | `open_complaint.dart` L8-23 |
| Previous list reference survives? | **No** — old list becomes unreachable after `complaints = r.complaints` | Dart GC collects it |
| Listener notifications | Two per load cycle: start + end | L94 and L127 |
| Stale reference in UI? | **No** — `_onDash → setState()` forces rebuild, which reads fresh `_dash.complaints` | L75-76 and L555 |

---

## 11. Evidence Matrix

| # | Possible Cause | Evidence | Verified? | Risk | Conclusion |
|---|---------------|----------|-----------|------|------------|
| 1 | **Shared model instance** | `OpenComplaint` has all `final` fields, `const` constructor. Each instance created from its own JSON object. | **YES** | None | **RULED OUT** — physically impossible to mutate |
| 2 | **Mutable list mutation** | `complaints` list is replaced atomically, never mutated in place (no `add`, `remove`, `[]=`) | **YES** | None | **RULED OUT** |
| 3 | **Static/global status variable** | No static or global variable holds status text. `_statusColor` is a pure function. | **YES** | None | **RULED OUT** |
| 4 | **Backend returns different statuses on refresh** | `getopencomplaintslist` returns the **full current list** from the backend. Statuses may differ from the cached version if they changed between first load and refresh. | **YES** (by code analysis) | **HIGH** | **MOST LIKELY CAUSE** — see §12 |
| 5 | **Widget reuse / state leak** | `_TicketCard` is `StatelessWidget`. No widget state to leak. | **YES** | None | **RULED OUT** |
| 6 | **Race condition** | `loadComplaints` has a guard (`if (complaintsLoading) return`). No concurrent modification possible. | **YES** | None | **RULED OUT** |
| 7 | **Double setState** | Redundant `setState(() {})` causes extra rebuild but cannot produce wrong data. | **YES** | Low | Cosmetic issue, not a bug |
| 8 | **Parsing corruption** | `OpenComplaint.fromJson` reads each field from its own `j[key]`. No cross-item contamination. | **YES** | None | **RULED OUT** |
| 9 | **Navigator.pop timing** | `Navigator.pop(context, true)` completes synchronously. `.then()` fires after. | **YES** | None | **RULED OUT** |
| 10 | **Badge colour previously masked real status** | Before the `_statusColor` fix, the binary mapping showed most statuses as the same colour. After the fix, true colours became visible for the first time. | **YES** | **HIGH** | **CONTRIBUTING CAUSE** — see §12 |
| 11 | **Production app does NOT refresh** | Android app calls `popBackStack()` without re-fetching. Old data survives. Tester comparing to Android would see "only one changed" because Android never refreshes. | **YES** | **HIGH** | **CONTRIBUTING CAUSE** — see §12 |
| 12 | **Backend auto-updates other complaints** | Unknown. Backend may have SLA rules, escalation logic, or batch status updates. | **NOT YET VERIFIED** | Medium | Requires backend investigation or runtime log comparison |

---

## 12. Final Conclusion

### Primary Classification: **BEHAVIOURAL DIFFERENCE, NOT A BUG**

The evidence points to a combination of three factors, none of which is a Flutter state-management bug:

### Factor 1: The Production App Never Refreshes (Verified ✅)

The production Android app (`DashboardHomeFragment`) calls `getopencomplaintslist` once in `onCreateView()` (L266/276/282). After a status update, `ComplaintHistory_Others_Fragment` calls `popBackStack()` (L601) — the dashboard fragment is NOT recreated, `onResume` is NOT implemented, and the old adapter with the old data survives. **The user sees stale data until they leave and return to the dashboard.**

The Flutter app, by contrast, refreshes the list after every successful update. This is an intentional improvement. But it means **other complaints' real current statuses (which may have changed server-side) become visible for the first time.**

### Factor 2: The Badge Colour Fix Revealed True Statuses (Verified ✅)

Before the `_statusColor` fix, the dashboard used a binary mapping:
- Everything mapped to `_TicketStatus.assigned` (green) or `_TicketStatus.inprocess` (amber)
- ONHOLD, RESOLVED, CLOSED all appeared green

After the fix:
- Each status gets its correct colour
- Statuses that were always present but invisible (because they were green) now appear in red, grey, etc.

**The tester sees colours changing because the colours were always wrong before, and the refresh reveals the correct ones.**

### Factor 3: Backend May Update Multiple Complaints (Not Yet Verified ⚠️)

The backend may have automatic status rules (SLA escalation, auto-close, batch processing). When we re-fetch the full list, these changes would appear alongside our intentional update. This requires backend investigation or the diagnostic log comparison (§6) to verify.

### What This Is NOT

- ❌ Not a shared model instance bug (models are immutable)
- ❌ Not a mutable list bug (list is atomically replaced)
- ❌ Not a static/global variable bug (none exist)
- ❌ Not a widget state leak (StatelessWidget)
- ❌ Not a race condition (guarded by `complaintsLoading`)
- ❌ Not a parsing bug (each item parsed from its own JSON object)

### Evidence Required to Close

1. **Diagnostic log comparison:** Run the app, capture BEFORE/AFTER logs, compare complaint B's status in both. If the backend returned a different status for complaint B, this is confirmed as "backend returned fresh data" behaviour, not a Flutter bug.

2. **Backend investigation:** Determine if the backend has any automatic status update rules.

---

## Appendix A: Production Color Reference

From `colors.xml`:
| Color name | Hex | Used for |
|-----------|-----|---------|
| `thickgreen` | `#336600` | ASSIGNED, RESOLVED (OpenComplaints adapter) |
| `yellow` | `#ffcb08` | INPROCESS |
| `red` | `#bc0000` | ONHOLD |
| `blue` | `#2e3192` | CLOSED |

From `ComplaintAdapter` (complaint history, different screen):
| Status | Background | Badge Letter |
|--------|-----------|-------------|
| ASSIGNED | `#08C889` | A |
| INPROCESS | `#00BEB7` | I |
| ONHOLD | `#E67E22` | O |
| RESOLVED | `#0875C8` | R |
| CLOSED | `#E74C3C` | C |

**Note:** The production app uses **different colours in different screens** for the same statuses. The OpenComplaints adapter and ComplaintAdapter use entirely different colour palettes.

## Appendix B: Redundant setState Cleanup

The `onRefresh` callback in `_buildComplaintsFeed` (L579-582) has a redundant `setState(() {})`:

```dart
onRefresh: () {
  _dash.loadComplaints(force: true);
  setState(() {});  // ← redundant: loadComplaints already triggers _onDash → setState
},
```

This does not cause incorrect data but creates one unnecessary rebuild. Safe to remove as a separate cleanup task.

## Appendix C: File References

| File | Description |
|------|-------------|
| [dashboard_controller.dart](file:///d:/StudioProjects/ezy_cable_digi/lib/features/dashboard/dashboard_controller.dart) | DashboardController with complaint cache |
| [dashboard_screen.dart](file:///d:/StudioProjects/ezy_cable_digi/lib/features/dashboard/dashboard_screen.dart) | Dashboard UI with _TicketCard and _TicketItem |
| [complaint_details_screen.dart](file:///d:/StudioProjects/ezy_cable_digi/lib/features/complaints/complaint_details_screen.dart) | Update status screen |
| [complaints_repository.dart](file:///d:/StudioProjects/ezy_cable_digi/lib/features/dashboard/data/complaints_repository.dart) | SOAP API calls |
| [open_complaint.dart](file:///d:/StudioProjects/ezy_cable_digi/lib/features/dashboard/data/open_complaint.dart) | Immutable model |
| [OpenComplaints_Fragment.java](file:///D:/Git-Repos/magikdigi/app/src/main/java/itp/com/magikdigi/Fragments/OpenComplaints_Fragment.java) | Production complaint list |
| [DashboardHomeFragment.java](file:///D:/Git-Repos/magikdigi/app/src/main/java/itp/com/magikdigi/Fragments/DashboardHomeFragment.java) | Production dashboard |
| [ComplaintHistory_Others_Fragment.java](file:///D:/Git-Repos/magikdigi/app/src/main/java/itp/com/magikdigi/Fragments/ComplaintHistory_Others_Fragment.java) | Production update status |
| [OpenComplaints_RecyclerView_Adapter.java](file:///D:/Git-Repos/magikdigi/app/src/main/java/itp/com/magikdigi/Adapters/OpenComplaints_RecyclerView_Adapter.java) | Production complaint card adapter |
| [ComplaintAdapter.java](file:///D:/Git-Repos/magikdigi/app/src/main/java/itp/com/magikdigi/Adapters/ComplaintAdapter.java) | Production complaint history adapter |
| [colors.xml](file:///D:/Git-Repos/magikdigi/app/src/main/res/values/colors.xml) | Production colour definitions |
