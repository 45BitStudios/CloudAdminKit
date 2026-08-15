import Foundation
import Testing
@testable import CloudAdminPush

@Suite("CloudAdminPush")
struct CloudAdminPushTests {
    @Test("PushTarget encodes to the server's expected JSON keys")
    func pushTargetEncoding() throws {
        func json(_ target: PushTarget) throws -> [String: String] {
            let data = try JSONEncoder().encode(target)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        }

        #expect(try json(.user("u1")) == ["userId": "u1"])
        #expect(try json(.device("d1")) == ["deviceId": "d1"])
        #expect(try json(.token("abc123")) == ["deviceToken": "abc123"])
    }
}
