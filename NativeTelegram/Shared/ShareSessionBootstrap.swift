import Foundation

/// Export a separate, encrypted TDLib database snapshot before the main
/// application's TDLib client starts. The Share Extension uses this private
/// copy, never the active main database, so it can send by itself.
///
/// The snapshot is made only once. The extension maintains its own TDLib data
/// after that. This uses the same Telegram authorization, not a bot account.
struct ShareSessionConfiguration: Codable {
    let apiID: Int
    let apiHash: String
    let encryptionKey: String
}

enum ShareSessionBootstrap {
    static var groupRoot: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareMailbox.appGroup
        )!
    }

    static var databaseDirectory: URL {
        groupRoot.appendingPathComponent("share-tdlib", isDirectory: true)
    }

    static var filesDirectory: URL {
        groupRoot.appendingPathComponent("share-files", isDirectory: true)
    }

    static var configURL: URL {
        groupRoot.appendingPathComponent("share-session.json")
    }

    static func configuration() throws -> ShareSessionConfiguration {
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(ShareSessionConfiguration.self, from: data)
    }

    static func prepareBeforeMainTDLibStarts(
        apiID: Int,
        apiHash: String,
        encryptionKey: String,
        mainDatabaseDirectory: URL
    ) throws {
        let manager = FileManager.default
        let root = groupRoot
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        // Never overwrite a database already used by Share Extension.
        guard !manager.fileExists(atPath: configURL.path) else { return }
        guard manager.fileExists(atPath: mainDatabaseDirectory.path) else { return }

        // The main TDLib client must not be opened yet. Copy the whole database
        // directory including SQLite WAL sidecars for one consistent snapshot.
        let staging = root.appendingPathComponent("share-tdlib-" + UUID().uuidString)
        try manager.copyItem(at: mainDatabaseDirectory, to: staging)
        try manager.moveItem(at: staging, to: databaseDirectory)
        try manager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        let config = ShareSessionConfiguration(
            apiID: apiID, apiHash: apiHash, encryptionKey: encryptionKey
        )
        let json = try JSONEncoder().encode(config)
        try json.write(to: configURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseDirectory.path
        )
    }
}
