# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A **Host** iPhone/iPad mirrors its screen to nearby **Viewers** using **Wi-Fi Aware** + **Network.framework**. Capture uses **ReplayKit** (Broadcast Upload Extension). Video is **H.264** (VideoToolbox). No internet, no accounts, no servers.

> **Current status (27 Sep 2025)**  
> • **M1 pairing** is working end-to-end with heartbeats and session IDs.  
> • **Real H.264 streaming is live**: after pairing and starting **Broadcast**, the Upload extension encodes ReplayKit frames (VTCompressionSession) and streams H.264 over UDP to the Viewer, which assembles/decodes and shows a **live preview with fps/kbps/drop stats**.  
> • Control currently runs over **infrastructure Wi-Fi** (same network) while Aware is used for discovery; pure P2P is planned.

---

## Minimum OS
- **iOS 26 only** (physical devices).

---

## Targets
- **BeamRoomHost** (SwiftUI app)
- **BeamRoomViewer** (SwiftUI app)
- **BeamRoomBroadcastUpload** (Broadcast Upload Extension: `RPBroadcastSampleHandler`)
- **BeamCore** (Swift Package with shared protocols, wire formats, config, logging)

---

## Capabilities (current state)
- **Host**: App Group `group.com.conornolan.beamroom` **and** **Wi-Fi Aware** (`Publish` + `Subscribe`).
- **Viewer**: **Wi-Fi Aware** (`Subscribe`) only.
- **Broadcast Upload**: **App Group only** (no Wi-Fi Aware in the extension).

**WiFiAwareServices** (in each target’s `Info.plist`):
- Media: `"_beamroom._udp"`
- Control: `"_beamctl._tcp"`
  - Host marks both as **Publishable = true** and **Subscribable = true**.
  - Viewer marks both as **Subscribable = true** (Publishable may be false).

> Tip: Xcode’s Capabilities UI may not show Wi-Fi Aware. Use the `.entitlements` files below and ensure your provisioning profiles include the capability.

---

## Local network privacy
- Host and Viewer list the Bonjour service types and include a Local Network Usage description string in `Info.plist`.

Example (shape matters; keep `WiFiAwareServices` as a *dictionary* of dictionaries):

    <key>NSBonjourServices</key>
    <array>
      <string>_beamroom._udp</string>
      <string>_beamctl._tcp</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>BeamRoom uses the local network to discover and connect to nearby devices for screen sharing.</string>
    <key>WiFiAwareServices</key>
    <dict>
      <key>_beamctl._tcp</key>
      <dict>
        <key>Publishable</key><true/>
        <key>Subscribable</key><true/>
      </dict>
      <key>_beamroom._udp</key>
      <dict>
        <key>Publishable</key><true/>
        <key>Subscribable</key><true/>
      </dict>
    </dict>

*(On Viewer, set `Publishable` to false if you prefer; keep `Subscribable` true. The Host publishes both.)*

---

## Build & Run (M1 + H.264 streaming)

1. **Open the workspace**  
   Open `BeamRoom.xcworkspace` (not the individual `.xcodeproj`). You should see Host, Viewer and the Upload extension.

2. **Set signing + deployment**  
   In **BeamRoomHost**, **BeamRoomViewer**, and **BeamRoomBroadcastUpload**:
   - Select your Apple **Team**.
   - Set **iOS Deployment Target** to **26.0**.
   - Ensure each target’s **Bundle Identifier** matches its App ID.

3. **Add capabilities (per target)**  
   - **Host** → **App Groups** `group.com.conornolan.beamroom` + **Wi-Fi Aware** (via entitlements file).  
   - **Viewer** → **Wi-Fi Aware** (via entitlements file).  
   - **Broadcast Upload** → **App Groups** `group.com.conornolan.beamroom` (no Wi-Fi Aware).

4. **Run Host**  
   Build & run **BeamRoomHost** on a device, then tap **Publish**. You’ll see:
   - “Advertising `<Device Name>` on `_beamctl._tcp`”
   - “Media UDP ready on port ####”
   - A **Broadcast** section with the system **Start Broadcast** button (picker auto-detects the bundled Upload extension).

5. **Run Viewer**  
   Build & run **BeamRoomViewer** on another device (or a second run on the same device). You’ll see:
   - A live list of discovered Hosts.
   - A **Find & Pair Host (Wi-Fi Aware)** button (uses DeviceDiscoveryUI when available).

6. **Pair**  
   Tap the Host in the list → the Viewer shows a **4-digit code**.  
   - With **Auto-accept** on (Host), pairing is immediate (for testing).  
   - Otherwise, the Host gets a **Pair Requests** row to **Accept**/**Decline**.

7. **Start Broadcast (real H.264 stream)**  
   On the **Host**, tap **Start Broadcast** (ReplayKit picker). The **Upload extension** starts, encodes H.264, and streams over UDP to the Viewer. You should see:
   - **Preview** rendering live screen video  
   - **Stats** line: `fps • kbps • drops`

> For now both **control** and **UDP media** run over infra **Wi-Fi** (same SSID). Discovery runs via Bonjour + Aware. P2P control/transport is planned.

---

## Repo layout (short)

    BeamCore/
      Sources/BeamCore/
        AwareSupport.swift          # Wi-Fi Aware helpers
        BeamBrowser.swift           # Viewer discovery (NWBrowser + NetServiceBrowser)
        BeamControlServer.swift     # Host TCP control + Bonjour; writes UDP peer into App Group
        BeamControlClient.swift     # Viewer TCP control client + heartbeats
        MediaUDP.swift              # Host UDP listener (learns viewer peer from hello)
        UDPMediaClient.swift        # Viewer UDP receiver + H.264 assembler/decoder + stats
        H264Wire.swift              # UDP H.264 header, flags, param-set codec
        H264Assembler.swift         # Reassembly of fragmented AVCC across UDP packets
        H264Decoder.swift           # VTDecompressionSession wrapper
        BeamMessages.swift          # HandshakeRequest/Response, Heartbeat, BroadcastStatus
        BeamTransportParameters.swift
        BeamConfig.swift            # Service names, control port (52345), App Group keys
        Logging.swift, BeamLogView.swift
        BeamCore.swift              # Version banner (`BeamCore.hello()`)

    BeamRoomHost/
      App/HostRootView.swift        # Publish/Stop, Auto-accept, Pair Requests, Broadcast picker (no test stream UI)

    BeamRoomViewer/
      App/ViewerRootView.swift      # Discovery list, Pairing sheet, inline preview + stats

    BeamRoomBroadcastUpload/
      H264Encoder.swift             # VTCompressionSession → AVCC samples (+ SPS/PPS)
      UDPMediaSender.swift          # Sends H.264 over UDP to the learned Viewer peer
      SampleHandler.swift           # Toggles “broadcast on/off” flag; drives encoder/sender
      Info.plist, entitlements

---

## Exact entitlements (copy/paste)

**Host — `BeamRoomHost/BeamRoomHost.entitlements`**
    
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
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
    </plist>

**Viewer — `BeamRoomViewer/BeamRoomViewer/BeamRoomViewer.entitlements`**
    
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>com.apple.developer.wifi-aware</key>
      <array>
        <string>Subscribe</string>
      </array>
    </dict>
    </plist>

**Broadcast Upload — `BeamRoomBroadcastUpload/BeamRoomBroadcastUpload.entitlements`**
    
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>com.apple.security.application-groups</key>
      <array>
        <string>group.com.conornolan.beamroom</string>
      </array>
    </dict>
    </plist>

> In **Build Settings → Code Signing Entitlements**, point each target to its file above (both **Debug** and **Release**).

---

## Control protocol (M1)

**Transport**
- **TCP** control: Host listens on **52345** (`NWListener`, infra Wi-Fi).  
- **UDP** media: Host opens an **ephemeral UDP port** and announces it to the Viewer in the handshake.

**Framing:** newline-delimited JSON (one JSON object per line).

**Messages**
- **Handshake**  
      Viewer → Host:
        {"app":"beamroom","ver":1,"role":"viewer","code":"1234"}
      Host → Viewer:
        {"ok":true,"sessionID":"<uuid>","udpPort":53339}
      On reject:
        {"ok":false,"message":"Declined"}

- **Heartbeats (both directions)**  
      {"hb":1}

- **Broadcast status (Host → Viewer)**  
      {"on":true}

**Session state**
- `Idle → Connecting → WaitingAcceptance → Paired`  
  (Viewer shows status in the Pair sheet; Host lists Pending Pairs if Auto-accept is off.)

---

## UDP H.264 media wire format (live)

- **Viewer → Host** sends a one-shot UDP “hello” (and periodic keepalives) to the Host’s announced UDP port; the Host records the Viewer’s `(ip,port)` and writes it into the **App Group**.  
- **Upload extension (Host) → Viewer** sends **H.264 AVCC** over UDP **from the extension** to the learned Viewer peer:
  - **Header (big-endian, fixed size; see `BeamCore/H264Wire.swift`)**  
    Fields: `magic`, `seq`, `partIndex`, `partCount`, `flags`, `width`, `height`, `configBytes`
  - **Payload**  
    - On the **first part** of a keyframe, `configBytes` is the size of concatenated SPS/PPS (param sets) and the payload starts with that blob.  
    - After the config (if any), each part carries a slice of the **AVCC** buffer (length-prefixed NAL units).  
    - `partCount` allows fragmentation to respect Wi-Fi MTU; we cap payloads to ~1200 bytes to avoid fragmentation.

---

## Verify Wi-Fi Aware (copy/paste)

**Host (expect `Publish`,`Subscribe`)**
    
    APP=$(xcodebuild -workspace BeamRoom.xcworkspace -scheme BeamRoomHost -configuration Debug -sdk iphoneos -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/ {td=$2} /FULL_PRODUCT_NAME/ {fp=$2} END {print td "/" fp}')
    codesign -d --entitlements :- "$APP" 2>/dev/null | tee /tmp/host-ents.plist
    /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.wifi-aware' /tmp/host-ents.plist
    security cms -D -i "$APP/embedded.mobileprovision" > /tmp/host-profile.plist
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.wifi-aware' /tmp/host-profile.plist

**Viewer (expect `Subscribe`)**
    
    APP=$(xcodebuild -workspace BeamRoom.xcworkspace -scheme BeamRoomViewer -configuration Debug -sdk iphoneos -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/ {td=$2} /FULL_PRODUCT_NAME/ {fp=$2} END {print td "/" fp}')
    codesign -d --entitlements :- "$APP" 2>/dev/null | tee /tmp/viewer-ents.plist
    /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.wifi-aware' /tmp/viewer-ents.plist
    security cms -D -i "$APP/embedded.mobileprovision" > /tmp/viewer-profile.plist
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.wifi-aware' /tmp/viewer-profile.plist

---

## Action plan

**M1 — Discovery & pairing (Wi-Fi Aware + control channel)** ✅  
**M2 — Broadcast picker & capture plumbing** ✅  
- Host has system **Start Broadcast** (`RPSystemBroadcastPickerView`); broadcast **On/Off** pushed to Viewers.
- Upload extension toggles an **App Group flag** on start/finish.

**M3 — Live streaming (H.264 over UDP)** ✅  
- Upload: `VTCompressionSession` → AVCC (+ SPS/PPS);  
- Wire: Fragmentation-aware UDP header;  
- Viewer: assembler + `VTDecompressionSession` → inline preview + stats.

**Next (M4)** — Adaptive bitrate/resolution/framerate; multi-viewer fan-out on Host; pointer/ink overlay; optional local MP4 recording (Host Pro).

---

## Troubleshooting (quick)
- **Preview stays blank**  
  Ensure **Broadcast** is **On** (Host). On Host logs you should see **“UDP peer ready …”** (from the Viewer hello). In the extension logs, look for **“udp-send Peer changed → …”** and **“UDP ready → …”**.  
- **“profile doesn’t match com.apple.developer.wifi-aware”**  
  Fix the entitlement **type** (must be an **array**), refresh/select a **Development** profile that includes Wi-Fi Aware, rebuild to a **device**.  
- **Entitlements missing in app**  
  Check **Build Settings → Code Signing Entitlements** path for both Debug and Release.  
- **Bonjour publish error −72000**  
  We auto-retry; if persistent, toggle **Publish/Stop** once.  
- **DRM windows/media**  
  ReplayKit will deliver **black frames** by design; that’s expected.

---

## Notes
- Entirely offline/private; no servers.  
- Control and media currently prefer Wi-Fi infrastructure; AWDL-only control/transport planned.  
- Stats shown are approximate (wall-clock rate over recent frames).  
