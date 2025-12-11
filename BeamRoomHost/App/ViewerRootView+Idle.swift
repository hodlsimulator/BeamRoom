//
//  ViewerRootView+Idle.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import UIKit
import BeamCore

extension ViewerRootView {

    // MARK: - Idle state before any video arrives

    var idleStateView: some View {
        ScrollView(showsIndicators: false) {
            idleScrollContent
                // Attach the UIKit helper to the scroll view so it
                // hard-locks horizontally while keeping vertical scroll.
                .background(VerticalScrollConfigurator())
        }
    }

    /// The actual contents of the idle scroll view.
    private var idleScrollContent: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            heroCard

            if model.showPermHint && model.browser.hosts.isEmpty {
                permissionHint
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 70) // space above pinned bottom controls
    }

    // MARK: - Main hero card (discovery + host list)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header row – title + icon
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        StepChip(number: 1, label: "Watch")
                    }

                    Text("Watch a nearby screen")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(idleSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(10)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }

            // Discovery + host selection area
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusPill(
                        icon: "dot.radiowaves.left.and-right",
                        label: hostsStatusLabel
                    )

                    if model.browser.hosts.isEmpty {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .font(.caption2)

                if model.browser.hosts.isEmpty {
                    discoveringView
                } else {
                    primaryConnectButton()

                    if model.browser.hosts.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other nearby Hosts")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            hostList
                        }
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.2), value: model.browser.hosts)
    }

    private var hostsStatusLabel: String {
        let count = model.browser.hosts.count

        switch count {
        case 0:
            return "Searching for Hosts"
        case 1:
            return "1 Host found"
        default:
            return "\(count) Hosts found"
        }
    }

    private var idleSubtitle: String {
        let count = model.browser.hosts.count

        if count == 0 {
            // No Hosts discovered yet – explain the simple flow.
            return "Open BeamRoom on another device, choose Share, and it will appear here automatically."
        } else if count == 1 {
            // Single Host – matches the auto‑connect behaviour.
            return "Found 1 nearby Host. Tap below or wait for automatic pairing."
        } else {
            // Multiple Hosts – user chooses which one to join.
            return "Found \(count) nearby Hosts.\nChoose one below to start watching."
        }
    }

    // MARK: - Host list + discovery

    private var primaryHost: DiscoveredHost? {
        if let selected = model.selectedHost {
            return selected
        }
        return model.browser.hosts.first
    }

    @ViewBuilder
    func primaryConnectButton() -> some View {
        if let host = primaryHost {
            Button {
                model.pick(host)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(host.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var discoveringView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BeamRoom is searching on this network for devices sharing from the Share tab.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

            Text("As soon as a Host is found it appears here and connects automatically.\nIf nothing shows up, tap Start nearby pairing below.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    @ViewBuilder
    var hostList: some View {
        VStack(spacing: 8) {
            ForEach(model.browser.hosts) { host in
                Button {
                    model.pick(host)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .imageScale(.medium)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                                .font(.body)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Text("Tap to connect")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    var permissionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing showing up?")
                    .font(.footnote.weight(.semibold))

                Text("Local Network access for BeamRoom may need to be enabled in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 6)

            Button("Open") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.18))
            )
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .foregroundStyle(.white)
    }
}

// MARK: - Small reusable views for styling

private struct StatusPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)

            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.16))
        )
    }
}

private struct StepChip: View {
    let number: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.semibold))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.9))
                )
                .foregroundColor(Color.accentColor)

            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
    }
}

// MARK: - Glass card styling

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(
                        color: .black.opacity(0.45),
                        radius: 16,
                        x: 0,
                        y: 8
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Scroll locking helper

private struct VerticalScrollConfigurator: UIViewRepresentable {

    final class Coordinator {
        var observation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        // Defer configuration until the view is in the hierarchy,
        // so enclosingScrollView can actually find the ScrollView.
        DispatchQueue.main.async {
            configure(using: view, coordinator: context.coordinator)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            configure(using: uiView, coordinator: context.coordinator)
        }
    }

    private func configure(using view: UIView, coordinator: Coordinator) {
        guard let scrollView = view.enclosingScrollView else { return }

        // Match the Share tab feel but add a hard horizontal lock.
        scrollView.isDirectionalLockEnabled = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsHorizontalScrollIndicator = false

        // Clamp any horizontal offset that might sneak through.
        coordinator.observation?.invalidate()
        coordinator.observation = scrollView.observe(
            \.contentOffset,
            options: [.new]
        ) { scrollView, _ in
            let offset = scrollView.contentOffset

            // Only adjust if there’s meaningful horizontal movement.
            if abs(offset.x) > 0.5 {
                let locked = CGPoint(x: 0, y: offset.y)
                scrollView.setContentOffset(locked, animated: false)
            }
        }
    }
}

private extension UIView {
    /// Walks up the view hierarchy to find the nearest enclosing UIScrollView.
    var enclosingScrollView: UIScrollView? {
        var candidate: UIView? = self

        while let current = candidate {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            candidate = current.superview
        }

        return nil
    }
}
