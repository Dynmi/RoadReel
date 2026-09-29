# RoadReel 1.0.0

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/roadreel-logo.png" width="88" alt="RoadReel app icon">
</p>

RoadReel turns a TeslaCam folder into one synchronized, searchable timeline. Browse Sentry, Saved, and Recent recordings; switch among up to six cameras; and export the moments you want to keep. Everything runs locally on your Mac—no account or upload required.

English is the default interface. Simplified Chinese is available from the sidebar at any time.

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/roadreel-overview.png" width="720" alt="RoadReel in English with anonymized demo metadata, six synchronized camera views, and a shared timeline">
</p>

## What you can do

- Plug in a TeslaCam USB drive and let RoadReel discover your recordings. Reconnected drives load automatically; macOS may ask for folder access the first time.
- Browse Recent, Saved, and Sentry events with thumbnails, search, and sorting.
- Watch up to six cameras on one timeline. Switch between Single, All Cameras, and Spatial views, with each camera's original aspect ratio preserved.
- Review footage at up to 8× speed, zoom into details, or enter full screen.
- Adjust playback brightness and contrast without altering your files.
- Easily export a full camera recording or a ±30-second MP4 excerpt to save or share.
- Trim every camera together: choose the range, preview it, and use **Trim & Replace**. Cameras are processed in parallel; the same project name and recording structure are retained, and the original goes to Trash after verification.
- Use compact native macOS controls on a white workspace, with English and Simplified Chinese interfaces.
- Check GitHub Releases automatically for updates. When an update is available, click the amber sidebar button to download, verify, install, and reopen RoadReel.
- Open the GitHub project from the app logo, sidebar, menu, or the visible link on the welcome screen.

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/roadreel-spatial.png" width="720" alt="Spatial view showing all six cameras around the vehicle">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/roadreel-camera-switch.png" width="560" alt="Single view with the full camera frame, camera thumbnails, and bottom playback controls">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/roadreel-trim.png" width="720" alt="Selecting a time range to retain across all six cameras">
</p>

Vehicle speed, steering, brake, and accelerator values are not included in standard TeslaCam USB exports. RoadReel shows the available footage and event data without inventing telemetry.

## Download

- [RoadReel-1.0.0.dmg](https://github.com/Dynmi/RoadReel/releases/download/v1.0.0/RoadReel-1.0.0.dmg) — installer image

Requires macOS 14 or later. The universal build supports both Apple silicon and Intel Macs.

This refreshed 1.0 release contains build 2. If you have the original build without an updater, install this DMG once to enable future in-app updates. `appcast.xml` is the signed update metadata used by RoadReel; you only need to download the DMG.

## First launch

This community build is ad-hoc signed, but not Apple-notarized. After copying RoadReel to Applications, Control-click it and choose **Open**. If macOS blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway** beside the RoadReel message.

如果 macOS 拦截 RoadReel，请打开“系统设置 → 隐私与安全性”，点击 RoadReel 提示旁的“仍要打开（Open Anyway）”。

<p align="center">
  <img src="https://raw.githubusercontent.com/Dynmi/RoadReel/main/docs/open-anyway.png" width="520" alt="Open Anyway for RoadReel in macOS Privacy & Security">
</p>

The app screenshots use anonymized sample location metadata. No source videos are included in the download or this repository.

RoadReel is independent software and is not affiliated with Tesla, Inc.
