# BROADBAND PAYMENT FLOW

**Status:** 📘 **Documentation / investigation only — NOT implemented, NOT live-tested.** Broadband is out
of the current STB-cash release scope. **No code is written until this document is reviewed and the 🔴/🟡
items are closed by live testing.**

## Verification taxonomy (strict)
- ✅ **Verified by live testing** — confirmed with real logs + backend + database in *this* project. **Broadband currently has NONE of these.**
- 🟡 **Verified from existing application logic only** — derived from how the existing app builds the request / drives the UI. Strong, but **not proven** for our client until live-tested.
- 🔴 **Not yet verified** — backend-internal or otherwise unconfirmed; **must not be assumed**.

> Rule: a 🟡 item is **never** upgraded to ✅ without an actual live test (logs + backend + DB).
> ⚠️ **Everything in this document is 🟡 or 🔴. Nothing about broadband is ✅ yet.**

> No real customer identifiers, receipt numbers, tokens, or device values appear in this document.

---

## 0. Verification status at a glance

| Area | Status |
|---|---|
| Customer-type detection (STB / Broadband / Both) | ✅ live-verified (isBroadband + bbUserId from search) |
| Broadband pending source (from GPA `broadcaster_pending_amount`) | ✅ live-verified (parsed; 0 = real for tested customers) |
| Broadband request fields + when they are sent | ✅ live-verified (bbAmount/bbUser/bbDue/renewal sent; STB amount=0) |
| Send → staging row created | ✅ live-verified (our ₹1 = staging_id 58) |
| `billing_id = 0` for broadband | ✅ live-verified |
| Live response shape | ✅ live-verified: `status=0`, `receipt=NA` (deferred) |
| `broadband_payment_staging` schema | ✅ live-verified (see §9) |
| Renewal flag behaviour (client side) | 🟡 logic (sent as is_renewal; backend effect 🔴) |
| UI validation rules | 🟡 logic (STB amount check skipped for BB) |
| **Settlement (staging → detail → receipt)** | 🔴 **NOT verifiable on test** — all staging rows stuck at `staging_status=1`, `broadband_payment_id=0`; production-only |
| Broadband receipt format + timing (detail table) | 🔴 not verified (production-only; deferred) |
| Retry / failure handling (backend) | 🔴 not verified |
| Renewal flag backend effect | 🔴 not verified |

**Verified live (2026-06-26):** a ₹1 broadband payment on a broadband-only customer returned `status=0`,
`receipt=NA`, and created one `broadband_payment_staging` row (`staging_status=1`, `paid_amount=1.00`,
`billing_id=0`, `payment_mode=Cash`, `remarks=broadband payment`, linked by `stb_customer_id` +
`broadband_customer_id`). The broadband pending (`broadcaster_pending_amount`) was unchanged afterwards —
consistent with deferred settlement. **No staging row on this server has ever settled** (all
`staging_status=1`, no `broadband_payment_details` rows) → settlement is a production-only path we cannot
verify here.

---

## 1. Customer types & detection 🟡

The customer record carries a **customer type** indicator:

| customer_type | Meaning | Broadband fields used |
|---|---|---|
| 0 | STB only | No |
| 1 | Broadband only | Yes |
| 2 | STB **and** Broadband | Yes (both STB + broadband) |

- A **broadband account identifier** (`broadband_user_id`) travels with the customer record from search.
- For STB-only (type 0) it is treated as empty → **all broadband UI and request fields are suppressed**.
- For type 1 or 2, the broadband account id is present → broadband amount field + **renewal checkbox**
  become visible.

> 🟡 Master switch: **"is this a broadband payment?" = "is the broadband account id non-empty?"**
> (logic-only; confirm live that our client reads `customer_type` / `broadband_user_id` correctly.)

---

## 2. Pending retrieval (GPA) — broadband portion 🟡

The same Pending Retrieval (GPA) call used for STB also returns the broadband pending:

| GPA field | Drives | Notes |
|---|---|---|
| `cable_pending_amount` | The **STB** amount owed (the main amount field) | rounded per the tenant's rounding mode (ACTUAL / ROUND / CEIL) |
| `broadcaster_pending_amount` | The **broadband** amount owed (the broadband amount field) | same rounding mode |

- If `broadcaster_pending_amount > 0`, the **broadband amount field is prefilled** with it; else blank.
- Rounding mode is a tenant/login setting applied to both pending values.

> 🟡 Logic-only. (Note: GPA itself is ✅ live-verified for STB; the **broadband fields** of the GPA
> response have not been exercised live → 🟡 until a broadband customer is tested.)

---

## 3. Broadband amount calculation 🟡 / 🔴

- 🟡 The **broadband amount to collect** = the broadband amount field — **prefilled from
  `broadcaster_pending_amount`**, editable (max 7 chars, 2 decimals).
- 🔴 **No discount on the broadband amount** — discount logic targets the STB/cable portion only.
  *Confirm against backend that a broadband row never carries a discount.*
- 🟡 Post-payment display: **broadband outstanding = broadcaster_pending_amount − broadband paid**
  (display only; authoritative balance is the next GPA read).

---

## 4. Request contract — broadband-specific fields 🟡 (population) / 🔴 (server effect)

Broadband uses the **same** payment-submission request as STB (full field set). The broadband-specific
fields are populated **only when the broadband account id is non-empty**; otherwise empty/zero (as for STB-only).

| Field | Purpose | Source / value | When populated | Status |
|---|---|---|---|---|
| `broadband_payment_amount` | Broadband amount being paid (numeric) | broadband amount field | broadband only; else `0.0` | 🟡 |
| `broadband_user_id` | Broadband account being paid | customer's broadband account id | broadband only; else empty | 🟡 |
| `broadband_due` | Broadband amount owed at payment time | `broadcaster_pending_amount` (as text) | broadband only; else empty | 🟡 |
| `is_for_renewal` | Whether this is a renewal | renewal checkbox → `"1"`/`"0"` | broadband only; else empty | 🟡 client / 🔴 effect |
| `billingId` | Bill to settle | from GPA | always sent | 🔴 value for broadband |
| `amount` | The **STB** amount (0 for broadband-only) | main amount field | STB portion | 🟡 |
| `payment_flag` | Channel marker = `4` | constant | always | 🟡 |
| (all other standard fields) | per the STB contract | — | always | ✅ for STB / 🟡 here |

**Key points:**
- 🟡 The four broadband fields are sent **only** for broadband customers.
- 🟡 For **broadband-only**, the **STB `amount` is 0** and the broadband amount carries the payment.
- 🟡 For **combined** (type 2), **both** `amount` and `broadband_payment_amount` can be non-zero in one
  submission (see `STB_BROADBAND_COMBINED_PAYMENT.md`).
- 🔴 `billing_id` value for a broadband-only customer (an earlier DB sample suggested broadband **detail
  rows** store `billing_id = 0`, but the request value **and** the stored value must both be confirmed live).

---

## 5. Renewal behaviour (`is_for_renewal`) 🟡 client / 🔴 backend

- 🟡 A **renewal checkbox** is shown only for broadband customers; checked → `"1"`, else `"0"`.
- 🔴 The backend effect of the renewal flag (extending the subscription period vs. plain balance payment)
  is **Not yet verified**.

---

## 6. UI validation rules 🟡

From the existing make-payment validation:

- STB amount checks are **skipped for broadband-only** (the "≥ 1 / not empty" rules are STB-only).
- For a **broadband customer**, the broadband amount must be valid (empty/invalid → rejected).
- **Partial-payment restriction** (a tenant login setting) applies **only to STB**.
- **Discount validation** (max-% cap) is evaluated on the STB/cable pending only.
- **Network presence** is checked before submission.

> 🟡 Logic-only; re-verify each rule live on a broadband customer.

---

## 7. Settlement lifecycle (staging → third-party → settled) 🔴 Not yet verified

> **Highest-risk, least-verified part.** The app only **sends** the payment; staging/third-party/settlement
> is backend-internal, seen only in an **earlier DB sample**, not reproduced live. **All of §7 must be
> confirmed before implementation.**

Working model to verify (do **not** treat as fact):
1. Broadband payment first written to a **staging area** with an in-progress status.
2. A backend process calls a **third-party broadband API**.
3. On success → a **broadband payment detail** record with a server receipt; on failure → retried / marked failed.

Confirm: status values, retry counters, failure-message capture, the trigger from staging→detail, and the
**latency** between submission and settlement.

---

## 8. Receipt generation — ✅ response behaviour verified · 🔴 settlement receipt production-only

Live-verified (2026-06-26):
- **Broadband-only payment** (no STB leg): response `receipt=NA` — the broadband leg stages; the real
  receipt is issued later at settlement (production-only). ✅
- **Combined payment** (STB + broadband in one submission): response returns a **real STB receipt**
  (`CR{dealer}/…`) immediately for the STB leg, while the **broadband ₹ stages separately** (deferred).
  So a combined receipt carries a real number from the STB leg; the broadband portion settles async. ✅
- **On-screen receipt parity (Milestone C) ✅:** the receipt now shows, matching the existing app —
  broadband-only → *Broadband User Id* + *Broadband Paid*; combined → additionally *STB Paid* + *Total
  Paid*; the receipt number is shown as-is (`NA` for broadband-only, real for combined).

Still 🔴 (production-only): the broadband **detail-table receipt** (format/timing) after third-party
settlement — never settles on the test server.
- ⚠️ Implementation must **not** assume an immediate broadband receipt for the broadband-only case.

**PDF / thermal-print receipt:** the broadband fields are added to the **on-screen** receipt only so far;
the printed receipt parity is pending (tracked under the broader Receipt-parity task).

---

## 9. Backend tables affected 🔴 Not yet verified

| Table (working assumption) | Expected role | Status |
|---|---|---|
| broadband staging table | First write on submission; status/retry/failure | 🔴 confirm name + columns |
| broadband payment detail table | Final record on success; holds server receipt | 🔴 confirm name + columns |
| STB payment-detail table | Only for the STB portion of a combined payment | ✅ (STB side, live-verified) |

🔴 Confirm whether broadband touches STB billing/balance tables at all, or is fully separate.

---

## 10. Sequence diagram (🔴 dashed steps unverified)

```
Collector                App                         Backend                     3rd-party BB API
   │                       │                            │                                │
   │ open broadband cust   │                            │                                │
   │──────────────────────▶│  GPA (pending)             │                                │
   │                       │───────────────────────────▶│                                │
   │                       │◀── cable + broadcaster ────│                                │
   │ enter BB amount,      │     pending                │                                │
   │ (optional renewal)    │                            │                                │
   │ tap Pay ──────────────▶│  payment submission        │                                │
   │                       │   (broadband_* fields set) │                                │
   │                       │───────────────────────────▶│                                │
   │                       │              🔴 write STAGING row (in-progress)              │
   │                       │◀── status (🔴 receipt? ) ──│                                │
   │                       │              🔴 call BB API ───────────────────────────────▶│
   │                       │                            │◀──────── result ───────────────│
   │                       │              🔴 on success: DETAIL row + receipt             │
   │                       │              🔴 on fail: retry / mark failed                 │
   │ re-open customer ─────▶│  GPA (read-after-write)    │                                │
   │                       │◀── updated broadcaster ────│                                │
   │                       │     pending                │                                │
```

---

## 11. Backend verification queries (to run during live testing)

> Table/column names are **working assumptions from an earlier sample** — confirm with the senior before
> relying on them. Never run against production data.

```sql
-- A) Staging row created on submission (confirm table + columns first)
SELECT *
FROM   broadband_payment_staging
WHERE  broadband_customer_id = <bb customer key>
ORDER  BY 1 DESC LIMIT 1;     -- expect an in-progress status + retry counter

-- B) Final broadband detail row after settlement (confirm table + columns first)
SELECT receipt_no, paid_amount, billing_id, broadband_user_id
FROM   broadband_payment_details
WHERE  broadband_customer_id = <bb customer key>
ORDER  BY 1 DESC LIMIT 1;     -- expect a server receipt; confirm billing_id value

-- C) Read-after-write: re-run GPA in the app; compare broadcaster_pending_amount before/after
```

---

## 12. Expected database changes (🔴 to confirm live)

| Step | Expected change | Status |
|---|---|---|
| On submission | One staging row (in-progress) | 🔴 |
| On settlement success | One detail row with server receipt | 🔴 |
| On settlement failure | Staging row marked failed / retried; **no** detail row | 🔴 |
| Balance | `broadcaster_pending_amount` drops by the amount paid (after settlement) | 🔴 timing |

---

## 13. Expected API responses 🔴 Not yet verified

- Immediate response shape for a broadband/combined submission is **unknown** (status only? + deferred
  reference? + receipt?). **Capture live before implementation** so parsing is built from a real response.

---

## 14. Error scenarios & required handling (mandatory at implementation)

| Scenario | Required behaviour |
|---|---|
| Network failure on submit | No success assumed; clear message; no receipt; no UI inconsistency |
| SOAP / transport failure | Caught; clear message; no receipt |
| Malformed / empty response | Parsed defensively (missing fields → safe defaults); never crash |
| Invalid / unexpected status code | Treated as failure; backend message surfaced; no receipt |
| Duplicate submission | Blocked by in-flight guard (one staging row max) |
| Timeout | Treated as unknown/failed; **must not** assume success; guide collector to re-check via GPA before re-paying |
| Backend validation failure | Surface backend message; no receipt |
| Third-party settlement failure (async) | Surfaced per the (🔴) staging/failure model; collector told it is pending/failed, not "paid" |

⚠️ **Timeout + async settlement is the central risk.** Never show a confirmed receipt unless settlement is
confirmed; steer the collector to verify via GPA rather than blindly re-pay.

---

## 15. Production risks

1. 🔴 **Async settlement / deferred receipt** — biggest risk; timing + UX unverified.
2. 🔴 **Double payment via timeout** — retry on timeout while staging already accepted. Needs idempotency + re-check-before-retry.
3. 🔴 **Receipt format** differs from STB and is unverified.
4. 🔴 **Renewal semantics** — wrong `is_for_renewal` could mis-renew.
5. 🔴 **billing_id** value for broadband unverified.
6. 🔴 **Partial broadband payment** support unverified.
7. 🔴 **Combined customers** (type 2) add ordering/settlement complexity (separate document).

---

## 16. Testing checklist (broadband-only customer, test server, tiny amount)

- [ ] Customer type detected as broadband; broadband amount field + renewal checkbox visible.
- [ ] GPA prefills the broadband amount from `broadcaster_pending_amount`.
- [ ] Submission sends `broadband_payment_amount`, `broadband_user_id`, `broadband_due`, `is_for_renewal`
      correctly; STB `amount = 0`.
- [ ] Capture the **live response** shape (status, receipt present or not).
- [ ] Query (A): a staging row is created.
- [ ] Query (B): a detail row + server receipt appears after settlement; note the latency.
- [ ] Read-after-write: `broadcaster_pending_amount` drops by the amount paid.
- [ ] Renewal on/off produces the correct backend effect.
- [ ] Network-fail / timeout / malformed-response handled with no crash, no false receipt.
- [ ] Behaviour compared against the existing application for the same customer.

> Each ticked + evidenced item upgrades the matching section from 🟡/🔴 to ✅.

---

## 17. Definition of Done (12-step — feature stays "In Progress" until all true)

1. Existing implementation investigated — 🟡 done (this doc)
2. API contract verified — 🟡 request fields / 🔴 response shape (capture live)
3. Backend behaviour verified — 🔴
4. Database behaviour verified — 🔴
5. Documentation completed — 🟡 (this doc; revise as items are tested)
6. Flutter implementation completed — ⬜
7. Static analysis clean — ⬜
8. Manual testing completed — ⬜
9. Error handling verified — ⬜
10. Compared against the existing application behaviour — ⬜
11. Backend data verified — ⬜
12. User explicitly approves — ⬜

---

## 18. Open items to close before implementation (the 🔴 list)

1. Capture a **live broadband payment** request + response (shape, receipt presence).
2. Confirm the **staging table** name, columns, and status lifecycle.
3. Confirm the **detail table** name, columns, receipt format, and `billing_id` value.
4. Confirm **settlement latency** and the **retry/failure** model.
5. Confirm the **renewal flag** backend effect.
6. Confirm **partial-payment** support for broadband.
7. Confirm **idempotency** (timeout double-submit safety) for the async path.

**Until these are closed, broadband stays documented-only and unimplemented.**
