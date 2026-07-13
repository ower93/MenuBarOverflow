#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MenuBarOverflow"
DISPLAY_NAME="Menu Bar Overflow"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_VERSION="${APP_VERSION:-1.0}"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
CONFIGURATION="release"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
NOTARIZE="${NOTARIZE:-0}"
WORK_DIR=""
MOUNT_DEVICE=""

usage() {
  cat <<'USAGE'
Usage: ./script/package_dmg.sh [options]

Builds the stable dist/MenuBarOverflow.app, validates it, and creates dist/MenuBarOverflow-<version>.dmg.

Options:
  --debug             Build the debug configuration.
  --release           Build the release configuration (default).
  --developer-id      Use DEVELOPER_ID_APPLICATION and hardened runtime.
  --adhoc             Use an ad-hoc signature (default, local distribution only).
  --notarize          Submit the Developer ID-signed DMG and staple its ticket.
  -h, --help          Show this help.

Environment:
  APP_VERSION=1.0
  SIGNING_MODE=adhoc|developer-id
  DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAMID)'
  NOTARIZE=1
  NOTARYTOOL_PROFILE=profile-name
  or APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

clear_bundle_attributes() {
  local bundle="$1"
  /usr/bin/xattr -cr "$bundle" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.FinderInfo "$bundle" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.ResourceFork "$bundle" 2>/dev/null || true
}

cleanup() {
  local status=$?
  if [[ -n "$MOUNT_DEVICE" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DEVICE" -quiet 2>/dev/null || true
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT

for arg in "$@"; do
  case "$arg" in
    --debug) CONFIGURATION="debug" ;;
    --release) CONFIGURATION="release" ;;
    --developer-id) SIGNING_MODE="developer-id" ;;
    --adhoc) SIGNING_MODE="adhoc" ;;
    --notarize) NOTARIZE=1 ;;
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

if [[ "$NOTARIZE" == "1" && "$SIGNING_MODE" != "developer-id" ]]; then
  fail "notarization requires --developer-id or SIGNING_MODE=developer-id"
fi
if [[ "$NOTARIZE" == "1" && "$CONFIGURATION" != "release" ]]; then
  fail "notarization requires a release build"
fi

build_args=("--$CONFIGURATION" --no-launch)
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  build_args+=(--developer-id)
else
  build_args+=(--adhoc)
fi

APP_VERSION="$APP_VERSION" SIGNING_MODE="$SIGNING_MODE" "$ROOT_DIR/script/build_and_run.sh" "${build_args[@]}"
[[ -d "$APP_BUNDLE" ]] || fail "validated app bundle was not created: $APP_BUNDLE"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"
DMG_ROOT="$WORK_DIR/dmg-root"
mkdir -p "$DMG_ROOT"
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
clear_bundle_attributes "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH" >/dev/null
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity.}"
  DMG_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
else
  DMG_SIGN_IDENTITY="-"
fi
/usr/bin/codesign --force --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH" >/dev/null
DMG_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$DMG_PATH" 2>&1)"
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  [[ "$DMG_SIGNING_DETAILS" == *"Authority=$DEVELOPER_ID_APPLICATION"* ]] || fail "DMG Developer ID signature does not match DEVELOPER_ID_APPLICATION"
else
  [[ "$DMG_SIGNING_DETAILS" == *"Signature=adhoc"* ]] || fail "expected an ad-hoc DMG signature"
fi
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

ATTACH_PLIST="$WORK_DIR/attach.plist"
/usr/bin/hdiutil attach -readonly -nobrowse -plist "$DMG_PATH" > "$ATTACH_PLIST"
MOUNT_POINT=""
for index in {0..9}; do
  candidate_mount="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$ATTACH_PLIST" 2>/dev/null || true)"
  candidate_device="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:dev-entry" "$ATTACH_PLIST" 2>/dev/null || true)"
  if [[ -n "$candidate_mount" && -n "$candidate_device" ]]; then
    MOUNT_POINT="$candidate_mount"
    MOUNT_DEVICE="$candidate_device"
    break
  fi
done
[[ -n "$MOUNT_POINT" ]] || fail "could not determine the mounted DMG path"
[[ -d "$MOUNT_POINT/$APP_NAME.app" ]] || fail "DMG does not contain $APP_NAME.app"
[[ -L "$MOUNT_POINT/Applications" ]] || fail "DMG does not contain an Applications shortcut"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || fail "Applications shortcut points to the wrong location"
/usr/bin/codesign --verify --strict --verbose=2 "$MOUNT_POINT/$APP_NAME.app" >/dev/null
/usr/bin/hdiutil detach "$MOUNT_DEVICE" -quiet
MOUNT_DEVICE=""

notarize_dmg() {
  /usr/bin/xcrun --find notarytool >/dev/null 2>&1 || fail "notarytool is unavailable; select or install an Apple toolchain that provides it"
  local -a credentials=()
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARYTOOL_PROFILE")
  else
    : "${APPLE_ID:?Set NOTARYTOOL_PROFILE or APPLE_ID for notarization.}"
    : "${APPLE_TEAM_ID:?Set NOTARYTOOL_PROFILE or APPLE_TEAM_ID for notarization.}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Set NOTARYTOOL_PROFILE or APPLE_APP_SPECIFIC_PASSWORD for notarization.}"
    credentials=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
  fi

  /usr/bin/xcrun notarytool submit "$DMG_PATH" --wait "${credentials[@]}"
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
}

if [[ "$NOTARIZE" == "1" ]]; then
  notarize_dmg
fi

echo "Validated DMG: $DMG_PATH"
