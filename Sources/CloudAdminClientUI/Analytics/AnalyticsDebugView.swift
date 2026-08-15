//
//  AnalyticsDebugView.swift
//  CloudAdminClientUI
//
//  Debug view for monitoring analytics events and queue status
//

import CloudAdminClient
import SwiftUI

// MARK: - Analytics Debug View

/// A debug view for monitoring analytics events and queue status
/// A debug screen showing queue status and recent analytics events, with actions to flush
/// the queue or fire a test event. Drop into a developer settings menu; not for release UI.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct AnalyticsDebugView: View {
    @State private var observer = AnalyticsObserver()
    @State private var isRefreshing = false
    @State private var selectedEvent: AnalyticsEvent?
    @State private var showingEventDetail = false

    public init() {}

    public var body: some View {
        List {
            statusSection
            actionsSection
            recentEventsSection
        }
        .navigationTitle("Analytics Debug")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await observer.startObserving(refreshInterval: 2)
        }
        .onDisappear {
            observer.stopObserving()
        }
        .sheet(isPresented: $showingEventDetail) {
            if let event = selectedEvent {
                EventDetailView(event: event)
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Queue Status") {
            LabeledContent("Events in Queue", value: "\(observer.queueSize)")

            if let lastUpload = observer.lastUploadTime {
                LabeledContent("Last Upload") {
                    Text(lastUpload, style: .relative)
                }
            } else {
                LabeledContent("Last Upload", value: "Never")
            }

            LabeledContent("Analytics Enabled", value: observer.isEnabled ? "Yes" : "No")

            if let userID = observer.userID {
                LabeledContent("User ID", value: userID)
            } else {
                LabeledContent("User ID", value: "Anonymous")
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                Task {
                    isRefreshing = true
                    await observer.flush()
                    isRefreshing = false
                }
            } label: {
                HStack {
                    Text("Flush Queue")
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                    }
                }
            }
            .disabled(observer.queueSize == 0 || isRefreshing)

            Button {
                Task {
                    await observer.refresh()
                }
            } label: {
                Text("Refresh Status")
            }

            Button("Track Test Event") {
                Task {
                    await AnalyticsService.shared?.trackCustom(
                        "debug_test_event",
                        properties: ["source": "debug_view", "timestamp": Date().timeIntervalSince1970]
                    )
                    await observer.refresh()
                }
            }
        }
    }

    // MARK: - Recent Events Section

    private var recentEventsSection: some View {
        Section("Recent Events (\(observer.recentEvents.count))") {
            if observer.recentEvents.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Analytics events will appear here")
                )
            } else {
                ForEach(observer.recentEvents) { event in
                    EventRow(event: event)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEvent = event
                            showingEventDetail = true
                        }
                }
            }
        }
    }
}

// MARK: - Event Row

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct EventRow: View {
    let event: AnalyticsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.eventType.displayName)
                    .font(.headline)

                Spacer()

                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let name = event.eventName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let screen = event.screenName {
                Text("Screen: \(screen)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Event Detail View

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct EventDetailView: View {
    let event: AnalyticsEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Event Info") {
                    LabeledContent("Type", value: event.eventType.displayName)
                    if let name = event.eventName {
                        LabeledContent("Name", value: name)
                    }
                    LabeledContent("Timestamp") {
                        Text(event.timestamp, style: .date)
                        Text(event.timestamp, style: .time)
                    }
                    LabeledContent("Event ID", value: event.id.uuidString.prefix(8) + "...")
                    LabeledContent("Session ID", value: event.sessionID.uuidString.prefix(8) + "...")
                }

                Section("User Info") {
                    if let userID = event.userID {
                        LabeledContent("User ID", value: userID)
                    } else {
                        LabeledContent("User ID", value: "Anonymous")
                    }
                    LabeledContent("Anonymous ID", value: event.anonymousID.prefix(8) + "...")
                }

                if event.screenName != nil || event.previousScreenName != nil {
                    Section("Navigation") {
                        if let screen = event.screenName {
                            LabeledContent("Screen", value: screen)
                        }
                        if let prev = event.previousScreenName {
                            LabeledContent("Previous Screen", value: prev)
                        }
                        if let duration = event.duration {
                            LabeledContent("Duration", value: String(format: "%.1fs", duration))
                        }
                    }
                }

                Section("Device Info") {
                    LabeledContent("Model", value: event.deviceInfo.model)
                    LabeledContent("OS Version", value: event.deviceInfo.osVersion)
                    LabeledContent("App Version", value: event.deviceInfo.appVersion)
                    LabeledContent("Build", value: event.deviceInfo.buildNumber)
                    LabeledContent("Locale", value: event.deviceInfo.locale)
                    LabeledContent("Timezone", value: event.deviceInfo.timezone)
                    LabeledContent("Network", value: event.deviceInfo.networkType.rawValue.capitalized)
                    LabeledContent("Low Power", value: event.deviceInfo.isLowPowerMode ? "Yes" : "No")
                }

                if !event.properties.isEmpty {
                    Section("Properties") {
                        ForEach(Array(event.properties.keys.sorted()), id: \.self) { key in
                            if let value = event.properties[key] {
                                LabeledContent(key, value: "\(value.value)")
                            }
                        }
                    }
                }

                if let errorInfo = event.errorInfo {
                    Section("Error Info") {
                        LabeledContent("Domain", value: errorInfo.domain)
                        LabeledContent("Code", value: "\(errorInfo.code)")
                        LabeledContent("Message", value: errorInfo.message)
                        LabeledContent("Fatal", value: errorInfo.isFatal ? "Yes" : "No")
                        if let stack = errorInfo.stackTrace {
                            #if os(watchOS) || os(tvOS)
                            // DisclosureGroup not available on watchOS/tvOS
                            Text("Stack Trace: \(stack.prefix(100))...")
                                .font(.caption.monospaced())
                            #else
                            DisclosureGroup("Stack Trace") {
                                Text(stack)
                                    .font(.caption.monospaced())
                            }
                            #endif
                        }
                    }
                }

                if event.latitude != nil || event.longitude != nil {
                    Section("Location") {
                        if let lat = event.latitude {
                            LabeledContent("Latitude", value: String(format: "%.6f", lat))
                        }
                        if let lon = event.longitude {
                            LabeledContent("Longitude", value: String(format: "%.6f", lon))
                        }
                    }
                }
            }
            .navigationTitle("Event Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
#Preview {
    NavigationStack {
        AnalyticsDebugView()
    }
}
#endif
