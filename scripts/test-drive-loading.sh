#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d "${TMPDIR:-/tmp}/roadreel-drive-test.XXXXXX")
ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=c=teal:s=192x128:r=24:d=2' -c:v libx264 -pix_fmt yuv420p "$scratch/sample.mp4"
swiftc -module-cache-path "$scratch/module-cache" -target "$(uname -m)-apple-macosx14.0" -parse-as-library -o "$scratch/test-drives" RoadReel/AppLanguage.swift RoadReel/ThumbnailService.swift RoadReel/TeslaCamViewModel.swift RoadReel/TeslaProjectTrimmer.swift scripts/test-drive-loading.swift
"$scratch/test-drives" "$scratch"
printf 'Test artifacts: %s\n' "$scratch"
