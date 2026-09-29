#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null
scratch=$(mktemp -d "${TMPDIR:-/tmp}/roadreel-trim-test.XXXXXX")
for color in red lime blue; do
  ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=$color:s=192x128:r=24:d=3" -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$scratch/$color.mp4"
done
for spec in 'red-short red 2.75' 'lime-short lime 2.5'; do
  read -r name color duration <<< "$spec"
  ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=$color:s=192x128:r=24:d=$duration" -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=$duration" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$scratch/$name.mp4"
done
ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=c=yellow:s=1544x1000:r=24:d=3' -c:v libx265 -x265-params log-level=error -tag:v hvc1 -pix_fmt yuv420p "$scratch/native-hevc.mp4"
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library -o "$scratch/test-trim" RoadReel/AppLanguage.swift RoadReel/ThumbnailService.swift RoadReel/TeslaCamViewModel.swift RoadReel/TeslaProjectTrimmer.swift scripts/test-project-trim.swift
"$scratch/test-trim" "$scratch"
python3 - "$scratch/success/2026-01-01_12-00-00" <<'PY'
import subprocess, pathlib, sys
folder = pathlib.Path(sys.argv[1])
for suffix, expected in [('02', 0), ('03', 1), ('06', 2)]:
    p = folder / f'2026-01-01_12-00-{suffix}-front.mp4'
    rgb = subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-frames:v','1','-vf','scale=1:1','-f','rawvideo','-pix_fmt','rgb24','-'])
    assert rgb[expected] > 200 and all(c < 30 for i,c in enumerate(rgb) if i != expected), (p, rgb)
print('PASS: selected frames cross source boundaries in the correct order')
thumbnail = folder.parents[1] / 'native-size' / folder.name / 'thumb.png'
rgb = subprocess.check_output(['ffmpeg','-v','error','-i',str(thumbnail),'-frames:v','1','-vf','scale=1:1','-f','rawvideo','-pix_fmt','rgb24','-'])
assert rgb[0] > 200 and rgb[1] > 200 and rgb[2] < 30, (thumbnail, rgb)
print('PASS: thumbnail stays on the front camera regardless of parallel completion order')
PY
printf 'Test artifacts: %s\n' "$scratch"
