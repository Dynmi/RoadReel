# App updates

RoadReel uses Sparkle 2.10.0 with a custom sidebar interface. Checks run at launch and every six hours while running. Nothing downloads until the user clicks the dark amber **Update** button. The app menu also offers **Check for Updates…**. The update downloads, verifies, installs and relaunches; the installed application and recordings remain intact if verification or download fails. The UI blocks new recording operations during installation, and an update cannot start during export, trim or deletion in any window.

The feed is `https://github.com/Dynmi/RoadReel/releases/latest/download/appcast.xml`. Each published release must contain its DMG **and the matching signed appcast.xml**. The feed is update metadata, not another installation package. Keep the release published, stable and marked latest. Upload the DMG first and the feed last. Never edit a signed feed by hand.

## Signing and builds

The app requires Ed25519 signatures for both the feed and archive, including verification before extraction. Only the public key is in `Configuration/Info.plist`. The private key is stored in the macOS login Keychain under Sparkle's account `io.github.Dynmi.RoadReel`. Do not commit, print or upload it. Keep a secure private backup when moving release machines. Do not generate a replacement key for existing installations: without a Developer ID identity, losing this key requires a manual reinstall to establish new trust.

The initial integrated build is `1.0.0 (2)`. Sparkle compares `CFBundleVersion`, so **increase CURRENT_PROJECT_VERSION for every published build**, including replacements of the same `v1.0.0` release. Changing only the visible version or overwriting an asset is insufficient. An explicit build can also be supplied to packaging:

```sh
./scripts/build-release.sh 1.0.0 3
```

This produces `release/RoadReel-1.0.0.dmg` and `release/appcast.xml`. It does not publish. The script checks that the Keychain public key matches the application's embedded public key and refuses to create an unsigned feed. An ordinary Xcode build needs no release key. Forks must use their own key and feed URL.

The first updater-enabled version must be installed manually by users of the original 1.0 build, which contains no updater. If the feed is unavailable, automatic checks stay quiet; manual checks report a connection/feed error rather than falsely claiming the application is current.

## Sandbox and packaging

Keep App Sandbox enabled. The application has outgoing network access and Sparkle's two bundle-specific mach-lookup exceptions. `SUEnableInstallerLauncherService` enables Sparkle's installer XPC service. `scripts/sign-app.sh` expands the bundle ID in entitlements and signs nested components in order. Avoid signing nested executables with the app's sandbox entitlements or using `codesign --deep` to sign them.

Public builds currently use ad-hoc code signatures. Ed25519 provides update authenticity, but does not replace Apple's notarization/Gatekeeper checks. macOS can require authorization when the application is installed in a location owned by another user. The standard Sparkle installer handles that prompt; do not bypass system authorization or strip quarantine.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [sandbox integration](https://sparkle-project.org/documentation/sandboxing/), [publishing updates](https://sparkle-project.org/documentation/publishing/).

## Integration tests

After a local Release build, run:

```sh
python3 scripts/test-app-updates.py build/release-1.0.0/DerivedData/Build/Products/Release/RoadReel.app
```

This needs the release signing key and a logged-in macOS desktop. It creates isolated application copies and sandbox IDs, serves signed test feeds on localhost, and exercises the real installer. Cases cover same-visible-version build upgrades and relaunch, recording-operation interlocks, cancellation and retry, corrupt downloads, altered feeds, current builds and missing feeds. Local HTTP is enabled only in those disposable fixtures. It never installs over `/Applications/RoadReel.app` or accesses recordings. Test artifacts and result logs remain under `build/updater-tests-*`.
