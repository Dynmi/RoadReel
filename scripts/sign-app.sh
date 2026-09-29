#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:?Usage: sign-app.sh /path/to/RoadReel.app}"
identity="${ROADREEL_CODESIGN_IDENTITY:--}"
framework="$app_path/Contents/Frameworks/Sparkle.framework"
entitlements=$(mktemp)
trap 'rm -f "$entitlements"' EXIT

# codesign does not expand Xcode build variables. Resolve them for this bundle,
# including isolated test builds, before granting the Sparkle mach services.
python3 - "$repo_dir/RoadReel/RoadReel.entitlements" "$app_path" "$entitlements" <<'PY'
import plistlib, sys
from pathlib import Path
source, app, output = sys.argv[1:]
info = plistlib.loads((Path(app) / 'Contents/Info.plist').read_bytes())
data = Path(source).read_text().replace('$(PRODUCT_BUNDLE_IDENTIFIER)', info['CFBundleIdentifier'])
Path(output).write_text(data)
PY

if [ -d "$framework" ]; then
  codesign --force --sign "$identity" --options runtime "$framework/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign "$identity" --options runtime --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign "$identity" --options runtime "$framework/Versions/B/Autoupdate"
  codesign --force --sign "$identity" --options runtime "$framework/Versions/B/Updater.app"
  codesign --force --sign "$identity" --options runtime "$framework"
fi
codesign --force --sign "$identity" --entitlements "$entitlements" "$app_path"
codesign --verify --deep --strict "$app_path"
