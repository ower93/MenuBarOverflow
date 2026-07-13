# MenuBarOverflow

A small macOS menu-bar utility focused on one job: put reachable menu-bar extras in a dropdown so crowded or clipped icons can still be opened.

## How It Works

- The app creates one `NSStatusItem`.
- On click, it scans running apps for Accessibility `AXExtrasMenuBar` children.
- The dropdown lists each menu extra with a real captured icon when Screen Recording is granted, otherwise the owning app icon.
- Selecting an item performs the menu extra's Accessibility press action.
- The dropdown includes an `Open at Login` toggle backed by macOS's login-item service for the installed app.

This is intentionally narrower than Thaw. Thaw physically manages status-item layout using private WindowServer/CoreGraphics APIs, large invisible divider items, screen capture, and synthesized menu-bar drag/click events. MenuBarOverflow does not move or hide anything; it only gives you a second way to reach existing menu-bar items.

## Permissions

- Accessibility is required so the app can enumerate and press menu extras.
- Screen Recording is optional and only improves icon fidelity. Without it, app icons are used as fallback images.

## Build, Install, and Distribute

The scripts always build one stable signed bundle at `dist/MenuBarOverflow.app`. The default signature is ad hoc and intended for a local personal installation. To install it without administrator access and run it from a location that Open at Login can use:

```bash
./script/build_and_run.sh --install --verify
```

To create a drag-to-Applications DMG:

```bash
./script/package_dmg.sh
```

`./script/launch.sh` launches only an installed copy from `~/Applications` or `/Applications`; use `./script/launch.sh --install` to build and install first. See [Distribution](docs/DISTRIBUTION.md) for the permission, login startup, Developer ID, hardened-runtime, and notarization flows.
