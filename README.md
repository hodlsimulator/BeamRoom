# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A **Host** iPhone/iPad mirrors its screen to nearby **Viewers** using **Wi-Fi Aware** + **Network.framework**. Capture uses **ReplayKit** (Broadcast Upload Extension). Video is **H.264** (VideoToolbox). No internet, no accounts, no servers.

> Current status (27 Sep 2025): **M1 (pairing) is working** end-to-end with heartbeats and session IDs. For now the control link runs over **infrastructure Wi-Fi** (same network) while we keep Aware for discovery; pure P2P is planned.

---

## Minimum OS
- **iOS 26 only** (real devices).

---

## Targets
- **BeamRoomHost** (SwiftUI app)
- **BeamRoomViewer** (SwiftUI app)
- **BeamRoomBroadcastUpload** (Broadcast Upload Extension: `RPBroadcastSampleHandler`)
- **BeamCore** (Swift Package with shared protocols, config, logging)

---

## Capabilities (current state)
- **Host**: App Group `group.com.conornolan.beamroom` **and** **Wi-Fi Aware** (`Publish` + `Subscribe`).
- **Viewer**: **Wi-Fi Aware** (`Subscribe`) only.
- **Broadcast Upload**: **App Group only** (no Wi-Fi Aware on the extension).

**WiFiAwareServices** (in each target’s `Info.plist`):
- Media: `"_beamroom._udp"`
- Control: `"_beamctl._tcp"`
  - Host marks both as **Publishable = true**.
  - Viewer marks both as **Subscribable = true**.

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

*(On Viewer, set `Publishable` to false and keep `Subscribable` true; the Host publishes both.)*

---

## Build & Run (M1)

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
   Build and run **BeamRoomHost** on a device, then tap **Publish**. You’ll see:
   - “Advertising `<Device Name>` on `_beamctl._tcp`”
   - “Media UDP ready on port ####”
   - A **Broadcast** section with a system **Start Broadcast** button (picker auto-detects the bundled Upload extension).

5. **Run Viewer**  
   Build and run **BeamRoomViewer** on another device (or the same device via a second run). You’ll see:
   - A live list of discovered Hosts.
   - A **Find & Pair Host (Wi-Fi Aware)** button (uses DeviceDiscoveryUI when available).

6. **Pair**  
   Tap the Host in the list → the Viewer shows a **4-digit code**.  
   - With **Auto-accept** on (Host), pairing is immediate (for testing).  
   - Otherwise, the Host gets a **Pair Requests** row to **Accept**/**Decline**.

7. **Result**  
   The Viewer sheet flips to **Paired ✓**, showing:
   - `Session: <UUID>`
   - `Broadcast: On/Off` (live-pushed from Host)
   - `Media UDP port: ####` (announced by Host)

> For M1, the control link uses infra **Wi-Fi** (same SSID), not AWDL. Discovery runs via Bonjour + Aware. P2P control is planned.

---

## Repo layout (short)

    BeamCore/
      Sources/BeamCore/
        AwareSupport.swift          # Wi-Fi Aware helpers
        BeamBrowser.swift           # Viewer discovery (NWBrowser + NetServiceBrowser)
        BeamControlServer.swift     # Host TCP control server + Bonjour publish + UDP port announce
        BeamControlClient.swift     # Viewer TCP control client + heartbeats
        BeamMessages.swift          # HandshakeRequest/Response, Heartbeat, MediaParams
        BroadcastStatus.swift       # { "on": Bool }
        BeamTransportParameters.swift
        BeamConfig.swift            # Service names, control port (52345), App Group keys
        Logging.swift, BeamLogView.swift
        BeamCore.swift              # Version banner (`BeamCore.hello()`)

    BeamRoomHost/
      App/HostRootView.swift        # Publish/Stop, Auto-accept, Pair Requests, Broadcast picker

    BeamRoomViewer/
      App/ViewerRootView.swift      # Discovery list, Pairing sheet, status

    BeamRoomBroadcastUpload/
      SampleHandler.swift           # Toggles “broadcast on/off” flag (M2 plumbing)

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
- **TCP** control: Host listens on **52345** (`NWListener`, infra Wi-Fi only).  
- **UDP** media: Host opens an ephemeral UDP port and announces it to the Viewer.

**Framing:** newline-delimited JSON (one JSON object per line).

**Messages**
- **M1 — Handshake**  
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

- **M3 — Media parameters (Host → Viewer)**  
      {"udpPort":53339}

**Session state**
- `Idle → Connecting → WaitingAcceptance → Paired`  
  (Viewer shows status in the Pair sheet; Host lists Pending Pairs if Auto-accept is off.)

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

## Action plan (M1 → M3)

**M1 — Discovery & pairing (Wi-Fi Aware + control channel)** ✅
- **Services & roles**
  - Host: publish `_beamctl._tcp` (control) and `_beamroom._udp` (media).
  - Viewer: subscribe to both; display nearby Hosts.
- **Pairing UX**
  - List discovered Hosts with device name + **4-digit code**.
  - Tap Host → Host shows confirm prompt with the same code → accept to pair (or auto-accept for testing).
- **Control channel (TCP)**
  - Tiny JSON handshake, heartbeats every ~5s, reconnect on failure.
- **Deliverables**
  - Control server/client + Pairing UI + in-app log viewer.

**M2 — Broadcast picker & capture plumbing (partial in place)**
- **Host UI**
  - System **Start Broadcast** button (`RPSystemBroadcastPickerView`) auto-detects the bundled Upload extension.
  - **Broadcast On/Off** reflected in Host UI and pushed to Viewers over control.
- **Upload extension**
  - `SampleHandler` toggles an **App Group flag** on start/finish; no media yet.
- **Next**
  - Add a simple “UDP hello” from Viewer to Host immediately after M3 to verify reachability.

**M3 — Fake frames end-to-end (prove transport)**
- **Transport**
  - Keep TCP for control; send **synthetic frames** on UDP at ~10–15 fps (e.g. colour bars/moving gradient).
  - Viewer decodes and displays; record loss/jitter.
- **Metrics**
  - Overlay: fps, kbps, loss %, RTT.
- **Then**
  - Replace with real H.264 (Upload: `VTCompressionSession`; Viewer: `VTDecompressionSession`), then add ABR.

---

## Troubleshooting (quick)
- **“profile doesn’t match com.apple.developer.wifi-aware”**  
  Fix the entitlement **type** (must be an **array**), refresh/select a **Development** profile that includes Wi-Fi Aware, rebuild to a **device**.
- **Entitlements missing in app**  
  Check **Build Settings → Code Signing Entitlements** path for both Debug and Release.
- **Bonjour publish error −72000**  
  We auto-retry; if persistent, toggle **Publish/Stop** once.
- **Simulator shows up**  
  Always select a **physical device** for builds that you intend to verify.

---

## Notes
- DRM/protected screens render **black by design** (ReplayKit).
- For now the control socket is **Wi-Fi only**; AWDL-only control will come once M2/M3 are stable.
