# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A single BeamRoom app lets one iPhone/iPad act as a **Host** (shares its screen) and other iPhones/iPads act as **Viewers** (watch). Everything runs on the local network using **Wi-Fi Aware** + **Network.framework**; capture uses a **ReplayKit Broadcast Upload Extension**, video is **H.264** (VideoToolbox), and there are **no accounts, no servers, no internet dependency**.

## Current status (Dec 2025)

- **Unified app:** One BeamRoom app with two modes – **Share** (Host) and **Watch** (Viewer).
- **Pairing (M1) works end-to-end** with heartbeats and session IDs.
- **Real H.264 streaming is live:** after pairing and starting a **Screen Broadcast**, the Upload2 extension encodes ReplayKit frames and streams H.264 over UDP to the active Viewer; the Viewer assembles/decodes and shows a **live full-screen preview**.

- **Background streaming (no background audio):** streaming continues while the Host app is backgrounded because the **Broadcast Upload extension** owns the media path while the broadcast is active. The app does **not** rely on a silent audio keepalive.
- **Video-only:** audio is not transmitted/played in the current version (ReplayKit audio sample buffers are ignored).

- **More robust background behaviour (no audio):**
  - The app treats **TCP control** and **UDP media** as separate planes.
  - If the Host UI is suspended in the background, the **control plane may drop**, but the Viewer keeps the **UDP media plane** running so video can continue.
  - Viewer starts/keeps UDP based on “I know the UDP port and I’m paired”, rather than gating strictly on a “broadcastOn” control flag (which can be delayed/missed during backgrounding).
  - The Upload2 sender avoids “flapping” active peers by using a longer peer-staleness window and by treating outbound video sends as activity.

- **Control + media are P2P-ready:** Network paths allow both infrastructure Wi-Fi and peer-to-peer (AWDL / Wi-Fi Aware), so a traditional router is optional.
- Debug stats (fps/kbps/drops) are available in the pairing sheet rather than as a persistent overlay on top of the video.
- Devices can connect over a shared Wi-Fi network, personal hotspot, or direct peer-to-peer link.

## Minimum OS

- **iOS 26 only** (physical devices).

## Targets

- **BeamRoomHost** – main SwiftUI app.

This is the app that ships; it has two modes:

- **Share** tab → Host UI (start hosting, auto-accept pairing, start Screen Broadcast, logs).
- **Watch** tab → Viewer UI (discover Hosts, pair, full-screen preview with a clean video surface).

- **BeamRoomUpload2** – ReplayKit Broadcast Upload extension (`SampleHandler`) – the current extension used for real H.264 streaming.
- **BeamRoomBroadcastUpload** – older Broadcast Upload extension; kept around for comparison and experiments.
- **BeamCore** – Swift Package with shared protocols, wire formats, config, logging, and H.264 helpers.

## How it works (high level)

- **Control plane (TCP):** the Host publishes `_beamctl._tcp` and accepts pairing. Control messages carry session state and the current media UDP port.
- **Media plane (UDP):**
  - The Viewer sends periodic UDP keep-alives (“hello” datagrams) to the Host’s broadcast media port.
  - The Broadcast Upload extension adopts the most recently seen Viewer endpoint as the active peer and sends H.264 packets to it.
  - Media streaming is designed to be resilient if the Host UI is backgrounded and the control channel becomes unreliable.

- **Encoding/decoding:** ReplayKit frames are encoded to H.264 (AVCC) via VideoToolbox in the Upload2 extension. The Viewer reassembles packets, decodes with VideoToolbox, and displays frames in a full-screen surface.

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
- `_beamctl._tcp` → Publishable = true
- `_beamroom._udp` → Publishable = true
