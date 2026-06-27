# STB-CASH RELEASE-READINESS ASSESSMENT

**Scope of this release:** STB customers, **cash** payment, with **discount**. Broadband, STB+Broadband
combined, and card/bank modes are explicitly **out of scope** (follow-up).

**Governing docs:** `PAYMENT_FLOW_SPEC.md` (source of truth) · `PAYMENT_EXECUTION_PLAN.md` (sequencing) ·
`MAKE_PAYMENT.md` (contract + evidence).

**Verdict:** 🟢 **Functionally ready** for STB cash on the **test** server — the payment flow is verified
end-to-end against real backend rows. 🔴 **NOT yet shippable to production** until the operational
blockers in §4 are cleared (endpoint switch, real device id + registration, temp-log removal, receipt ₹
glyph). These are release-engineering items, not payment-logic gaps.

---

## 1. What is VERIFIED (live, against backend rows)

| Area | Result | Evidence |
|---|---|---|
| STB cash success (positive-due) | ✅ | `status=0` + server receipt + one `acc_payment_details` row (`payment_flag=4`, amount/receipt/billingId consistent) |
| Read-after-write | ✅ | Pending reduced by exactly the amount paid on every payment |
| Discount honored | ✅ | Bill clears to 0 (due = cash + discount); verified at multiple discount values |
| Discount recording parity | ✅ | Two-row model (cash row `discount_penalty_flag=0` + discount row `=1`), identical Flutter↔Android; `is_discount` always 0 in both |
| Discount config from login | ✅ | `enable_payment_discount` gates the field; `max_discount_percent_allowed` sourced from login (placeholder removed) |
| Discount math / UX | ✅ | amount = due − discount (auto-recompute); discount > due clamps to full due |
| Zero-due payment (G3) | ✅ | Accepted as advance → pending goes negative |
| Credit-customer payment (G2) | ✅ | Accepted (`status=0`); old "No records found" was the partial request |
| Network failure (G8) | ✅ | Throws, **no** `status=0`, **no** receipt, pending unchanged |
| Double-submit | ✅ | One `[MPAY]`, pending cleared to exactly 0 (a duplicate would overpay → negative) |

**Money-safety posture (all enforced):**
- Receipt number is **server-issued** only — never fabricated.
- A receipt is built **only** on `status=0`; any failure/transport error produces no receipt and no local "success".
- No local SQLite payment insert for online payments (server is the source of truth).
- Double-submit guarded client-side; the money-level check (pending → exactly 0) confirms no duplicate applied.

---

## 2. Known limitations accepted for this release

| Item | Status | Risk | Decision |
|---|---|---|---|
| Discount role-permission gate (`customer_discount`) | Not wired (gated on `enable_payment_discount` only) | Low — server still validates; a discount still records correctly | Accepted (per scope decision); full gate is a follow-up |
| Max-discount-% at non-100 cap | Only the value `100` exercised | Low — the value flows through unchanged and the server is the final authority | Accepted; revisit if a dealer uses a non-100 cap |
| Server-side idempotency | Unconfirmed (client guard only) | Low for cash (collector present) | Accepted; client guard verified |
| GPS latitude/longitude | Sent as `0.0` (geolocator not wired) | Low — payment succeeds; row stores 0/0 | Accepted; wire real GPS as a follow-up |
| `adv_payment_flag` on advances | Expected set; not yet row-confirmed | Low | Confirm opportunistically |

---

## 3. Out of scope (follow-up releases — do NOT ship as working)

- **Broadband** payment (staging → third-party → settled).
- **STB + Broadband** combined payment + combined discount.
- **Card / bank** payment modes (fields exist in the request but are unverified).

These must not be presented as functional in this release.

---

## 4. 🔴 Operational blockers — REQUIRED before a production build

These gate the production APK regardless of payment-logic readiness (see `API_MIGRATION_RECORD.md` →
PRODUCTION BLOCKERS):

1. **Endpoint switch to production.** Build currently targets the **test** server. The release build must
   point `namespace` at the production data server (and BMS as appropriate).
2. **Real device identifier + registration.** Release sends an empty `imei` by design today; wire a real
   device id and verify the SMS-Key device-registration flow (a fresh install's id is unregistered).
3. **Remove temporary diagnostic logs.** Strip `[LOGIN]`, `[GPA]`, `[MPAY]` (and any other temp logs)
   from the release build. (Kept intentionally through validation; now safe to remove.)
4. **Receipt ₹ glyph.** The PDF receipt font has no ₹ glyph — embed a Unicode TTF or fall back to "Rs."
5. **iOS device-identifier strategy** (if iOS is in the release).

---

## 5. Pre-release smoke test (production, controlled)

After §4 is cleared, run ONE controlled production smoke test:
- A tiny cash payment on a known/disposable customer → `status=0` + server receipt + a backend row.
- Reverse it via the standard adjustment/void process.
- Confirm a discounted payment writes the two-row pattern (cash + discount-flag row).
- Confirm a network-fail produces no receipt/no row.

---

## 6. Go / No-Go

- **STB cash on test server:** ✅ **GO** — payment logic is verified end-to-end.
- **STB cash production build:** 🔴 **NO-GO until §4 cleared.** No payment-logic work remains; the blockers
  are endpoint/device/logging/receipt-font release tasks.

**Recommended next step:** clear §4 (operational blockers), rebuild against production, run §5, then sign
off. Owner + go/no-go date to be assigned.
