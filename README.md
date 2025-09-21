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

## Capabilities
- **Host + Extension**: App Group `group.com.conornolan.beamroom` and **Wi-Fi Aware** entitlement.
- **WiFiAwareServices** declared in each target’s `Info.plist`:
  - Media: `"_beamroom._udp"`
  - Control: `"_beamctl._tcp"`

> Tip: Host will typically *publish* the services; Viewer will *subscribe*. Xcode’s Capabilities UI may not show Wi-Fi Aware—use the provided `.entitlements` files.

---

## Local network privacy
- Host and Viewer list Bonjour service types and present a Local Network Usage description string in their `Info.plist`.

---

## Build & Run (M0)

1. **Open the workspace**  
   Open `BeamRoom.xcworkspace` (not the individual `.xcodeproj`). You should see both Host and Viewer.

2. **Set signing + deployment**  
   In **BeamRoomHost**, **BeamRoomViewer**, and **BeamRoomBroadcastUpload**:
   - Select your Apple **Team**.
   - Set **iOS Deployment Target** to **26.0**.

3. **Add capabilities**  
   - **Host target** ➜ add **App Group** `group.com.conornolan.beamroom` and **Wi-Fi Aware**.  
   - **Broadcast Upload Extension** ➜ add **App Group** `group.com.conornolan.beamroom` and **Wi-Fi Aware**.  
   - **Viewer** ➜ no capabilities for M0.

4. **Run Host**  
   Build and run **BeamRoomHost** on a device: it launches a simple screen.

5. **Run Viewer**  
   Build and run **BeamRoomViewer** on another device (or the same device via a second run): it launches a simple screen.

6. **Extension status**  
   The Broadcast Upload Extension compiles with the app bundle. You’ll wire it into the UI at **M2**.

---

## Milestones snapshot
- **M0 (this commit)**: Workspace, targets, capabilities, empty screens. All targets build to a device.
- **Next**: M1 discovery/pairing → M2 broadcast picker → M3 fake frames → (then real encode/decode + transport).

---

## Notes
- DRM/protected screens render **black by design** (ReplayKit).
- If the **Wi-Fi Aware** entitlement isn’t visible in Xcode’s Capabilities pane, the provided `.entitlements` files already declare it.
