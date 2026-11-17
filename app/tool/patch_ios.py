"""Adds what Lumis needs to the iOS project made by `flutter create --platforms ios .` (safe to run again).

    python tool/patch_ios.py

- ios/Runner/Info.plist: the app name "Lumis" and the messages iOS shows when the app asks for the camera, the photo
  library or the location (without them iOS closes the app the moment it asks).
- ios/Podfile: iOS 13 or later, which the camera, location and secure storage plugins support.
"""
import plistlib
import re
import sys
from pathlib import Path

ios = Path(__file__).resolve().parents[1] / "ios"
info = ios / "Runner" / "Info.plist"
if not info.exists():
    sys.exit("Run `flutter create --platforms ios .` first: ios/Runner/Info.plist is missing.")

with info.open("rb") as f:
    plist = plistlib.load(f)
plist.update({
    "CFBundleDisplayName": "Lumis",
    "NSCameraUsageDescription": "Lumis uses the camera to take a photo of the skin you want to check.",
    "NSPhotoLibraryUsageDescription": "Lumis lets you choose a photo of your skin from your library.",
    "NSLocationWhenInUseUsageDescription": "Lumis uses your location only to sort dermatology clinics by distance. "
                                           "It is not stored.",
    "NSMicrophoneUsageDescription": "Lumis does not record sound. The camera asks for this permission by default.",
})
schemes = set(plist.get("LSApplicationQueriesSchemes", [])) | {"tel", "https"}
plist["LSApplicationQueriesSchemes"] = sorted(schemes)
with info.open("wb") as f:
    plistlib.dump(plist, f)
print("Info.plist: app name Lumis, camera / photo library / location messages, tel and https links")

podfile = ios / "Podfile"
if podfile.exists():
    p = podfile.read_text(encoding="utf-8")
    p2 = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", p, count=1, flags=re.M)
    if p2 != p:
        podfile.write_text(p2, encoding="utf-8")
        print("Podfile: iOS 13.0 or later")
    else:
        print("Podfile: left as it is")
else:
    print("Podfile: not there yet (Codemagic creates it on the first build; Flutter's default is iOS 13)")
