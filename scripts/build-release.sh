#!/bin/bash

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-1.0.0}"
build_dir="$repo_dir/build/release-$version"
derived_dir="$build_dir/DerivedData"
artifact_dir="$repo_dir/release"
staging_dir="$build_dir/dmg"
app_path="$derived_dir/Build/Products/Release/RoadReel.app"
dmg_path="$artifact_dir/RoadReel-$version.dmg"
update_dir="$build_dir/update-feed"
package_dir="$repo_dir/build/SourcePackages"
build_settings=("MARKETING_VERSION=$version")
if [ -n "${2:-}" ]; then
  build_settings+=("CURRENT_PROJECT_VERSION=$2")
fi

mkdir -p "$build_dir" "$artifact_dir" "$staging_dir"

xcodebuild \
  -project "$repo_dir/RoadReel.xcodeproj" \
  -scheme RoadReel \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  -clonedSourcePackagesDirPath "$package_dir" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  "${build_settings[@]}" \
  clean build

"$repo_dir/scripts/sign-app.sh" "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
lipo -archs "$app_path/Contents/MacOS/RoadReel"

rm -f "$dmg_path"

rm -rf "$staging_dir/RoadReel.app" "$staging_dir/Applications"
ditto "$app_path" "$staging_dir/RoadReel.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
  -volname "RoadReel $version" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

# Generate both archive and feed signatures using the existing Keychain key.
# Never silently generate another key: installed apps trust the embedded public key.
sparkle_bin="$package_dir/artifacts/sparkle/Sparkle/bin"
expected_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_path/Contents/Info.plist")
actual_key=$("$sparkle_bin/generate_keys" --account io.github.Dynmi.RoadReel -p)
if [ "$expected_key" != "$actual_key" ]; then
  printf 'Update signing key is missing or does not match the app. See docs/updates.md.\n' >&2
  exit 1
fi
mkdir -p "$update_dir"
rm -f "$update_dir/appcast.xml" "$update_dir/RoadReel-$version.dmg"
cp "$dmg_path" "$update_dir/"
"$sparkle_bin/generate_appcast" \
  --account io.github.Dynmi.RoadReel \
  --download-url-prefix "https://github.com/Dynmi/RoadReel/releases/download/v$version/" \
  --maximum-deltas 0 --maximum-versions 1 \
  "$update_dir"
cp "$update_dir/appcast.xml" "$artifact_dir/appcast.xml"

printf 'Publish RoadReel-%s.dmg and appcast.xml together from %s\n' "$version" "$artifact_dir"
