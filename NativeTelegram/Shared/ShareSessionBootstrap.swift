import Foundation

/// The iOS Share Extension signs into Telegram independently, using its own
/// sandbox and TDLib database. No App Group entitlement or container is needed.
struct ShareSessionConfiguration: Codable {
    let apiID: Int
    let apiHash: String
    let encryptionKey: String
}

enum ShareSessionError: LocalizedError {
    case missingAPICredentials

    var errorDescription: String? {
        switch self {
        case .missingAPICredentials:
            return "分享功能需要自己的 Telegram API ID 和 API Hash。首次使用時輸入一次，或請 OC 在分享延伸功能的 Info.plist 一起預置。"
        }
    }
}

enum ShareSessionBootstrap {
    static var root: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("AccessiGramShare", isDirectory: true)
    }

    static var databaseDirectory: URL {
        root.appendingPathComponent("tdlib", isDirectory: true)
    }

    static var filesDirectory: URL {
        root.appendingPathComponent("files", isDirectory: true)
    }

    static var configURL: URL {
        root.appendingPathComponent("telegram-config.json")
    }

    static func configuration() throws -> ShareSessionConfiguration {
        if FileManager.default.fileExists(atPath: configURL.path) {
            return try JSONDecoder().decode(
                ShareSessionConfiguration.self, from: Data(contentsOf: configURL)
            )
        }

        let info = Bundle.main.infoDictionary ?? [:]
        let idText = (info["TelegramAPIID"] as? String)
            ?? "\(info["TelegramAPIID"] as? Int ?? 0)"
        let hash = (info["TelegramAPIHash"] as? String) ?? ""
        guard let id = Int(idText), id > 0, !hash.isEmpty else {
            throw ShareSessionError.missingAPICredentials
        }
        return try saveCredentials(apiID: id, apiHash: hash)
    }

    @discardableResult
    static func saveCredentials(apiID: Int, apiHash: String) throws -> ShareSessionConfiguration {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
        let config = ShareSessionConfiguration(
            apiID: apiID, apiHash: apiHash, encryptionKey: key
        )
        let bytes = try JSONEncoder().encode(config)
        try bytes.write(to: configURL, options: .atomic)
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: configURL.path
        )
        return config
    }

    static func reset() throws {
        try FileManager.default.removeItem(at: root)
    }
}
