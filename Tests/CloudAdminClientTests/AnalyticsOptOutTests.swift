import Foundation
import Testing
@testable import CloudAdminClient

@Suite(.serialized)
struct AnalyticsOptOutTests {
    private func makeService() -> AnalyticsService {
        UserDefaults.standard.removeObject(forKey: AnalyticsService.optOutStorageKey)
        return AnalyticsService(configuration: AnalyticsConfiguration(
            containerIdentifier: "iCloud.test.analytics.\(UUID().uuidString)",
            batchSize: 10_000,
            batchInterval: 3600,
            isEnabled: true
        ))
    }

    private func teardown(_ service: AnalyticsService) async {
        await service.clearQueue()
        await service.optIn()
        UserDefaults.standard.removeObject(forKey: AnalyticsService.optOutStorageKey)
    }

    @Test func optOutStopsEnqueueAndClearsQueue() async {
        let service = makeService()
        await Task.yield()
        await service.clearQueue()
        await service.trackScreen("Home")
        await service.trackCustom("ping")
        #expect(await service.queueSize >= 1)

        await service.optOut()
        #expect(await service.isOptedOut)
        #expect(await service.isEnabled == false)
        #expect(await service.queueSize == 0)

        await service.trackScreen("Home")
        await service.trackCustom("still_off")
        await service.trackButtonTap("x")
        #expect(await service.queueSize == 0)
        await teardown(service)
    }

    @Test func optOutSurvivesNewInstance() async {
        let first = makeService()
        await first.optOut()

        let second = AnalyticsService(configuration: AnalyticsConfiguration(
            containerIdentifier: "iCloud.test.analytics.\(UUID().uuidString)",
            batchSize: 10_000,
            batchInterval: 3600,
            isEnabled: true
        ))
        await second.trackScreen("Home")
        #expect(await second.isOptedOut)
        #expect(await second.queueSize == 0)
        await teardown(second)
    }

    @Test func optInResumesTracking() async {
        let service = makeService()
        await service.optOut()
        await service.trackCustom("skipped")
        #expect(await service.queueSize == 0)

        await service.optIn()
        #expect(await service.isOptedOut == false)
        #expect(await service.isEnabled)
        await service.trackCustom("accepted")
        #expect(await service.queueSize >= 1)
        await teardown(service)
    }

    @Test func purgeUserDataStillClearsQueueAfterOptOut() async throws {
        let service = makeService()
        await service.trackScreen("Home")
        await service.optOut()
        try await service.purgeUserData()
        #expect(await service.queueSize == 0)
        await teardown(service)
    }
}
