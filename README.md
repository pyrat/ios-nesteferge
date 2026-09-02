# Nesteferge for iOS

Native iOS client for the [Nesteferge](../nesteferge) ferry timetable API. Finds the
Norwegian ferry you are driving towards from your GPS position and heading, then
counts down to the next departure. Runs on iPhone, iPad and CarPlay.

Deliberately plain: stock SwiftUI controls, system fonts and colours, Dynamic Type
and dark mode for free. The only colour in the app is the countdown turning amber
under ten minutes and red under two.

## Requirements

- Xcode 16 or later (developed against Xcode 26.5)
- iOS 17.0+
- A running Nesteferge API (see below)

## Running

```sh
# 1. Start the API from the sibling repo
cd ../nesteferge && go run ./cmd/ferrytimes-api      # listens on :8000

# 2. Build and run
open Nesteferge.xcodeproj
```

Or from the command line:

```sh
xcodebuild -scheme Nesteferge -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme Nesteferge -destination 'platform=iOS Simulator,name=iPhone 16' test
```

In the Simulator, set a position near a quay so `/api/guess` returns something:
**Features ▸ Location ▸ Custom Location…** → `62.39`, `6.33` (Festøya/Solavågen), or:

```sh
xcrun simctl location booted set 62.39,6.33
```

> **If the scan says no ferries were found, check this first.** The Simulator
> defaults to Cupertino and resets to it readily; `/api/guess` correctly returns
> zero candidates for any location outside Norway.

### Pointing at a different API

The base URL defaults to `http://localhost:8000` and can be changed two ways, in
increasing precedence:

1. The `NESTEFERGE_API_BASE_URL` build setting (baked into `Info.plist`).
2. The **Settings** sheet in the app (gear icon), which persists to `UserDefaults`.
   It has a *Test connection* button that pings `/api/health`.

App Transport Security only permits cleartext HTTP for `localhost`; any other host
must be HTTPS.

## CarPlay

The CarPlay scene is declared in `Info.plist` under
`CPTemplateApplicationSceneSessionRoleApplication` and handled by
`CarPlaySceneDelegate`.

To test it:

```sh
scripts/run-carplay.sh
```

That builds, installs, boots the simulator and sets a location near a quay. Then:

1. In the Simulator menu: **I/O ▸ External Displays ▸ CarPlay** (only needed once —
   the setting persists per device).
2. Open Nesteferge from the CarPlay home screen window.

To grab a picture of the car screen rather than the phone:

```sh
xcrun simctl io booted screenshot --display 2 /tmp/carplay.png
```

> If clicks in the Simulator stop registering entirely — including on built-in apps
> like Messages — the Simulator's input state has wedged. Quit and reopen it.
> If the CarPlay screen goes blank after the app is terminated, reconnect the
> display via **I/O ▸ External Displays** (Disabled, then CarPlay).

The car UI is intentionally a reduced version of the phone:

- A `CPListTemplate` of nearby ferries, populated automatically on connect, with a
  **Rescan** bar button.
- Tapping one pushes a `CPInformationTemplate` with the countdown, the next
  departure and the two after it, refreshed in place once a second.
- **No text search.** Typing a quay name is not something to be doing while
  driving, and CarPlay's list limits make it a poor fit anyway.

Phone and car share one `FerryStore`, so selecting a ferry in one updates the other.

> **Entitlement:** shipping CarPlay to a real head unit or the App Store requires
> `com.apple.developer.carplay-driving-task`, which Apple must grant
> (<https://developer.apple.com/carplay/>).
>
> The Simulator needs it too, and this is genuinely awkward:
>
> - **Without** it the app never appears on the CarPlay home screen. The
>   `Info.plist` scene manifest alone is not enough.
> - **With** it applied via `codesign`, AMFI rejects the binary and the app cannot
>   launch — POSIX 153 (`EBADEXEC`), reported as the misleading
>   *"request was denied by service delegate (SBMainWorkspace)"*.
> - `xcodebuild` silently strips the key from the `.xcent`, because no
>   provisioning profile grants it, so a plain build is launchable but invisible.
>
> `scripts/run-carplay.sh` resolves this with a two-pass install: sign with the
> entitlement and install to register the CarPlay capability, then sign without it
> and install *over the top* to get a launchable binary. Don't `simctl uninstall`
> between the passes, and re-run the script after erasing the device.

## Architecture

```
Nesteferge/
  App/        NestefergeApp.swift          SwiftUI entry point
  Core/       Models.swift                 Codable mirrors of openapi.yaml
              APIClient.swift              actor; async GETs, error mapping
              AppSettings.swift            base URL + last selection (UserDefaults)
              LocationService.swift        CLLocationManager → single async fix
              DepartureFormatter.swift     countdown / clock / day labels (Europe/Oslo)
              FerryStore.swift             @Observable single source of truth
  Views/      RootView, CountdownView, CandidateRow, SettingsView
  CarPlay/    CarPlaySceneDelegate.swift   CPListTemplate + CPInformationTemplate
  Resources/  Assets.xcassets, en/nb/nn.lproj
```

`FerryStore` owns the whole lifecycle — guess, selection, departures, the 1 Hz
countdown and the 60 s schedule refetch — and both UIs are thin renderers over it.
The refetch is what keeps the list correct across midnight; timers are suspended
when the app is not active.

### Notes on behaviour worth knowing

- **Heading**: the GPS course is only trusted while actually moving
  (`speed > 0.5 m/s`); otherwise the magnetic compass is used, which is the only
  useful signal when sitting stationary at a quay. This mirrors the web app.
- **Times** are always rendered in `Europe/Oslo` regardless of device time zone,
  because that is what the API's schedules mean. "Today"/"Tomorrow" are compared
  in Oslo calendar days for the same reason.
- **Search results** are promoted into the candidate list so a manually chosen
  route is also visible in CarPlay. They carry no distance, so the row shows the
  county instead.

## Localization

English (base), Norwegian bokmål (`nb`) and nynorsk (`nn`), ported from the web
app's i18n table. The language follows the system setting.

## Tests

36 tests in `NestefergeTests`:

- `ModelDecodingTests` — decodes the exact payloads from `../nesteferge/API.md`, so
  the tests fail if the documented contract and the Swift models drift apart.
  Covers nullable fields and the `+02:00` / fractional-seconds timestamp shapes.
- `APIClientTests` — `URLProtocol` stub; verifies query construction (including
  that `heading` is omitted when unavailable) and 404/422/500 error mapping.
- `DepartureFormatterTests` — countdown formatting, Oslo clock rendering and day
  labels across midnight.
- `AppSettingsTests` — URL normalisation and selection persistence.

```sh
xcodebuild -scheme Nesteferge -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Not implemented

Left out of v1 on purpose, all straightforward to add on top of `FerryStore`:
MapKit view of the route, Home Screen widget / Live Activity, offline caching of
`/api/routes` and `/api/terminals`, and favourites.
