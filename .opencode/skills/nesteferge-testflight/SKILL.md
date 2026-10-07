---
name: Nesteferge TestFlight
description: Release a new Nesteferge TestFlight build, increment the build number, run tests, archive and upload with Xcode, then commit and push the release to GitHub.
---

# Nesteferge TestFlight release

Run commands from the repository root. `ExportOptions.plist` beside this skill
contains the tested upload settings; its repository path is
`.opencode/skills/nesteferge-testflight/ExportOptions.plist`.

## App and prerequisites

- Project/scheme: `Nesteferge.xcodeproj` / `Nesteferge`.
- Bundle ID: `com.axb.nesteferge`; Apple team: `9FALWGDAH9`.
- App Store Connect app ID: `6816964574`.
- `Nesteferge/Info.plist` declares `ITSAppUsesNonExemptEncryption = false`:
  the app only uses Apple's built-in HTTPS networking. Preserve this declaration
  to avoid the encryption compliance questionnaire on each upload. Reassess it
  if custom encryption or cryptographic dependencies are introduced. Confirm the
  key is present and false in the archived app's `Info.plist` before upload.
- Use the signed-in Xcode account and automatic signing with
  `-allowProvisioningUpdates`. If authentication fails, ask the user to sign in
  through Xcode Settings > Accounts, then retry the failed step.
- Preserve the existing CarPlay entitlement. Successful build 3 archives include
  `com.apple.developer.carplay-driving-task`; do not use the simulator signing
  workaround for a distribution archive.

## Workflow

1. Inspect `git status --short --branch`, the diff, remotes, and recent commits.
   Fetch the remote and check divergence before releasing. Preserve unrelated
   work and stage only the intended release files. Use the current branch unless
   repository policy requires a release branch; never force-push.
2. Determine the latest build from App Store Connect if available, current
   `CURRENT_PROJECT_VERSION`, and recent archives under
   `~/Library/Developer/Xcode/Archives`. Archive `Info.plist` distribution records
   show whether a build was uploaded successfully. Choose an unused increasing
   build number and update all four `CURRENT_PROJECT_VERSION` entries in
   `Nesteferge.xcodeproj/project.pbxproj` (app/tests, Debug/Release). Keep
   `MARKETING_VERSION` unchanged unless a new app version was requested.
3. Run the existing test suite on an available iOS simulator (discover its ID
   with `xcrun simctl list devices available`):

   ```sh
   xcodebuild -project Nesteferge.xcodeproj -scheme Nesteferge -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' CODE_SIGNING_ALLOWED=NO test
   ```

   Store lengthy logs outside the repository, preferably in the harness-provided
   temporary directory. Resolve test failures before uploading.
4. Archive the exact release source with a unique path under Xcode's dated
   Archives directory, so the result also appears in Organizer:

   ```sh
   xcodebuild -project Nesteferge.xcodeproj -scheme Nesteferge -configuration Release -destination 'generic/platform=iOS' -archivePath '<ARCHIVE_PATH>' -allowProvisioningUpdates archive
   ```

   Require `ARCHIVE SUCCEEDED`. Check the archive's `Info.plist` for the expected
   version, build, bundle ID, and team before uploading.
5. Upload the archive:

   ```sh
   xcodebuild -exportArchive -archivePath '<ARCHIVE_PATH>' -exportOptionsPlist .opencode/skills/nesteferge-testflight/ExportOptions.plist -allowProvisioningUpdates
   ```

   Require `Upload succeeded` and `EXPORT SUCCEEDED`. Preserve logs and archive
   paths. If a build number is already used, increment the project number and
   create a fresh archive. Do not claim an upload succeeded from archive success
   alone. An upload reporting "processing" is submitted, not yet available to
   testers; check processing status when authenticated App Store Connect access
   is available. Do not submit an App Store production release.
6. Review `git diff --check` and the staged diff, commit the fix and build bump
   (plus workflow updates if applicable), then push to the current branch's
   GitHub upstream. If branch protections reject the push, follow the repository's
   PR workflow. Verify the remote commit and local status after pushing.
7. Report the app version/build, upload versus processing status, commit SHA,
   branch/GitHub link, test result, and any remaining blocker. Suggested tester
   notes should describe user-visible changes in the actual release.

Never commit archives, signing material, credentials, or upload logs.
