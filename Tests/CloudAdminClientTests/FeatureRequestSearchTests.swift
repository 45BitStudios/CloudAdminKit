import Foundation
import Testing
@testable import CloudAdminClient

@Suite struct FeatureRequestSearchTests {
    private func request(title: String, description: String, isPublic: Bool = true) -> FeatureRequest {
        FeatureRequest(
            id: UUID().uuidString,
            recordID: UUID().uuidString,
            title: title,
            description: description,
            priority: .medium,
            status: .submitted,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            category: .functionality,
            isPublic: isPublic
        )
    }

    @Test func emptyAndWhitespaceQueriesDoNotProduceAPredicateHit() {
        #expect(FeatureRequestService.normalizedSearchQuery("") == nil)
        #expect(FeatureRequestService.normalizedSearchQuery("   ") == nil)
        #expect(FeatureRequestService.normalizedSearchQuery("\n\t") == nil)
        #expect(FeatureRequestService.normalizedSearchQuery("dark") == "dark")
    }

    @Test func candidatePredicateDoesNotTouchDescription() {
        let format = FeatureRequestService.searchCandidatePredicate().predicateFormat
        #expect(!format.localizedCaseInsensitiveContains("description"))
        #expect(format.localizedCaseInsensitiveContains("isPublic"))
    }

    @Test func titleSubstringMatches() {
        let request = request(title: "Dark mode", description: "Please add a theme toggle.")
        #expect(FeatureRequestService.matchesSearch(request, query: "dark"))
        #expect(FeatureRequestService.matchesSearch(request, query: "MODE"))
        #expect(!FeatureRequestService.matchesSearch(request, query: "widget"))
    }

    @Test func descriptionSubstringMatches() {
        let request = request(title: "Settings", description: "Please add a dark theme.")
        #expect(FeatureRequestService.matchesSearch(request, query: "dark theme"))
        #expect(FeatureRequestService.matchesSearch(request, query: "THEME"))
    }
}
