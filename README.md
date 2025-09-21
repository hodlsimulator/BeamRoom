# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A Host iPhone/iPad mirrors its screen to nearby Viewers using Wi-Fi Aware + Network.framework. Capture uses ReplayKit (Broadcast Upload Extension). Video is H.264 (VideoToolbox). No Wi-Fi, no internet, no accounts, no servers.

## Minimum OS
iOS 26 only.

## Targets
- BeamRoomHost (SwiftUI app)
- BeamRoomViewer (SwiftUI app)
- BeamRoomBroadcastUpload (Broadcast Upload Extension: `RPBroadcastSampleHandler`)
- BeamCore (Swift Package with shared protocols, config, logging)

## Capabilities
Host + Extension: App Group `group.com.conornolan.beamroom` and Wi-Fi Aware entitlement.  
WiFiAwareServices declared in each Info.plist:
- Media: `_beamroom._udp`
- Control: `_beamctl._tcp`

## Local network privacy
Host/Viewer list Bonjour service types and show a local-network usage reason string.

## Build & Run (M0)
1. Open `BeamRoom.xcworkspace`.
2. Select your Apple Team on all three targets. Set iOS Deployment to 26.0.
3. Host target: add App Group + Wi-Fi Aware capability. Extension: add App Group + Wi-Fi Aware. Viewer: none for M0.
4. Build and run **BeamRoomHost** on a device: it launches a simple screen.
5. Build and run **BeamRoomViewer** on another device (or the same device, different run): it launches a simple screen.
6. The Broadcast Upload Extension is compiled and ready; you’ll wire it in at M2.

## Milestones snapshot
- M0 (this commit): Workspace, targets, capabilities, empty screens. All targets build to a device.
- Next: M1 discovery/pairing, M2 broadcast picker, M3 fake frames, etc.

## Notes
- DRM/protected screens render black by design (ReplayKit).
- If Wi-Fi Aware entitlement isn’t visible in Xcode’s UI, the provided `.entitlements` files already declare it.
