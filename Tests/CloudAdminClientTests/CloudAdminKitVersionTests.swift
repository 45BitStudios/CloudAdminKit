import Testing
@testable import CloudAdminClient

@Suite("CloudAdminKitVersion")
struct CloudAdminKitVersionTests {
    @Test("Advertised SPM pin stays 1.0.0")
    func advertisedPinIsOneOh() {
        #expect(CloudAdminKitVersion.current == "1.0.0")
    }
}
