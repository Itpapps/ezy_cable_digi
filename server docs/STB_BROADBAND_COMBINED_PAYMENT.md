# STB + BROADBAND COMBINED PAYMENT FLOW

**Status:** 📘 **Documentation / investigation only — NOT implemented, NOT live-tested.** Combined
(customer type 2) is out of the current STB-cash release scope. **No code until this is reviewed and the
🔴/🟡 items are closed by live testing.** Builds on `BROADBAND_PAYMENT_FLOW.md` and the (✅ live-verified)
STB flow.

## Verification taxonomy (strict)
- ✅ **Verified by live testing** — real logs + backend + database in *this* project. **Combined has NONE yet.** (Only the STB *leg* is ✅, in isolation.)
- 🟡 **Verified from existing application logic only** — how the existing app builds the request / drives UI. Not proven for our client until live-tested.
- 🔴 **Not yet verified** — backend-internal or unconfirmed; must not be assumed.

> A 🟡 item is **never** upgraded to ✅ without an actual live test. **Everything combined-specific here is 🟡 or 🔴.**
> No real customer identifiers, receipt numbers, tokens, or device values appear in this document.

---

## 0. Verification status at a glance

| Area | Status |
|---|---|
| Combined customer detection (type 2) | 🟡 logic only |
| Single submission carries both STB + broadband amounts | 🟡 logic only |
| STB amount source / discount applies to STB leg | 🟡 logic / 🔴 backend confirm |
| Broadband amount source (no discount) | 🟡 logic / 🔴 backend confirm |
| Total payable model (two separate fields, not one sum) | 🟡 logic only |
| Response carries a receipt number (read for all types) | 🟡 logic / 🔴 populated-for-broadband? |
| Receipt screen shows both STB + broadband amounts | 🟡 logic only |
| Settlement order (STB immediate + broadband async) | 🔴 not verified |
| Tables updated (STB detail + broadband staging→detail) | 🔴 not verified |
| Failure/partial-settlement (one leg succeeds, one fails) | 🔴 not verified |
| Idempotency / duplicate safety on the combined path | 🔴 not verified |

---

## 1. Combined customer detection 🟡

- `customer_type = 2` → label "STB & BroadBand"; the broadband account id is **non-empty**.
- Therefore **both** the STB amount field **and** the broadband amount field + renewal checkbox are shown.
- Master switches: STB leg is always present; broadband leg is active because the broadband account id is non-empty.

---

## 2. Amount model 🟡

A combined payment is **two amounts in one submission** — they are **not** summed into a single field:

| Component | Field | Source (from GPA) | Discount |
|---|---|---|---|
| STB | `amount` | `cable_pending_amount` | discount applies (STB leg) 🟡/🔴 |
| Broadband | `broadband_payment_amount` | `broadcaster_pending_amount` | **no discount** 🟡/🔴 |

- 🟡 **Total payable** = STB amount + broadband amount, but each travels in its own field; there is no
  single "combined total" field in the request.
- 🟡 The STB amount follows the verified STB rule: `amount = cable due − discount` (discount on the STB leg only).
- 🟡 The broadband amount = the broadband field (prefilled from `broadcaster_pending_amount`), **no discount**.
- 🔴 Confirm on the backend that the discount is applied to the STB leg **only** and never to the broadband amount.

---

## 3. Request structure 🟡 (population) / 🔴 (server effect)

One submission with the **full field set**; both legs populated:

| Field | Combined value | Status |
|---|---|---|
| `amount` | STB amount (cable due − discount) | 🟡 |
| `discount_applied` | discount on the STB leg (0 if none) | 🟡 |
| `billingId` | from GPA (STB bill) | 🟡 / 🔴 value |
| `due_amount` | STB pending | 🟡 |
| `broadband_payment_amount` | broadband amount | 🟡 |
| `broadband_user_id` | broadband account id | 🟡 |
| `broadband_due` | `broadcaster_pending_amount` (text) | 🟡 |
| `is_for_renewal` | renewal checkbox "1"/"0" | 🟡 client / 🔴 effect |
| `payment_flag` | `4` | 🟡 |
| (all other standard fields) | per STB contract | ✅ STB / 🟡 here |

🔴 The **server-side effect** of a combined submission (does it create the STB detail row immediately
AND a broadband staging row in one call?) is **Not yet verified**.

---

## 4. Response structure 🟡 / 🔴

- 🟡 The payment response is parsed for `receiptNumber`, `billAmount`, `paidAmount`, custom number,
  dealer business name, bill-for-month, tax fields — **for all customer types** (the receipt screen reads
  these regardless of STB/broadband/combined).
- 🟡 For the receipt screen, the **paid amount shown** for a combined customer is the **STB API
  `paidAmount`**, and the broadband amount is carried separately (`broadband_payment_amount` +
  `stb_payment_amount`).
- 🔴 **Whether the response carries a real receipt number for the broadband leg immediately** (vs the STB
  receipt only, with broadband settling later) is **Not yet verified** — must capture a live combined response.

---

## 5. Settlement order 🔴 Not yet verified

Working model to verify (do **not** treat as fact):
- The **STB leg** settles **immediately** (like a normal STB payment → STB payment-detail row + receipt).
- The **broadband leg** goes through the **async staging → third-party → detail** path (per
  `BROADBAND_PAYMENT_FLOW.md` §7).
- 🔴 So a combined payment likely has **mixed settlement timing**: STB done now, broadband pending. This
  must be confirmed and the **receipt/confirmation UX designed around it** (e.g. "STB paid; broadband
  processing").

---

## 6. Tables updated 🔴 Not yet verified

| Table | Expected role | Status |
|---|---|---|
| STB payment-detail | STB leg, immediate (✅ structure known from STB) | 🔴 confirm it fires within a combined call |
| broadband staging | broadband leg, in-progress | 🔴 |
| broadband payment detail | broadband leg, on settlement | 🔴 |

🔴 Confirm whether one combined submission writes the STB detail row **and** the broadband staging row, or
whether the legs are independent.

---

## 7. Validation rules 🟡

- For combined, **both** the STB amount and the broadband amount must be valid before submit.
- Discount validation (max-%) applies to the **STB** leg only.
- Partial-payment restriction (tenant setting) applies to the **STB** leg only.
- Network presence checked before submit.

> 🟡 Logic-only; re-verify live on a type-2 customer.

---

## 8. Sequence diagram (🔴 dashed steps unverified)

```
Collector            App                          Backend                    3rd-party BB API
   │                  │  GPA                        │                               │
   │ open type-2 cust │────────────────────────────▶│                               │
   │                  │◀ cable + broadcaster pending│                               │
   │ enter STB amt    │                             │                               │
   │ + BB amt         │                             │                               │
   │ (+discount STB)  │                             │                               │
   │ tap Pay ─────────▶│  ONE submission             │                               │
   │                  │  (amount + broadband_*)     │                               │
   │                  │────────────────────────────▶│                               │
   │                  │      STB detail row (now)   │                               │
   │                  │      🔴 BB staging row (now) │                               │
   │                  │◀── status + receiptNumber ──│ (🔴 STB receipt; BB deferred?) │
   │                  │      🔴 BB API call ─────────────────────────────────────────▶│
   │                  │                             │◀──── result ──────────────────│
   │                  │      🔴 BB detail row + receipt (later)                       │
   │ re-open cust ────▶│  GPA (read-after-write)     │                               │
   │                  │◀ cable=0? broadcaster=0?    │  (🔴 timing per leg)           │
```

---

## 9. Backend verification queries (live testing)

> Confirm table/column names with the senior first. Never run against production.

```sql
-- STB leg (immediate) — one new STB payment-detail row
SELECT receipt_no, paid_amount, billing_id, payment_flag, is_discount, discount_penalty_flag
FROM   acc_payment_details
WHERE  customer_id = <combined customer key>
ORDER  BY paid_on DESC LIMIT 5;   -- expect STB cash row (+ discount row if discounted)

-- Broadband leg (async) — staging then detail (confirm tables/columns first)
SELECT * FROM broadband_payment_staging
WHERE  broadband_customer_id = <bb account key> ORDER BY 1 DESC LIMIT 1;

SELECT receipt_no, paid_amount, billing_id FROM broadband_payment_details
WHERE  broadband_customer_id = <bb account key> ORDER BY 1 DESC LIMIT 1;

-- Read-after-write: GPA again; expect cable_pending and broadcaster_pending both reduced
-- (broadcaster possibly only after async settlement — note the timing)
```

---

## 10. Expected database changes (🔴 to confirm live)

| Step | Expected change | Status |
|---|---|---|
| On submission | STB detail row (immediate) + broadband staging row | 🔴 |
| STB leg | `cable_pending_amount` drops by STB paid (+ discount row if discounted) | 🔴 confirm within combined call |
| Broadband leg | staging → detail on settlement; `broadcaster_pending_amount` drops after settlement | 🔴 |
| Failure (one leg) | the other leg's state when one fails | 🔴 **critical to verify** |

---

## 11. Failure & recovery scenarios 🔴 (the hard part)

Combined adds a failure mode STB-alone does not have: **one leg succeeds, the other fails.**

| Scenario | Required behaviour (at implementation) |
|---|---|
| Network/transport failure on submit | No success assumed for **either** leg; no receipt; clear message |
| STB leg succeeds, broadband leg fails (async) | Must **not** present the whole payment as fully done; show STB paid + broadband pending/failed; never a single "paid" receipt implying both |
| Timeout after submit | Treat as unknown; **re-check via GPA per leg** before any retry; never blind re-pay |
| Malformed / missing fields in response | Parse defensively; never crash; no fabricated receipt |
| Duplicate submission | In-flight guard; verify the backend doesn't double-charge either leg |
| Partial broadband settlement | Surface broadband as pending; STB unaffected |

🔴 The exact partial-success behaviour is **Not yet verified** and is the **central combined-payment risk**.

---

## 12. Production risks

1. 🔴 **Partial success** (STB paid, broadband failed) — the defining combined risk; UX + recovery unverified.
2. 🔴 **Mixed receipt timing** — STB immediate, broadband deferred; one receipt screen must represent both correctly.
3. 🔴 **Double-charge on retry/timeout** across two legs — idempotency unverified.
4. 🔴 **Discount mis-application** to the broadband leg — confirm STB-only.
5. 🔴 **billing_id** semantics across legs.
6. 🟡→🔴 **Renewal** combined with an STB payment in one call — effect unverified.

---

## 13. Testing checklist (type-2 customer, test server, tiny amounts)

- [ ] Customer detected as type 2; both amount fields + renewal checkbox visible.
- [ ] GPA prefills STB from `cable_pending_amount` and broadband from `broadcaster_pending_amount`.
- [ ] Submit small STB amount + small broadband amount in one payment; capture the **live request + response**.
- [ ] STB leg: one STB payment-detail row (+ discount row if discounted) immediately.
- [ ] Broadband leg: staging row now; detail row + receipt after settlement; note latency.
- [ ] Receipt screen represents **both** legs correctly (no single misleading "paid in full").
- [ ] Read-after-write: `cable_pending` drops immediately; `broadcaster_pending` drops after settlement.
- [ ] **Partial-failure test:** force the broadband leg to fail; confirm STB stays paid and broadband shows pending/failed, no false receipt.
- [ ] Network-fail / timeout / malformed-response handled with no crash, no false receipt, no double-charge.
- [ ] Discount applied to STB leg only; broadband carries no discount.
- [ ] Behaviour compared against the existing application for the same customer.

> Each ticked + evidenced item upgrades the matching section from 🟡/🔴 to ✅.

---

## 14. Definition of Done (12-step — stays "In Progress" until all true)

1. Existing implementation investigated — 🟡 done (this doc)
2. API contract verified — 🟡 request / 🔴 response (capture live)
3. Backend behaviour verified — 🔴
4. Database behaviour verified — 🔴
5. Documentation completed — 🟡 (this doc; revise as items are tested)
6. Flutter implementation completed — ⬜
7. Static analysis clean — ⬜
8. Manual testing completed — ⬜
9. Error handling verified (incl. partial success) — ⬜
10. Compared against the existing application behaviour — ⬜
11. Backend data verified — ⬜
12. User explicitly approves — ⬜

---

## 15. Open items to close before implementation (the 🔴 list)

1. Capture a **live combined** request + response (both legs, receipt presence per leg).
2. Confirm **STB detail row fires immediately** within a combined call.
3. Confirm **broadband staging → detail** for the broadband leg + settlement latency.
4. Confirm **partial-success** behaviour (one leg fails) — the critical risk.
5. Confirm **discount is STB-leg only**.
6. Confirm **idempotency** across both legs (timeout/retry safety).
7. Confirm **read-after-write timing** per leg.

**Prerequisite:** `BROADBAND_PAYMENT_FLOW.md` 🔴 items must be closed first — combined depends on the
broadband leg being understood and verified.

**Until these are closed, combined stays documented-only and unimplemented.**
