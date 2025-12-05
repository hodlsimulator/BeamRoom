//
//  AboutView.swift
//  BeamRoomHost
//
//  Created by . . on 12/6/25.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    overviewSection
                    useCasesSection
                    diagramsSection
                    howItWorksSection
                    privacySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("About BeamRoom")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BeamRoom")
                .font(.largeTitle.bold())

            Text("Quick, local screen sharing between iPhone and iPad on the same network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What BeamRoom does")
                .font(.headline)

            Text("""
BeamRoom mirrors the screen of a Host device to one or more Viewer devices nearby. Everything runs on the local network, with no accounts and no internet dependency.
""")
                .font(.body)
        }
    }

    private var useCasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Examples")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Playtesting a game together on the sofa.")
                bullet("Walking a family member through an app or settings page.")
                bullet("Previewing an iOS build on a second device while adjusting layouts.")
                bullet("Practising a talk by mirroring an iPad to an iPhone across the room.")
                bullet("Sharing a diagram or sketch from a tablet during a quick discussion.")
            }
        }
    }

    private var diagramsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagrams")
                .font(.headline)

            VStack(spacing: 16) {
                ExampleDiagram(
                    title: "One-to-one",
                    description: "A single Host mirrors its screen to one nearby Viewer on the same Wi‑Fi.",
                    leftIcon: "iphone",
                    leftTitle: "Host",
                    leftSubtitle: "Sharing the screen",
                    rightIcon: "iphone",
                    rightTitle: "Viewer",
                    rightSubtitle: "Watching"
                )

                ExampleDiagram(
                    title: "Around the table",
                    description: "An iPad in the centre shares to a phone so text can be read more comfortably.",
                    leftIcon: "ipad",
                    leftTitle: "Host iPad",
                    leftSubtitle: "Drawing or browsing",
                    rightIcon: "iphone",
                    rightTitle: "Viewer iPhone",
                    rightSubtitle: "Close-up view"
                )

                ExampleDiagram(
                    title: "Practice session",
                    description: "A presenter rehearses a slide deck from an iPad while a Viewer in another spot follows along.",
                    leftIcon: "ipad",
                    leftTitle: "Presenter",
                    leftSubtitle: "Slides on screen",
                    rightIcon: "iphone",
                    rightTitle: "Listener",
                    rightSubtitle: "Following along"
                )
            }
        }
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)

            Text("""
The Share tab turns a device into a Host and advertises it on the local network.

The Watch tab discovers nearby Hosts and pairs with one of them. Once paired, a Screen Broadcast started from Control Centre or from the Share tab sends video frames from the Host to the Viewer.
""")
                .font(.body)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.headline)

            Text("""
BeamRoom is designed for local use:

• No accounts.
• No remote servers.
• Traffic stays on the local network between Host and Viewer devices.
""")
                .font(.body)
        }
    }

    // MARK: - Helpers

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.body)
    }
}

// MARK: - Diagram components

struct ExampleDiagram: View {
    let title: String
    let description: String
    let leftIcon: String
    let leftTitle: String
    let leftSubtitle: String
    let rightIcon: String
    let rightTitle: String
    let rightSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                DeviceBubble(
                    systemImage: leftIcon,
                    title: leftTitle,
                    subtitle: leftSubtitle
                )

                Image(systemName: "arrow.left.and.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                DeviceBubble(
                    systemImage: rightIcon,
                    title: rightTitle,
                    subtitle: rightSubtitle
                )
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DeviceBubble: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .padding(8)

            Text(title)
                .font(.footnote.weight(.semibold))

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: 120)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
        )
    }
}
