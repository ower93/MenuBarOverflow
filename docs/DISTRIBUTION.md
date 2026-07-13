# Distribution

## Local Build and Installation

The build and packaging scripts create these validated outputs:

- `dist/MenuBarOverflow.app`
- `dist/MenuBarOverflow-<APP_VERSION>.dmg`

`build_and_run.sh` leaves the loose app bundle in `dist`. `package_dmg.sh` uses that bundle as packaging input, validates the copy mounted from the completed image, and removes the loose bundle so the DMG is the only distribution artifact.

The default is ad-hoc signing. It is appropriate for a personal machine, but it is not a notarized public release.

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --install --verify
./script/package_dmg.sh
```

`--install` copies the validated app to `~/Applications/MenuBarOverflow.app` by default, so it does not need administrator access. `INSTALL_DIR=/Applications` is supported when an administrator-installed copy is required. The application only treats `~/Applications` and `/Applications` as standard installation locations for login startup.

The DMG contains the app and an `Applications` shortcut. Drag the app into either Applications location before enabling startup at login. The scripts validate the Info.plist, executable, required resources, app signature, DMG signature, compressed image, and the mounted DMG contents before reporting success.

## First Run and Permissions

1. Start the installed app with `./script/launch.sh`, or open it from Applications.
2. From the app menu, choose **Request Accessibility Access** or **Open Accessibility Settings**, then enable **Menu Bar Overflow** under **Privacy & Security > Accessibility**. This permission is required to discover and press menu-bar extras.
3. For captured menu-extra icons, use **Request Screen Recording for Real Icons** in the app menu, then enable it under **Privacy & Security > Screen Recording**. The app remains usable without this optional permission.
4. After updating an ad-hoc-signed local build, macOS may require permissions to be granted again. This is normal for local, non-notarized builds.

## Open at Login

The app uses macOS's `SMAppService.mainApp` login-item service rather than a custom LaunchAgent. The **Open at Login** toggle is available only when the running bundle is installed in `~/Applications` or `/Applications`; it is deliberately unavailable from a DMG, `dist`, Downloads, or another temporary location.

After dragging the app into Applications, open that installed copy and choose **Open at Login**. macOS may require approval in **System Settings > General > Login Items**; the app shows an approval state and provides a direct Settings link. Turning the toggle off unregisters the same system login item.

`./script/launch.sh` deliberately refuses to launch `dist/MenuBarOverflow.app`; use `./script/launch.sh --install` for a build-install-launch cycle.

## Developer ID, Hardened Runtime, and Notarization

Use this path for a release outside your own machine. It requires a valid Developer ID Application certificate and an Apple toolchain with `notarytool`; the scripts do not assume either is available.

```bash
security find-identity -v -p codesigning

export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
./script/package_dmg.sh --developer-id
```

`--developer-id` (or `SIGNING_MODE=developer-id`) signs the application with the declared identity, enables the hardened runtime with a secure timestamp, validates the resulting signature, and signs the DMG with the same identity.

For notarization, provide either a Keychain profile or the three Apple credential variables. Keep credentials out of shell history and source control.

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARYTOOL_PROFILE='menu-bar-overflow-notary'
./script/package_dmg.sh --developer-id --notarize
```

Alternatively:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export APPLE_ID='you@example.com'
export APPLE_TEAM_ID='TEAMID'
export APPLE_APP_SPECIFIC_PASSWORD='app-specific-password'
NOTARIZE=1 ./script/package_dmg.sh --developer-id
```

When notarization is requested, the script submits the DMG, waits for Apple's result, staples the ticket, validates the stapled ticket, and runs Gatekeeper assessment. A Developer ID-signed but not-yet-notarized DMG may not pass Gatekeeper; that is expected, so Gatekeeper assessment is only a required packaging check after successful notarization.

## Build Environment

The package targets macOS 14 or later. Build with a matching Apple Swift toolchain and macOS SDK. If `swift build` reports that the SDK and compiler versions do not match, select or install a matching full Xcode version before retrying. The scripts use a temporary Clang module cache to avoid relying on a writable global compiler cache.

Useful overrides:

```text
APP_VERSION=1.0            DMG filename and CFBundleShortVersionString
BUILD_NUMBER=1             CFBundleVersion
SIGNING_MODE=adhoc         Default local signing mode
SIGNING_MODE=developer-id  Distribution signing mode
INSTALL_DIR=~/Applications Default install location; /Applications also supported
NOTARIZE=1                 Request notarization from package_dmg.sh
NOTARYTOOL_PROFILE=name    Preferred notarization credentials source
```
