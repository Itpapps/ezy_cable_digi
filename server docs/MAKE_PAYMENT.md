# MAKE PAYMENT (`mpay`) — Investigation & Verification Matrix

**Status:** ✅ **STB Phase-1 (cash) VERIFIED end-to-end** on a positive-due customer — real `makePayments`
returned `statusCode=0` + a server receipt, and a matching `acc_payment_details` row (`payment_flag=4`)
was created. `MakePaymentRepository` → `PaymentController.pay()` (28-field parity request, double-submit
guarded, server-issued receipt, NO local insert). Broadband / STB+Broadband / bank·card·upi = follow-up
(out of launch scope). See PAYMENT_FLOW_SPEC.md + PAYMENT_EXECUTION_PLAN.md (Phase A).

**Implementation files:** `lib/features/payment/data/make_payment_repository.dart` (new) ·
`lib/features/payment/payment_controller.dart` (`pay()` rewritten) ·
`lib/features/payment/data/pending_amount_repository.dart` (now also captures `billingId`).
**Source of truth:** D:\Git-Repos\magikdigi + verified Android testing/backend investigation (done externally).

> No sensitive values stored. Test ONLY against a local/test server + disposable test customer; NEVER live.

## API contract (Android)
- SOAP method `makePayments` (`mpay`); wrapper element `paymentInfo`, `i:type="makePaymentsInfo"`;
  posted to `PAY_URL` (confirm same data server vs gateway).
- ⚠️ Android marshals float fields (`MarshalFloat`/`MarshalDouble`) — `amount` is a typed float; the
  Flutter text envelope must send a server-accepted numeric format.
- `payment_flag = 4` = online app payment.

## Request fields (`makePaymentsInfo`) — key
`altCustomerId` (= customer_id), `authToken`, `imei`, `amount` (float), `billingId`, `due_amount`,
`modeType` (cash/bank/card/upi), `chequeNo/bank/branch/chequeDate` (bank), `rrnNo/cardholderName/paynearpaymentdetails`
(card), `discount_applied`/`discount_penalty_flag`/`max_discount_percentage_allowed` (STB discount), `sendsms`,
`payment_flag`, `transaction_number`, `mobileNumber`, `latitude`/`longitude`,
`broadband_payment_amount`/`broadband_user_id`/`broadband_due`/`is_for_renewal` (broadband).

## Evidence status — VERIFIED vs ASSUMED
> Rule: only mark VERIFIED when backed by observed backend rows / captured request-response, not source code alone.

### ✅ VERIFIED (STB) — from `acc_payment_details` backend rows
An app payment (`payment_flag=4`) inserts one row into `acc_payment_details` with these columns:
`customer_id, dealer_id, employee_id, billing_id, paid_on, payment_mode, paid_amount,`
`receipt_no, payment_flag(=4), latitude, longitude, is_discount, discount_penalty_flag, adv_payment_flag`.
- **`receipt_no` is server-generated**, pattern `CR{dealer_id}/{seq}/{counter}` → never fabricate client-side.
- `master_transaction_no` is **empty** for app payments (populated for web/adjustment rows, `payment_flag=0`).
- `adv_payment_flag=1` when paying with no/over-due balance (recorded as an **advance**); else `0`.
- Response carries `statusCode`/`statusMessage` + the server `receiptNumber` (exact response field names still
  to be locked from a captured response).

### 🟡 ASSUMED / evidence not yet reviewed
| Item | Needed evidence |
|---|---|
| `acc_billing` balance reduction (STB) | before/after rows for the paid `billing_id` |
| Broadband payment | `broadband_payment_details` + `broadband_payment_staging` rows |
| STB + Broadband | combined rows across all tables |
| Discount | an `is_discount=1` row + `discount_logs` / `customer_discount_penalty` |
| `mpay` request/response XML | captured request + response (to build/parse) |

### Backend tables (mapping)
| Customer type | Tables | Status |
|---|---|---|
| STB | `acc_payment_details` (+ `acc_billing`) | acc_payment_details ✅ · acc_billing 🟡 (before/after still needed) |
| Broadband | `broadband_payment_staging` → `broadband_payment_details` | ✅ flow verified |
| STB + Broadband | all of the above | 🟡 (combined rows + discount not yet seen) |

## Round-2 VERIFIED evidence (DB + Android getPendingAmount log)

### Broadband payment is ASYNC via staging (third-party)
`broadband_payment_staging` (cols incl. `staging_status`, `tries`, `staging_retrying`, `failed_message`,
`api_response`, `due_from_bb`, `broadband_payment_id`) → row inserted on payment (`staging_status=1`),
then a process calls the **third-party broadband API**, then on success a `broadband_payment_details`
row is created with the server `receipt_no`. Implications:
- Broadband uses **`billing_id = 0`**; STB uses a real `billing_id`.
- Separate **`broadband_customer_id`** (+ linked `stb_customer_id`), `is_renewal`, `receipt_from=MobileApp`.
- Broadband **receipt format** `…BR/RCPT/{year-week}/{counter}` (vs STB `CR{dealer}/{seq}/{counter}`).
- Confirms **no broadband discount** + deferred settlement (don't assume immediate receipt for broadband).

### GPA response — full field set (verified)
`statusCode, statusMessage, customerName, mobileNumber, pendingAmount, billingId, discount_amount,`
`total_payment_after_discount, discount_start/end_date, penalty_amount, total_payment_after_penalty,`
`penalty_start/end_date, discount_penalty_flag, nickname, cable_pending_amount,`
`broadcaster_pending_amount, last_paid_amount, last_paid_date, payments_count, adjustment_count`.
- **`billingId` for `mpay` comes from THIS response** (resolves the earlier unknown).
- STB vs broadband split = **`cable_pending_amount`** vs **`broadcaster_pending_amount`**.
- ⚠️ Our Flutter `PendingAmountRepository` currently reads only `pendingAmount`. For `mpay` it must ALSO
  capture **`billingId`** (and likely `cable_pending_amount`/`broadcaster_pending_amount` for STB+BB).

### Android parsing bug to NOT replicate
Android does raw `Double.valueOf("anyType{}")` on empty gpa fields → `NumberFormatException`
(`CustomerMgmt_MakePayment_Fragment:2004/2011/2023/2047`). Flutter uses `tryParse ?? 0.0` — keep that.
Real ksoap2 envelope includes `id="o0" c:root="1"` + per-field `i:type`; our simplified envelope works
(server lenient) — no change needed.

### ✅ VERIFIED — mpay request/response (STB, with discount)
Captured from Android (STB customer, with a discount). **"Captured real mpay request XML" and
"Captured real mpay response" = VERIFIED.**

**Request** (wrapper `paymentInfo`, `i:type="makePaymentsInfo"`):
| Field | Example | Note |
|---|---|---|
| `altCustomerId` | 927631 | = customer_id |
| `authToken`, `imei` | — | session + device |
| `amount` (float) | `59.0` | = `due_amount − discount_applied` (99 − 40) |
| `billingId` | 7695029 | **from the GPA response** |
| `due_amount` (float) | `99.0` | the pending |
| `discount_applied` (float) | `40.0` | STB discount |
| `discount_penalty_flag` | `"0000"` | **4-char string**, not `"0"` |
| `max_discount_percentage_allowed` | 100 | |
| `modeType` | `"cash"` | lowercase |
| `sendsms` | 1 | |
| `payment_flag` | 4 | mobile-app online payment |
| `latitude`/`longitude` | — | GPS |
| `transaction_number` | `""` | empty for fresh online |
| `broadband_payment_amount` | `0.0` | present even for STB (zero) |

**Response** (ksoap2 `key=value`):
`statusCode=0`, `statusMessage`, `customerName`, **`receiptNumber`** (server `CR{dealer}/{seq}/{counter}`),
`amount`, `billNumber`, `dealerBusinessName`, `bill_for_month` → the receipt is built from these.

Confirms: STB **discount works** (due 99 / discount 40 / paid 59); `billingId` comes from GPA;
`receiptNumber` is server-issued. → **STB Phase-1 is fully specified and unblocked.**

**Discount UX parity (Android `afterTextChanged` :607–639):** the collector types the **discount**;
the **amount field auto-recomputes to `due − discount`** (discount > due clamps amount to full due).
At submit: `amount` = the discounted amount field, `discount_applied` = discount, `due_amount` = gpa pending.
Flutter mirror: `PaymentController.onDiscountChanged()` (wired to the discount field's `onChanged`).
⚠️ Not yet enforced client-side: the max-discount-% cap (Android :623 uses `LoginActivity.MAX_DISCOUNT_
PERCENT_ALLOWED`, which we don't capture from login) — the server still validates `max_discount_percentage_allowed`.

### ✅ Phase-1 STB cash — VERIFIED (positive-due customer, end-to-end)
A real Flutter `mpay` on a **positive-due** STB customer succeeded end-to-end:
- Response `statusCode=0`, **server receipt** issued (dealer-prefixed pattern), `msg=Success.`
- Backend `acc_payment_details` row created: `payment_flag=4`, `payment_mode=Cash`, `paid_amount` = the
  tiny test amount, `receipt_no` = the response receipt (identical), `billing_id` = the GPA billingId,
  `is_discount=0`, `master_transaction_no` empty. Server normalises `discount_penalty_flag "0000"→"0"`.
- On-screen receipt shows the server receipt number (not fabricated).

**Conclusion: H1 confirmed** — the earlier "No records found" was the **partial 16-field request**, not the
customer. The 28-field parity fix resolved it. STB cash payment works. (Read-after-write pending-reduction
is the final operational glance; the DB row already proves application.)

---

### 🔴 (Historical) Phase-1 first live test — FAILED (`statusCode=1` "No records found")
First real Flutter `mpay` attempt (partial 16-field request, on a credit/advance customer). Result:
`status=1 receipt= msg=No records found` (no money moved — failure path threw before a receipt).
Superseded by the verified success above. Investigation (Android read-only):

- **Endpoint ruled out:** `PAY_NAMESPACE`/`PAY_URL` (Fragment :92–93) are **identical** to GPA's
  `NAMESPACE`/`login_serverUrl`. Our Flutter `mpay` already posts there. GPA succeeded on the same server.
- **Request-shape deviation (real):** `makePaymentsInfo` is `KvmSerializable`, `getPropertyCount()=28` —
  Android marshals **all 28 fields in fixed order** (unused = null/0). For **cash** (Fragment :1816–1859)
  it sets altCustomerId, authToken, amount, billingId, **remarks**, due_amount, max_discount_%,
  **mobileNumber**, imei, modeType, sendsms, payment_flag, discount_penalty_flag, latitude, longitude,
  transaction_number="" (+ broadband fields only if broadband; discount_applied only if customer_discount=1).
  Our Flutter sends **only 16** named fields (omits remarks, mobileNumber, cheque/card/broadband fields).
- **Scenario was an edge case:** the test customer had **negative pending (advance/credit)** and we paid ₹1 —
  different from the verified-working positive-due customer. We have **never** had a successful Flutter `mpay`
  yet (the verified evidence was captured from Android, not Flutter).

**Two hypotheses (not yet decided):**
- H1 — partial 16-field request ≠ 28-field contract → server can't match.
- H2 — advance/credit customer has no open bill → "No records found" is a legitimate response.
  (A clean `statusCode=1`, not a SOAP fault, suggests the server parsed the request → leans H2.)

**Decisive test (pending):** capture Android's `Log.e("makepayment", …)` request+response for the SAME
customer. Android-also-fails ⇒ H2 (scenario). Android-succeeds ⇒ H1 (our request shape).

**Justified fix either way (parity, not new behavior):** make `MakePaymentRepository` send the full
**28-field** `makePaymentsInfo` in Android's order (add `remarks`, `mobileNumber`, null/empty/zero defaults
for cheque/card/broadband).

**✅ DONE — 28-field parity fix applied** (`make_payment_repository.dart`): all 28 fields now sent in
Android's exact index order; `payment_controller.dart` passes `remarks` + `mobileNumber`. analyze clean.

**⚠️ RETEST CONSTRAINT:** customer 926055 is a **credit/advance** account (Android GPA confirmed
`pendingAmount=-520`, `last_paid_amount=60`) — paying it may *legitimately* return "No records found".
The retest MUST use a **positive-due STB customer** + a tiny amount. If a positive-due customer now
returns `status=0` + a real receipt → H1 confirmed (it was our partial request). If it still fails →
capture Android's `makepayment` request/response on that same customer to compare.

### ✅ VERIFIED — discount recording model (full Flutter↔Android parity)
A discounted STB payment writes **two rows** to `acc_payment_details` sharing the **same receipt_no**:
| Row | paid_amount | is_discount | discount_penalty_flag |
|---|---|---|---|
| Cash | amount collected (= due − discount) | 0 | **0** |
| Discount | the discount amount | 0 | **1** |
- `is_discount` is **always 0** (Flutter AND Android) — it is NOT the discount marker; the **second row
  with `discount_penalty_flag=1`** is. Earlier `is_discount=0` worry was a red herring.
- The server creates the discount row from the `discount_applied` field we send (>0 → discount row).
- Confirmed identical between a Flutter discounted payment and an Android discounted payment on the same
  customer → **G4 closed, full parity.** Balance also clears correctly (due = cash + discount → pending 0).

### ✅ VERIFIED — advance / zero-due / credit (G2, G3)
Live, with the full 28-field request:
- **Zero-due** customer paid → accepted, `status=0`, recorded as advance → pending goes negative (G3).
- **Credit** customer (negative pending) paid → accepted, `status=0` (G2). The old "No records found" was
  the **partial 16-field request**, NOT the credit status. (`adv_payment_flag` expected set on advances.)

### Still missing (investigation only — NOT blocking STB Phase 1)
- STB + Broadband **combined discount** behavior.
- Broadband **staging lifecycle timing** (when receipt/balance settle).
- **Idempotency / double-submit** server behavior.
- Other payment **modes** (bank/card/upi) field requirements.

## Payment Verification Matrix
| Aspect | STB | Broadband | STB + Broadband |
|---|---|---|---|
| Amount field | `amount` | `broadband_payment_amount` | both |
| Pending source | `gpa.pendingAmount` (cable) | `broadcaster_pending_amount`/`broadband_due` | both |
| Discount | ✅ supported | ❌ not supported (third-party) | ⚠️ UNVERIFIED |
| Tables | acc_payment_details, acc_billing | broadband_payment_details, broadband_payment_staging | all four |
| Settlement | immediate | likely staged/async | mixed |
| Receipt # | server-issued | server-issued (timing TBC) | server-issued |

## Remaining unknowns
1. **Discount (PRIMARY):** STB+Broadband combined behavior; server validation vs `max_discount_percentage_allowed`; `discount_penalty_flag` values.
2. Broadband **staging** = async? Balance/receipt immediate or deferred?
3. `modeType` exact strings + required fields per mode.
4. `billingId` source.
5. Idempotency / double-submit server behaviour.
6. `payment_flag` offline value.

## Missing evidence needed before implementing
- [ ] Captured real `mpay` **request** XML (lock fields + amount format).
- [ ] Captured real `mpay` **response** XML (lock `receiptNumber` + status field names).
- [ ] STB+Broadband **discount rule** (or decision to defer broadband+discount).

## Definition of Done (per the 9-step rule) — STB cash Phase-1
1. Android source ✅ 2. Contract (real req/resp) ✅ (STB) 3. Flutter impl (real mpay) ✅
4. Analyze ✅ (clean) 5. Manual UI ✅ (live payment, status=0 + receipt + DB row)
6. Android compare ✅ (request contract matches; same server, same receipt pattern)
7. Error handling: double-submit guard ✅ (code) · network-fail ▢ (still to exercise)
8. Docs ✅ 9. **User approval ▢** ← gate

## Money-safety rules (enforced before/while implementing)
- Test only on a local/test server + disposable customer + tiny amount.
- Never fabricate a receipt number — use the server's.
- Guard double-submit (the current local-dummy inserts on every submit — must not carry into `mpay`).
- Confirm `PAY_URL` is NOT `digi.kccl.tv` (live) in test builds.
