// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import Foundation
import Observation
import Security

private struct HAConnection: Codable {
    var url: URL
    var device_id: String
    var credential: String
    var receipts: [HomeAssistantReceipt] = []
}

@MainActor @Observable private final class HACredentialVault: HomeAssistantJournal {
    private(set) var connection: HAConnection?
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.agawlbb.alarmbeans.homeassistant",
         kSecAttrAccount as String: "device"]
    }
    init() { try? reload() }
    func reload() throws {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { connection = nil; return }
        guard status == errSecSuccess, let data = result as? Data else { throw AlarmError.message("Keychain unavailable.") }
        connection = try JSONDecoder().decode(HAConnection.self, from: data)
    }
    func store(_ value: HAConnection) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = query
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AlarmError.message("Could not save pairing in Keychain.") }
        } else if status != errSecSuccess { throw AlarmError.message("Could not save pairing in Keychain.") }
        connection = value
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AlarmError.message("Could not remove pairing.") }
        connection = nil
    }
    var receipts: [HomeAssistantReceipt] { connection?.receipts ?? [] }
    func save(_ receipts: [HomeAssistantReceipt]) throws {
        guard var connection else { throw AlarmError.unavailable }
        connection.receipts = receipts
        try store(connection)
    }
}

private final class HANetwork: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // Never forward a pairing token or bearer credential through a redirect.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func post(url: URL, data: Data, credential: String? = nil) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credential { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        let (body, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, body.count <= 65536 else {
            throw AlarmError.message("Home Assistant unavailable or pairing revoked.")
        }
        return body
    }
}

@MainActor private final class HAHTTPTransport: HomeAssistantTransport {
    let connection: HAConnection
    init(_ connection: HAConnection) { self.connection = connection }
    func exchange(_ report: HomeAssistantReport) async throws -> [HomeAssistantRequest] {
        struct Reply: Decodable { let requests: [HomeAssistantRequest] }
        let url = connection.url.appendingPathComponent("api/alarm_beans/device/\(connection.device_id)/sync")
        let body = try await HANetwork().post(url: url, data: JSONEncoder().encode(report), credential: connection.credential)
        return try JSONDecoder().decode(Reply.self, from: body).requests
    }
}

@MainActor private final class HASessionJournal: HomeAssistantJournal {
    let vault: HACredentialVault
    let credential: String
    init(vault: HACredentialVault, credential: String) { self.vault = vault; self.credential = credential }
    var receipts: [HomeAssistantReceipt] { vault.connection?.credential == credential ? vault.receipts : [] }
    func save(_ receipts: [HomeAssistantReceipt]) throws {
        guard vault.connection?.credential == credential else { throw AlarmError.message("Pairing changed during synchronization.") }
        try vault.save(receipts)
    }
}

@MainActor @Observable final class HomeAssistantBridge {
    private let coordinator: PairCoordinator
    private let vault = HACredentialVault()
    private var syncing = false
    private var syncAgain = false
    var message: String?
    var paired: Bool { vault.connection != nil }
    var host: String { vault.connection?.url.host ?? "" }
    init(coordinator: PairCoordinator) { self.coordinator = coordinator }

    func pair(_ pairing: HomeAssistantPairing) async throws {
        try pairing.validate()
        struct Reply: Decodable { let device_id: String; let credential: String }
        let body = try await HANetwork().post(url: pairing.url.appendingPathComponent("api/alarm_beans/pair"),
                                              data: JSONEncoder().encode(["token": pairing.token]))
        let reply = try JSONDecoder().decode(Reply.self, from: body)
        guard UUID(uuidString: reply.device_id) != nil, (32...128).contains(reply.credential.count),
              reply.credential.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw AlarmError.unavailable }
        try vault.store(HAConnection(url: pairing.url, device_id: reply.device_id, credential: reply.credential))
        await synchronize()
    }

    func synchronize() async {
        if syncing { syncAgain = true; return }
        syncing = true
        defer {
            syncing = false
            if syncAgain {
                syncAgain = false
                Task { await self.synchronize() }
            }
        }
        do {
            try vault.reload()
            guard let connection = vault.connection else { return }
            // Fetch the current Watch epoch before attempting an external edit.
            await coordinator.synchronize()
            try await HomeAssistantSync(coordinator: coordinator, transport: HAHTTPTransport(connection),
                                       journal: HASessionJournal(vault: vault, credential: connection.credential)).synchronize()
            message = nil
        } catch { message = "Could not sync. Open both apps and try again." }
    }

    func disconnect() async throws {
        guard let connection = vault.connection else { return }
        _ = try await HANetwork().post(url: connection.url.appendingPathComponent("api/alarm_beans/device/\(connection.device_id)/revoke"),
                                       data: Data("{}".utf8), credential: connection.credential)
        try vault.remove()
        message = nil
    }
}
