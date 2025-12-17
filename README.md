# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A single BeamRoom app lets one iPhone/iPad act as a **Host** (shares its screen) and other iPhones/iPads act as **Viewers** (watch). Everything runs on the local network using **Wi-Fi Aware** + **Network.framework**; capture uses a **ReplayKit Broadcast Upload Extension**, video is **H.264** (VideoToolbox), and there are **no accounts, no servers, no internet dependency**.

## Current status (Dec 2025)

- **Unified app:** One BeamRoom app with two modes – **Share** (Host) and **Watch** (Viewer).
- **Pairing works end-to-end** with heartbeats and session IDs.
- **Real H.264 streaming is live:** after pairing and starting a **Screen Broadcast**, the Upload2 extension encodes ReplayKit frames and streams H.264 over UDP to the active Viewer; the Viewer assembles/decodes and shows a **live full-screen preview**.
- **Video-only:** audio is not transmitted/played in the current version (ReplayKit audio sample buffers are ignored).

### Background streaming (no background audio)

Streaming is designed to remain usable while the Host app is backgrounded, without relying on an audio keepalive (no `UIBackgroundModes` audio).

- The app treats **TCP control** and **UDP media** as separate planes.
- If the Host UI is suspended in the background, the **control plane may drop**, but the Viewer keeps the **UDP media plane** running so video can continue.
- Viewer starts/keeps UDP based on “paired + I know the UDP port”, rather than gating strictly on a “broadcastOn” control flag (which can be delayed/missed during backgrounding).

### Background robustness improvements (Dec 2025)

These changes are focused on reducing “goes blank” / “drops while backgrounded” without using audio:

- **Viewer UDP keep-alives:** the Viewer sends periodic UDP hello datagrams (`BRHI!`) while watching to keep the Host/extension’s active peer mapping fresh.
- **Viewer liveness watchdog:** if UDP stalls (no datagrams for a short window), the Viewer forces a clean UDP reconnect even if Network.framework doesn’t surface a hard error.
- **Stable media port preference:** the Broadcast Upload extension prefers binding media UDP on `controlPort + 1` (52346) when available, falling back to an ephemeral port if needed. The chosen port is written to the App Group (`br.broadcast.udpPort`) for the Viewer to use.
- **Peer eviction on send failure:** outbound send errors evict the active peer immediately so the next keepalive can be re-adopted cleanly instead of wedging on a dead connection.

## Minimum OS

- **iOS 26 only** (physical devices).

## Targets

- **BeamRoomHost** – main SwiftUI app (this is the shipping app; contains both Share + Watch modes).
- **BeamRoomUpload2** – ReplayKit Broadcast Upload extension (`SampleHandler`) – current extension used for real H.264 streaming.
- **BeamRoomBroadcastUpload** – older Broadcast Upload extension; kept around for comparison/experiments.
- **BeamCore** – Swift Package with shared protocols, wire formats, config, logging, and H.264 helpers.
- **BeamRoomViewer** – legacy standalone Viewer app (kept for testing; the unified Viewer lives inside BeamRoomHost).

## How it works (high level)

### Control plane (TCP)

- The Host publishes `_beamctl._tcp` and accepts pairing.
- Control messages carry session state and the current media UDP port.
- Control runs on a fixed TCP port:
  - `BeamConfig.controlPort = 52345`

### Media plane (UDP)

- The Viewer sends periodic UDP keep-alives (“hello” datagrams) to the Host’s broadcast media port.
- The Broadcast Upload extension adopts the most recently seen Viewer endpoint as the active peer and sends H.264 packets to it.
- Media streaming is designed to be resilient if the Host UI is backgrounded and the control channel becomes unreliable.

### Encoding/decoding

- ReplayKit frames are encoded to H.264 (AVCC) via VideoToolbox in the Upload2 extension.
- The Viewer reassembles packets, decodes with VideoToolbox, and displays frames in a full-screen surface.

## Capabilities (current state)

### BeamRoomHost (unified app)

- App Group: `group.com.conornolan.beamroom`
- Wi-Fi Aware entitlements: includes `Publish` (and may include `Subscribe` when enabled).
- `WiFiAwareServices` (Info.plist):
  - Control: `_beamctl._tcp`
  - Media: `_beamroom._udp`
  - Both marked `Publishable = true` (Host publishes both services).
- Local Network privacy keys:
  - `NSBonjourServices` includes `_beamroom._udp` and `_beamctl._tcp`
  - `NSLocalNetworkUsageDescription` present
- Background modes:
  - **No `UIBackgroundModes` audio.**
  - Background streaming is handled by the Broadcast Upload extension while the broadcast is active.

The Viewer mode inside BeamRoomHost uses a defensive `AwareSupport` helper that only touches Wi-Fi Aware subscriber APIs if the plist has a `Subscribable` config for the service, avoiding framework assertions when subscriber support is not configured.

### Broadcast Upload (Upload2)

- App Group: `group.com.conornolan.beamroom`
- No Wi-Fi Aware (extension does not need it).
- Video-only: ignores ReplayKit audio sample buffers.

> Tip: Xcode’s Capabilities UI may not show Wi-Fi Aware. Use the `.entitlements` files and ensure provisioning profiles include the capability.

## Local network privacy (Info.plist shape)

NSBonjourServices
- `_beamroom._udp`
- `_beamctl._tcp`

NSLocalNetworkUsageDescription
- BeamRoom uses the local network to discover and connect to nearby devices for screen sharing.

WiFiAwareServices
- `_beamctl._tcp` → ServiceRole = Publishable
- `_beamroom._udp` → ServiceRole = Publishable
