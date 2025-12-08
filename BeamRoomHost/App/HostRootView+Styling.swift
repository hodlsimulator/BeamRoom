//
//  HostRootView+Styling.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI

// MARK: - Small reusable views for HostRootView

struct HostStatusPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)

            Text(label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.14))
        )
    }
}

struct HostLiveBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )

            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.18))
        )
        .foregroundStyle(.white)
    }
}

struct HostStepChip: View {
    let number: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            if number > 0 {
                Text("\(number)")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.9))
                    )
                    .foregroundColor(Color.accentColor)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color.white.opacity(0.85))
            }

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

// MARK: - Glass card styling for HostRootView

struct HostGlassCardModifier: ViewModifier {
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
                    .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
            )
    }
}

extension View {
    func hostGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(HostGlassCardModifier(cornerRadius: cornerRadius))
    }
}
