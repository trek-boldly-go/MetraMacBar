# MetraMacBar

A lightweight macOS menu bar app that shows upcoming Metra train departures from your station. No dock icon, no window — just a tram icon in your menu bar with the next train's departure time.

Built for BNSF line, Naperville → Chicago (inbound) by default.

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ — comes with Xcode, or install the [Swift toolchain](https://www.swift.org/download/) standalone
- Xcode Command Line Tools: `xcode-select --install`

## Quick Start

```bash
git clone https://github.com/yourusername/MetraMacBar.git
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

When a token is present, the app polls Metra's GTFS-RT feed every 10 minutes for live departure times including real-time delays. If the feed is unavailable or no token is configured, it automatically falls back to Metra's published static schedule (downloaded and cached locally). The "Scheduled" badge and greyed-out Refresh button indicate static mode.

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

Currently hardcoded to BNSF line, Naperville station, inbound (direction 1). To change the default, edit `RouteConfig.default` in [Sources/MetraTracker/Config.swift](Sources/MetraTracker/Config.swift). See [CLAUDE.md](CLAUDE.md) for architecture notes on extending to other lines.

## License

MIT — see [LICENSE](LICENSE).
# MetraMacBar
