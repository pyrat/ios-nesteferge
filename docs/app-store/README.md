# App Store screenshots

Real simulator captures of the app using the production API and simulated GPS
positions in Norway. Captured on 5 October 2026; departures and countdowns reflect
the time of capture, not a fixed demonstration timetable.

## Upload

In App Store Connect, open **Distribution → iOS App 1.0 → App Previews and
Screenshots**. Select the listing language, then upload the matching files:

| Listing language | Device | Folder | PNG dimensions |
| --- | --- | --- | --- |
| Norwegian | iPhone 6.5-inch | `screenshots/nb/iphone/` | 1284 × 2778 |
| Norwegian | iPad 13-inch | `screenshots/nb/ipad/` | 2064 × 2752 |
| English | iPhone 6.5-inch | `screenshots/en/iphone/` | 1284 × 2778 |
| English | iPad 13-inch | `screenshots/en/ipad/` | 2064 × 2752 |

Use filename order: Anda–Lote, Festøya–Hundeidvika, Moss–Horten. Each image shows the
departure countdown, following sailings and nearby crossings for that location.
These are full-screen app captures; no device frame or marketing caption is
required to upload them. The contact sheet is a review aid, not an upload asset.

Captured with iPhone 17 Pro Max and iPad Pro 13-inch (M5), iOS 26.5. The main app
screens use Bokmål or English; simulator system chrome may use English.

The iPhone upload images have been proportionally resized with a small centred
vertical crop to match the 6.5-inch upload slot. Original 1320 × 2868 captures
are preserved in `originals/iphone-6.9/`. The capture script produces native-size
images; repeat this conversion if recapturing for the 6.5-inch slot.

## Recreate

From the iOS repository root, build a simulator app:

```sh
xcodebuild -quiet -project Nesteferge.xcodeproj -scheme Nesteferge \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /path/to/screenshot-build CODE_SIGNING_ALLOWED=NO build

python3 scripts/capture-store-screenshots.py \
  /path/to/screenshot-build/Build/Products/Debug-iphonesimulator/Nesteferge.app
```

The script's default simulator IDs refer to the capture machine; pass `--iphone`
and `--ipad` to use other devices. Choose devices with supported screenshot sizes.
The script reinstalls Nesteferge on those simulators, clearing their saved route
selection, and changes simulated location and appearance. It clears status-bar
overrides when finished. It does not change application source code.

Review every capture for loading/error screens before upload. Slow network
responses can require a longer wait in the capture script. If your capture tool
produces an alpha channel, convert to RGB PNG without changing the dimensions.

[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
