//
//  RemoteSettingsDebugView.swift
//  CloudAdminClientUI
//
//  Debug UI for viewing remote settings
//

import CloudAdminClient
import SwiftUI

/// Debug view for inspecting remote settings
///
/// This view displays all remote settings and their current values,
/// organized by type for easy inspection.
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     RemoteSettingsDebugView()
/// }
/// ```
/// A debug screen listing remote settings with their current values, searchable and
/// filterable by type. Drop into a developer settings menu; not for release UI.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct RemoteSettingsDebugView: View {
    @Environment(\.remoteSettingsObserver) private var observer
    @State private var settings: [RemoteSetting] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var filterType: SettingValueType?

    public init() {}

    public var body: some View {
        List {
            statusSection

            if !filteredSettings.isEmpty {
                settingsSection
            } else if !isLoading {
                emptyStateSection
            }
        }
        #if !os(watchOS)
        .searchable(text: $searchText, prompt: "Search settings")
        .toolbar {
            toolbarContent
        }
        .refreshable {
            await refreshSettings()
        }
        #endif
        .navigationTitle("Remote Settings")
        .task {
            await loadSettings()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Label("Total Settings", systemImage: "gearshape.fill")
                Spacer()
                Text("\(settings.count)")
                    .foregroundStyle(.secondary)
            }

            ForEach(SettingValueType.allCases, id: \.self) { type in
                let count = settings.filter { $0.value.type == type }.count
                if count > 0 {
                    HStack {
                        Label(type.displayName, systemImage: iconForType(type))
                        Spacer()
                        Text("\(count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastRefresh = observer?.lastRefresh {
                HStack {
                    Label("Last Refresh", systemImage: "clock")
                    Spacer()
                    Text(lastRefresh, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var settingsSection: some View {
        Section {
            ForEach(filteredSettings) { setting in
                SettingRowView(setting: setting)
            }
        } header: {
            #if os(watchOS)
            Text("Settings")
            #else
            HStack {
                Text("Settings")
                Spacer()
                typeFilterMenu
            }
            #endif
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView(
                "No Settings Found",
                systemImage: "gearshape.slash",
                description: Text(searchText.isEmpty ? "No remote settings configured" : "No settings match your search")
            )
        }
    }

    #if !os(watchOS)
    private var typeFilterMenu: some View {
        Menu {
            Button {
                filterType = nil
            } label: {
                HStack {
                    Text("All Types")
                    if filterType == nil {
                        Spacer()
                        Label("Selected", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            Divider()

            ForEach(SettingValueType.allCases, id: \.self) { type in
                Button {
                    filterType = type
                } label: {
                    HStack {
                        Label(type.displayName, systemImage: iconForType(type))
                        if filterType == type {
                            Spacer()
                            Label("Selected", systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(filterType != nil ? .blue : .secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await refreshSettings() }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(isLoading)
        }

        #if !os(tvOS)
        ToolbarItem(placement: .secondaryAction) {
            Button {
                Task { await clearCache() }
            } label: {
                Label("Clear Cache", systemImage: "trash")
            }
        }
        #endif
    }
    #endif

    // MARK: - Computed Properties

    private var filteredSettings: [RemoteSetting] {
        var result = settings

        if let filterType = filterType {
            result = result.filter { $0.value.type == filterType }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.stringRepresentation.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result.sorted { $0.key < $1.key }
    }

    // MARK: - Methods

    private func loadSettings() async {
        guard let service = RemoteSettingsService.shared else { return }

        isLoading = true
        settings = await service.allSettings
        isLoading = false
    }

    private func refreshSettings() async {
        guard let service = RemoteSettingsService.shared else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await service.fetchSettings(forceRefresh: true)
            settings = await service.allSettings
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func clearCache() async {
        guard let service = RemoteSettingsService.shared else { return }
        await service.clearCache()
        await refreshSettings()
    }

    private func iconForType(_ type: SettingValueType) -> String {
        switch type {
        case .string: return "textformat"
        case .bool: return "switch.2"
        case .int: return "number"
        case .double: return "number.circle"
        case .url: return "link"
        }
    }
}

// MARK: - Setting Row View

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct SettingRowView: View {
    let setting: RemoteSetting

    @State private var isExpanded = false

    var body: some View {
        #if os(watchOS) || os(tvOS)
        // Simplified view for watchOS/tvOS without DisclosureGroup
        labelView
        #else
        DisclosureGroup(isExpanded: $isExpanded) {
            detailsView
        } label: {
            labelView
        }
        #endif
    }

    private var labelView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(setting.key)
                    .font(.headline)

                Text(setting.value.stringRepresentation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            typeIndicator
        }
    }

    private var typeIndicator: some View {
        Text(setting.value.type.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colorForType(setting.value.type).opacity(0.2), in: Capsule())
            .foregroundStyle(colorForType(setting.value.type))
    }

    #if !os(watchOS)
    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Type", value: setting.value.type.displayName)
            detailRow("Value", value: setting.value.stringRepresentation)
            detailRow("Modified", value: setting.modifiedDate.formatted())

            if let description = setting.settingDescription, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.caption)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            // Show copyable value for URLs
            if case .url(let url) = setting.value {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
    #endif

    private func colorForType(_ type: SettingValueType) -> Color {
        switch type {
        case .string: return .blue
        case .bool: return .green
        case .int: return .orange
        case .double: return .purple
        case .url: return .cyan
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
#Preview {
    NavigationStack {
        RemoteSettingsDebugView()
    }
}
#endif
