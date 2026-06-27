# PAYMENT EXECUTION PLAN

**Governing document:** `PAYMENT_FLOW_SPEC.md` (the payment source of truth). This plan does not add new
behaviour — it sequences the work needed to **verify and finish** the payment feature within the deadline
with minimum production risk.

**Operating rules (carried from this task):** no assumptions; no "complete" without runtime verification;
no behaviour inferred from source alone; no backend behaviour inferred without evidence.

**Legend:** 🔴 Critical blocker · 🟠 High risk · 🟡 Medium risk · ⚪ Can defer

> ✅ **Phase A / G1 VERIFIED.** A successful STB cash payment was reproduced through the new client on a
> positive-due customer: `statusCode=0` + server receipt + a matching `acc_payment_details` row
> (`payment_flag=4`, amount + receipt + billing id consistent). H1 confirmed (the earlier "No records
> found" was the partial request; the full 28-field request fixed it). Remaining: read-after-write
> pending-reduction glance (G9), then discount parity (G4) + hardening (G8/G10).

---

## 1. Open Evidence Gaps (from PAYMENT_FLOW_SPEC.md)

| # | Gap | Spec ref |
|---|---|---|
| G1 | No successful payment reproduced through the new client (STB, positive-due). | Gaps #1 |
| G2 | Advance/credit customer: is "No records found" the correct response, or does production take an advance? | Gaps #2 |
| G3 | Zero-due customer behaviour on a payment attempt. | Gaps #3 |
| G4 | Maximum-discount-% value + source (login-provided) + backend validation. | Gaps #4 |
| G5 | Broadband end-to-end: staging → third-party → settled timing, receipt format, rows. | Gaps #5 |
| G6 | STB + Broadband combined: discount, receipt, combined rows. | Gaps #6 |
| G7 | Other payment modes (bank/cheque, card): fields + behaviour. | Gaps #7 |
| G8 | Server idempotency / double-submit behaviour. | Gaps #8 |
| G9 | STB billing balance reduction (before/after rows). | Gaps #9 |
| G10 | Status-code map for non-zero codes other than 1 and 3. | Gaps #10 |

---

## 2. Gap Categorisation

| Category | Gaps | Rationale |
|---|---|---|
| 🔴 **Critical blocker** | **G1** | Without a verified STB success, there is no shippable payment feature. |
| 🟠 **High risk** | **G2, G4, G8** | G2 = wrong handling of credit accounts (refuse a valid payment, or take a wrong one). G4 = discount is money; a wrong cap can over-discount. G8 = double-charge risk (mitigated by the client guard, but server behaviour unconfirmed). |
| 🟡 **Medium risk** | **G3, G9, G10** | G3 = edge case, low frequency. G9 = correctness confirmation (the success response already proves application; this confirms the ledger). G10 = better error messaging. |
| ⚪ **Can defer** | **G5, G6, G7** | Deferrable **only if** the launch scope is **STB cash**. If broadband or non-cash customers must transact at launch, G5/G7 promote to 🔴. **Scope decision required from you.** |

**✅ SCOPE DECISION (locked):** the first release is **STB + Cash only**. Broadband (G5), STB+Broadband
combined (G6), card/bank modes (G7), and advanced discount scenarios are **follow-up phases** unless found
mandatory for release. **No further feature work until Phase A (G1) is verified.**
→ G5/G6/G7 deferred. Active focus: **G1**, then G4 (discount parity, STB) and G8/G10 (hardening).

---

## 3. Fastest Safe Implementation Sequence

Assuming the recommended **STB-cash-first** scope:

```
0. Collect Phase-A evidence (E1, E2, E3, E9)         ← you + senior, in parallel with nothing blocking
1. Phase A — STB cash success validation              ← the release-critical path
2. Phase D(partial) — STB discount parity (E4)        ← money correctness, small add-on to A
3. Harden — double-submit + failure messaging (G8,G10)
4. Phase B — Broadband (E5) [follow-up release]
5. Phase C — STB + Broadband (E6) [follow-up release]
6. Phase D(full) — other modes + edge cases (G3,G7) [follow-up]
```

The code for STB cash (full request contract, server-receipt-only, double-submit guard, discount
auto-recalc) already exists and is analyzer-clean; Phase A is therefore **verification-led**, not
build-led. The first action is evidence, not code.

---

## 4. Evidence Still Needed From You

| ID | Evidence | Unblocks | Priority |
|---|---|---|---|
| E1 | Production payment on a **positive-due STB** customer: request + response | G1, Phase A | 🔴 first |
| E2 | Production payment attempt on the **advance/credit** customer | G2 | 🟠 |
| E3 | Backend payment-detail **row** after a test payment | G1, G9 | 🔴 |
| E4 | The **max-discount-%** value + where login provides it | G4, Phase D | 🟠 |
| E9 | Backend **billing balance** before/after a test payment | G9 | 🟡 |
| E5 | Broadband **staging + detail** rows + timing (only if broadband in scope) | G5, Phase B | scope |
| E6 | Zero-due customer behaviour in production | G3 | 🟡 |

---

## 5. Evidence Collection Procedures

> For every item: the production-app action to run, the backend query to execute, and the exact expected
> result. Use the **test/non-production server** and a **disposable customer + tiny amount**. Where a
> column name is an assumption, it is marked — confirm it against the actual schema before relying on it.

### E1 — Positive-due STB payment (production app)
- **App test:** open the production app → search the positive-due test customer (e.g. the one showing a
  positive amount owed) → Make Payment → pay a **tiny** amount (e.g. ₹1) in **cash** → capture the
  payment request log and the payment response log.
- **Capture:** the full request field set + the full response.
- **Expected result:** response **status = 0**, a **server receipt number** present, an amount equal to
  what was paid, and bill metadata (bill number, dealer name, bill-for month). This is the golden
  reference Phase A must reproduce byte-comparable.

### E2 — Advance/credit customer payment (production app)
- **App test:** in the production app, open the **credit customer** (the one whose pending shows a
  negative balance) → attempt a tiny cash payment → capture request + response.
- **Expected result (decision):**
  - If production returns **status = 0** with an advance receipt → the new client must support advance
    payments (and G2 becomes an implementation item).
  - If production also returns **"No records found"** → "No records found" is the **correct** behaviour
    for credit customers, and the new client is already correct; we only need a friendlier message.

### E3 — Payment-detail row (backend)
- **Backend query (run after a successful test payment):**
  ```sql
  SELECT customer_id, dealer_id, employee_id, billing_id, paid_on, payment_mode,
         paid_amount, receipt_no, payment_flag, is_discount, discount_penalty_flag,
         adv_payment_flag, master_transaction_no, latitude, longitude
  FROM   acc_payment_details
  WHERE  customer_id = <test customer key>
  ORDER  BY paid_on DESC
  LIMIT  1;
  ```
- **Expected result:** exactly **one** new row; `payment_flag = 4`; `paid_amount` = the tiny amount;
  `receipt_no` = the server receipt from the response; `master_transaction_no` empty; `adv_payment_flag`
  = 0 for a normal positive-due payment.

### E4 — Maximum-discount-% (login + backend)
- **App test:** log in on the production app as the test dealer; capture the login response and note the
  field that carries the maximum-discount-percent allowed (and the discount-enabled flag).
- **Backend query (confirm the dealer's configured limit — table/column to confirm):**
  ```sql
  -- Confirm the actual table/column with the senior; example shape:
  SELECT max_discount_percent_allowed, payment_discount_enabled
  FROM   <dealer/role settings table>
  WHERE  dealer_id = <test dealer id>;
  ```
- **Expected result:** a specific integer percentage (e.g. 100) and an enabled flag. This is the value the
  client must source from login rather than hard-code.

### E9 — Billing balance before/after (backend)
- **Backend query (run immediately before and after a test payment):**
  ```sql
  -- Column name for the outstanding balance to be confirmed with the senior.
  SELECT billing_id, <outstanding_balance_column>
  FROM   acc_billing
  WHERE  billing_id = <billing id from Pending Retrieval>;
  ```
- **Expected result:** the outstanding balance **decreases by exactly the amount paid** between the two
  reads.

### E5 — Broadband staging + settlement (backend, only if broadband in scope)
- **App test:** pay a broadband test customer a tiny broadband amount in the production app.
- **Backend queries:**
  ```sql
  -- 1) staging row appears immediately
  SELECT broadband_payment_id, broadband_customer_id, stb_customer_id, staging_status,
         tries, staging_retrying, failed_message, due_from_bb, receipt_from, is_renewal
  FROM   broadband_payment_staging
  WHERE  broadband_customer_id = <bb customer id>
  ORDER  BY broadband_payment_id DESC LIMIT 1;

  -- 2) final detail row appears after third-party settlement
  SELECT receipt_no, paid_amount, billing_id
  FROM   broadband_payment_details
  WHERE  broadband_customer_id = <bb customer id>
  ORDER  BY 1 DESC LIMIT 1;
  ```
- **Expected result:** staging row first (`staging_status` = pending/in-progress); later a detail row with
  a server receipt and **`billing_id = 0`**. Note the elapsed time between the two (settlement latency).

### E6 — Zero-due customer (production app)
- **App test:** open a customer whose pending = 0 in the production app → attempt a payment → capture the
  response (or note if the app blocks payment entirely).
- **Expected result:** documents whether zero-due is blocked client-side, accepted as advance, or rejected
  by the backend.

---

## 6 & 7. Phased Execution

### Phase A — STB payment success validation 🔴 (release-critical)
- **Prerequisites:** E1 (production reference), session/login working, Pending Retrieval returning amount
  owed + billing identifier (already verified), full request contract in place (already built).
- **Implementation tasks:** none expected beyond what exists — Phase A is verification-led. If E1 shows a
  field/format mismatch, the only change is to align the request to the production reference.
- **Verification tasks:**
  1. Pay a tiny amount on a positive-due test customer; confirm `status = 0` + server receipt.
  2. Confirm the on-screen receipt uses server values only.
  3. Read-after-write: re-open the customer; pending dropped by exactly the amount paid.
  4. E3 query: exactly one payment-detail row, `payment_flag = 4`, matching receipt/amount.
  5. Double-tap Pay rapidly → at most one row (client guard).
  6. Kill network mid-pay → no receipt, no row.
- **Rollback plan:** the action is server-authoritative and additive (one payment row). If a wrong test
  payment lands, reverse it via the standard backend adjustment/void process on the **test** server; never
  edit rows by hand on production. Because testing is tiny-amount + test-server + disposable customer, blast
  radius is negligible.
- **Release risk:** 🔴 until verified; 🟢 once all six checks pass and match production.

### Phase B — Broadband payment validation (follow-up unless in launch scope)
- **Prerequisites:** Phase A signed off; E5 evidence; broadband test customer.
- **Implementation tasks:** populate broadband fields (amount, account id, due, renewal) on the existing
  request; handle **deferred** receipt (do not assume an immediate receipt number).
- **Verification tasks:** staging row created; settlement progresses to a detail row; receipt handled per
  its deferred nature; **no discount** path offered.
- **Rollback plan:** staging is reversible on the test server via the standard broadband void/retry tooling;
  confirm with the senior before any manual change.
- **Release risk:** 🟠 (asynchronous settlement; partial-settlement UX must be correct).

### Phase C — STB + Broadband combined validation (follow-up)
- **Prerequisites:** Phases A & B signed off; a combined test customer; E6-style combined evidence.
- **Implementation tasks:** carry both STB and broadband amounts in one submission.
- **Verification tasks:** both components settle on their own paths; amounts reconcile; receipt behaviour
  documented per component.
- **Rollback plan:** as B (broadband) + as A (STB), per component, on the test server.
- **Release risk:** 🟠 (mixed settlement timing; reconciliation).

### Phase D — Discount parity validation
- **Prerequisites:** E4 (max-discount value + source); Phase A signed off.
- **Implementation tasks (STB, money-critical):** source the max-discount-% from login (replace the
  placeholder); confirm amount = due − discount and the discount-> due clamp match production.
- **Verification tasks:** discount below cap succeeds; discount above cap is blocked the same way as
  production; the discounted amount in the payment-detail row matches.
- **Rollback plan:** discount affects only the amount field; reverse a wrong test payment via the standard
  adjustment process on the test server.
- **Release risk:** 🟠 (money). Must match production exactly before sign-off.

---

## 8. 48-Hour-Before-Release Checklist

> Run entirely on the **test/non-production** server first; then a single controlled production smoke test
> with a tiny amount on a disposable/known customer, reversed afterwards via the standard process.

**Scope & evidence**
- [ ] Launch scope confirmed (STB cash only vs. broadband/combined/card included).
- [ ] Every 🔴/🟠 gap for the in-scope features is **closed and re-verified** (no open ⛔ in scope).
- [ ] E1 production reference captured and matched by the new client.

**STB cash (must all pass)**
- [ ] Positive-due payment → `status = 0` + **server** receipt.
- [ ] Read-after-write: pending dropped by exactly the amount paid.
- [ ] Exactly one payment-detail row; `payment_flag = 4`; receipt/amount match the response.
- [ ] Double-tap → at most one payment.
- [ ] Network failure mid-pay → no receipt, no row.
- [ ] Backend rejection → backend message shown, no receipt.
- [ ] Behaviour matches the production app for the same customer.

**Discount (if discount enabled in scope)**
- [ ] Amount = due − discount; discount > due clamps to full due.
- [ ] Max-discount-% sourced from login (not hard-coded); above-cap blocked like production.
- [ ] Discounted amount recorded correctly in the payment-detail row.

**Credit / zero-due**
- [ ] Advance/credit behaviour matches production (per E2): either supported or cleanly rejected with a
      clear message — never a silent wrong charge.
- [ ] Zero-due behaviour matches production (per E6).

**Money safety (cross-cutting)**
- [ ] No fabricated receipts anywhere.
- [ ] No "success" recorded on any failure path.
- [ ] Double-submit protection verified.
- [ ] Server receipts only; client never constructs one.

**Operational**
- [ ] App points at the correct **production** endpoint for the release build (and the test build at test).
- [ ] Device identifier strategy correct for the release (registered device path).
- [ ] Temporary diagnostic logging removed from the release build.
- [ ] A documented reversal/adjustment procedure exists for an erroneous payment.
- [ ] Go/no-go owner identified; sign-off recorded.

---

## Immediate Next Action

The single highest-leverage step is **E1 + E2**: in the production app, run a tiny cash payment on the
**positive-due** customer (e.g. 927630) and on the **advance/credit** customer (e.g. 926055), and capture
both request + response. E1 unblocks Phase A (the release-critical path); E2 settles whether the
"No records found" we saw is a bug or correct behaviour. Everything else sequences behind those two.
