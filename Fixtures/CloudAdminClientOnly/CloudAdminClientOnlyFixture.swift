import CloudAdminClient

/// Watch / tv companion fixture: links **only** `CloudAdminClient` (no UI, no push).
/// Proves the core SDK compiles on every platform Package.swift claims.
public enum CloudAdminClientOnlyFixture: Sendable {
    public static func touch() {
        _ = FeatureFlagConfiguration(containerIdentifier: "iCloud.test.fixture")
        _ = RemoteSettingsConfiguration(containerIdentifier: "iCloud.test.fixture")
        _ = AnalyticsConfiguration(containerIdentifier: "iCloud.test.fixture")
        _ = CloudAdminKitVersion.current
    }
}
