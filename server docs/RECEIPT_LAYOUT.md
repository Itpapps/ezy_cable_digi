# RECEIPT LAYOUT — existing app (parity reference)

**Status:** 📘 Investigation / documentation. Source = the existing application's receipt code (on-screen
payment-details screen + thermal-print builder). **Goal: make the Flutter receipt match this as closely as
practical — do NOT redesign.**

## Verification taxonomy
- ✅ Verified by live testing (printed/visual compare in this project) — **none yet for the print path**.
- 🟡 Verified from existing application logic only — the layouts below (read from the app's code).
- 🔴 Not yet verified.

> No real receipt numbers / customer values here — placeholders only.

---

## 1. Thermal print format — 🟡 (exact, from the existing app's print builder)

32-column paper. Separator line = **32 dots** (`................................`). Each field line is a
**17-char left-padded label + `:` + value**. Header/footer blocks are **dealer-configurable** (stored in
printer settings: `header1`, `header2`, `footer1`, `footer2`).

```
................................
{header1}                         ← dealer header line 1
................................
{header2}                         ← dealer header line 2
................................
         PAYMENT RECEIPT
................................
{Day Mon DD YYYY HH:MM:SS}        ← printed date/time (device clock)
................................
CRF NUMBER       :{crf}           ← ONLY if use_caf == 1
CUSTOMER NAME    :{custName}
ACCOUNT NUMBER   :{custId}
LCO CUST ID      :{lcoCustId}     ← ⚠️ value passed in the "mobileNo" slot (app quirk — verify what it carries)
CUSTOMER ADDRESS :{custAdd}
RECEIPT NUMBER   :{receiptNo}     ← server receipt; "NA" for broadband-only
LAST PAID DATE   :{lastPaidDate}
BILL FOR         :{billFor}
{PAID.AMT | Broadband Amt} :{paidAmt}   ← label = "Broadband Amt" for BroadBand-ONLY; else "PAID.AMT"
................................
BILL.AMT         :{billAmt}
BROADBAND ID     :{broadbandUserId}        ← only if broadbandUserId != ""
BROADBAND Amt    :{broadbandPaidAmount}    ← only if broadband AND NOT BroadBand-only (i.e. combined)
TOTAL PAID AMT   :{paidAmt + broadbandPaid}← only if combined
{tax lines}                                ← only if is_sync_bills==2 && gstCount>0 && taxv != 0
TOT.DUE.AMT      :{dueAmt}
OUT.AMT          :{outAmt}
DISCOUNT.AMT     :{discount}               ← only if customer_discount==1 && enable_payment_discount==1
................................
{footer1}
................................
{footer2}
................................
(3 blank lines)
```

**Per-customer-type rules (🟡, identical to the on-screen rules already implemented):**
| | PAID line | BROADBAND ID | BROADBAND Amt | TOTAL PAID AMT |
|---|---|---|---|---|
| STB-only | `PAID.AMT` = STB paid | — | — | — |
| Broadband-only | `Broadband Amt` = broadband paid | shown | — | — |
| STB + Broadband (combined) | `PAID.AMT` = STB paid | shown | shown | shown (STB + BB) |

**Notes:**
- A second builder exists for **wider paper** (97-col, `line_97bt`) — same fields, wider separators. 🟡
- Tax lines only print when GST is configured (`is_sync_bills==2 && gstCount>0`) and the value ≠ 0.
- Date is the **device clock** at print time (not a server field).
- `header1/2`, `footer1/2` come from the printer-settings store; **may be empty** → must print blank safely.

---

## 2. On-screen receipt — 🟡 (existing payment-details screen field order)

Two grouped sections. Field order (existing app):
- **Customer info:** Customer Name · CRF · Bill For · NickName · Account/Customer Id · Mobile No ·
  LCO Customer Id · Address · Receipt No.
- **Payment info:** Discount Amount (if discount enabled) · Bill Amount · Total Due · Out Amount ·
  **broadband block** (Broadband User Id, Broadband Paid; + STB Paid + Total Paid for combined).
- **Customer Type** is shown.
- Amount-rounding (ACTUAL / ROUND / CEIL) is a tenant/login setting applied to displayed amounts.

**Flutter current on-screen receipt** already shows CUSTOMER INFO + PAYMENT INFO cards and (Milestone C)
the broadband block. Differences vs the existing app: **field ordering + labels** differ somewhat, and a
few fields (CRF, Customer Type placement, NickName) are arranged differently. → parity = align order/labels.

---

## 3. Flutter gaps (current state)

| Path | Current Flutter | Gap vs existing app |
|---|---|---|
| On-screen | CUSTOMER INFO + PAYMENT INFO cards + broadband block (Milestone C ✅) | field **order/labels** differ; CRF/NickName/Customer-Type placement |
| **Thermal print** | **Placeholder** (`printReceipt` prints "EZY CABLE DIGI / Cable Bill / TOTAL"; only name/mobile/amount/date) | 🔴 **does not match at all** — missing header/footer, CRF, account no, LCO id, address, receipt no, last paid date, bill for, bill amt, broadband block, total due, out amt, discount, taxes |
| PDF | (PDF builder shows Customer Type etc.) | broadband block + field-order parity pending |

**Biggest gap = the thermal print** — it must be rebuilt to the §1 format with the full field set, fed
**only** from the backend-confirmed payment result (never fabricated).

---

## 4. Data the print needs (must be threaded through — none fabricated)

From the payment result + customer + GPA (all already available in the flow):
`header1/2, footer1/2` (printer settings) · `crf` · `custName` · `custId/accountNo` · `lcoCustId` ·
`custAddress` · `receiptNo` (server; "NA" for BB-only) · `lastPaidDate` · `billFor` · `paidAmt` (STB) ·
`billAmt` · `broadbandUserId` · `broadbandPaidAmount` · `dueAmt` · `outAmt` · `discount` · `customerType`
· tax names/values (if GST configured).

⚠️ Several of these (outAmt, billAmt, dueAmt, lastPaidDate, billFor, tax fields, header/footer) are **not
currently captured** in the Flutter payment/receipt flow → they must be sourced from the verified
response/GPA before the print can match. Anything unavailable must be handled as **empty/safe**, never invented.

---

## 5. Incremental implementation plan (after this doc is reviewed)

1. **On-screen parity** — reorder/relabel the existing cards to match §2 (low risk; data already present).
2. **Thermal-print rebuild** — replace the placeholder `printReceipt` with the §1 format; thread the full
   field set; per-type broadband rules; safe-empty for missing fields. Test-print all three types.
3. **PDF parity** — mirror §1/§2 in the PDF builder (broadband block + ordering).
4. **Header/footer** — source `header1/2`, `footer1/2` from printer settings (confirm where stored).

**Stop after each** for a visual/printed compare against the existing app.

---

## 6. Error-handling requirements (all paths)
- No crashes / null exceptions: every field defaults to empty/`"NA"`/`0.00` when missing.
- Missing broadband values → omit the broadband lines (don't print blanks with labels).
- Empty header/footer → print nothing for that block (no crash).
- Never print a value not present in the backend-confirmed result.
- Analyzer stays clean.

---

## 7. Definition of Done (12-step) — stays "In Progress"
1. Existing receipt investigated — 🟡 done (this doc)
2. Layout/format documented — 🟡 done (this doc)
3. On-screen parity implemented — ⬜
4. Thermal-print parity implemented — ⬜
5. PDF parity implemented — ⬜
6. Analyzer clean — ⬜
7. STB receipt compared (screen + print + PDF) — ⬜
8. Broadband-only receipt compared — ⬜
9. Combined receipt compared — ⬜
10. Missing-field / empty-header error paths verified — ⬜
11. Printed output matches existing app — ⬜
12. User explicitly approves — ⬜

---

## 8. Open items to confirm before/while implementing
1. The `LCO CUST ID` line value (app passes it in the `mobileNo` slot) — confirm what it actually prints.
2. Where `header1/2`, `footer1/2` are stored/configured (printer settings) and how to read them in Flutter.
3. Whether the Flutter flow can source `outAmt`, `billAmt`, `dueAmt`, `lastPaidDate`, `billFor`, taxes —
   or which are acceptably empty for the first parity pass.
4. Printer width handling (32-col vs 97-col) — which our target printer uses.
