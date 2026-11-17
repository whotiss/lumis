# Lumis app (Flutter, Android)

The phone app. It holds no clinical logic: every result sentence, band and explanation comes from the backend
(`backend/app/wording.py`), so the screening-aid wording (NFR8) lives in one place.

## First-time setup (Windows, PowerShell, from the `app` folder)

```powershell
flutter create --project-name lumis --org my.lumis --platforms android .
flutter pub add provider http http_parser flutter_secure_storage camera image_picker image geolocator url_launcher intl
python tool/patch_android.py
flutter analyze
flutter test
```

`flutter create` adds the Android project around the existing `lib/` and `test/` (it does not overwrite them).
`tool/patch_android.py` adds the camera, location and internet permissions, the app name and minSdk 24.

## Run

Phone connected by USB with developer mode and USB debugging on (or an emulator):

```powershell
flutter run
```

The app talks to the live server on Cloud Run. For a backend on this computer:
`flutter run --dart-define=API_URL=http://10.0.2.2:8000` (emulator) or your computer's address on the Wi-Fi.

Release build for testers: `flutter build apk --release` (the file is `build/app/outputs/flutter-apk/app-release.apk`).

## iPhone (no Mac needed)

The iOS app is built on a cloud Mac by **Codemagic** and installed from Windows with **Sideloadly**, using a normal
Apple ID. An app installed this way **stops opening after 7 days**: reinstall it the day before a demo. (With the paid
Apple Developer Program, US$99 a year, a TestFlight build lasts 90 days instead.)

Once, in the `app` folder:

```powershell
flutter create --platforms ios .
python tool/patch_ios.py
```

Then commit and push. `patch_ios.py` adds the messages iOS shows when the app asks for the camera, photos or location
(without them iOS closes the app) and the name "Lumis".

1. **Build:** sign in at codemagic.io with GitHub, add the `lumis` repository, choose `codemagic.yaml`, start the
   workflow **iOS for sideloading**. After about 10 to 15 minutes download `lumis-unsigned.ipa` from the build page.
2. **iPhone, once:** Settings, Privacy & Security, Developer Mode on (the phone restarts).
3. **Install:** Sideloadly on Windows (it needs Apple's iTunes and iCloud from apple.com, not the Microsoft Store
   versions). Connect the iPhone by cable, drop the `.ipa` in, enter your Apple ID, Start.
4. **iPhone, first launch:** Settings, General, VPN & Device Management, trust your Apple ID.

## Screens (CP1 section 3.4.2)

| Screen | File | Requirement |
|---|---|---|
| Welcome (what Lumis is and is not) | `screens/welcome_screen.dart` | NFR8 |
| Consent (English / Bahasa Malaysia, versioned, required boxes start unticked) | `screens/consent_screen.dart` | NFR4 |
| Register, log in | `screens/register_screen.dart`, `login_screen.dart` | FR11 |
| Home (one main action) | `screens/home_screen.dart` | |
| Capture (camera with a square framing guide, live light and steadiness check, gallery) | `screens/capture_screen.dart`, `photo_check.dart` | FR1 |
| Optional questions (skippable) | `screens/questions_screen.dart` | FR2 |
| Analyzing (progress ring, steps; and the photo-check message) | `screens/processing_screen.dart` | NFR1 |
| Result (confidence scale, explanation, screening-aid statement, share with a doctor as PDF) | `screens/result_screen.dart`, `report_pdf.dart` | FR3, FR4, FR5, FR9 |
| Find a dermatologist (map, filters, call / directions / website, lower-cost option) | `screens/clinics_screen.dart` | FR6 |
| History (review, delete) | `screens/history_screen.dart` | FR7, FR10 |
| About the conditions | `screens/conditions_screen.dart` | FR8 |
| Settings (light / dark / match phone, consents, log out, delete account) | `screens/settings_screen.dart` | FR10, NFR4 |

## Look and feel ("follow the light", redesign 2026-11-18)

- **Colors:** cream, paper and indigo in light mode; night blue and lavender in dark mode (`theme.dart`,
  `LumisPalette`). Settings has Light / Dark / Match phone; the moon/sun button on Home switches directly. The camera
  is always dark.
- **Type:** Jost Light for headings and the LUMIS wordmark, Inter for reading text, bundled in `assets/fonts`
  (SIL Open Font License, Latin only; Chinese text will use the phone's own font).
- **The star** (`sparkle.dart`): a four-point star with a star-shaped glow that slowly brightens and dims. It also shows
  confidence: bright and glowing for High, faint for Low, an outline for Inconclusive. The animation stops when the
  phone asks for reduced motion.
- **Confidence scale:** Inconclusive / Low / High. There is no "Moderate" step: on 2026-11-15 the moderate band was
  labeled "Low confidence" because those results were right only 31% of the time on phone photos.
- **Analyzing screen:** "Photo received" is real progress (bytes sent). After that the server reports no progress, so
  the ring moves on a timer based on the usual 4 to 5 seconds and only closes when the result arrives.
- **Live camera check:** light (too dark / too bright) and movement, measured on the centre square of the preview a few
  times a second. Focus is not checked live, because smooth skin has little texture and would often be called
  blurry. The thresholds in `photo_check.dart` are first guesses to tune on real phones. It warns; it never blocks.
- **Share with a doctor:** a one-page A4 PDF (photo, result, the person's answers, Claude's description, how reliable
  the model was in testing from `GET /model`, and "not a diagnosis, not clinically validated"). Made on the phone and
  shared with the phone's share sheet; nothing is uploaded.
- **Map:** OpenStreetMap tiles through `flutter_map`, with the attribution OpenStreetMap requires. Directions open
  Apple Maps on iPhone and Google Maps on Android.

## Design decisions

- **State:** Provider. `AuthState` (login, consent status) is the only shared state; screens load their own data.
- **Login token:** Android encrypted storage (`flutter_secure_storage`), never plain preferences. An expired login
  returns the person to the welcome screen.
- **Camera:** in-app camera with a square guide. The photo is cropped to the square (80% of the shorter side) and
  scaled to at most 1280 px before upload, so what the person framed is what is analyzed and the upload stays small
  on mobile data. Gallery photos are sent whole (scaled to 1280 px).
- **Location:** asked for only on the clinic screen, only if the person agreed to it, and sent in the request body
  (never stored or logged by the server). Without it the list is A to Z.
- **Confidence:** a three-step star scale with the server's sentence, never a percentage. No red or green, so a result
  never looks like a verdict.
- **Questions before a screening:** optional and skippable. They are saved with the result; they do not change it, and
  the app says so.
- **Offline or server asleep:** every screen that loads data has a retry. The processing screen explains that the
  first check after a quiet period can take up to a minute (Cloud Run cold start).
