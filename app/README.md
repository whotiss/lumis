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

## Screens (CP1 section 3.4.2)

| Screen | File | Requirement |
|---|---|---|
| Welcome (what Lumis is and is not) | `screens/welcome_screen.dart` | NFR8 |
| Consent (English / Bahasa Malaysia, versioned, required boxes start unticked) | `screens/consent_screen.dart` | NFR4 |
| Register, log in | `screens/register_screen.dart`, `login_screen.dart` | FR11 |
| Home (one main action) | `screens/home_screen.dart` | |
| Capture (camera with a square framing guide, gallery) | `screens/capture_screen.dart` | FR1 |
| Optional questions (skippable) | `screens/questions_screen.dart` | FR2 |
| Processing (and the photo-check message) | `screens/processing_screen.dart` | NFR1 |
| Result (band, explanation, screening-aid statement) | `screens/result_screen.dart` | FR3, FR4, FR5, FR9 |
| Find a dermatologist (by distance, or A to Z) | `screens/clinics_screen.dart` | FR6 |
| History (review, delete) | `screens/history_screen.dart` | FR7, FR10 |
| About the conditions | `screens/conditions_screen.dart` | FR8 |
| Settings (consents, log out, delete account) | `screens/settings_screen.dart` | FR10, NFR4 |

## Design decisions

- **State:** Provider. `AuthState` (login, consent status) is the only shared state; screens load their own data.
- **Login token:** Android encrypted storage (`flutter_secure_storage`), never plain preferences. An expired login
  returns the person to the welcome screen.
- **Camera:** in-app camera with a square guide. The photo is cropped to the square (80% of the shorter side) and
  scaled to at most 1280 px before upload, so what the person framed is what is analyzed and the upload stays small
  on mobile data. Gallery photos are sent whole (scaled to 1280 px).
- **Location:** asked for only on the clinic screen, only if the person agreed to it, and sent in the request body
  (never stored or logged by the server). Without it the list is A to Z.
- **Confidence:** a three-step band with a label, never a percentage. No red or green, so a result never looks like a
  verdict.
- **Questions before a screening:** optional and skippable. They are saved with the result; they do not change it, and
  the app says so.
- **Offline or server asleep:** every screen that loads data has a retry. The processing screen explains that the
  first check after a quiet period can take up to a minute (Cloud Run cold start).
