# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A **Host** iPhone/iPad mirrors its screen to nearby **Viewers** using **Wi-Fi Aware** + **Network.framework**. Capture uses **ReplayKit** (Broadcast Upload Extension). Video is **H.264** (VideoToolbox). No Wi-Fi, no internet, no accounts, no servers.

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

---

## Build & Run (M0)

1. **Open the workspace**  
   Open `BeamRoom.xcworkspace` (not the individual `.xcodeproj`). You should see both Host and Viewer.

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
   Build and run **BeamRoomHost** on a device: it launches a simple screen.

5. **Run Viewer**  
   Build and run **BeamRoomViewer** on another device (or the same device via a second run): it launches a simple screen.

6. **Extension status**  
   The Broadcast Upload Extension compiles with the app bundle. You’ll wire it into the UI at **M2**.

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

**M1 — Discovery & pairing (Wi-Fi Aware + control channel)**
- **Services & roles**
  - Host: publish `_beamctl._tcp` (control) and `_beamroom._udp` (media).
  - Viewer: subscribe to both; display nearby Hosts.
- **Pairing UX**
  - Show list of discovered Hosts with device name + short **4-digit code**.
  - Tap Host → Host shows confirm prompt with the same code → accept to pair.
- **Control channel (TCP)**
  - Define a tiny JSON handshake: `{app:"beamroom", ver:1, role:"viewer", code:"1234"} → {ok:true, sessionID:"…", udpPort:…}`
  - Heartbeats every ~5s; reconnect on failure.
- **Session state**
  - `Idle → Discovering → Pairing → Paired → (M2) Broadcasting → (M3) Streaming`.
- **Deliverables**
  - `BeamCore/Transport.swift`: control/session structs + simple TCP client/server wrappers.
  - `HostRootView` / `ViewerRootView`: discovery list + pairing UI + status.

**M2 — Broadcast picker & capture plumbing (no real video yet)**
- **Host UI**
  - Add a `Start Broadcast` button using `RPSystemBroadcastPickerView` with the **Upload extension bundle id**.
  - Add a `Stop Broadcast` button; reflect extension start/stop via `NotificationCenter` or app-group flag.
- **Upload extension**
  - `SampleHandler` stubs: on `broadcastStarted(withSetupInfo:)` toggle a shared app-group flag; on `finishBroadcastWithError(_:)` clear it.
- **Deliverables**
  - Host shows **“Broadcast: On/Off”** badge; control channel carries `broadcastStatus`.

**M3 — Fake frames end-to-end (prove transport)**
- **Transport**
  - Keep TCP for control; send **synthetic frames** on UDP media channel at ~10–15 fps (e.g. colour bars / moving gradient generated on Host).
  - Viewer decodes the simple payload (e.g. raw BGRA tiles or a tiny RLE) and displays; measure packet loss/jitter.
- **Metrics**
  - Basic stats overlay: fps, kbps, loss %, RTT on control.
- **Deliverables**
  - `BeamCore/BeamConfig.swift`: knobs for fps/bitrate/mtu.
  - `ViewerRootView`: frame renderer that can consume the fake payload.

> After M3, swap fake frames for real H.264: create a `VTCompressionSession` in the Upload extension; emit NAL units; Host relays packets over UDP; Viewer uses `VTDecompressionSession` to display. Add ABR later.

---

## Troubleshooting (quick)
- **“profile doesn’t match com.apple.developer.wifi-aware”**  
  Fix the entitlement **type** (must be an **array**), refresh/select a **Development** profile that includes Wi-Fi Aware, rebuild to a **device**.
- **Entitlements missing in app**  
  Check **Build Settings → Code Signing Entitlements** path for both Debug and Release.
- **Simulator shows up**  
  Always select a **physical device** for builds that you intend to verify.

---

## Notes
- DRM/protected screens render **black by design** (ReplayKit).
- If the **Wi-Fi Aware** entitlement isn’t visible in Xcode’s Capabilities pane, the provided `.entitlements` files already declare it.
