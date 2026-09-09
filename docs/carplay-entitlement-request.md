# CarPlay entitlement request

Working copy of the request submitted to Apple for the CarPlay **Driving Task**
entitlement, kept in the repo so the wording can be revised if the first attempt
is denied.

- **Submit at:** <https://developer.apple.com/contact/carplay> (behind Apple ID
  sign-in; use the Account Holder for team 9FALWGDAH9, since accepting the
  CarPlay Entitlement Addendum needs that role)
- **Entitlement:** `com.apple.developer.carplay-driving-task` (iOS 16+)
- **Status:** approved
- **Submitted on:** —
- **Outcome:** approved

**The form is the whole first step.** No build, TestFlight release or App Store
listing is required — Apple reviews the written description against predefined
criteria, then adds the entitlement to the *developer account* as a managed
capability. It is not granted to a bundle ID. Submitting early therefore costs
nothing: the review runs while the app is unchanged.

> Apple's [Requesting CarPlay Entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
> page lists only six entitlements and omits the driving task one. That page is
> out of date; the CarPlay Developer Guide (2026-06-08) lists
> `com.apple.developer.carplay-driving-task` as available since iOS 16. Select
> **Driving Task** on the form regardless of what that page shows.

Note also that CarPlay apps face an *additional* set of App Store Review
guidelines at submission time, separate from this entitlement grant.

---

## After approval

Approval alone changes nothing in a build. Three further steps are required, and
the second is the one that is easy to miss — skip it and the build still succeeds,
but the app silently never appears in the car:

1. **Identifiers → create an explicit App ID** for `com.axb.nesteferge`. The team
   currently signs against the wildcard profile `9FALWGDAH9.*`, and wildcard App
   IDs cannot carry CarPlay capabilities.
2. **App ID → Additional Capabilities tab → enable CarPlay → Save**, then
   generate a new provisioning profile and import it into Xcode.
3. **Turn off automatic signing** and point `CODE_SIGN_ENTITLEMENTS` back at
   `Nesteferge/Nesteferge.entitlements` (which already declares the key), dropping
   the `Nesteferge-Device.entitlements` override used for device builds today.

Until then there is no way to test on a real head unit: the entitlement gates
whether the icon appears on the CarPlay home screen, so neither a tethered device
nor Apple's standalone CarPlay Simulator is a way around it. Development stays on
the iOS Simulator via `scripts/run-carplay.sh`.

---

## Guidelines this app is written against

From the [CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf),
"Additional guidelines for CarPlay driving task apps". These are concrete and
checkable, so they are worth re-reading before any change to the CarPlay UI:

| # | Guideline | How Nesteferge complies |
|---|-----------|-------------------------|
| 1 | Must enable tasks people need to do while driving | Departure countdown for the quay being approached |
| 2 | Must use the provided templates | `CPListTemplate` + `CPInformationTemplate` only |
| 3 | No CarPlay UI for unrelated tasks | No settings or setup in the car |
| 4 | No refresh more than once per 10 s | `CarPlaySceneDelegate.countdownRefreshInterval` = 10 s |
| 5 | No POI refresh more than once per 60 s | No POI template used |
| 6 | Not a location finder | No search, browsing or map in the car |
| 7 | No use cases outside the vehicle | Input is GPS position and heading |

Guideline 4 is why the car shows a minute-resolution countdown
(`DepartureFormatter.coarseCountdown`) while the phone keeps its 1 Hz `mm:ss`
display. A ticking seconds value in the car would either breach the rule or
visibly jump in 10-second steps.

---

## Request text

> **App name:** Nesteferge
> **Bundle ID:** `com.axb.nesteferge`
> **Team ID:** 9FALWGDAH9
> **Requested entitlement:** `com.apple.developer.carplay-driving-task`
> **Category:** Driving Task
>
> **What the app does**
>
> Nesteferge tells drivers when the next Norwegian car ferry departs from the quay
> they are currently driving towards. Norway's road network depends on ferry
> crossings: for many journeys the ferry *is* a segment of the road, and the
> departure time determines whether you continue, slow down, or take an
> alternative route. The app covers 207 terminals across 158 routes.
>
> The app determines the relevant quay automatically from the device's GPS
> position and heading, then counts down to the next departure. The driver does
> not search, browse or type — the ferry they are approaching is inferred from the
> drive itself.
>
> **Why CarPlay is essential**
>
> This information is only useful while driving, and is needed at exactly the
> moment when handling a phone is least acceptable. A driver approaching a quay
> wants a single glance to answer "do I make this sailing?". Today that means
> picking up the phone at the point of the drive where attention matters most.
>
> The app has no use case outside the vehicle. Its input is the vehicle's position
> and heading; away from a road approaching a quay it has nothing to display.
>
> **Category fit — a driving task, not a location finder**
>
> The CarPlay UI cannot search for, browse or map ferry quays. It shows only the
> quays the driver is currently approaching, derived from GPS and heading, and the
> countdown for the selected one. There is no map, no POI browsing and no
> free-text search in the car. Text search exists in the iPhone app only, and is
> deliberately not exposed in CarPlay.
>
> The task is short and bounded: confirm the quay, read the countdown. Nothing in
> the CarPlay UI relates to account setup, configuration or any task unrelated to
> the drive.
>
> **Templates used**
>
> - `CPListTemplate` — nearby quays, populated automatically on connect, with a
>   single "Rescan" bar button.
> - `CPInformationTemplate` — the countdown, the next departure time and the
>   following two sailings.
>
> No other templates, no custom UI, no map or real-time video.
>
> **Safety considerations**
>
> - The countdown is reachable in one tap from the root list; the list populates
>   itself on connect, so the common case requires zero interaction.
> - Data items refresh once every 10 seconds, in line with the driving task
>   guidelines. The countdown is displayed at minute resolution ("12 min")
>   specifically so it remains accurate at that cadence rather than presenting a
>   ticking seconds value that would invite repeated glances.
> - List entries are short: quay name and route, sized for the templates' own
>   typography.
> - No interaction is ever required to keep information current; the display
>   updates itself.
> - Nothing in the CarPlay UI asks the driver to pick up their iPhone.
>
> **Expected launch timeline**
>
> The iPhone app is complete and is scheduled to ship in approximately three
> weeks. The CarPlay implementation is already built and tested against the
> CarPlay Simulator, and will ship in the first release following entitlement
> approval.
>
> **Expected user base**
>
> Fewer than 1,000 users in the first year, growing with adoption in Norway's
> ferry-dependent regions.

---

## Notes on the wording

- **User numbers are deliberately conservative.** Apple does not grant
  entitlements on the basis of scale — the review is category fit, safety and
  in-drive necessity. An inflated figure (Norway's entire population is about 5.5
  million) invites scrutiny of everything else in the request, and denials rarely
  come with reasons. National coverage is instead evidenced by the route and
  terminal counts, which come from the API's own `/api/health`.
- **The timeline separates the two releases** rather than implying CarPlay ships
  at launch, which is not possible: approval takes roughly 2–4 weeks and no
  CarPlay build can ship before it. The launch date is the one claim here that
  Apple can later observe, so it should stay accurate.
- **Guideline 6 is the likeliest point of challenge**, since a "nearby ferries"
  list superficially resembles a location finder. The defence is that the car UI
  cannot be used to *find* anything: it only surfaces what the drive implies. That
  argument is worth leading with in any appeal.
