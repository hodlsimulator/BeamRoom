//
//  BeamLogView.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//
//  Updated: 2025-09-27
//  - Large, accessible VerbosityDial (chips) with haptics
//  - Uses system Material so it adopts iOS 26 styling automatically
//  - No word wrapping on verbosity buttons/pills
//

import SwiftUI
import UIKit

public struct BeamLogView: View {
    @ObservedObject private var log = BeamInAppLog.shared
    @State private var autoScroll = true
    @State private var showShare = false
    @State private var shareText = ""
    @State private var lastID: UUID?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [shareText]).ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: title + compact controls
            HStack(spacing: 10) {
                Text("Debug Log")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 8)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Button {
                    UIPasteboard.general.string = log.dumpText()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(.bordered)

                Button {
                    shareText = log.dumpText()
                    showShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    BeamInAppLog.shared.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(.bordered)
            }

            // Large, easy Verbosity “dial”
            VerbosityDial(level: $log.minLevel)
        }
        .padding(12)
        .background(.thinMaterial) // adopts iOS 26 look automatically
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(log.entries) { e in
                        LogRow(entry: e).id(e.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: log.entries.last?.id) { _, newID in
                guard autoScroll, let id = newID else { return }
                lastID = id
                withAnimation(.easeOut) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onAppear {
                if let id = log.entries.last?.id {
                    lastID = id
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Verbosity Dial (large, chip-based)

private struct VerbosityDial: View {
    @Binding var level: BeamLogLevel

    // Left → right, least → most verbose
    private let ordered: [BeamLogLevel] = [.error, .warn, .info, .debug]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label row
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash")
                    .accessibilityHidden(true)
                Text("Verbosity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(humanLabel(for: level))
                    .font(.subheadline.monospaced())
                    .lineLimit(1)                // no wrapping
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(color(for: level))
                            .opacity(0.12) // view opacity (not ShapeStyle)
                    )
                    .overlay(
                        Capsule()
                            .stroke(color(for: level), lineWidth: 1)
                            .opacity(0.35)
                    )
                    .accessibilityHidden(true)
                Image(systemName: "speaker.wave.3")
                    .accessibilityHidden(true)
            }

            // Big, tap-friendly chip row
            HStack(spacing: 8) {
                ForEach(ordered, id: \.self) { lv in
                    levelChip(for: lv)
                        .onTapGesture {
                            if level != lv {
                                level = lv
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            }
                        }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Verbosity")
            .accessibilityValue(humanLabel(for: level))
        }
    }

    @ViewBuilder
    private func levelChip(for lv: BeamLogLevel) -> some View {
        let selected = (lv.rank == level.rank)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        HStack(spacing: 6) {
            Image(systemName: icon(for: lv))
            Text(shortLabel(for: lv))
                .font(.body.weight(.semibold))
                .lineLimit(1)            // no wrapping on chip text
                .truncationMode(.tail)
                .minimumScaleFactor(0.95)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 88)
        .contentShape(shape)
        .foregroundStyle(selected ? color(for: lv) : .primary)
        // Background: use Material by default (adopts iOS 26), tint when selected
        .background(
            Group {
                if selected {
                    shape.fill(color(for: lv))
                        .opacity(0.18) // apply opacity to the filled view
                } else {
                    shape.fill(.ultraThinMaterial) // pure ShapeStyle
                }
            }
        )
        // Stroke: choose style first, then apply view opacity
        .overlay(
            shape
                .stroke(selected ? color(for: lv) : Color.secondary,
                        lineWidth: selected ? 1.5 : 1)
                .opacity(selected ? 0.55 : 0.25)
        )
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(humanLabel(for: lv))
        .accessibilityHint(selected ? "Current level" : "Set verbosity to \(humanLabel(for: lv))")
    }

    private func shortLabel(for lv: BeamLogLevel) -> String {
        switch lv {
        case .error: return "Errors"
        case .warn:  return "Warnings"
        case .info:  return "Info"
        case .debug: return "Debug"
        }
    }

    private func humanLabel(for lv: BeamLogLevel) -> String {
        switch lv {
        case .error: return "Errors only"
        case .warn:  return "Warnings and errors"
        case .info:  return "Info, warnings, errors"
        case .debug: return "Everything (debug)"
        }
    }

    private func icon(for lv: BeamLogLevel) -> String {
        switch lv {
        case .error: return "xmark.octagon.fill"
        case .warn:  return "exclamationmark.triangle.fill"
        case .info:  return "info.circle.fill"
        case .debug: return "ladybug.fill"
        }
    }

    private func color(for lv: BeamLogLevel) -> Color {
        switch lv {
        case .error: return .red
        case .warn:  return .orange
        case .info:  return .blue
        case .debug: return .secondary
        }
    }
}

// MARK: - Log row

private struct LogRow: View {
    let entry: BeamLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts(entry.ts))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color(for: entry.level))
                .frame(width: 54, alignment: .leading)

            Text(entry.tag)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    private func ts(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "HH:mm:ss.SSS"
        return df.string(from: d)
    }

    private func color(for level: BeamLogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}

// MARK: - Share sheet wrapper

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
