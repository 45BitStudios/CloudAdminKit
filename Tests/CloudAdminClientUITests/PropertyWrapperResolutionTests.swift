import CloudAdminClient
import CloudAdminClientUI
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PropertyWrapperResolutionTests {

    private func reset() {
        FeatureFlagService.shared = nil
        RemoteSettingsService.shared = nil
        FeatureFlagEvaluationCache.reset()
        RemoteSettingsEvaluationCache.reset()
    }

    @Test("FeatureEnabled falls back to wrapper default when the service is unconfigured")
    func featureEnabledUnconfiguredUsesDefault() {
        reset()
        #expect(FeatureEnabled.resolvedValue("new_paywall", default: true) == true)
        #expect(FeatureEnabled.resolvedValue("new_paywall", default: false) == false)
    }

    @Test("FeatureEnabled reads configure-time defaults without an observer")
    func featureEnabledConfiguredWithoutObserver() {
        reset()
        FeatureFlagService.configure(with: .init(
            containerIdentifier: "com.cloudadminkit.test.flags.\(UUID().uuidString)",
            defaultFlags: ["new_paywall": true]
        ))
        #expect(FeatureEnabled.resolvedValue("new_paywall", default: false) == true)
        #expect(FeatureEnabled.resolvedValue("missing_flag", default: true) == true)
        reset()
    }

    @Test("DEBUG override changes isEnabled and FeatureEnabled")
    func featureEnabledHonorsOverride() async {
        reset()
        let service = FeatureFlagService.configure(with: .init(
            containerIdentifier: "com.cloudadminkit.test.flags.\(UUID().uuidString)",
            defaultFlags: ["new_paywall": false]
        ))
        #expect(await service.isEnabled("new_paywall") == false)
        await service.setOverride("new_paywall", value: true)
        #expect(await service.isEnabled("new_paywall") == true)
        #expect(await service.isEnabledWithOverrides("new_paywall") == true)
        #expect(FeatureEnabled.resolvedValue("new_paywall", default: false) == true)
        reset()
    }

    @Test("FeatureEnabled prefers observer state when one is installed")
    func featureEnabledPrefersObserver() {
        reset()
        FeatureFlagService.configure(with: .init(
            containerIdentifier: "com.cloudadminkit.test.flags.\(UUID().uuidString)",
            defaultFlags: ["new_paywall": true]
        ))
        let observer = FeatureFlagObserver()
        // Observer has not refreshed, so its empty map should win over the cache.
        #expect(FeatureEnabled.resolvedValue("new_paywall", default: false, observer: observer) == false)
        reset()
    }

    @Test("Remote*Setting wrappers fall back to defaults when unconfigured")
    func remoteSettingsUnconfiguredUsesDefault() {
        reset()
        #expect(RemoteDoubleSetting.resolvedValue("apiTimeout", default: 30) == 30)
        #expect(RemoteStringSetting.resolvedValue("supportEmail", default: "help@app.com") == "help@app.com")
        #expect(RemoteBoolSetting.resolvedValue("maintenance", default: true) == true)
        #expect(RemoteIntSetting.resolvedValue("retries", default: 3) == 3)
        #expect(RemoteURLSetting.resolvedValue("home", default: URL(string: "https://example.com"))?.absoluteString == "https://example.com")
    }

    @Test("Remote*Setting wrappers read configure-time defaults without an observer")
    func remoteSettingsConfiguredWithoutObserver() {
        reset()
        RemoteSettingsService.configure(with: .init(
            containerIdentifier: "com.cloudadminkit.test.settings.\(UUID().uuidString)",
            defaults: [
                "apiTimeout": .double(42),
                "supportEmail": .string("ok@app.com"),
                "maintenance": .bool(true),
                "retries": .int(9),
                "home": .url(URL(string: "https://configured.example")!)
            ]
        ))
        #expect(RemoteDoubleSetting.resolvedValue("apiTimeout", default: 30) == 42)
        #expect(RemoteStringSetting.resolvedValue("supportEmail", default: "help@app.com") == "ok@app.com")
        #expect(RemoteBoolSetting.resolvedValue("maintenance", default: false) == true)
        #expect(RemoteIntSetting.resolvedValue("retries", default: 3) == 9)
        #expect(RemoteURLSetting.resolvedValue("home", default: URL(string: "https://example.com"))?.absoluteString == "https://configured.example")
        reset()
    }
}
