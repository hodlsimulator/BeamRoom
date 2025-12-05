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

            Text("Share your iPhone or iPad screen straight to another device nearby. No accounts, no cables.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What BeamRoom does")
                .font(.headline)

            Text(
                """
                BeamRoom takes the screen from one device (the Host) and shows it live on one or more other devices (the Viewers) in the same place.

                It can work on normal home Wi-Fi, on a personal hotspot, or even with no router at all, as long as Wi-Fi is switched on for both devices.
                """
            )
            .font(.body)
        }
    }

    private var useCasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ideas for using BeamRoom")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Playtesting a game together on the sofa while one person controls it.")
                bullet("Helping a family member use an app or change a setting while they just watch.")
                bullet("Checking how an iOS build looks on a second device without passing phones around.")
                bullet("Practising a talk by mirroring an iPad to an iPhone across the room.")
                bullet("Sharing a quick sketch or diagram from a tablet during a chat.")
                bullet("Watching your own phone on another screen while it is on a stand across the room.")
                bullet("Letting a child watch a video on an iPad while the phone doing the streaming stays with you.")
                bullet("Comparing colours, fonts or layouts on two different screens at the same time.")
                bullet("Showing a step-by-step how-to to a friend in a café without handing over your phone.")
                bullet("Walking through screenshots, mock-ups or a prototype with someone sitting beside you.")
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
                    description: "A single Host mirrors its screen to one nearby Viewer. Good for help and quick demos.",
                    leftIcon: "iphone",
                    leftTitle: "Host",
                    leftSubtitle: "Sharing the screen",
                    rightIcon: "iphone",
                    rightTitle: "Viewer",
                    rightSubtitle: "Watching"
                )

                ExampleDiagram(
                    title: "Around the table",
                    description: "An iPad in the middle shares to a phone so someone can see text or drawings more clearly.",
                    leftIcon: "ipad",
                    leftTitle: "Host iPad",
                    leftSubtitle: "Drawing or browsing",
                    rightIcon: "iphone",
                    rightTitle: "Viewer iPhone",
                    rightSubtitle: "Close-up view"
                )

                ExampleDiagram(
                    title: "Practice session",
                    description: "A presenter rehearses a slide deck on an iPad while a Viewer in another spot follows along.",
                    leftIcon: "ipad",
                    leftTitle: "Presenter",
                    leftSubtitle: "Slides on screen",
                    rightIcon: "iphone",
                    rightTitle: "Listener",
                    rightSubtitle: "Following along"
                )

                ExampleDiagram(
                    title: "Coach and learner",
                    description: "One person taps through menus on their phone while the other watches and learns on a second device.",
                    leftIcon: "iphone",
                    leftTitle: "Coach",
                    leftSubtitle: "Tapping through steps",
                    rightIcon: "iphone",
                    rightTitle: "Learner",
                    rightSubtitle: "Watching calmly"
                )

                ExampleDiagram(
                    title: "Parent and child",
                    description: "A parent keeps the Host phone, but the child watches the mirrored screen on an iPad.",
                    leftIcon: "iphone",
                    leftTitle: "Parent",
                    leftSubtitle: "Controls playback",
                    rightIcon: "ipad",
                    rightTitle: "Child",
                    rightSubtitle: "Watches on iPad"
                )

                ExampleDiagram(
                    title: "Desk and sofa",
                    description: "A phone on a stand acts as the Host, sending the screen to a Viewer in a more comfortable spot.",
                    leftIcon: "iphone",
                    leftTitle: "Desk phone",
                    leftSubtitle: "On a stand",
                    rightIcon: "iphone",
                    rightTitle: "Sofa phone",
                    rightSubtitle: "Comfortable view"
                )
            }
        }
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)

            Text(
                """
                • The Share tab makes your device the Host.
                • The Watch tab looks for Hosts nearby and connects to one of them.
                • Once paired, starting a Screen Broadcast sends live video from the Host to the Viewer.

                BeamRoom does not need a full home network. It works when both devices have Wi-Fi turned on and are close to each other. A normal router, a hotspot, or a direct wireless link between the devices all work.
                """
            )
            .font(.body)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.headline)

            Text(
                """
                BeamRoom is built for nearby, in-person use:

                • No accounts.
                • No remote servers.
                • Screen data is sent only between the Host and Viewer devices.
                """
            )
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
