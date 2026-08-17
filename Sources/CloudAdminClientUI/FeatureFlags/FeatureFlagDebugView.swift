//
//  FeatureFlagDebugView.swift
//  CloudAdminClientUI
//
//  Debug UI for viewing and overriding feature flags
//

import CloudAdminClient
import SwiftUI

/// Debug view for inspecting and overriding feature flags
///
/// This view displays all feature flags and their current states,
/// and allows developers to override flags for testing purposes.
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     FeatureFlagDebugView()
/// }
/// ```
///
/// ## Features
/// - View all flags and their states
/// - See flag metadata (platforms, versions, payloads)
/// - Override flags locally (debug builds only)
/// - Refresh flags from CloudKit
/// - Clear local cache
/// A debug screen listing feature flags with their effective state, and (in `DEBUG` builds)
/// local overrides for testing. Drop into a developer settings menu; not for release UI.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct FeatureFlagDebugView: View {
    @Environment(\.featureFlagObserver) private var observer
    @State private var flags: [FeatureFlag] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showOnlyEnabled = false
    @State private var showOnlyApplicable = true

    #if DEBUG
    @State private var overrides: [String: Bool] = [:]
    #endif

    public init() {}

    public var body: some View {
        List {
            statusSection

            if !filteredFlags.isEmpty {
                flagsSection
            } else if !isLoading {
                emptyStateSection
            }
        }
        #if !os(watchOS)
        .searchable(text: $searchText, prompt: "Search flags")
        #endif
        .navigationTitle("Feature Flags")
        #if !os(watchOS)
        .toolbar {
            toolbarContent
        }
        .refreshable {
            await refreshFlags()
        }
        #endif
        .task {
            await loadFlags()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Label("Total Flags", systemImage: "flag.fill")
                Spacer()
                Text("\(flags.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                Spacer()
                Text("\(flags.filter { $0.isEnabled }.count)")
                    .foregroundStyle(.green)
            }

            HStack {
                Label("Applicable", systemImage: "target")
                Spacer()
                Text("\(flags.filter { $0.isApplicableToCurrentPlatform }.count)")
                    .foregroundStyle(.secondary)
            }

            if let lastRefresh = observer?.lastRefresh {
                HStack {
                    Label("Last Refresh", systemImage: "clock")
                    Spacer()
                    Text(lastRefresh, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
            if !overrides.isEmpty {
                HStack {
                    Label("Local Overrides", systemImage: "wrench.fill")
                    Spacer()
                    Text("\(overrides.count)")
                        .foregroundStyle(.orange)
                }
            }
            #endif
        } header: {
            Text("Status")
        }
    }

    private var flagsSection: some View {
        Section {
            ForEach(filteredFlags) { flag in
                FlagRowView(
                    flag: flag,
                    isOverridden: isOverridden(flag.key),
                    overrideValue: overrideValue(for: flag.key),
                    onToggleOverride: { toggleOverride(flag) }
                )
            }
        } header: {
            #if os(watchOS)
            Text("Flags")
            #else
            HStack {
                Text("Flags")
                Spacer()
                filterMenu
            }
            #endif
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView(
                "No Flags Found",
                systemImage: "flag.slash",
                description: Text(searchText.isEmpty ? "No feature flags configured" : "No flags match your search")
            )
        }
    }

    #if !os(watchOS)
    private var filterMenu: some View {
        Menu {
            Toggle("Enabled Only", isOn: $showOnlyEnabled)
            Toggle("Applicable Only", isOn: $showOnlyApplicable)

            Divider()

            #if DEBUG
            if !overrides.isEmpty {
                Button(role: .destructive) {
                    clearOverrides()
                } label: {
                    Label("Clear Overrides", systemImage: "xmark.circle")
                }
            }
            #endif
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(hasActiveFilters ? .blue : .secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await refreshFlags() }
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

        #if DEBUG && !os(tvOS)
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button {
                    clearCache()
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                }

                Button {
                    clearOverrides()
                } label: {
                    Label("Clear Overrides", systemImage: "xmark.circle")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
        }
        #endif
    }
    #endif  // !os(watchOS)

    // MARK: - Computed Properties

    private var filteredFlags: [FeatureFlag] {
        var result = flags

        if showOnlyEnabled {
            result = result.filter { $0.isEnabled }
        }

        if showOnlyApplicable {
            result = result.filter { $0.isApplicableToCurrentPlatform }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.key.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result.sorted { $0.key < $1.key }
    }

    private var hasActiveFilters: Bool {
        showOnlyEnabled || !showOnlyApplicable || !searchText.isEmpty
    }

    // MARK: - Methods

    private func loadFlags() async {
        guard let service = FeatureFlagService.shared else { return }

        isLoading = true
        flags = await service.allFlags

        #if DEBUG
        for key in await service.overrides.keys {
            overrides[key] = await service.overrides[key]
        }
        #endif

        isLoading = false
    }

    private func refreshFlags() async {
        guard let service = FeatureFlagService.shared else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await service.fetchFlags(forceRefresh: true)
            flags = await service.allFlags
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func isOverridden(_ key: String) -> Bool {
        #if DEBUG
        return overrides[key] != nil
        #else
        return false
        #endif
    }

    private func overrideValue(for key: String) -> Bool? {
        #if DEBUG
        return overrides[key]
        #else
        return nil
        #endif
    }

    private func toggleOverride(_ flag: FeatureFlag) {
        #if DEBUG
        Task {
            guard let service = FeatureFlagService.shared else { return }

            if overrides[flag.key] != nil {
                await service.setOverride(flag.key, value: nil)
                overrides.removeValue(forKey: flag.key)
                await observer?.setOverride(flag.key, value: nil)
            } else {
                let newValue = !flag.isEnabled
                await service.setOverride(flag.key, value: newValue)
                overrides[flag.key] = newValue
                await observer?.setOverride(flag.key, value: newValue)
            }
        }
        #endif
    }

    private func clearOverrides() {
        #if DEBUG
        Task {
            guard let service = FeatureFlagService.shared else { return }
            await service.clearOverrides()
            overrides.removeAll()
            if let observer {
                for key in observer.flagStates.keys {
                    await observer.setOverride(key, value: nil)
                }
            }
        }
        #endif
    }

    private func clearCache() {
        Task {
            guard let service = FeatureFlagService.shared else { return }
            await service.clearCache()
            await refreshFlags()
        }
    }
}

// MARK: - Flag Row View

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct FlagRowView: View {
    let flag: FeatureFlag
    let isOverridden: Bool
    let overrideValue: Bool?
    let onToggleOverride: () -> Void

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
                HStack(spacing: 4) {
                    Text(flag.key)
                        .font(.headline)

                    if isOverridden {
                        Label("Overridden", systemImage: "wrench.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 4) {
                    ForEach(flag.platforms.platformStrings, id: \.self) { platform in
                        Text(platform)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }

                    if let version = flag.minVersion {
                        Text("v\(version)+")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            effectiveStateIndicator
        }
    }

    private var effectiveStateIndicator: some View {
        let effectiveValue = overrideValue ?? flag.isEnabled
        return Circle()
            .fill(effectiveValue ? Color.green : Color.red.opacity(0.5))
            .frame(width: 12, height: 12)
            .overlay {
                if isOverridden {
                    Circle()
                        .stroke(Color.orange, lineWidth: 2)
                }
            }
    }

    #if !os(watchOS)
    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("State", value: flag.isEnabled ? "Enabled" : "Disabled")
            detailRow("Applicable", value: flag.isApplicableToCurrentPlatform ? "Yes" : "No")
            detailRow("Modified", value: flag.modifiedDate.formatted())

            if let payload = flag.payload, !payload.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Payload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(payload)
                        .font(.caption.monospaced())
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            #if DEBUG
            Divider()

            Button {
                onToggleOverride()
            } label: {
                Label(
                    isOverridden ? "Remove Override" : "Add Override",
                    systemImage: isOverridden ? "xmark.circle" : "wrench"
                )
            }
            .buttonStyle(.bordered)
            .tint(isOverridden ? .orange : .blue)
            #endif
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
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
#Preview {
    NavigationStack {
        FeatureFlagDebugView()
    }
}
#endif
