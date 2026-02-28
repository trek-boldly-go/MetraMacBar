# MetraMacBar — AI Assistant Guide

Native macOS menu bar app showing upcoming Metra train departures. SwiftUI + AppKit hybrid,
built with Swift Package Manager. No external dependencies.

## Architecture

```
AppDelegate
  └── MenuBarController          NSStatusItem + NSPopover + 10-min refresh timer
        ├── MetraService         GTFS-RT real-time feed (requires API token)
        ├── GTFSScheduleService  Static GTFS schedule fallback (cached ZIP)
        └── AppState             @ObservableObject shared between controller and views
              └── TrainListView  SwiftUI popover content
                    └── TrainRowView
```

Real-time takes priority. If `appState.apiToken` is nil or the RT fetch throws, the controller
falls through to `GTFSScheduleService`. `appState.isRealTime` is the single source of truth
driving all live-vs-static UI differences.

## Key Files

| File | Purpose |
|------|---------|
| `Sources/MetraTracker/main.swift` | NSApplication bootstrap |
| `Sources/MetraTracker/AppDelegate.swift` | `.accessory` policy, Keychain load, tooltip delay |
| `Sources/MetraTracker/Config.swift` | `RouteConfig` struct + `ConfigStore` (UserDefaults JSON) |
| `Sources/MetraTracker/Models.swift` | `TrainDeparture` (with `isRealTime`), `AppState` |
| `Sources/MetraTracker/KeychainHelper.swift` | API token CRUD in macOS Keychain |
| `Sources/MetraTracker/GTFSRTParser.swift` | Zero-dependency binary protobuf parser for GTFS-RT |
| `Sources/MetraTracker/MetraService.swift` | Fetch GTFS-RT binary feed, filter to relevant trains |
| `Sources/MetraTracker/GTFSScheduleService.swift` | Download, cache, parse static GTFS ZIP |
| `Sources/MetraTracker/MenuBarController.swift` | Status item, popover, slot cycling, refresh loop |
| `Sources/MetraTracker/Views/SetupView.swift` | `SettingsView` (line/token/slots) + `SlotEditorView` |
| `Sources/MetraTracker/Views/TrainListView.swift` | Popover UI (header, train rows, footer) |

## Build

```bash
make run      # build release + assemble MetraTracker.app + open
make clean    # remove .build/ and MetraTracker.app/
```

No Xcode project — Swift Package Manager only. App bundle is assembled by the Makefile with
ad-hoc code signing (`codesign --sign -`).

## API

- **Endpoint:** `https://gtfspublic.metrarr.com/gtfs/public/tripupdates`
- **Auth:** Query param `?api_token=KEY` (NOT Basic Auth — deprecated Nov 2025)
- **Format:** Binary protobuf (GTFS-RT spec); parsed by `GTFSRTParser.swift` with no external deps
- **Static GTFS ZIP:** `https://schedules.metrarail.com/gtfs/schedule.zip`
- **Published timestamp:** `https://schedules.metrarail.com/gtfs/published.txt` (version check)

## Static Schedule Cache

Cached to `~/Library/Application Support/com.metratracker/gtfs/`.
Files used: `trips.txt`, `stop_times.txt`, `calendar.txt`, `calendar_dates.txt`.
Cache is refreshed when `published.txt` differs from remote, or falls back to local cache if
the network is unavailable. Files must be non-empty to be considered valid (guards against
zero-byte files from failed prior extractions).

## Secrets

- API token stored in macOS Keychain: service `com.metratracker`, account `apiToken`
- Never stored in code, UserDefaults, or any file
- `KeychainHelper` provides `saveToken()`, `loadToken()`, `deleteToken()`

## Configuration

`RouteConfig` (in `Config.swift`) holds `lineId`, `maxTrains`, and `slots: [RouteSlot]`.
Persisted to UserDefaults as JSON (key: `routeConfig`). Defaults to BNSF, Naperville, inbound (1).

Each `RouteSlot` has a `startTime`/`endTime` window ("HH:mm" 24h Central), `departureStopId`,
optional `destinationStopId` (filters express trains that skip the stop), and `directionId`.
`activeSlot()` picks the current slot by time; users can cycle manually with the ⇄ button.

Everything is configurable from the Settings panel (gear icon) — line, API token, and slots —
populated from the cached GTFS data. Direction: `0` = outbound, `1` = inbound (toward Chicago).

## Coding Conventions

- **No external dependencies** — stdlib + AppKit/SwiftUI/Foundation only
- **Main actor** — all `AppState` mutations must happen on `@MainActor`; use
  `Task { @MainActor in ... }` in async refresh paths
- **Popover size** — `popover.contentSize = NSSize(width: 300, height: 360)` in
  `configurePopover()`. Do not remove this or use `fittingSize` at init time — the popover
  will anchor incorrectly (appears at top of screen instead of below the menu bar button)
- **isRealTime branching** — all UI differences between live and static mode key off
  `appState.isRealTime`; do not add separate flags
- **Train number extraction** — BNSF trip IDs are `BNSF_BN####_V#_A`; the run number lives
  in the first underscore-component that has ≥3 digits (`BN1200` → `#1200`). Do not use
  `.last` after splitting — that returns the service-period suffix (`A`, `AA`, etc.)
- **GTFS time parsing** — departure times can exceed `23:59:59` for overnight service;
  `parseGTFSTime` in `GTFSScheduleService` handles the hour overflow
- **String comparison for time filtering** — zero-padded `HH:MM:SS` strings compare correctly
  with `>=` up to 23:59:59; this is intentional, not a bug

## Testing

`make run` is the primary verification method. There are no automated tests.
Useful manual checks:
- With no token: app shows static schedule, "Scheduled" badge, greyed Refresh button
- With valid token: app shows live departures, "Updated Xs ago" footer, blue Refresh button
- With invalid token: RT fetch fails, falls back to static (error cleared if token is nil)
