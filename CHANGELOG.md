# Changelog

## 1.0.0 — refreshed 2026-10-03 (build 2)

- Add GitHub project links to the sidebar, app menu, top-left logo, and empty player page. Make the empty page's folder-selection button slightly larger.
- Check GitHub Releases for signed updates at launch and every six hours. Show a dark amber sidebar button when an update is available; one click downloads, verifies, installs and relaunches. Downloads can be cancelled, and recording operations block installation.
- Integrate Sparkle 2.10 with its sandboxed installer and signed feeds/archives. Package a DMG and appcast.xml; increment the internal build number even when retaining the 1.0 release tag.

- Browse local TeslaCam USB drives and folders, with Recent, Saved, and Sentry categories, searchable recording thumbnails, sorting, and English/Simplified Chinese interfaces.
- Automatically discover connected drives at launch, retry while newly mounted drives become ready, and reload after reconnecting. Preserve folder authorization while offline and explain access failures instead of showing an empty library.
- Play up to six cameras in sync using Single, All Cameras, and Spatial layouts. Preserve every camera's original aspect ratio, highlight identifiable event cameras, and show event and segment markers on the shared timeline.
- Use trackpad zoom and pan in Single view, with video-focused full-screen playback and predictable exit controls.
- Give the main video more space with a compact sidebar, larger recording thumbnails, bottom playback controls, and native macOS buttons and segmented controls on a white workspace.
- Include 0.5×–8× playback and brightness/contrast controls that also work on paused frames without changing recordings or exported files.
- Export a camera's full recording or a ±30-second MP4 excerpt from the Export menu or camera context menu.
- Trim recordings with draggable timeline endpoints, playhead start/end buttons, and range preview. Keep the same project name and TeslaCam structure, verify staged outputs before replacement, and move originals to Trash with rollback on failure.
- Trim up to six cameras concurrently and report completion progress. Accept normal camera-duration differences, restrict the range to footage available on every camera, and drain cancelled or failed exports before cleaning up staged files.
- Include the black car-and-sensing app icon, a compact drive selector, and a vertical storage indicator.
- Ship universal Apple silicon and Intel packages for macOS 14 and later. Videos stay local; no account, upload, analytics SDK, or cloud service is required.

The original 1.0.0 release was published on 2026-09-29. This refreshed source and download retain the same version and release tag.
