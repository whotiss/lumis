"""Adds what Lumis needs to the Android project made by `flutter create` (safe to run more than once).

    python tool/patch_android.py

- AndroidManifest.xml: internet (release builds need it), camera and location permissions, the app name "Lumis",
  and the <queries> Android 11+ needs before the app may open the phone dialer, maps and web pages.
- app/build.gradle(.kts): minSdk 24 (Android 7.0), which the camera, secure storage and location plugins support.
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "android" / "app"
manifest = root / "src" / "main" / "AndroidManifest.xml"
if not manifest.exists():
    sys.exit("Run `flutter create` first: android/app/src/main/AndroidManifest.xml is missing.")

raw = manifest.read_bytes().decode("utf-8")
crlf = "\r\n" in raw                         # Windows line endings: work on \n, write back as they were
m = raw.replace("\r\n", "\n")
permissions = [
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
]
missing = [p for p in permissions if p not in m]
if missing:
    lines = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in missing)
    m = re.sub(r"(<manifest[^>]*>\n)", r"\1" + lines.replace("\\", "\\\\"), m, count=1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Lumis"', m, count=1)
if "android.intent.action.DIAL" not in m:
    queries = (
        "        <intent>\n            <action android:name=\"android.intent.action.DIAL\"/>\n"
        "            <data android:scheme=\"tel\"/>\n        </intent>\n"
        "        <intent>\n            <action android:name=\"android.intent.action.VIEW\"/>\n"
        "            <data android:scheme=\"https\"/>\n        </intent>\n"
    )
    if "<queries>" in m:
        m = m.replace("<queries>\n", "<queries>\n" + queries, 1)
    else:
        m = m.replace("</manifest>", "    <queries>\n" + queries + "    </queries>\n</manifest>", 1)
manifest.write_bytes((m.replace("\n", "\r\n") if crlf else m).encode("utf-8"))
print("AndroidManifest.xml: permissions", "added " + ", ".join(missing) if missing else "already there",
      "| label Lumis | queries for dialer and web")

gradle = next((p for p in [root / "build.gradle.kts", root / "build.gradle"] if p.exists()), None)
if gradle:
    g = gradle.read_text(encoding="utf-8")
    g2 = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", lambda x: "minSdk = 24" if gradle.suffix == ".kts"
                else "minSdkVersion 24", g)
    if g2 != g:
        gradle.write_text(g2, encoding="utf-8")
        print(gradle.name + ": minSdk set to 24")
    else:
        print(gradle.name + ": minSdk left as it is (check it is at least 24)")
