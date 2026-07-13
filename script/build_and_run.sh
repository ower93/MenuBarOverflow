#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR"
APP_NAME="MenuBarOverflow"
BUNDLE_ID="com.codex.MenuBarOverflow"
DISPLAY_NAME="Menu Bar Overflow"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RESOURCE_DIR="$PACKAGE_DIR/Sources/$APP_NAME/Resources"
CONFIGURATION="release"
INSTALL_APP=false
LAUNCH_APP=true
VERIFY=false
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
APP_VERSION="${APP_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
TEMP_DIR=""
LOCK_DIR=""

usage() {
  cat <<'USAGE'
Usage: ./script/build_and_run.sh [options]

Builds a signed MenuBarOverflow.app at dist/MenuBarOverflow.app.

Options:
  --debug             Build the debug configuration.
  --release           Build the release configuration (default).
  --install           Copy the validated app to ~/Applications (or INSTALL_DIR).
  --no-launch         Do not open the app after building or installing it.
  --verify            After launch, verify that MenuBarOverflow is running.
  --developer-id      Sign with DEVELOPER_ID_APPLICATION and hardened runtime.
  --adhoc             Sign ad hoc (default, suitable for local use).
  -h, --help          Show this help.

Environment:
  SIGNING_MODE=adhoc|developer-id
  DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAMID)'
  APP_VERSION=1.0 BUILD_NUMBER=1 INSTALL_DIR="$HOME/Applications"
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT

for arg in "$@"; do
  case "$arg" in
    --debug) CONFIGURATION="debug" ;;
    --release) CONFIGURATION="release" ;;
    --install) INSTALL_APP=true ;;
    --no-launch) LAUNCH_APP=false ;;
    --verify) VERIFY=true ;;
    --developer-id) SIGNING_MODE="developer-id" ;;
    --adhoc) SIGNING_MODE="adhoc" ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

case "$SIGNING_MODE" in
  adhoc|developer-id) ;;
  *) fail "SIGNING_MODE must be 'adhoc' or 'developer-id'" ;;
esac

case "$APP_VERSION" in
  *[!0-9A-Za-z._-]*|'') fail "APP_VERSION may contain only letters, numbers, '.', '_' and '-'" ;;
esac
case "$BUILD_NUMBER" in
  *[!0-9]*|'') fail "BUILD_NUMBER must be a positive integer" ;;
esac

if [[ "$INSTALL_APP" == true && "$INSTALL_DIR" != "/Applications" && "$INSTALL_DIR" != "$HOME/Applications" ]]; then
  fail "INSTALL_DIR must be /Applications or $HOME/Applications so Open at Login can find the app"
fi

mkdir -p "$DIST_DIR"
LOCK_DIR="$DIST_DIR/.${APP_NAME}.build.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "another build or package operation is already using $DIST_DIR"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.build.XXXXXX")"
STAGED_APP="$TEMP_DIR/$APP_NAME.app"
CLANG_CACHE_DIR="$TEMP_DIR/clang-module-cache"
SWIFT_SCRATCH_DIR="$TEMP_DIR/swift-build"

build_product() {
  echo "Building $APP_NAME ($CONFIGURATION)..."
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build \
    --package-path "$PACKAGE_DIR" \
    --scratch-path "$SWIFT_SCRATCH_DIR" \
    -c "$CONFIGURATION"

  local bin_dir
  bin_dir="$(CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build \
    --package-path "$PACKAGE_DIR" \
    --scratch-path "$SWIFT_SCRATCH_DIR" \
    -c "$CONFIGURATION" \
    --show-bin-path)"
  EXECUTABLE="$bin_dir/$APP_NAME"
  [[ -x "$EXECUTABLE" ]] || fail "built executable not found: $EXECUTABLE"
}

write_info_plist() {
  cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

stage_bundle() {
  [[ -d "$RESOURCE_DIR" ]] || fail "resources directory not found: $RESOURCE_DIR"
  mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
  cp "$EXECUTABLE" "$STAGED_APP/Contents/MacOS/$APP_NAME"
  cp -R "$RESOURCE_DIR/." "$STAGED_APP/Contents/Resources/"
  write_info_plist
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

clear_bundle_attributes() {
  local bundle="$1"
  /usr/bin/xattr -cr "$bundle" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.FinderInfo "$bundle" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.ResourceFork "$bundle" 2>/dev/null || true
}

verify_bundle_signature() {
  local bundle="$1"
  local attempt
  for attempt in {1..5}; do
    clear_bundle_attributes "$bundle"
    if /usr/bin/codesign --verify --strict --verbose=2 "$bundle" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  /usr/bin/codesign --verify --strict --verbose=2 "$bundle" >/dev/null
}

validate_bundle() {
  local bundle="$1"
  local plist="$bundle/Contents/Info.plist"
  local resource
  local -a required_resources=(
    AppIcon.png
    AppIconDark.png
    LogoMark.png
    LogoMarkDark.png
    MenuBarOverflow.icns
    MenuBarOverflowDark.icns
    StatusBarIconTemplate.png
  )

  [[ -d "$bundle" ]] || fail "app bundle not found: $bundle"
  [[ -x "$bundle/Contents/MacOS/$APP_NAME" ]] || fail "app executable is missing or not executable"
  /usr/bin/plutil -lint "$plist" >/dev/null
  [[ "$(plist_value "$plist" CFBundleExecutable)" == "$APP_NAME" ]] || fail "Info.plist has an invalid executable"
  [[ "$(plist_value "$plist" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail "Info.plist has an invalid bundle identifier"
  [[ "$(plist_value "$plist" CFBundlePackageType)" == "APPL" ]] || fail "Info.plist is not an application bundle"
  [[ "$(plist_value "$plist" LSMinimumSystemVersion)" == "14.0" ]] || fail "Info.plist has an invalid minimum macOS version"

  for resource in "${required_resources[@]}"; do
    [[ -f "$bundle/Contents/Resources/$resource" ]] || fail "required resource is missing: $resource"
  done

  verify_bundle_signature "$bundle"
  local signing_details
  signing_details="$(/usr/bin/codesign -dvv "$bundle" 2>&1)"
  [[ "$signing_details" == *"Identifier=$BUNDLE_ID"* ]] || fail "signature identifier does not match $BUNDLE_ID"
  if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    [[ "$signing_details" == *"Signature=adhoc"* ]] || fail "expected an ad-hoc signature"
  else
    [[ "$signing_details" == *"Authority=$DEVELOPER_ID_APPLICATION"* ]] || fail "Developer ID signature does not match DEVELOPER_ID_APPLICATION"
    [[ "$signing_details" == *"runtime"* ]] || fail "Developer ID build is missing the hardened runtime"
  fi
}

sign_bundle() {
  local -a sign_args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID")
  if [[ "$SIGNING_MODE" == "developer-id" ]]; then
    sign_args+=(--options runtime --timestamp)
  else
    sign_args+=(--requirements "=designated => identifier \"$BUNDLE_ID\"")
  fi

  clear_bundle_attributes "$STAGED_APP"
  /usr/bin/codesign "${sign_args[@]}" "$STAGED_APP" >/dev/null
}

publish_bundle() {
  local destination="$1"
  local destination_parent
  destination_parent="$(dirname "$destination")"
  mkdir -p "$destination_parent"
  rm -rf "$destination"
  /usr/bin/ditto --norsrc --noextattr "$STAGED_APP" "$destination"
  # hdiutil and Finder can attach metadata after a bundle is copied. Keep the
  # published bundle free of extended attributes before validating its seal.
  clear_bundle_attributes "$destination"
  validate_bundle "$destination"
}

stop_running_app() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME" || true
    sleep 0.2
  fi
}

build_product
stage_bundle

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity.}"
  SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
else
  SIGN_IDENTITY="-"
fi

sign_bundle
validate_bundle "$STAGED_APP"

if [[ "$LAUNCH_APP" == true || "$INSTALL_APP" == true ]]; then
  stop_running_app
fi

publish_bundle "$APP_BUNDLE"

LAUNCH_TARGET="$APP_BUNDLE"
if [[ "$INSTALL_APP" == true ]]; then
  INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
  publish_bundle "$INSTALLED_APP"
  LAUNCH_TARGET="$INSTALLED_APP"
  echo "Installed: $INSTALLED_APP"
fi

echo "Validated app bundle: $APP_BUNDLE"

if [[ "$LAUNCH_APP" == true ]]; then
  /usr/bin/open -n "$LAUNCH_TARGET"
fi

if [[ "$VERIFY" == true ]]; then
  [[ "$LAUNCH_APP" == true ]] || fail "--verify requires launching the app; omit --no-launch"
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      echo "$APP_NAME launched from $LAUNCH_TARGET"
      exit 0
    fi
    sleep 0.25
  done
  fail "$APP_NAME did not stay running"
fi
