#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MenuBarOverflow"

usage() {
  cat <<'USAGE'
Usage: ./script/launch.sh [--install] [--verify]

Launches an installed copy from ~/Applications or /Applications. It never launches
dist/MenuBarOverflow.app because Open at Login must target an installed app.

  --install  Build, validate, install to ~/Applications, then launch.
  --verify   Confirm that MenuBarOverflow remains running after launch.
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

INSTALL=false
VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --verify) VERIFY=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

if [[ "$INSTALL" == true ]]; then
  build_args=(--install)
  [[ "$VERIFY" == true ]] && build_args+=(--verify)
  exec "$ROOT_DIR/script/build_and_run.sh" "${build_args[@]}"
fi

INSTALLED_APP=""
for candidate in "$HOME/Applications/$APP_NAME.app" "/Applications/$APP_NAME.app"; do
  if [[ -d "$candidate" ]]; then
    INSTALLED_APP="$candidate"
    break
  fi
done

[[ -n "$INSTALLED_APP" ]] || fail "MenuBarOverflow is not installed. Run ./script/launch.sh --install or drag the DMG app into Applications first."
[[ -x "$INSTALLED_APP/Contents/MacOS/$APP_NAME" ]] || fail "installed app is incomplete: $INSTALLED_APP"
/usr/bin/codesign --verify --strict --verbose=2 "$INSTALLED_APP" >/dev/null

/usr/bin/open -n "$INSTALLED_APP"

if [[ "$VERIFY" == true ]]; then
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      echo "$APP_NAME launched from $INSTALLED_APP"
      exit 0
    fi
    sleep 0.25
  done
  fail "$APP_NAME did not stay running"
fi
