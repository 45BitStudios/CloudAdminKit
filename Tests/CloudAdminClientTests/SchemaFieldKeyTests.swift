import CloudKit
import Foundation
import Testing
@testable import CloudAdminClient

/// Fails if a `FieldKey` raw value (or a write helper) emits a CloudKit field
/// that `Schema/client-schema.ckdb` does not declare for that record type.
@Suite struct SchemaFieldKeyTests {
    private func schemaText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Schema/client-schema.ckdb")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func declaredFields(recordType: String, in schema: String) throws -> Set<String> {
        let marker = "RECORD TYPE \(recordType) ("
        guard let start = schema.range(of: marker) else {
            Issue.record("Missing RECORD TYPE \(recordType) in client-schema.ckdb")
            return []
        }
        let rest = schema[start.upperBound...]
        guard let end = rest.range(of: ");") else {
            Issue.record("Unterminated RECORD TYPE \(recordType)")
            return []
        }
        let body = rest[..<end.lowerBound]
        var fields = Set<String>()
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("GRANT"), !line.hasPrefix("\"___") else { continue }
            let name = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            if let name {
                fields.insert(name)
            }
        }
        return fields
    }

    @Test func featureRequestFieldKeysMatchSchema() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "FeatureRequest", in: schema)
        for key in FeatureRequest.FieldKey.allCases {
            #expect(declared.contains(key.rawValue), "FeatureRequest.\(key) is not in client-schema.ckdb")
        }
    }

    @Test func analyticsEventFieldKeysMatchSchema() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "AnalyticsEvent", in: schema)
        for key in AnalyticsEvent.FieldKey.allCases {
            #expect(declared.contains(key.rawValue), "AnalyticsEvent.\(key) is not in client-schema.ckdb")
        }
    }

    @Test func featureFlagFieldKeysMatchSchema() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "FeatureFlag", in: schema)
        for key in FeatureFlag.FieldKey.allCases {
            #expect(declared.contains(key.rawValue), "FeatureFlag.\(key) is not in client-schema.ckdb")
        }
    }

    @Test func remoteSettingFieldKeysMatchSchema() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "RemoteSetting", in: schema)
        for key in RemoteSetting.FieldKey.allCases {
            #expect(declared.contains(key.rawValue), "RemoteSetting.\(key) is not in client-schema.ckdb")
        }
    }

    @Test func featureRequestWriteEmitsOnlyDeclaredFields() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "FeatureRequest", in: schema)
        let request = FeatureRequest(
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
            tags: ["ui"],
            contactEmail: "a@b.com",
            votes: 42,
            isPublic: true
        )
        let record = try request.toCKRecord()
        for key in record.allKeys() {
            #expect(declared.contains(key), "toCKRecord wrote undeclared field \(key)")
        }
        #expect(record["id"] == nil)
    }

    @Test func analyticsEventWriteEmitsOnlyDeclaredFields() throws {
        let schema = try schemaText()
        let declared = try declaredFields(recordType: "AnalyticsEvent", in: schema)
        let event = AnalyticsEvent(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            userID: "user-1",
            anonymousID: "anon-1",
            eventType: .screenView,
            eventName: "Home",
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            deviceInfo: DeviceInfo(
                model: "iPhone15,2",
                osVersion: "26.0",
                appVersion: "1.0.0",
                buildNumber: "1",
                locale: "en_US",
                timezone: "America/Chicago",
                screenScale: 3,
                isLowPowerMode: false,
                networkType: .wifi
            ),
            screenName: "Home"
        )
        let record = event.toRecord()
        for key in record.allKeys() {
            #expect(declared.contains(key), "toRecord wrote undeclared field \(key)")
        }
        #expect(record["id"] == nil)

        let restored = try #require(AnalyticsEvent(from: record))
        #expect(restored.id == event.id)
    }
}
