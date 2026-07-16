# Managed Icons Implementation Plan

## Goal

Let users choose which third-party menu bar items should be managed by Menu Bar
Overflow. A managed item should no longer consume visible menu bar space, but it
must remain discoverable and activatable from the overflow panel.

This feature depends on behavior that macOS does not expose through public
cross-process `NSStatusItem` APIs. It must therefore remain opt-in, experimental,
recoverable, and isolated from the existing read-only overflow behavior.

## User Experience

- Add a **Manage Icons** command to the footer or context menu.
- Show every detected menu bar item, not only items that are currently clipped.
- Give each movable item two destinations:
  - **Menu Bar**: leave the original item in the visible menu bar.
  - **Menu Bar Overflow**: move the original item into the managed hidden region.
- Keep unsupported system and privacy indicators visible and explain why they
  cannot be managed.
- Allow drag reordering inside the overflow grid.
- Persist both the managed set and overflow ordering.
- Provide **Restore All Menu Bar Icons** as an always-available recovery action.

## Safety Contract

- The feature is disabled by default.
- Existing scanning and activation continue to work when management is disabled.
- A failed move must leave or restore the item in the visible menu bar.
- Never intentionally leave an item at the WindowServer blocked position
  (`x = -1`).
- Persist an operation journal before moving an item and clear it only after
  verifying the destination.
- On launch, recover interrupted operations before applying saved management
  preferences.
- Do not manage transient screen-recording, microphone, camera, or other
  non-movable system indicators.

## Architecture

### Stable Item Identity

The current scan identifier contains PID and frame data, which changes across
launches and moves. Introduce a separate persisted identity based on:

1. bundle identifier or a documented fallback owner identity;
2. normalized accessibility title;
3. ordinal among equivalent items owned by the same app.

Window ID, PID, frame, and AX element remain runtime-only data.

### Scanner Modes

Split scanning into two modes:

- **Overflow scan** returns items that are clipped or assigned to the managed
  hidden region.
- **Management scan** returns every detected movable item plus unsupported items
  needed by the configuration interface.

The scanner should match Accessibility items to menu bar WindowServer windows
and expose the matched window ID and movement capability.

### Preference Store

Persist:

- whether experimental management is enabled;
- stable identities assigned to the overflow;
- custom overflow order;
- the last verified section and neighboring item for recovery;
- an operation journal for moves interrupted by termination or a crash.

Unknown or newly discovered items default to **Menu Bar**. Items that temporarily
disappear retain their saved assignment and order.

### Movement Engine

Implement a small, isolated menu bar movement service modeled on the proven Thaw
behavior:

- generate Command-drag events targeted at the source and destination window IDs;
- serialize move operations;
- pause while the user is actively interacting with the menu bar;
- verify WindowServer bounds after every move;
- retry with bounded timeouts;
- recover blocked items to the visible section;
- return a typed result rather than silently mutating UI state.

Menu Bar Overflow's own status item acts as the visible boundary and temporary
activation anchor. Movement code must not be mixed into the SwiftUI panel model.

### Managed Activation

When a managed item is selected:

1. capture its hidden return destination;
2. temporarily move it next to the Menu Bar Overflow status item;
3. wait for the menu bar window position to settle;
4. activate the original item;
5. observe the opened menu, panel, or window;
6. return the item to the managed hidden region after the interface closes;
7. use a watchdog timeout and startup recovery if the normal return path fails.

The existing popup relocation remains a secondary enhancement. It should not be
required for the item to return safely.

## Delivery Phases

### Phase 1: Stable Ordering

- Add stable persisted identities.
- Add drag reordering to the existing three-column overflow grid.
- Persist order and provide **Reset Order**.
- Add identity, merge, and ordering tests.

### Phase 2: Management Interface

- Add management scanning for visible and hidden items.
- Add the **Manage Icons** interface and per-item destination controls.
- Mark unsupported items clearly.
- Save preferences without moving real menu bar items yet.

### Phase 3: Experimental Movement

- Implement and test the serialized Command-drag movement engine.
- Move selected third-party items into and out of the managed region.
- Add verification, retries, blocked-item recovery, and **Restore All**.
- Gate the feature behind an explicit experimental confirmation.

### Phase 4: Activation Lifecycle

- Temporarily show managed items for activation.
- Detect the opened interface and rehide after it closes.
- Handle rapid repeated clicks, app termination, relaunch, display changes, and
  macOS Space changes.

### Phase 5: Compatibility Release

- Test representative AppKit, SwiftUI, Electron, system, and multi-icon apps.
- Test single- and multi-display configurations.
- Validate startup recovery after forced termination during each move phase.
- Document known unsupported items and macOS-version sensitivity.
- Ship first as a prerelease before enabling it in the stable build.

## Definition of Done

- Users can choose supported items to occupy only Menu Bar Overflow.
- Managed assignments and custom order survive application and system restarts.
- Selecting a managed item opens its original interface and returns it afterward.
- Unsupported items remain usable and cannot be accidentally hidden.
- **Restore All Menu Bar Icons** succeeds without requiring a reinstall.
- Existing overflow-only behavior remains available when the experiment is off.
- Automated tests cover identity, ordering, move-state transitions, recovery, and
  preference migration.
