#!/bin/bash

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-1.0.0}"
build_dir="$repo_dir/build/release-$version"
derived_dir="$build_dir/DerivedData"
artifact_dir="$repo_dir/release"
staging_dir="$build_dir/dmg"
app_path="$derived_dir/Build/Products/Release/RoadReel.app"
zip_path="$artifact_dir/RoadReel-$version-macOS-universal.zip"
dmg_path="$artifact_dir/RoadReel-$version.dmg"

mkdir -p "$build_dir" "$artifact_dir" "$staging_dir"

xcodebuild \
  -project "$repo_dir/RoadReel.xcodeproj" \
  -scheme RoadReel \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$version" \
  clean build

codesign --force --sign - \
  --entitlements "$repo_dir/RoadReel/RoadReel.entitlements" \
  "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
lipo -archs "$app_path/Contents/MacOS/RoadReel"

rm -f "$zip_path" "$dmg_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

rm -rf "$staging_dir/RoadReel.app" "$staging_dir/Applications"
ditto "$app_path" "$staging_dir/RoadReel.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
  -volname "RoadReel $version" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

(
  cd "$artifact_dir"
  shasum -a 256 "$(basename "$dmg_path")" "$(basename "$zip_path")" > SHA256SUMS.txt
)

printf 'Release artifacts created in %s\n' "$artifact_dir"
