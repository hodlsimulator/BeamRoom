# BeamRoom (iOS 26)

BeamRoom is a serverless, high-quality screen-sharing app. A Host iPhone/iPad mirrors its screen to nearby Viewers using Wi-Fi Aware + Network.framework. Capture uses ReplayKit (Broadcast Upload Extension). Video is H.264 (VideoToolbox). No Wi-Fi, no internet, no accounts, no servers.

## Minimum OS
iOS 26 only.

## Targets (M0)
- BeamRoomHost (SwiftUI app)
- BeamRoomViewer (SwiftUI app) — add next
- BeamRoomBroadcastUpload (Broadcast Upload Extension) — add to Host next
- BeamCore (Swift Package) — add next

## Build (M0)
Open `BeamRoom.xcworkspace` in Xcode. Run Host on a device (scaffold screen).
