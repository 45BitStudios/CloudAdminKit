import Foundation
import Testing

@Suite struct PrivacyManifestTests {
    private func manifest() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CloudAdminClient/PrivacyInfo.xcprivacy")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func declaresRequiredReasonAPIsTheClientUses() throws {
        let plist = try manifest()
        #expect(plist.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(plist.contains("CA92.1"))
        #expect(plist.contains("C56D.1"))
        #expect(plist.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        #expect(plist.contains("C617.1"))
    }

    @Test func doesNotDeclareTracking() throws {
        let plist = try manifest()
        #expect(plist.contains("<key>NSPrivacyTracking</key>"))
        #expect(plist.contains("<false/>"))
        #expect(!plist.contains("NSPrivacyAccessedAPICategoryLocation"))
        #expect(!plist.contains("NSPrivacyAccessedAPICategoryContacts"))
    }
}
