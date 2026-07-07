# 📱 iOS Release Guide — Magik Digi

> ⚙️ **Current iOS identity = MAGIK.** The iOS project is set to Bundle ID
> `itp.com.magikdigi` and display name **Magik Digi**. So your **first** iOS app
> on the App Store is **Magik Digi**. Build it with `--target lib/main_magik.dart`.
> (Ezy on iOS is a later step — see the "BOTH APPS" section at the bottom. It needs
> the Mac scheme setup; it does **not** block shipping Magik now.)
 
> rent one in the cloud (you already have "cloud Xcode"), drive it from Windows,
> and test on the **iPhone you already have**. This is a checklist, not magic.
> Do it top-to-bottom and you will ship.

---

## 0. The 3 things you must understand before anything else

1. **iOS and Android are two completely separate releases.**
   - Your **Android production keystore + alias = Android ONLY.** It does **nothing**
     for iOS. iOS is signed by **Apple's own certificates**, created in the cloud.
     👉 Put the Android key away for this whole guide. Don't try to use it.

2. **You need an Apple Developer Program membership — $99/year.** No way around it.
   This is what lets you sign, upload, and publish iOS apps. (Android had Google
   Play's one-time $25; Apple is $99/year.)

3. **The build happens on a Mac — but a *cloud* Mac counts.**
   - You have "cloud Xcode" → that is a **Mac in a browser** (e.g. MacinCloud /
     MacStadium). That is the **best** option because you get a full Xcode and can
     do *everything* from it. This guide assumes that.
   - Alternative with **zero Mac at all**: Codemagic (see Appendix B).

---

## 1. What is ALREADY DONE ✅ (you don't touch these)

These were already set up in the code — you can tick them off:

| Item | Status | Value |
|---|---|---|
| iOS project exists & compiles | ✅ | `ios/Runner.xcworkspace` |
| **Bundle ID** (the app's unique id) | ✅ | `itp.com.magikdigi` |
| **App display name** (under the icon) | ✅ | `Magik Digi` |
| **Location** permission text | ✅ | done |
| **Bluetooth** permission text (printer) | ✅ | done |
| **Camera** permission text (QR scan) | ✅ | done |
| **Minimum iOS version** | ✅ | iOS 13.0 |
| **Version number** | ✅ | `1.0.0` (build `1`) |

So the code side is ready for a **first submission**. Everything below is **accounts,
signing, and clicking buttons** — no coding.

---

## 2. What is PENDING ⏳ (this whole guide)

1. Create an **Apple Developer account** (pay $99).
2. Register the **Bundle ID** in Apple's portal.
3. Create the **app record** in App Store Connect (the "iOS console").
4. **Sign** the app (Xcode does this automatically once you log in).
5. **Build** the app (`.ipa`) on the cloud Mac.
6. **Upload** it to App Store Connect → TestFlight.
7. **Test on your iPhone** via the TestFlight app.
8. Fill the **store listing** (screenshots, description, privacy) and **submit for review.**

---

## 3. Shopping list — get these ready NOW

- [ ] A working **email** + phone (for the Apple ID / Developer account).
- [ ] A **credit/debit card** for the $99/year.
- [ ] Your **iPhone** (to verify identity + test via TestFlight).
- [ ] Access to your **cloud Mac + Xcode**.
- [ ] A **Privacy Policy web page** (a public URL — Apple *requires* it). If you
      don't have one, make a simple page (even a Google Sites / Notion public page).
- [ ] **App screenshots** (you'll take these from the app on your iPhone or simulator).
- [ ] A short **app description** + a few **keywords** + a **category** (e.g. Business).

---

# 🚶 STEP-BY-STEP (do in this exact order)

## PHASE A — Apple Developer account  ⏱️ ~30 min + 1–2 days approval

1. On your **iPhone**, install the **"Apple Developer"** app (App Store) — it makes
   identity verification easy.
2. On Windows (or the phone), go to **developer.apple.com** → **Account** → sign in
   with your Apple ID (create one if needed).
3. Click **Enroll** in the Apple Developer Program.
4. Choose **Individual** (simplest — your name) or **Organization** (needs a D-U-N-S
   number, slower). For most, **Individual** is fine.
5. Pay **$99**. 
6. Apple may take **24–48 hours** to approve. ☕ Wait for the confirmation email.
   👉 Nothing else can happen until this is approved. Start here **today**.

---

## PHASE B — Register the Bundle ID  ⏱️ ~10 min (after approval)

1. Go to **developer.apple.com → Certificates, Identifiers & Profiles → Identifiers**.
2. Click the **+** button → **App IDs** → **App** → Continue.
3. **Description:** `Magik Digi`
4. **Bundle ID:** select **Explicit** and type exactly: `itp.com.magikdigi`
   ⚠️ It **must** match the code exactly — copy-paste it.
5. Under **Capabilities**, you can leave defaults (the app doesn't need special ones
   for a first release; Bluetooth/Camera/Location work via the permission texts
   already in the app).
6. Click **Register**.

---

## PHASE C — Create the app in App Store Connect ("iOS console")  ⏱️ ~15 min

1. Go to **appstoreconnect.apple.com** → **My Apps** → click **+** → **New App**.
2. Fill in:
   - **Platform:** iOS
   - **Name:** `Magik Digi` (this is what shows on the store)
   - **Primary Language:** English (India) or your choice
   - **Bundle ID:** pick `itp.com.magikdigi` from the dropdown (it appears because
     you registered it in Phase B)
   - **SKU:** any unique text, e.g. `magikdigi001` (internal only, never shown)
   - **User Access:** Full Access
3. Click **Create**. The app record now exists (empty — you'll fill it in Phase H).

---

## PHASE D — Get the project onto the cloud Mac  ⏱️ ~20 min

> You need the code + Flutter on the cloud Mac to build it.

1. Log into your **cloud Mac** (browser).
2. Open **Terminal** (Launchpad → Terminal).
3. Install Flutter **if it's not there**:
   - Easiest: follow **docs.flutter.dev → Get started → macOS**. (Download Flutter,
     unzip, add to PATH, run `flutter doctor`.)
4. Get your project onto the Mac:
   - If your code is in **git**: `git clone <your-repo-url>` then `cd` into it.
   - If not in git: zip the project folder on Windows, upload to the cloud Mac
     (Google Drive / the cloud Mac's file transfer), unzip.
5. In the project folder, run:
   ```
   flutter pub get
   cd ios
   pod install
   cd ..
   ```
   (If `pod install` complains, run `flutter build ios --no-codesign` once first —
   it generates the iOS config, then retry.)

---

## PHASE E — Signing (Xcode does it for you)  ⏱️ ~15 min

1. On the cloud Mac, open the project's iOS workspace in Xcode:
   - In Terminal: `open ios/Runner.xcworkspace`
   - ⚠️ Open **`Runner.xcworkspace`**, NOT `Runner.xcodeproj`.
2. In Xcode's left sidebar, click the blue **Runner** at the very top.
3. Select the **Runner** target → **Signing & Capabilities** tab.
4. ✅ Tick **"Automatically manage signing."**
5. **Team:** pick your Apple Developer account from the dropdown.
   - If it's not there: Xcode menu → **Settings → Accounts → +** → sign in with your
     Apple ID → then come back and pick the Team.
6. Confirm **Bundle Identifier** shows `itp.com.magikdigi`.
7. Xcode now **automatically creates the signing certificate + provisioning profile**.
   If you see a green checkmark / no red errors → signing is done. 🎉
   (This is the part the Android key CANNOT do — Apple must issue this.)

---

## PHASE F — Build the app (`.ipa`)  ⏱️ ~15–30 min

**Option 1 (simplest — Terminal):**
```
flutter build ipa --release --target lib/main_magik.dart
```
- ⚠️ The `--target lib/main_magik.dart` is **required** — without it the build uses
  the shared entry point and won't be the Magik app. (The iOS project is already set
  to the Magik bundle id + name, so **no `--flavor` flag is needed** for this
  single-app release.)
- When done, the file is at: `build/ios/ipa/*.ipa`.

**Option 2 (Xcode Archive — more visual):**
1. In Xcode, top bar → set the device target to **"Any iOS Device (arm64)"**
   (NOT a simulator).
2. Menu → **Product → Archive**.
3. When it finishes, the **Organizer** window opens with your archive.

> ⚠️ If build fails with **"CocoaPods not installed"** or pod errors → run
> `sudo gem install cocoapods` then `cd ios && pod install && cd ..` and rebuild.

---

## PHASE G — Upload to App Store Connect + TestFlight  ⏱️ ~15 min + processing

**If you used Xcode Archive (Option 2):**
1. In the **Organizer** → select the archive → **Distribute App**.
2. Choose **App Store Connect** → **Upload** → Next → Next (keep defaults) → **Upload**.

**If you used `flutter build ipa` (Option 1):**
1. Open the **Transporter** app on the Mac (free, from the Mac App Store).
2. Sign in with your Apple ID → **+ Add App** → pick the `.ipa` → **Deliver**.

**Then:**
3. Go to **appstoreconnect.apple.com → your app → TestFlight** tab.
4. Wait **15–60 minutes** — the build shows as **"Processing."** When it turns to a
   version number, it's ready.
5. If it asks about **Export Compliance**, answer **No** to "uses non-exempt
   encryption" (the app only uses standard HTTPS). *(Optional: I can add a one-line
   `ITSAppUsesNonExemptEncryption = NO` to Info.plist so it never asks again — tell
   me when you're ready; it's a config, not code.)*

---

## PHASE H — Test on YOUR iPhone via TestFlight  ⏱️ your pace

> This is how you test before the public sees it. No cables, no Mac.

1. On your **iPhone**, install the free **"TestFlight"** app from the App Store.
2. In **App Store Connect → your app → TestFlight → Internal Testing** → **+** →
   create a group → add yourself (your Apple ID email) as a tester.
3. Assign the processed build to that group.
4. You get an **email / TestFlight notification** → open TestFlight → **Install**.
5. **Test EVERYTHING** on the real phone:
   - Login (online + offline), Dashboard, Customer search + scan (camera),
   - **Payment** (cash + bank), **printing** (Bluetooth thermal printer),
   - Receipt / history print + share, Complaints, Analytics, Settings.
   - Confirm the permission popups (Location, Bluetooth, Camera) appear with your text.

👉 Fix anything broken → rebuild (Phase F) with a **higher build number**
(`1.0.0+2`, then `+3`…) → re-upload → re-test. Repeat until happy.

---

## PHASE I — Fill the store listing + Submit for review  ⏱️ ~2–4 hours + 1–3 day review

1. **App Store Connect → your app → the "1.0 Prepare for Submission" page.** Fill:
   - **Screenshots** (REQUIRED): at least one set for **6.7"** (iPhone 15 Pro Max size)
     and **6.5"**. Take them from the app on your iPhone (or a simulator on the Mac),
     screenshot the key screens (login, dashboard, payment, receipt).
   - **Description:** what the app does (a paragraph).
   - **Keywords:** e.g. `cable, billing, collection, dth, lco`.
   - **Support URL** + **Privacy Policy URL** (REQUIRED — the web page from your
     shopping list).
   - **Category:** Business (or Finance).
   - **Age Rating:** answer the questionnaire (likely 4+).
2. **App Privacy** section → declare what data you collect (login, location, etc.) —
   answer honestly (Apple requires this "nutrition label").
3. Under **Build**, click **+** and select the TestFlight build you tested.
4. Click **Add for Review** → **Submit for Review**.
5. Apple reviews in **1–3 days**. If **rejected**, they tell you why → fix → resubmit.
   Common rejections: missing privacy policy, permission text unclear, crash on launch
   — none of which apply if TestFlight testing (Phase H) passed. ✅

🎉 **Approved → it goes live on the App Store.**

---

## 4. ⏱️ Realistic Timeline

| Phase | Time |
|---|---|
| A. Apple Developer account (+approval) | 30 min + **1–2 days waiting** |
| B. Register Bundle ID | 10 min |
| C. Create app in App Store Connect | 15 min |
| D. Project onto cloud Mac | 20 min (once) |
| E. Signing in Xcode | 15 min |
| F. Build `.ipa` | 15–30 min |
| G. Upload + processing | 15 min + up to 1 hr wait |
| H. TestFlight testing | your pace (½–1 day) |
| I. Listing + submit + **Apple review** | 2–4 hrs + **1–3 days review** |
| **TOTAL** | **~1 week** (mostly waiting on Apple, not work) |

---

## 5. About the TWO apps (ezy + magik) — read this

- This app has **two flavors**: **Magik Digi** (`itp.com.magikdigi`) and
  **Ezy Cable Digi** (`com.ezy.cable.digi`). On Android these are two apps.
- **For your FIRST iOS release, do ONLY the Magik app** — that's what the current iOS
  project is set to (`itp.com.magikdigi`, built with `--target lib/main_magik.dart`).
  It's the simplest path and gets you into TestFlight fast.
- **Ezy as a second iOS app is a later step** — it needs a **second scheme +
  second bundle id** created in Xcode (easy on the cloud Mac) and its **own** App
  Store Connect record. It does **not** block the Magik app.

---

## 6. 🆘 Common errors & fixes (bookmark this)

| Error | Meaning | Fix |
|---|---|---|
| "No account for team / Signing requires a development team" | Not signed into Apple ID in Xcode | Xcode → Settings → Accounts → + → sign in → pick Team (Phase E) |
| "CocoaPods not installed" | Mac missing pods | `sudo gem install cocoapods` then `cd ios && pod install` |
| "The bundle ... is invalid / already exists" | Bundle ID mismatch/typo | Must be exactly `itp.com.magikdigi` everywhere |
| Build number already used | You re-uploaded the same `+1` | Bump `pubspec.yaml` version to `1.0.0+2`, `+3`… each upload |
| "Missing export compliance" | Encryption question | Answer **No** (standard HTTPS) — or add the plist key (ask me) |
| App rejected: privacy | No privacy policy URL | Add a public Privacy Policy web page |
| Android keystore doesn't work | You tried the Android key on iOS | It never will — iOS uses Apple certs (Phase E) |

---

## 7. What I need from YOU (so I can help further)

I can't create Apple accounts or click buttons for you, but I **can**:
- Add the `ITSAppUsesNonExemptEncryption` plist key (skips the compliance prompt).
- Set up the **Ezy second flavor** on iOS (schemes/config) when you're on the Mac.
- Bump the **version/build number** for re-uploads.
- Help debug any **build error** — just paste the exact error text here.

To move forward, tell me:
1. Is your **Apple Developer account** approved yet? (Phase A)
2. Is your **cloud Xcode** a full Mac-in-browser (you can open Xcode) or a CI service?
3. Do you have a **Privacy Policy URL**?

---

## 8. TL;DR — the shortest possible path

1. **Pay $99** for Apple Developer (today) → wait for approval.
2. Register Bundle ID `itp.com.magikdigi` → create the app in App Store Connect.
3. On the cloud Mac: open `ios/Runner.xcworkspace` in Xcode → tick **Automatically
   manage signing** → pick your **Team**.
4. `flutter build ipa --release --target lib/main_magik.dart` → upload via **Transporter**.
5. **TestFlight** it to your iPhone → test payment + printing.
6. Fill listing + **Submit for Review** → live in 1–3 days.

You've got this. One phase at a time. 

---

# 🍏🍎 BOTH APPS ON iOS — Ezy + Magik (flavors)

> You want **both** Ezy Cable Digi **and** Magik Digi live on the App Store. That's
> normal — it's **one codebase → two separate store apps**, exactly like your two
> Android apps. This section is everything for that.

## The mental model
| | Ezy app | Magik app |
|---|---|---|
| Dart entry | `lib/main_ezy.dart` | `lib/main_magik.dart` |
| Bundle id | `com.ezy.cable.digi` | `itp.com.magikdigi` |
| Display name | Ezy Cable Digi | Magik Digi |
| App Store record | its own | its own |
| TestFlight | its own | its own |

You do the **store side twice** (two bundle ids, two app records, two builds) + a
**one-time iOS "scheme" setup** in Xcode. After the one-time setup, building either
app is a single command.

> ⚠️ The scheme setup below is the **only** part that truly needs **Xcode on the Mac**
> (schemes live inside Xcode). Do it **with me live** the first time — ping me when
> you're on the cloud Mac and I'll confirm each screen. It's ~20 min, done once.

---

## PART M — One-time iOS flavor setup (in Xcode, on the cloud Mac)

### M1. Open the project
```bash
open ios/Runner.xcworkspace
```

### M2. Create build configurations for each flavor
1. Click the blue **Runner** at the very top of the left panel.
2. Select the **Runner PROJECT** (the top item, *not* the target below it) → **Info** tab.
3. Under **Configurations** you'll see **Debug / Release / Profile**.
4. For **each** one, click **+** → **Duplicate … Configuration**, and make these **six**:
   - `Debug-ezy`, `Debug-magik`
   - `Release-ezy`, `Release-magik`
   - `Profile-ezy`, `Profile-magik`

### M3. Set bundle id (+ name) per flavor
1. Click the **Runner TARGET** → **Build Settings** tab.
2. Search **"Product Bundle Identifier"** → expand it → set:
   - every **`*-ezy`** config → `com.ezy.cable.digi`
   - every **`*-magik`** config → `itp.com.magikdigi`
3. For the display name, we'll set `CFBundleDisplayName` per flavor (I'll show the
   exact spot live — the bundle id is the critical one).

### M4. Create the two schemes
1. Top bar → scheme dropdown (says "Runner") → **Manage Schemes…**
2. **+** → Target: Runner → name it exactly **`ezy`** → OK. Again → **`magik`**.
3. Edit **`ezy`** → for **Run / Test / Profile / Analyze / Archive**, set **Build
   Configuration** to the matching **`*-ezy`** (Run→Debug-ezy, Archive→Release-ezy, …).
4. Same for **`magik`** → the **`*-magik`** configs.
5. **Tick "Shared"** for BOTH schemes (so Flutter can see them).

### M5. Verify from Terminal (no account needed)
```bash
flutter build ios --flavor ezy   --target lib/main_ezy.dart   --no-codesign
flutter build ios --flavor magik --target lib/main_magik.dart --no-codesign
```
Both should compile. If it says *"scheme not found"* → the scheme name must match the
`--flavor` name **exactly** (`ezy` / `magik`) and be **Shared**.

---

## PART N — Two store records + two builds

1. **Register BOTH bundle ids** (Phase B, done twice): `com.ezy.cable.digi` **and**
   `itp.com.magikdigi`.
2. **Create BOTH apps** in App Store Connect (Phase C, twice):
   - "Ezy Cable Digi" → `com.ezy.cable.digi`
   - "Magik Digi" → `itp.com.magikdigi`
3. **Build + upload each** (on the cloud Mac):
   ```bash
   # Magik
   flutter build ipa --release --flavor magik --target lib/main_magik.dart
   # → upload the .ipa via Transporter → it auto-lands in the "Magik Digi" app

   # Ezy
   flutter build ipa --release --flavor ezy --target lib/main_ezy.dart
   # → upload → lands in the "Ezy Cable Digi" app
   ```
   Transporter routes each `.ipa` to the correct app **by its bundle id** — you don't
   pick; it just matches.
4. Each app has its **own TestFlight** → add testers → install on your iPhone.

---

## Ongoing (every future update)
- Bump the version (`1.0.0+2`, `+3`…).
- Build **both** flavors (the two commands above).
- Upload **both** `.ipa`s.
- Each goes to its own app / TestFlight.

## Remember
- **Both apps still share the ONE $99 account** — you don't pay twice.
- The current iOS project is set to a single identity (Ezy). Part M **replaces** that
  with proper `ezy` + `magik` schemes so both are buildable.
- Do Part M **with me on the Mac** the first time — it's fiddly once, trivial after.
