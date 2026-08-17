import CloudKit
import Foundation
import Testing
@testable import CloudAdminClient

/// Round-trips a `FeatureRequest` through its CloudKit conversion to prove the new
/// `FieldKey` enum maps to the same wire fields the old string literals used.
@Suite struct FeatureRequestRecordTests {
    private func sample() -> FeatureRequest {
        FeatureRequest(
            id: "req-1",
            recordID: "req-1",
            title: "Dark mode",
            description: "Please add a dark theme.",
            priority: .high,
            status: .reviewing,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_500),
            userID: "user-9",
            category: .userInterface,
            tags: ["ui", "theming"],
            contactEmail: "a@b.com",
            votes: 42,
            isPublic: true
        )
    }

    @Test func roundTripPreservesFields() throws {
        let original = sample()
        let record = try original.toCKRecord()
        let restored = try #require(try FeatureRequest.fromCKRecord(record))

        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.description == original.description)
        #expect(restored.priority == original.priority)
        #expect(restored.status == original.status)
        #expect(restored.category == original.category)
        #expect(restored.votes == original.votes)
        #expect(restored.isPublic == original.isPublic)
        #expect(restored.userID == original.userID)
        #expect(restored.contactEmail == original.contactEmail)
        #expect(restored.tags == original.tags)
    }

    @Test func fieldKeyRawValuesMatchWireSchema() {
        // These are the field names deployed clients read; they must never change.
        #expect(FeatureRequest.FieldKey.isPublic.rawValue == "isPublic")
        #expect(FeatureRequest.FieldKey.createdAt.rawValue == "createdAt")
        #expect(FeatureRequest.FieldKey.userID.rawValue == "userID")
        #expect(FeatureRequest.recordType == "FeatureRequest")
    }

    @Test func recordUsesFieldKeyNames() throws {
        let record = try sample().toCKRecord()
        #expect(record["title"] as? String == "Dark mode")
        #expect(record["votes"] as? Int == 42)
        #expect(record["isPublic"] as? Int == 1)
        #expect(record["id"] == nil)
    }

    @Test func fromCKRecordUsesRecordNameWhenIdFieldAbsent() throws {
        let record = try sample().toCKRecord()
        record["id"] = nil
        let restored = try #require(try FeatureRequest.fromCKRecord(record))
        #expect(restored.id == record.recordID.recordName)
    }
}
