# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A **Host** iPhone/iPad mirrors its screen to nearby **Viewers** using **Wi-Fi Aware** + **Network.framework**. Capture uses a **ReplayKit Broadcast Upload Extension**. Video is **H.264** (VideoToolbox). No internet, no accounts, no servers.

> **Current status (late 2025)**
>
> • **M1 pairing** works end-to-end with heartbeats and session IDs.  
> • **Real H.264 streaming is live**: after pairing and starting a **Broadcast**, the Upload2 extension encodes ReplayKit frames and streams H.264 over UDP to the Host, which relays to the Viewer; the Viewer assembles/decodes and shows a **live full-screen preview with fps/kbps/drop stats**.  
> • **Background streaming**: while broadcast is ON, the Host plays a loop of silent audio so the app can be backgrounded without dropping the stream.  
> • Control currently runs over **infrastructure Wi-Fi** (same network) while Aware is used for discovery; pure P2P is planned.

---

## Minimum OS

- **iOS 26 only** (physical devices).

---

## Targets

- **BeamRoomHost**  
  SwiftUI app on the device that shares its screen (the “Host”).

- **BeamRoomViewer**  
  SwiftUI app on the device that watches (the “Viewer”).

- **BeamRoomUpload2**  
  ReplayKit Broadcast Upload extension (`SampleHandler`) – the **current** extension used for real H.264 streaming.

- **BeamRoomBroadcastUpload**  
  Older Broadcast Upload extension; kept around for comparison and experiments.

- **BeamCore**  
  Swift Package with shared protocols, wire formats, config, logging, and H.264 helpers.

---

## Capabilities (current state)

- **Host**  
  - App Group: `group.com.conornolan.beamroom`  
  - Wi-Fi Aware: `Publish` + `Subscribe` entitlements  
  - WiFiAwareServices (Info.plist):  
    - Media: `"_beamroom._udp"`  
    - Control: `"_beamctl._tcp"`  
    - Both marked `Publishable = true`.

- **Viewer**  
  - Wi-Fi Aware: `Subscribe` entitlement  
  - WiFiAwareServices (Info.plist):  
    - Media: `"_beamroom._udp"`  
    - Control: `"_beamctl._tcp"`  
    - Marked `Subscribable = true`.

- **Broadcast Upload (Upload2)**  
  - App Group: `group.com.conornolan.beamroom`  
  - No Wi-Fi Aware (extension does not need it).

> Tip: Xcode’s Capabilities UI may not show Wi-Fi Aware. Use the `.entitlements` files and ensure provisioning profiles include the capability.

---

## Local network privacy

Host and Viewer list the Bonjour service types and include a Local Network Usage description string in `Info.plist`.

Shape (simplified):

    NSBonjourServices
      _beamroom._udp
      _beamctl._tcp

    NSLocalNetworkUsageDescription
      BeamRoom uses the local network to discover and connect to nearby devices for screen sharing.

    WiFiAwareServices
      _beamctl._tcp
        Publishable = true
      _beamroom._udp
        Publishable = true

On Viewer, you can omit `Publishable` and keep `Subscribable = true` if you prefer; the Host publishes both services, the Viewer subscribes.

---

## Build & Run (H.264 streaming + background Host)

1. **Open the workspace**

    Open `BeamRoom.xcworkspace` (not the individual `.xcodeproj`). You should see Host, Viewer, BeamRoomUpload2 and BeamCore.

2. **Set signing + deployment**

    In **BeamRoomHost**, **BeamRoomViewer**, and **BeamRoomUpload2**:

    - Select your Apple **Team**.  
    - Set **iOS Deployment Target** to **26.0**.  
    - Ensure each target’s **Bundle Identifier** matches its App ID.  
    - In **Build Settings**, set:
      - `MARKETING_VERSION` to e.g. `0.9.5`  
      - `CURRENT_PROJECT_VERSION` to your build number (e.g. `11`)

3. **Add capabilities (per target)**

    - **BeamRoomHost**
      - App Groups: `group.com.conornolan.beamroom`
      - Wi-Fi Aware: entitlements include `Publish`, `Subscribe`

    - **BeamRoomViewer**
      - Wi-Fi Aware: entitlements include `Subscribe`

    - **BeamRoomUpload2**
      - App Groups: `group.com.conornolan.beamroom`
      - No Wi-Fi Aware

4. **Run Host**

    Build & run **BeamRoomHost** on a physical device, then:

    - Set a **Service name** if you like (defaults to device name).  
    - Tap **Start hosting**.

    In the Host logs you should see:

    - `Host advertising 'iPhone' _beamctl._tcp on 52345`  
    - `Media UDP listener ready on <port>`  
    - `Media UDP ready on port <port>`  

    The Host is now:

    - Publishing the control and media Bonjour services.  
    - Listening for control connections on TCP 52345.  
    - Listening for media on an ephemeral UDP port.

5. **Run Viewer**

    Build & run **BeamRoomViewer** on another device (or a second run on the same device):

    - You’ll see a list of discovered Hosts.  
    - There is also a **Find & Pair Host (Wi-Fi Aware)** button which uses DeviceDiscoveryUI when available.

6. **Pair**

    - Tap the Host row in the Viewer list.  
    - The Viewer sends a handshake with a 4-digit code.  
    - With **Auto-accept** enabled on the Host, pairing is instant.  
    - If Auto-accept is off, the Host shows **pair requests** with **Accept** / **Decline** buttons.

    After pairing, logs show something like:

    - Host: `conn#1 accepted … AUTO-ACCEPT code 1234`  
    - Viewer: `Paired ✓ session=…` and `Media params: udpPort=<host UDP port>`

7. **Start Broadcast (real H.264 stream)**

    On the **Host**:

    - In the **Screen broadcast** section, tap **Start Screen Broadcast**.  
    - The hidden `RPSystemBroadcastPickerView` triggers the system sheet.  
    - Choose the **BeamRoomUpload2** extension.  
    - Tap **Start Broadcast**.

    When broadcast starts:

    - The Upload2 extension toggles the App Group “broadcast on/off” flag.  
    - Host’s poller sees it and flips `broadcastOn = true`.  
    - Viewer sees `Broadcast status → ON`.  
    - Upload2 starts encoding ReplayKit frames with `H264Encoder` and sending H.264 AVCC over UDP to the Host’s media port.  
    - The Host relays the stream to the active Viewer peer.

8. **Viewer live preview**

    Once media arrives, the Viewer logs something like:

    - `UDP rx first datagram: 1200 bytes`  
    - `UDP first valid H.264 frame ✓ 884x1920 (seq …)`

    The Viewer shows:

    - A **full-screen video** view with `aspectRatio(.fit)` so the entire frame is visible.  
    - A stats label at the bottom: `fps • kbps • drops`.

9. **Background Host behaviour**

    While **Broadcast** is **ON**:

    - `BackgroundAudioKeeper` starts a tiny loop of silence using `AVAudioEngine` + `AVAudioPlayerNode`, with `UIBackgroundModes = audio`.  
    - This keeps the Host process alive while the app is backgrounded.

    So as long as:

    - Host is “Start hosting”, and  
    - The broadcast is still ON (ReplayKit extension active),  

    the Host can go to the background and streaming to the Viewer continues.

    Stopping the broadcast (via Control Centre or the system sheet) flips the broadcast flag off, stops the background audio, and tears down the media path.

---

## Repo layout (short)

- **BeamCore/**
  - `AwareSupport.swift` – Wi-Fi Aware helpers  
  - `BeamBrowser.swift` – Viewer discovery (NWBrowser + NetServiceBrowser)  
  - `BeamControlServer.swift` – Host TCP control + Bonjour; publishes media port; tracks UDP peer  
  - `BeamControlClient.swift` – Viewer TCP control client + heartbeats  
  - `MediaUDP.swift` – Host UDP listener, learns viewer `(ip,port)` from hello and relays media  
  - `UDPMediaClient.swift` – Viewer UDP receiver + H.264 assembler/decoder + stats  
  - `H264Wire.swift` – UDP H.264 header, flags, param-set codec  
  - `H264Assembler.swift` – Reassembly of fragmented AVCC across UDP packets  
  - `H264Decoder.swift` – `VTDecompressionSession` wrapper  
  - `BeamMessages.swift` – HandshakeRequest/Response, Heartbeat, BroadcastStatus  
  - `BeamTransportParameters.swift` – network tuning knobs  
  - `BeamConfig.swift` – service names, control port (52345), App Group keys, broadcast flag  
  - `Logging.swift`, `BeamLogView.swift` – structured logging and in-app log viewer  
  - `BeamCore.swift` – version banner, shared helpers

- **BeamRoomHost/**
  - `App/HostRootView.swift` – Host UI (Start hosting, Auto-accept, Pairing, Screen broadcast, logs)  
  - `App/BackgroundAudioKeeper.swift` – silent audio loop to keep host alive while broadcast is ON  
  - `BeamRoomHost.entitlements` – App Group + Wi-Fi Aware entitlements  
  - `info.plist` – Bonjour, WiFiAwareServices, background audio, dynamic versions

- **BeamRoomViewer/**
  - `App/ViewerRootView.swift` – Viewer UI (discovery list, pairing sheet, full-screen preview + stats)  
  - `BeamRoomViewer.entitlements` – Wi-Fi Aware (Subscribe only)  
  - `info.plist` – Bonjour / Local network strings

- **BeamRoomUpload2/**
  - `H264Encoder.swift` – `VTCompressionSession` → AVCC samples (+ SPS/PPS)  
  - `UDPMediaSender.swift` – Sends H.264 over UDP from the extension to the Host’s media UDP port (loopback)  
  - `SampleHandler.swift` – Toggles “broadcast on/off” flag; drives encoder/sender  
  - `Info.plist` – Upload extension point, principal class, `RPBroadcastProcessMode`  
  - `BeamRoomUpload2.entitlements` – App Group only

- **BeamRoomBroadcastUpload/**  
  - Legacy upload extension (same shape as Upload2, but not used for the main flow).

---

## Exact entitlements (copy/paste)

**Host — `BeamRoomHost/BeamRoomHost.entitlements`**

    <dict>
        <key>com.apple.security.application-groups</key>
        <array>
            <string>group.com.conornolan.beamroom</string>
        </array>
        <key>com.apple.developer.wifi-aware</key>
        <array>
            <string>Publish</string>
            <string>Subscribe</string>
        </array>
    </dict>

**Viewer — `BeamRoomViewer/BeamRoomViewer/BeamRoomViewer.entitlements`**

    <dict>
        <key>com.apple.developer.wifi-aware</key>
        <array>
            <string>Subscribe</string>
        </array>
    </dict>

**Broadcast Upload (Upload2) — `BeamRoomUpload2/BeamRoomUpload2.entitlements`**

    <dict>
        <key>com.apple.security.application-groups</key>
        <array>
            <string>group.com.conornolan.beamroom</string>
        </array>
    </dict>

In **Build Settings → Code Signing Entitlements**, point each target to its file above (both **Debug** and **Release**).

---

## Control protocol

**Transport**

- **TCP** control: Host listens on **52345** (`NWListener`, infra Wi-Fi).  
- **UDP** media: Host opens an **ephemeral UDP port** and announces it to the Viewer in the handshake.

**Framing**

- Each control message is a single JSON object, newline-delimited (one JSON object per line).

**Messages**

- **Handshake**

    Viewer → Host:

        {"app":"beamroom","ver":1,"role":"viewer","code":"1234"}

    Host → Viewer:

        {"ok":true,"sessionID":"…","udpPort":53339}

    On reject:

        {"ok":false,"message":"Declined"}

- **Heartbeats (both directions)**

        {"hb":1}

- **Broadcast status (Host → Viewer)**

        {"on":true}

**Session state (Viewer)**

- `idle → connecting → waitingAcceptance → paired`  
  The Viewer shows status in the Pair sheet; Host lists Pending Pairs if Auto-accept is off.

---

## UDP H.264 media wire format (live)

- **Viewer → Host**  

  The Viewer sends a one-shot UDP “hello” (and periodic keepalives) to the Host’s announced media UDP port. The Host records the Viewer’s `(ip,port)` and treats it as the active peer.

- **Upload2 (ReplayKit) → Host**  

  The Upload2 extension on the Host encodes **H.264 AVCC** from ReplayKit and sends it over UDP to the Host’s local media listener (loopback). The Host’s `MediaUDP` actor then forwards those packets on to the active Viewer peer.

Wire format for the H.264 packets (see `BeamCore/H264Wire.swift`):

- **Header (big-endian, fixed size)**  
  Fields include:

    - `magic`  
    - `seq` (monotonic sequence number)  
    - `partIndex` (fragment index)  
    - `partCount` (total fragments for this frame)  
    - `flags` (bitfield: keyframe, hasParamSet, etc.)  
    - `width` / `height` (current frame dimensions)  
    - `configBytes` (size of SPS/PPS blob if present)

- **Payload**  

  On the **first part** of a keyframe, `configBytes` is the size of concatenated SPS/PPS (param sets). The payload starts with that blob, followed by the AVCC slice. Subsequent parts carry only more AVCC data.

- `partCount` allows fragmentation to respect the Wi-Fi MTU; payloads are capped to about ~1200 bytes to avoid IP fragmentation.

---

## Action plan / milestones

- **M1 — Discovery & pairing (Wi-Fi Aware + control channel)**  
  ✅ Host/Viewer discovery via Bonjour + Aware; control channel with heartbeats; session IDs; pairing UX.

- **M2 — Broadcast picker & capture plumbing**  
  ✅ Host has a system **Start Screen Broadcast** path (ReplayKit picker); broadcast **On/Off** pushed to Viewers via `BroadcastStatus`.

- **M3 — Live streaming (H.264 over UDP) + background Host**  
  ✅ Upload2: `VTCompressionSession` → AVCC (+ SPS/PPS) → UDP → Host → Viewer.  
  ✅ Viewer: assembler + `VTDecompressionSession` → full-screen preview + stats.  
  ✅ Host: background audio keeper + `UIBackgroundModes = audio` so the app can be backgrounded while streaming continues.

- **Next (M4)**  
  - Adaptive bitrate / resolution / framerate  
  - Multi-viewer fan-out on Host  
  - Pointer/ink overlay  
  - Optional local MP4 recording (likely Host “Pro”)

---

## Troubleshooting (quick)

- **Preview stays blank**

  - Ensure **Broadcast** is **ON** (Host).  
  - On Host logs, you should see `UDP peer ready: …` from the Viewer hello.  
  - In Upload2 logs, look for lines like `UDP uplink ready (local): 127.0.0.1:…` and packets being sent.

- **Viewer says Broadcast OFF**

  - Check the ReplayKit sheet actually started the BeamRoomUpload2 extension (Control Centre → Screen Recording → BeamRoom Upload2).  
  - Confirm the extension writes the broadcast flag and `BeamConfig.isBroadcastOn()` sees it.

- **App Store Connect validation complains about broadcast entitlements / attributes**

  - Make sure both Broadcast Upload Info.plists:  
    - Use `NSExtensionPointIdentifier = com.apple.broadcast-services-upload`.  
    - Have `NSExtensionPrincipalClass` pointing to `SampleHandler`.  
    - Have `RPBroadcastProcessMode` as a direct child of `NSExtension`, **not** inside `NSExtensionAttributes`.

- **Wi-Fi Aware profile errors**

  - The entitlement **type** must be an **array**.  
  - Make sure you are using a **Development** profile that includes Wi-Fi Aware; build to a physical device.  
  - Use the commands in the original entitlements section to inspect the app and profile.

- **Bonjour publish error −72000**

  - We auto-retry; if persistent, toggle Host **Start hosting** off/on; confirm Local Network permission is granted in Settings.

- **DRM content appears black**

  - ReplayKit will deliver black frames for protected windows/media by design.

---

## Notes

- Entirely offline/private; no servers involved.  
- Control and media currently prefer infrastructure Wi-Fi; AWDL-only control/transport is planned.  
- Stats shown in the Viewer are approximate wall-clock metrics; they’re meant as debugging aids, not lab-grade measurements.
