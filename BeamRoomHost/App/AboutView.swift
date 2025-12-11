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
            ZStack {
                backgroundView

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        overviewSection
                        quickStartSection
                        useCasesSection
                        whereItWorksBestSection
                        privacySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
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
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.12),
                    Color(red: 0.01, green: 0.01, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Cool blue glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.6),
                            Color.accentColor.opacity(0.0)
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .blur(radius: 40)
                .offset(x: -40, y: -80)

            // Warm complementary glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.45),
                            Color.orange.opacity(0.0)
                        ],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .blur(radius: 50)
                .offset(x: 80, y: 120)

            // Soft diagonal streak
            RoundedRectangle(cornerRadius: 200, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(-18))
                .blur(radius: 60)
                .offset(x: 40, y: 40)
        }
        .ignoresSafeArea()
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BeamRoom")
                .font(.largeTitle.bold())

            Text("Share your iPhone screen straight to another device nearby.\nNo accounts, no cables.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .hostGlassCard(cornerRadius: 30)
        .foregroundStyle(.white)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What BeamRoom does")
                .font(.headline)

            Text(
                """
                BeamRoom takes the screen from one device (the Host) and shows it live on one or more other devices (the Viewers) in the same place.

                It can work on normal home Wi‑Fi, on a personal hotspot, or even with no router at all, as long as Wi‑Fi is switched on for both devices.
                """
            )
            .font(.body)

            ExampleDiagram(
                title: "One-to-one",
                description: "A single Host mirrors its screen to one nearby Viewer. Good for help and quick demos.",
                leftIcon: "iphone",
                leftTitle: "Host iPhone",
                leftSubtitle: "Sharing the screen",
                rightIcon: "iphone",
                rightTitle: "Viewer iPhone",
                rightSubtitle: "Watching"
            )
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick start: one Host and one Viewer")
                .font(.headline)

            Text("A simple one‑to‑one setup between two iPhones in the same room.")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                Text("On the Host iPhone")
                    .font(.subheadline.weight(.semibold))

                step(1, "Open BeamRoom and choose the ‘Share’ tab.")
                step(2, "Tap ‘Start sharing’. This starts hosting and opens the Screen Broadcast sheet.")
                step(3, "In the sheet, pick ‘BeamRoom’ if needed, then tap ‘Start Broadcast’.")
                Text("If the sheet does not appear, open Control Centre, long‑press Screen Recording, choose ‘BeamRoom’, then tap Start Broadcast.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }

            Divider()
                .overlay(Color.white.opacity(0.25))

            VStack(alignment: .leading, spacing: 8) {
                Text("On the Viewer iPhone")
                    .font(.subheadline.weight(.semibold))

                step(1, "Open BeamRoom and choose the ‘Watch’ tab.")
                step(2, "Wait for the Host name to appear. If there is only one Host, BeamRoom may connect automatically.")
                step(3, "If it does not connect, tap the big ‘Connect to …’ button above.")
                step(4, "If the Host does not appear or Wi‑Fi is unreliable, scroll to ‘Nearby pairing’ at the bottom, tap ‘Start nearby pairing’, then choose the Host iPhone from the list.")
            }

            Text("Once paired and broadcasting, everything on the Host screen is mirrored live to the Viewer.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private var useCasesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ideas for using BeamRoom")
                .font(.headline)

            // Helping and support
            Text("Helping and support")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                bullet("Helping a family member use an app or change a setting while they just watch.")
                bullet("Showing step‑by‑step how to do something in Settings without handing over a phone.")
                bullet("Walking an older relative through banking or health apps while they see every tap.")
                bullet("Doing a quick “how to install this app” walkthrough for someone sitting beside you.")
            }

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

            // Work, testing and design
            Text("Work, testing and design")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Checking how an iOS build looks on a second device without passing phones around.")
                bullet("Reviewing UI changes with someone at a desk or table while one phone runs the app.")
                bullet("Comparing colours, fonts or layouts on two different screens at the same time.")
                bullet("Walking through screenshots, mock‑ups or a prototype with a colleague beside you.")
            }

            // Relaxed viewing and play
            Text("Relaxed viewing and play")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Playtesting a game together on the sofa while one iPhone controls it.")
                bullet("Practising a talk by mirroring slides from one iPhone to another.")
                bullet("Sharing a quick sketch or diagram from a notes app during a chat.")
                bullet("Leaving one phone charging or recording while its screen is mirrored to a second phone.")
                bullet("Two friends following the same recipe or tutorial while one phone actually runs it.")
            }
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private var whereItWorksBestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where it works best")
                .font(.headline)

            Text(
                """
                BeamRoom is tuned for short‑range sharing between devices in the same place. It is meant for nearby, in‑person use, not long‑distance streaming over the internet.
                """
            )
            .font(.body)

            VStack(alignment: .leading, spacing: 6) {
                bullet("Devices are in the same room, for example across a table or sofa.")
                bullet("Both devices have Wi‑Fi turned on, either on the same network or using a hotspot.")
            }

            ExampleDiagram(
                title: "At the table",
                description: "Two phones on the same table: one shares the screen while the other follows along.",
                leftIcon: "iphone",
                leftTitle: "Host",
                leftSubtitle: "Screen being shared",
                rightIcon: "iphone",
                rightTitle: "Viewer",
                rightSubtitle: "Comfortable view"
            )
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.headline)

            Text(
                """
                BeamRoom is built for nearby, in‑person use:

                • No accounts.
                • No remote servers.
                • Screen data is sent only between the Host and Viewer devices.
                """
            )
            .font(.body)
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    // MARK: - Helpers

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.body)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .frame(width: 18, alignment: .trailing)
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
