# MetraMacBar

A lightweight macOS menu bar app that shows upcoming Metra train departures from your station. No dock icon, no window — just a tram icon in your menu bar with the next train's departure time.

Defaults to BNSF line, Naperville → Chicago, but fully configurable via the built-in Settings panel.

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ — comes with Xcode, or install the [Swift toolchain](https://www.swift.org/download/) standalone
- Xcode Command Line Tools: `xcode-select --install`

## Quick Start

```bash
git clone https://github.com/trek-boldly-go/MetraMacBar.git
cd MetraMacBar
make run
```

The app launches as a menu bar item. Click the tram icon to see the next departures.

## Getting an API Key

MetraMacBar works without an API key using Metra's published static schedule, but a key unlocks **real-time departures with delay information**.

1. Register for free at [metrarail.com/developers](https://www.metrarail.com/developers)
2. Once approved, copy your API token
3. Click the tram icon → gear icon → paste your token → Save

Your token is stored securely in the macOS Keychain, never on disk or in plain text.

## How It Works

When a token is present, the app polls Metra's GTFS-RT binary feed every 10 minutes for live departure times including real-time delays. If the live feed returns fewer trains than your configured limit (e.g. trains that haven't left their origin station yet), the app pads the list with upcoming scheduled departures — live trains are marked with a small signal icon. If the feed is unavailable or no token is configured, it falls back entirely to Metra's published static schedule (downloaded and cached locally). The "Scheduled" badge indicates static mode.

## Build Commands

| Command | Description |
|---------|-------------|
| `make build` | Compile release binary |
| `make package` | Build + assemble `MetraTracker.app` |
| `make run` | Build, package, and open the app |
| `make clean` | Remove all build artifacts |

## Gatekeeper (Downloaded Releases)

macOS will quarantine apps downloaded from the internet. On first launch, right-click the app → **Open** → **Open** to bypass Gatekeeper, or run:

```bash
xattr -c MetraTracker.app
```

## Configuration

Click the tram icon → gear icon to open Settings. From there you can:

- **Switch lines** — any Metra line (BNSF, UP-N, MD-W, etc.), populated from the cached GTFS data
- **Add/edit route slots** — time-windowed routes so the app automatically shows the right direction (e.g. outbound in the morning, inbound in the evening). Slots include departure station, optional destination station (to filter express trains that skip your stop), and direction.
- **Manage your API token** — stored securely in the macOS Keychain

The ⇄ button in the popover header lets you manually cycle between slots when you're travelling outside your usual schedule.

## License

MIT — see [LICENSE](LICENSE).
