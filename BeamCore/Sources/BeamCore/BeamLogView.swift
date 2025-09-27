//
//  BeamLogView.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
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
        HStack(spacing: 10) {
            Text("Debug Log")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 8)

            Picker("Verbosity", selection: $log.minLevel) {
                Text("Debug").tag(BeamLogLevel.debug)
                Text("Info").tag(BeamLogLevel.info)
                Text("Warn").tag(BeamLogLevel.warn)
                Text("Error").tag(BeamLogLevel.error)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

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
        .padding(12)
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
                withAnimation(.easeOut) { proxy.scrollTo(id, anchor: .bottom) }
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

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
