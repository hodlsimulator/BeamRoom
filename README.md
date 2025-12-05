# BeamRoom (iOS 26)

BeamRoom is a serverless, high‑quality screen‑sharing app. A single BeamRoom app lets one iPhone/iPad act as a **Host** (shares its screen) and other iPhones/iPads act as **Viewers** (watch). Everything runs on the local network using **Wi‑Fi Aware** + **Network.framework**; capture uses a **ReplayKit Broadcast Upload Extension**, video is **H.264** (VideoToolbox), and there are **no accounts, no servers, no internet dependency**.

> **Current status (late 2025)**
>
> - **Unified app:** One BeamRoom app with two modes – **Share** (Host) and **Watch** (Viewer).
> - **M1 pairing** works end‑to‑end with heartbeats and session IDs.
> - **Real H.264 streaming is live**: after pairing and starting a **Broadcast**, the Upload2 extension encodes ReplayKit frames and streams H.264 over UDP to the Host, which relays to the Viewer; the Viewer assembles/decodes and shows a **live full‑screen preview**. Debug stats (fps/kbps/drops) are available in the pairing sheet rather than as a persistent overlay on top of the video.
> - **Background streaming**: while broadcast is ON, the Host plays a loop of silent audio so the app can be backgrounded without dropping the stream.
> - **Control + media are P2P‑ready**: Network paths allow both infrastructure Wi‑Fi and peer‑to‑peer (AWDL / Wi‑Fi Aware), so a traditional router is optional. Devices can connect over a shared Wi‑Fi network, personal hotspot, or direct peer‑to‑peer link.

---

## Minimum OS

- **iOS 26 only** (physical devices).

---

## Targets

- **BeamRoomHost** – main SwiftUI app. This is the app that ships; it has two modes:
  - **Share** tab → Host UI (start hosting, auto‑accept pairing, screen broadcast, logs).
  - **Watch** tab → Viewer UI (discover Hosts, pair, full‑screen preview with a clean video surface).
- **BeamRoomViewer** – legacy SwiftUI Viewer app target (kept for development/regression; not needed for shipping).
- **BeamRoomUpload2** – ReplayKit Broadcast Upload extension (`SampleHandler`) – the **current** extension used for real H.264 streaming.
- **BeamRoomBroadcastUpload** – older Broadcast Upload extension; kept around for comparison and experiments.
- **BeamCore** – Swift Package with shared protocols, wire formats, config, logging, and H.264 helpers.

---

## Capabilities (current state)

### BeamRoomHost (unified app)

- App Group: `group.com.conornolan.beamroom`
- Wi‑Fi Aware entitlements: includes `Publish` (and may include `Subscribe` when enabled).
- `WiFiAwareServices` (Info.plist):
  - Control: `"_beamctl._tcp"`
  - Media:  `"_beamroom._udp"`
  - Both marked `Publishable = true` (Host publishes both services).
- The Viewer mode inside BeamRoomHost uses a defensive `AwareSupport` helper that only touches Wi‑Fi Aware subscriber APIs if the plist has a `Subscribable` config for the service, avoiding framework assertions when subscriber support is not configured.

### BeamRoomViewer (legacy)

- Wi‑Fi Aware: `Subscribe` entitlement.
- `WiFiAwareServices` (Info.plist):
  - Media:  `"_beamroom._udp"`
  - Control: `"_beamctl._tcp"`
  - Marked `Subscribable = true`.

### Broadcast Upload (Upload2)

- App Group: `group.com.conornolan.beamroom`
- No Wi‑Fi Aware (extension does not need it).

> Tip: Xcode’s Capabilities UI may not show Wi‑Fi Aware. Use the `.entitlements` files and ensure provisioning profiles include the capability.

---

## Local network privacy

BeamRoom lists the Bonjour service types and includes a Local Network Usage description string in `Info.plist`.

Shape (simplified):

```text
NSBonjourServices
    _beamroom._udp
    _beamctl._tcp

NSLocalNetworkUsageDescription
    BeamRoom uses the local network to discover and connect to nearby devices for screen sharing.

WiFiAwareServices
    _beamctl._tcp   → Publishable = true
    _beamroom._udp  → Publishable = true
