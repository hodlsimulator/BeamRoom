//
//  AboutView.swift
//  BeamRoomHost
//
//  Created by . . on 12/6/25.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum LegalLinks {
        static let privacyPolicy = URL(string: "https://beamroom.app/privacy.html")!
    }

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
                        legalSection
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

            Text("Share an iPhone screen straight to another device nearby.\nNo accounts, no cables.")
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
                description: "A single Host mirrors its screen to one nearby Viewer.\nGood for quick help and simple demos.",
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

            Text("Follow these steps to mirror one iPhone to another in the same room.")
                .font(.body)

            // Host steps
            VStack(alignment: .leading, spacing: 8) {
                Text("On the Host iPhone")
                    .font(.subheadline.weight(.semibold))

                step(1, "Open BeamRoom and choose the ‘Share’ tab.")
                step(2, "Tap ‘Start sharing’.\nThis turns this iPhone into the Host and opens the Screen Broadcast sheet.")
                step(3, "In the sheet, pick ‘BeamRoom’ if needed, then tap ‘Start Broadcast’.")

                Text("If the sheet does not appear, open Control Centre, long‑press Screen Recording, choose ‘BeamRoom’, then tap Start Broadcast.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }

            Divider()
                .overlay(Color.white.opacity(0.25))

            // Viewer steps – Nearby pairing
            VStack(alignment: .leading, spacing: 8) {
                Text("On the Viewer iPhone")
                    .font(.subheadline.weight(.semibold))

                step(1, "Open BeamRoom and choose the ‘Watch’ tab.")
                step(2, "At the bottom, find the ‘Nearby pairing’ card and tap ‘Start nearby pairing’.")
                step(3, "When the picker appears, choose the Host iPhone from the list.")
                step(4, "After a moment, the Host screen appears on this iPhone while the Host keeps control.")
            }
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private var useCasesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everyday ways to use BeamRoom")
                .font(.headline)

            Text("BeamRoom is useful whenever one person is doing something on their iPhone and someone nearby wants to follow along on a second screen.")
                .font(.body)

            VStack(spacing: 10) {
                // 1. Helping with a phone
                UseCaseAccordion(
                    title: "Helping with a phone",
                    subtitle: "Showing where to tap",
                    systemImage: "person.crop.circle.badge.questionmark",
                    points: [
                        "Explaining what to tap in an unfamiliar app while everyone looks at the same screen.",
                        "Showing how to reach a page in Settings from across a table or sofa.",
                        "Talking through a message, email or web page that is easier to see on a second phone."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "person", label: "Helper"),
                        UseCaseChip(systemImage: "iphone", label: "Host"),
                        UseCaseChip(systemImage: "eye", label: "Viewer")
                    ]
                )

                // 2. Family admin
                UseCaseAccordion(
                    title: "Family admin",
                    subtitle: "Keeping everyone on the same page",
                    systemImage: "person.3",
                    points: [
                        "Looking at school or club messages together on a clear screen.",
                        "Checking dates for family events or visits while talking them through.",
                        "Reviewing simple forms or documents before they are sent."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "calendar", label: "Dates"),
                        UseCaseChip(systemImage: "envelope", label: "Messages"),
                        UseCaseChip(systemImage: "house", label: "Home")
                    ]
                )

                // 3. Planning something together
                UseCaseAccordion(
                    title: "Planning something together",
                    subtitle: "Looking at the same information",
                    systemImage: "calendar.badge.clock",
                    points: [
                        "Reviewing a simple plan or schedule while one person scrolls.",
                        "Checking options such as times, prices or choices so everyone can see clearly.",
                        "Looking at a list or notes with more than one person without passing one phone around."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "calendar.badge.clock", label: "Plan"),
                        UseCaseChip(systemImage: "list.bullet", label: "List"),
                        UseCaseChip(systemImage: "person.2", label: "Together")
                    ]
                )

                // 4. Shopping together
                UseCaseAccordion(
                    title: "Shopping together",
                    subtitle: "Choosing what to buy",
                    systemImage: "cart",
                    points: [
                        "Comparing items in an online shop while sitting together.",
                        "Looking at sizes, colours or details while one person controls the page.",
                        "Checking a basket or price total together before ordering."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "cart", label: "Shop"),
                        UseCaseChip(systemImage: "tag", label: "Choices"),
                        UseCaseChip(systemImage: "creditcard", label: "Total")
                    ]
                )

                // 5. Travel and journeys
                UseCaseAccordion(
                    title: "Travel and journeys",
                    subtitle: "Talking through where to go",
                    systemImage: "airplane",
                    points: [
                        "Showing a simple map while explaining where things are.",
                        "Checking a route to a place together while one person moves the map.",
                        "Looking at basic travel details such as stop names or addresses."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "airplane", label: "Trip"),
                        UseCaseChip(systemImage: "figure.walk", label: "Route"),
                        UseCaseChip(systemImage: "car.fill", label: "Transport")
                    ]
                )

                // 6. Learning and teaching
                UseCaseAccordion(
                    title: "Learning and teaching",
                    subtitle: "Explaining how something works",
                    systemImage: "graduationcap",
                    points: [
                        "Showing a short tutorial or guide while talking through it.",
                        "Pointing out controls or icons in an app when someone is new to it.",
                        "Going over simple instructions step by step while everyone can see."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "book", label: "Guide"),
                        UseCaseChip(systemImage: "lightbulb", label: "Idea"),
                        UseCaseChip(systemImage: "questionmark.circle", label: "Questions")
                    ]
                )

                // 7. Sharing things to watch
                UseCaseAccordion(
                    title: "Sharing things to watch",
                    subtitle: "Letting someone just sit back and view",
                    systemImage: "play.rectangle.on.rectangle",
                    points: [
                        "Showing photos or short videos to someone nearby on a second screen.",
                        "Letting someone watch a game or app from a comfortable seat while another person plays.",
                        "Using a second phone as a small preview screen while practising a talk or simple demo."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "photo.on.rectangle", label: "Photos"),
                        UseCaseChip(systemImage: "play.rectangle", label: "Clips"),
                        UseCaseChip(systemImage: "sparkles", label: "Demo")
                    ]
                )

                // 8. Games and fun
                UseCaseAccordion(
                    title: "Games and fun",
                    subtitle: "Watching the action",
                    systemImage: "gamecontroller",
                    points: [
                        "Letting someone watch a game from a better angle while another person plays.",
                        "Showing different levels or screens in a game without passing the phone around.",
                        "Watching a puzzle or quiz app together on a second phone."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "gamecontroller", label: "Game"),
                        UseCaseChip(systemImage: "person.2", label: "Together"),
                        UseCaseChip(systemImage: "sparkles", label: "Fun")
                    ]
                )

                // 9. Work and study
                UseCaseAccordion(
                    title: "Work and study",
                    subtitle: "Looking over simple content",
                    systemImage: "doc.text",
                    points: [
                        "Reading a short document or notes together.",
                        "Checking a simple slide or diagram while talking it through.",
                        "Looking at a to‑do list or reminder list with someone else."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "doc.text", label: "Notes"),
                        UseCaseChip(systemImage: "checkmark.circle", label: "Tasks"),
                        UseCaseChip(systemImage: "paperclip", label: "Files")
                    ]
                )

                // 10. Sorting out problems
                UseCaseAccordion(
                    title: "Sorting out problems",
                    subtitle: "Showing what is going wrong",
                    systemImage: "exclamationmark.triangle",
                    points: [
                        "Showing a strange message or pop‑up on the Host phone from a second screen.",
                        "Letting someone see error screens or alerts clearly while they suggest what to try.",
                        "Keeping the Host in hand while another person watches what happens."
                    ],
                    chips: [
                        UseCaseChip(systemImage: "exclamationmark.triangle", label: "Alert"),
                        UseCaseChip(systemImage: "hand.raised", label: "Help"),
                        UseCaseChip(systemImage: "wrench.and.screwdriver", label: "Fix")
                    ]
                )
            }
            .padding(.top, 4)
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
                BeamRoom is tuned for short‑range sharing between devices in the same place.
                It is meant for nearby, in‑person use, not long‑distance streaming over the internet.
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

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legal")
                .font(.headline)

            VStack(spacing: 0) {
                Button {
                    openURL(LegalLinks.privacyPolicy)
                } label: {
                    legalRow(
                        title: "Privacy Policy",
                        subtitle: "beamroom.app/privacy.html",
                        systemImage: "hand.raised.fill",
                        trailingSystemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(Color.white.opacity(0.18))

                NavigationLink {
                    EULAView()
                } label: {
                    legalRow(
                        title: "End-User Licence Agreement",
                        subtitle: "Read in the app",
                        systemImage: "doc.text.fill",
                        trailingSystemImage: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 26)
        .foregroundStyle(.white)
    }

    private func legalRow(
        title: String,
        subtitle: String,
        systemImage: String,
        trailingSystemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            Image(systemName: trailingSystemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

struct EULAView: View {
    private enum LegalText {
        static let effectiveDate = "12 December 2025"

        static let eula = """
        This End-User Licence Agreement ("Agreement") applies to BeamRoom (the "App").

        By downloading, installing, or using the App, you agree to this Agreement. If you do not agree, do not use the App.

        1. Acknowledgement
        This Agreement is between you and the App publisher / developer ("Developer"), not Apple. Apple is not responsible for the App or its content, except where the law requires otherwise.

        2. Scope of licence
        The Developer grants a limited, non-exclusive, non-transferable, revocable licence to use the App on Apple-branded devices that you own or control, for personal or internal use, in accordance with Apple’s App Store terms and this Agreement.

        3. Restrictions
        Unless the law allows it, the App must not be:
        • copied, modified, or distributed outside the normal App Store installation and family sharing mechanisms;
        • reverse engineered, decompiled, or disassembled;
        • used to develop a competing product or service; or
        • used in a way that interferes with the App, the local network, or other devices.

        4. Ownership
        The App and all associated intellectual property rights are owned by the Developer and/or its licensors. This Agreement does not transfer ownership of the App.

        5. Screen sharing, content, and safety
        BeamRoom enables nearby screen sharing. While sharing is active, viewers can see whatever appears on the host device’s screen, and they may be able to capture or record that content on their own devices.
        Only share with people you trust, and avoid sharing sensitive information (for example passwords, payment details, private messages, or confidential work material).

        You are responsible for:
        • ensuring you have permission to share any content displayed on the host screen;
        • complying with all applicable laws and third-party terms (including streaming or DRM restrictions); and
        • how and where the App is used (BeamRoom is intended for nearby, in-person use on local networks).

        6. Privacy
        The Developer’s Privacy Policy explains how BeamRoom handles information. It is available at:
        https://beamroom.app/privacy.html

        7. Purchases
        If the App offers in-app purchases, those purchases are processed by Apple. The Developer receives purchase state information from Apple (such as which product identifiers are active) so the App can unlock features.

        8. Maintenance and support
        The Developer, not Apple, is responsible for providing any maintenance and support for the App, if offered. Apple has no obligation to provide support services for the App.

        9. Warranty
        To the maximum extent permitted by law, the App is provided "as is" and "as available" without warranties of any kind. The Developer does not guarantee that the App will be uninterrupted, error-free, or work on all networks and environments.

        Some jurisdictions do not allow certain warranty exclusions, so some of the above may not apply.

        10. Product claims
        If any claim arises that the App fails to conform to any applicable legal or regulatory requirement, you agree that Apple is not responsible for investigating, defending, settling, or discharging that claim. Such claims are the responsibility of the Developer, subject to applicable law.

        11. Limitation of liability
        To the maximum extent permitted by law, the Developer will not be liable for indirect, incidental, special, consequential, or punitive damages, or for loss of profits, revenue, data, or goodwill, arising out of or related to the use of the App.

        Where liability cannot be excluded, it will be limited to the minimum extent permitted by law.

        12. Legal compliance
        You represent that:
        • you are not located in a country subject to a government embargo, and
        • you are not listed on any government list of prohibited or restricted parties,
        to the extent such restrictions apply to your use of the App.

        13. Third-party terms
        The App may interact with Apple frameworks and services (for example ReplayKit, Network.framework, and the App Store). Use of those services may be subject to Apple’s terms and policies.

        14. Termination
        This Agreement is effective until terminated. The Developer may terminate this Agreement if you breach it. Upon termination, you must stop using the App.

        15. Third-party beneficiary
        Apple and Apple’s subsidiaries are third-party beneficiaries of this Agreement. Upon your acceptance of this Agreement, Apple will have the right (and will be deemed to have accepted the right) to enforce this Agreement against you as a third-party beneficiary.

        16. Contact
        For support questions, contact:
        support@beamroom.app
        """
    }

    var body: some View {
        ZStack {
            backgroundView

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("End-User Licence Agreement")
                        .font(.title2.bold())

                    Text("Effective date: \(LegalText.effectiveDate)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))

                    Divider()
                        .overlay(Color.white.opacity(0.20))

                    Text(LegalText.eula)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(18)
                .hostGlassCard(cornerRadius: 26)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle("EULA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

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
}

// MARK: - Diagram components (Host ↔ Viewer)

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

// MARK: - Use‑case accordions (collapsible examples)

struct UseCaseChip: Identifiable, Hashable {
    let id = UUID()
    let systemImage: String
    let label: String
}

struct UseCaseDiagram: View {
    let chips: [UseCaseChip]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(chips) { chip in
                VStack(spacing: 4) {
                    Image(systemName: chip.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.12))
                        )

                    Text(chip.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct UseCaseAccordion: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let points: [String]
    let chips: [UseCaseChip]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(0.22))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    UseCaseDiagram(chips: chips)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(point)
                            }
                            .font(.footnote)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
