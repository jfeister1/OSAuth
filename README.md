# UniFi Join

Native **macOS (Apple Silicon)** app that discovers UniFi gear on your LAN and joins it to your current UniFi Network site.

## What it does

1. **Discovers** Ubiquiti / UniFi devices with the UDP/10001 discovery protocol (broadcast + multicast).
2. **Connects** to your UniFi Network console using a local Integration API key.
3. **Joins** selected devices to the configured site:
   - If a device is already *Pending Adoption*, adopts it through the official Network API.
   - If it is factory-default and not pending yet, issues SSH `set-inform`, then adopts.

## Requirements

- macOS 14+ on Apple Silicon (arm64)
- Xcode 16+
- A UniFi Network console (UDM / UCG / Cloud Key / self-hosted) with Integration API access
- This Mac on the same Layer-2 network as the devices you want to adopt

## Build

```bash
open UniFiJoin/UniFiJoin.xcodeproj
```

Select the **UniFiJoin** scheme, destination **My Mac**, then Run (`⌘R`).

From the command line on a Mac:

```bash
xcodebuild -project UniFiJoin/UniFiJoin.xcodeproj -scheme UniFiJoin -destination 'platform=macOS,arch=arm64' build
xcodebuild -project UniFiJoin/UniFiJoin.xcodeproj -scheme UniFiJoin -destination 'platform=macOS,arch=arm64' test
```

Sandboxing is off so the app can bind UDP/10001 and shell out to `/usr/bin/ssh` for Layer-3 inform. Hardened Runtime stays enabled.

## Setup

1. In UniFi Network open **Settings → Control Plane / Integrations → API Keys** and create a key.
2. Launch **UniFi Join** → **Settings** (⌘,).
3. Enter the console host/IP and API key. Prefer HTTPS and leave “Trust self-signed certificate” on for local gateways.
4. Click **Test connection**, pick your site, and **Save**.
5. Set **Inform host** to the address devices should use (usually the gateway LAN IP). Default port is `8080`.

Credentials are stored in the macOS Keychain.

## Use

1. Click **Scan** (⌘R) to probe the LAN.
2. Select factory-default or controller-pending devices.
3. Click **Join selected to site** (⌘↩).

Factory-default SSH credentials default to `ubnt` / `ubnt` and are configurable in Settings.

## Architecture

| Piece | Role |
| --- | --- |
| `DiscoveryService` | BSD UDP socket on port 10001; parses Ubiquiti TLV replies |
| `ControllerAPIClient` | UniFi Network Integration API (`/proxy/network/integration` and `/integration` fallback) |
| `InformService` | SSH `set-inform` for devices that are not pending yet |
| `AdoptionService` | Orchestrates inform → adopt |
| SwiftUI shell | Device list, inspector, Settings |

Official adopt call used:

```http
POST /v1/sites/{siteId}/devices
X-API-KEY: <key>
{ "macAddress": "aa:bb:cc:dd:ee:ff", "ignoreDeviceLimit": true }
```

## Notes

- Devices must be factory-default (or already pending) to join. Managed devices on another controller need a reset first.
- Port **10001/udp** must be open on the LAN segment. Inform traffic uses **8080/tcp** to the controller.
- This repository’s cloud environment cannot compile macOS binaries; build on a Mac.
