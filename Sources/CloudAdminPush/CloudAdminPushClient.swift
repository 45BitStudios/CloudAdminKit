//
//  CloudAdminPushClient.swift
//  CloudAdminPush
//
//  Thin HTTP client for a CloudAdmin server's push + Live Activity APIs.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors raised by ``CloudAdminPushClient``.
public enum CloudAdminPushError: Error, Sendable, LocalizedError {
    case invalidURL
    case httpStatus(Int, String?)
    case decoding(Error)
    case encoding(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL"
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body ?? "")"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encoding(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        }
    }
}

/// Target for ``CloudAdminPushClient/send(title:body:subtitle:badge:to:)``.
public enum PushTarget: Sendable, Encodable {
    case user(String)
    case device(String)
    case token(String)

    private enum CodingKeys: String, CodingKey {
        case userId, deviceId, deviceToken
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let id):
            try container.encode(id, forKey: .userId)
        case .device(let id):
            try container.encode(id, forKey: .deviceId)
        case .token(let token):
            try container.encode(token, forKey: .deviceToken)
        }
    }
}

/// HTTP client for a CloudAdmin server's push notifications and Live Activities.
///
/// Configure once per app and call register / send helpers. The server holds APNs
/// keys and CloudKit token storage; this client never talks to APNs directly.
public struct CloudAdminPushClient: Sendable {
    public let baseURL: URL
    public let appId: String
    public let apiKey: String
    public let deviceId: String
    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - baseURL: Server root, e.g. `https://your-cloudadmin-server.example.com`.
    ///   - appId: App identifier (`yourapp`, `empressblood`, …).
    ///   - apiKey: Shared API key (`API_KEY` / `X-API-Key`).
    ///   - deviceId: Stable per-install id (store in Keychain).
    ///   - session: URL session to use.
    public init(
        baseURL: URL,
        appId: String,
        apiKey: String,
        deviceId: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.appId = appId
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.session = session
    }

    // MARK: - Registration

    /// Registers or refreshes this device's APNs push token.
    public func registerDevice(token: Data, userId: String? = nil, environment: String? = nil) async throws {
        let body: [String: String?] = [
            "deviceId": deviceId,
            "pushToken": token.pushHexString,
            "userId": userId,
            "environment": environment
        ]
        try await put(path: "devices/\(deviceId)", body: body.compactMapValues { $0 })
    }

    /// Registers a Live Activity push-to-start token for an attributes type.
    public func registerPushToStartToken(_ token: Data, attributesType: String) async throws {
        let body: [String: String] = [
            "deviceId": deviceId,
            "attributesType": attributesType,
            "pushToStartToken": token.pushHexString
        ]
        try await put(
            path: "devices/\(deviceId)/liveactivity/start-tokens/\(attributesType)",
            body: body
        )
    }

    /// Registers an update token for an active Live Activity instance.
    ///
    /// - Parameters:
    ///   - id: The iOS `Activity.id`.
    ///   - updateToken: The activity's `pushToken` from `activity.pushTokenUpdates`.
    ///   - attributesType: The `ActivityAttributes` type name (e.g. `"BuildActivityAttributes"`).
    ///   - correlationId: An optional business key (e.g. a build id) shared across every device
    ///     running the same logical activity. Pass the value the server put in the activity's
    ///     `attributes` (for a **push-started** activity, read it back off `attributes`) so the
    ///     server can later drive update/end by correlation via ``updateLiveActivity(correlationId:contentState:)``
    ///     and ``endLiveActivity(correlationId:finalState:)``.
    public func registerLiveActivity(
        id: String,
        updateToken: Data,
        attributesType: String,
        correlationId: String? = nil
    ) async throws {
        var body: [String: String] = [
            "deviceId": deviceId,
            "activityId": id,
            "attributesType": attributesType,
            "updateToken": updateToken.pushHexString
        ]
        if let correlationId, !correlationId.isEmpty {
            body["correlationId"] = correlationId
        }
        try await put(path: "devices/\(deviceId)/liveactivities/\(id)", body: body)
    }

    /// Removes a Live Activity instance registration after it ends locally.
    public func unregisterLiveActivity(id: String) async throws {
        try await delete(path: "devices/\(deviceId)/liveactivities/\(id)")
    }

    // MARK: - Send

    /// Sends an alert push to a user, device, or raw token (webhook-friendly).
    public func send(
        title: String,
        body: String,
        subtitle: String? = nil,
        badge: Int? = nil,
        to target: PushTarget
    ) async throws {
        struct NotifyBody: Encodable {
            let title: String
            let body: String
            let subtitle: String?
            let badge: Int?
            let to: PushTarget
        }
        try await post(
            path: "push/notify",
            body: NotifyBody(title: title, body: body, subtitle: subtitle, badge: badge, to: target)
        )
    }

    /// Low-level send by hex device token (debug).
    public func send(toDeviceToken deviceToken: String, title: String, body: String) async throws {
        struct SendBody: Encodable {
            let deviceToken: String
            let title: String
            let body: String
        }
        try await post(
            path: "push/send",
            body: SendBody(deviceToken: deviceToken, title: title, body: body)
        )
    }

    /// Updates a personal Live Activity by application activity id.
    public func updateLiveActivity(id: String, contentState: some Encodable & Sendable) async throws {
        try await post(
            path: "push/liveactivity/update-by-id",
            body: LiveActivityUpdateBody(activityId: id, contentState: contentState)
        )
    }

    /// Ends a personal Live Activity by application activity id.
    public func endLiveActivity(id: String) async throws {
        struct Body: Encodable {
            let activityId: String
        }
        try await post(
            path: "push/liveactivity/end-by-id",
            body: Body(activityId: id)
        )
    }

    /// Ends a personal Live Activity with a final content state.
    public func endLiveActivity(id: String, finalState: some Encodable & Sendable) async throws {
        try await post(
            path: "push/liveactivity/end-by-id",
            body: LiveActivityEndBody(activityId: id, finalContentState: finalState)
        )
    }

    // MARK: - Correlation-keyed fan-out

    /// Starts a Live Activity on **every** device registered to a user.
    ///
    /// The server injects `correlationId` into `attributes`; each device echoes it back when it
    /// registers its update token (pass the same value to ``registerLiveActivity(id:updateToken:attributesType:correlationId:)``),
    /// so `updateLiveActivity(correlationId:...)` / `endLiveActivity(correlationId:...)` can fan out
    /// to all of them. Useful when one logical activity (e.g. a build) should appear on a developer's
    /// iPhone, iPad, and Mac at once.
    public func startLiveActivityByUser(
        userId: String,
        attributesType: String,
        attributes: some Encodable & Sendable,
        contentState: some Encodable & Sendable,
        correlationId: String? = nil
    ) async throws {
        try await post(
            path: "push/liveactivity/start-by-user",
            body: StartByUserBody(
                userId: userId,
                attributesType: attributesType,
                attributes: attributes,
                contentState: contentState,
                correlationId: correlationId
            )
        )
    }

    /// Updates **every** active Live Activity sharing a `correlationId` (all of a user's devices).
    public func updateLiveActivity(
        correlationId: String,
        contentState: some Encodable & Sendable
    ) async throws {
        try await post(
            path: "push/liveactivity/update-by-correlation",
            body: UpdateByCorrelationBody(correlationId: correlationId, contentState: contentState)
        )
    }

    /// Ends **every** active Live Activity sharing a `correlationId`.
    public func endLiveActivity(correlationId: String) async throws {
        try await post(
            path: "push/liveactivity/end-by-correlation",
            body: EndByCorrelationBody(correlationId: correlationId)
        )
    }

    /// Ends **every** active Live Activity sharing a `correlationId`, with a final content state.
    public func endLiveActivity(
        correlationId: String,
        finalState: some Encodable & Sendable
    ) async throws {
        try await post(
            path: "push/liveactivity/end-by-correlation",
            body: EndByCorrelationStateBody(correlationId: correlationId, finalContentState: finalState)
        )
    }

    // MARK: - Broadcast channels (iOS 18+)

    /// Creates an Apple Broadcast Live Activity channel for an event and returns its channel id.
    @discardableResult
    public func createChannel(
        eventId: String,
        attributesType: String,
        messageStoragePolicy: Int = 0
    ) async throws -> String {
        struct Body: Encodable {
            let eventId: String
            let attributesType: String
            let messageStoragePolicy: Int
        }
        struct Response: Decodable {
            let channelId: String
        }
        let response: Response = try await postJSON(
            path: "push/channels",
            body: Body(
                eventId: eventId,
                attributesType: attributesType,
                messageStoragePolicy: messageStoragePolicy
            )
        )
        return response.channelId
    }

    /// Fetches the APNs channel id previously stored for an event.
    public func channelId(for eventId: String) async throws -> String {
        struct Response: Decodable {
            let channelId: String
        }
        let response: Response = try await getJSON(path: "push/channels/\(eventId)")
        return response.channelId
    }

    /// Publishes a Live Activity update to everyone subscribed to the event's channel.
    public func send(toChannel eventId: String, contentState: some Encodable & Sendable) async throws {
        try await post(
            path: "push/channels/\(eventId)/update",
            body: ChannelEventBody(contentState: contentState, event: "update")
        )
    }

    /// Ends Live Activities on the event's channel, then deletes the APNs channel.
    public func endChannel(_ eventId: String, finalState: some Encodable & Sendable) async throws {
        try await post(
            path: "push/channels/\(eventId)/end",
            body: ChannelEventBody(contentState: finalState, event: "end")
        )
    }

    /// Force-deletes the APNs channel mapping without sending an end event.
    public func deleteChannel(_ eventId: String) async throws {
        try await delete(path: "push/channels/\(eventId)")
    }

    // MARK: - HTTP

    private func put(path: String, body: some Encodable) async throws {
        try await request(method: "PUT", path: path, body: body)
    }

    private func post(path: String, body: some Encodable) async throws {
        try await request(method: "POST", path: path, body: body)
    }

    private func postJSON<Response: Decodable>(path: String, body: some Encodable) async throws -> Response {
        let data = try await requestData(method: "POST", path: path, body: body)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CloudAdminPushError.decoding(error)
        }
    }

    private func getJSON<Response: Decodable>(path: String) async throws -> Response {
        let data = try await requestData(method: "GET", path: path, body: Optional<EmptyBody>.none)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CloudAdminPushError.decoding(error)
        }
    }

    private func delete(path: String) async throws {
        try await request(method: "DELETE", path: path, body: Optional<EmptyBody>.none)
    }

    private func request(method: String, path: String, body: (some Encodable)?) async throws {
        _ = try await requestData(method: method, path: path, body: body)
    }

    @discardableResult
    private func requestData(method: String, path: String, body: (some Encodable)?) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CloudAdminPushError.invalidURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = [basePath, "api", "v1", appId]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
            + "/"
            + path
        components.path = "/" + fullPath
        guard let url = components.url else {
            throw CloudAdminPushError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw CloudAdminPushError.encoding(error)
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAdminPushError.httpStatus(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudAdminPushError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return data
    }
}

// Request bodies for the generic Live Activity endpoints. Declared at file scope
// because Swift does not allow a generic type to be nested inside a generic function
// (which these opaque-parameter methods effectively are).
private struct LiveActivityUpdateBody<State: Encodable>: Encodable {
    let activityId: String
    let contentState: State
}

private struct LiveActivityEndBody<State: Encodable>: Encodable {
    let activityId: String
    let finalContentState: State
}

private struct ChannelEventBody<State: Encodable>: Encodable {
    let contentState: State
    let event: String
}

/// Empty placeholder for optional encode bodies.
struct EmptyBody: Encodable, Sendable {}

// MARK: - Correlation request bodies
//
// Declared at file scope (not nested in the generic client methods) so they compile under
// strict Swift 6 language mode, which disallows generic types nested in generic functions.

private struct StartByUserBody<A: Encodable, S: Encodable>: Encodable {
    let userId: String
    let attributesType: String
    let attributes: A
    let contentState: S
    let correlationId: String?
}

private struct UpdateByCorrelationBody<State: Encodable>: Encodable {
    let correlationId: String
    let contentState: State
}

private struct EndByCorrelationBody: Encodable {
    let correlationId: String
}

private struct EndByCorrelationStateBody<State: Encodable>: Encodable {
    let correlationId: String
    let finalContentState: State
}

private extension Data {
    var pushHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
