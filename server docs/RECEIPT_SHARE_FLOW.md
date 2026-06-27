# Receipt Share / PDF Flow — Existing Application Investigation

Scope: the **mobile payment receipt** share/PDF behaviour of the existing
application. This is the online payment-details receipt (the same receipt the
Print button uses). The CAF / offline copy is **out of scope**.

Verification legend:
- ✅ **Verified** — read directly from the existing application source.
- 🟡 **Not Yet Verified** — not confirmed by a live device test (or depends on
  account/role/device configuration we have not exercised).

---

## 1. Does the existing application have Share / Download / Both / Neither?

- ✅ **Share: YES.** The payment-details screen shows a **Share** icon. Tapping
  it builds a PDF and offers share targets.
- ✅ **Download: NO.** The payment-details screen has only two receipt action
  icons — **Print** and **Share**. There is no "Download PDF" / "Save PDF"
  button. The share code path writes a temporary PDF purely so it can be handed
  to another app; saving for the user is not a feature.

**Conclusion:** the existing app has **Share only** (no Download).

---

## 2. Share flow — how it is implemented

### 2.1 Entry point
- ✅ The Share icon's click handler calls a single method that builds the
  receipt text and hands it to a PDF helper.
- ✅ Share is **hidden** in two cases:
  - ✅ When the server role-permission flag `share_option == "0"`
    (default is `"1"` = shown; falls back to `"1"` if the permission is absent).
  - ✅ On specific POS hardware models (built-in-printer devices) the Share
    icon is hidden. (Device-model gate; not relevant to a normal Android phone.)

### 2.2 Receipt text built for the PDF
- ✅ A plain-text receipt string is assembled (this is a **different layout from
  the thermal print** — see §9). Key characteristics:
  - ✅ Separator line is a row of dashes (`--------`), **not** the thermal dots.
  - ✅ Header lines `header1` / `header2` (from printer settings) are printed
    only when non-empty, each followed by a separator.
  - ✅ Title line: ` PAYMENT RECEIPT ` (no dealer business name in the header).
  - ✅ Date line, then separator.
  - ✅ Title-case, space-padded labels, e.g. `Customer Name  :`, `Paid Amount    :`,
    `Bill Amount    :`, `Due Amount     :`, `Out Amount     :`, `Receipt No.    :`,
    `Lco Customer Id:`, `Address        :`, `Mobile No.     :`, `Last Paid Date :`,
    `Bill For       :`, `BroadBand ID   :`, `BroadBand Amt  :`, `Discount Amount:`.
  - ✅ `Due Amount` and `Out Amount` are **always** printed.
  - ✅ `Discount Amount` printed only when the discount permission is enabled.
  - ✅ Taxes printed only under the same conditions as the thermal receipt.
  - ✅ Footer lines `footer1` / `footer2` (printer settings) printed when non-empty.
- ✅ The filename handed to the PDF helper is `<customerName>.pdf`.

### 2.3 PDF generation
- ✅ Generated with the **iText** library (`com.itextpdf.text`).
- ✅ Page size: **A5**.
- ✅ The whole receipt text is added as a single **justified** `Paragraph`
  using iText's **default font** (a proportional font — **not** a monospace /
  Courier font). Space-based column alignment is therefore only approximate in
  the PDF.
- ✅ Document title metadata is set to the vendor name.

---

## 3. Is a PDF generated first? Is the receipt converted to PDF?
- ✅ **Yes.** The receipt is first rendered to a text string, then written into
  a real `.pdf` file on disk **before** any share intent is fired. The share
  always sends a PDF file (never plain text, never an image).

---

## 4. Which Android Intent(s) are used?

The share dialog (`dialog_share_layout`) offers **three** targets plus Cancel:

- ✅ **WhatsApp** — `Intent(ACTION_SEND)`, type `application/pdf`,
  `EXTRA_STREAM` = FileProvider URI, `setPackage("com.whatsapp")`.
  On failure: Toast "WhatsApp not Installed".
- ✅ **Email** — `Intent(ACTION_SEND)`, `EXTRA_SUBJECT = "Payment Receipt of <name>"`,
  `setDataAndType(uri, resolver.getType(uri))`, `FLAG_GRANT_READ_URI_PERMISSION`,
  `EXTRA_STREAM` = FileProvider URI, launched via
  `Intent.createChooser(intent, "Send email using...")`.
  On failure: Toast "No email clients installed.".
- ✅ **WhatsApp Business** — identical to WhatsApp but
  `setPackage("com.whatsapp.w4b")`. On failure: Toast "WhatsApp Business not Installed".
- ✅ Dialog title: "Are you sure, you want to share?" with a "Cancel" button.

Notes:
- ✅ WhatsApp / WhatsApp Business target a **specific package** directly (no
  chooser). Email uses a **chooser**.
- 🟡 Whether each target actually launches and attaches the PDF on a live device
  is **not yet verified** (read from source only).

---

## 5. Temporary file handling / storage location / cleanup

- ✅ **Location:** app-specific external storage —
  `getExternalFilesDir(DIRECTORY_DOWNLOADS)/<customerName>.pdf`
  (i.e. `Android/data/<applicationId>/files/Download/`). This is private to the
  app; no runtime storage permission is required on modern Android.
- ✅ **Cleanup before write:** immediately before generating a new PDF, the
  entire external `Download` directory is **deleted recursively**, then the new
  PDF is written. So only the most recent receipt PDF exists at a time.
- ✅ **Cleanup after share:** the PDF is **not** deleted after sharing. It
  persists until the next share call clears the directory again.
- ✅ **FileProvider:** authority `${applicationId}.provider`, paths from
  `@xml/provider_paths`; the share URI is obtained via
  `FileProvider.getUriForFile(...)`.
- ✅ **MIME type:** `application/pdf` for WhatsApp / WhatsApp Business; for email
  the type is resolved from the content URI (also PDF).

---

## 6. Permission handling
- ✅ On Android 11+ (R) the code checks `Environment.isExternalStorageManager()`
  and, when not granted, falls back to a `MediaStore` insert probe; otherwise it
  Toasts "Allow permission for storage access!".
- ✅ Because the actual file is written to **app-specific** external storage, the
  practical path does not require the user to grant storage permission.
- 🟡 Exact behaviour of the all-files-access branch on a specific OS version is
  **not yet verified** by live test.

---

## 7. Error handling (existing app)
- ✅ PDF not supported on device → Toast "PDF is not Supported".
- ✅ PDF generation throws → Toast with the exception message.
- ✅ WhatsApp / WhatsApp Business not installed → Toast naming the missing app.
- ✅ No email client → Toast "No email clients installed.".
- ✅ All failures are **non-fatal** (Toast only); the app never crashes on a
  missing share app.

---

## 8. User experience (existing app)
1. ✅ User opens the payment-details (receipt) screen after a payment.
2. ✅ User taps **Share**.
3. ✅ A PDF is generated silently to app storage.
4. ✅ A custom dialog appears: WhatsApp / Email / WhatsApp Business / Cancel.
5. ✅ Picking a target opens that app (or a chooser, for email) with the PDF
   attached; failures Toast a friendly message.
6. ✅ There is **no** "saved to Downloads" confirmation and **no** Download
   button — sharing is the only outcome.

---

## 9. Important discrepancy — Share PDF layout vs Thermal layout

- ✅ The existing app uses **two different receipt layouts**:
  - **Thermal print** (Bluetooth): dotted separators, UPPERCASE 17-char labels
    (`CUSTOMER NAME    :`, `PAID.AMT         :`, `TOT.DUE.AMT      :`, …).
  - **Share PDF** (this document): dashed separators, Title-case labels
    (`Customer Name  :`, `Paid Amount    :`, `Due Amount     :`, …), iText A5,
    proportional font.
- ✅ The current Flutter app builds **both** its thermal print and its PDF from a
  **single** thermal-style line builder (dots + UPPERCASE), per the earlier
  receipt-parity task. So the Flutter **shared PDF** currently matches the
  Android **thermal** layout, not the Android **share-PDF** layout.
- ✅ **Decision (resolved): Match Android share-PDF.** The Flutter **shared PDF**
  now has its own builder (`_buildSharePdfLines`) mirroring the Android `savePdf`
  text — dashed separators, Title-case 15-char labels, "Mobile No." (no Account
  Number line), broadband block under the customer name, no Total-Paid line,
  Due/Out always present — rendered on an **A5** page. The **thermal print** keeps
  its own dotted/UPPERCASE builder (`_buildReceiptLines`). The two layouts are now
  independent, exactly as in the existing app.
  - Font note: the existing app uses iText's default proportional font (columns
    align only approximately). Flutter renders the same text in **Courier** on A5
    so the intended columns align cleanly. 🟡 Accept on visual review.

---

## 10. Flutter — current state vs required parity

Current Flutter (`receipt_preview_screen.dart`):
- ✅ Has a **Share** path: builds a PDF to a temp dir and shares it via
  `share_plus` (`Share.shareXFiles`), with a bottom sheet offering Gmail,
  WhatsApp, WhatsApp Business.
- ✅ Has a **"DOWNLOAD PDF"** button (`_downloadButton` → `_downloadPdf`) that
  saves the PDF to the app documents dir and shows a "PDF saved" snackbar.

Required for parity:
- ✅ **Remove the Download button** — the existing app has no Download. (Action.)
- ✅ **Keep Share** — already present; the three targets (Gmail/Email, WhatsApp,
  WhatsApp Business) match the existing app's three targets.
- 🟡 **Share targeting:** the existing app sends to specific packages
  (`com.whatsapp`, `com.whatsapp.w4b`) and a chooser for email. Flutter's
  `share_plus` opens the system share sheet instead of package-targeted intents.
  Outcome is equivalent (user picks the app); replicating package-specific
  intents would require platform channels and is **not** implemented to avoid a
  new workflow. Documented as a known, accepted difference.

---

## 11. Definition of Done

- [ ] ✅ Download button removed from the Flutter receipt screen.
- [ ] ✅ Share remains functional and offers WhatsApp / Email / WhatsApp Business.
- [ ] ✅ PDF is generated to a temporary file before sharing; MIME is PDF.
- [ ] ✅ Sharing never crashes when PDF generation fails.
- [ ] ✅ Sharing never crashes when no share/target app is installed
      (friendly message instead).
- [ ] ✅ `flutter analyze` clean (no new issues).
- [ ] 🟡 User confirms on a live device: Share opens targets with the PDF
      attached for STB / Broadband / Combined receipts.
- [ ] 🟡 User decides the §9 layout question (thermal-style vs Android share-PDF
      style) — left unchanged until then.

---

## 12. Evidence index (existing application, read-only)

- Payment-details screen: Share/Print icons, `share_option` + device-model gate,
  `savePdf()` text builder, Print bundle.
- PDF helper: `showPDFUrl` → `downloadAndOpenPDF` (iText A5, temp file,
  recursive pre-delete) → `SharePDF_File` (3-option dialog) →
  `ShareViewWhatsupOrEmail` (ACTION_SEND, package targeting, chooser for email).
- Manifest: `FileProvider` authority `${applicationId}.provider`,
  `@xml/provider_paths`.
- Login: `share_option` parsed from role permissions, default `"1"`.
