import Foundation

/// The extension cannot read the containing app's sandbox or its private
/// Keychain records. It needs its own authorized TDLib directory in a genuine
/// App Group container; a normal app launch alone doesn't create that.
struct ShareSessionConfiguration: Codable {
    let apiID: Int
    let apiHash: String
    let encryptionKey: String
}

enum ShareSessionError: LocalizedError {
    case groupUnavailable
    case mainDatabaseUnavailable
    case snapshotFailed(String)
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .groupUnavailable:
            return "App Group 權限不存在。請 OC 確認主 App 和分享延伸功能的簽名都包含 group.org.accessigram.native；單純開啟 App 無法修復缺少的簽署權限。"
        case .mainDatabaseUnavailable:
            return "找不到主 App 的 TDLib 登入資料庫。請先完成登入；新版 App 會在授權完成後自動建立分享登入。"
        case .snapshotFailed(let detail):
            return "無法建立分享登入副本：\(detail)"
        case .configurationMissing:
            return "分享登入資料尚未建立，請先開啟已登入的 Accessi Gram。若持續出現，請檢查 App Group 簽署權限。"
        }
    }
}

enum ShareSessionBootstrap {
    static var groupRoot: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareMailbox.appGroup
        )
    }

    static var databaseDirectory: URL {
        (groupRoot ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("share-tdlib", isDirectory: true)
    }

    static var filesDirectory: URL {
        (groupRoot ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("share-files", isDirectory: true)
    }

    static var configURL: URL {
        (groupRoot ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("share-session.json")
    }

    static func status() -> String {
        guard groupRoot != nil else {
            return "分享功能無法使用：缺少 App Group 簽署權限"
        }
        guard FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: databaseDirectory.path)
        else {
            return "分享登入資料尚未建立"
        }
        return "分享登入副本已準備，可在其他 App 的分享選單使用"
    }

    static func clearAuthorization() {
        guard let root = groupRoot else { return }
        let manager = FileManager.default
        for file in [configURL, databaseDirectory, filesDirectory,
                     root.appendingPathComponent("recipients.json"),
                     root.appendingPathComponent("pending-shares"),
                     root.appendingPathComponent("shared-uploads")] {
            try? manager.removeItem(at: file)
        }
    }

    static func configuration() throws -> ShareSessionConfiguration {
        guard groupRoot != nil else { throw ShareSessionError.groupUnavailable }
        guard FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: databaseDirectory.path)
        else { throw ShareSessionError.configurationMissing }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(ShareSessionConfiguration.self, from: data)
    }

    /// Safe to call repeatedly. An initial attempt may find no database if
    /// this is the first-ever login; authorizationStateReady retries it.
    @discardableResult
    static func prepareBeforeMainTDLibStarts(
        apiID: Int,
        apiHash: String,
        encryptionKey: String,
        mainDatabaseDirectory: URL
    ) throws -> String {
        let manager = FileManager.default
        guard let root = groupRoot else { throw ShareSessionError.groupUnavailable }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        if manager.fileExists(atPath: configURL.path),
           manager.fileExists(atPath: databaseDirectory.path) {
            return status()
        }

        guard manager.fileExists(atPath: mainDatabaseDirectory.path) else {
            throw ShareSessionError.mainDatabaseUnavailable
        }

        if !manager.fileExists(atPath: databaseDirectory.path) {
            let staging = root.appendingPathComponent(
                "share-tdlib-" + UUID().uuidString, isDirectory: true
            )
            do {
                try manager.copyItem(at: mainDatabaseDirectory, to: staging)
                try manager.moveItem(at: staging, to: databaseDirectory)
            } catch {
                try? manager.removeItem(at: staging)
                throw ShareSessionError.snapshotFailed(error.localizedDescription)
            }
        }

        try manager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let config = ShareSessionConfiguration(
            apiID: apiID,
            apiHash: apiHash,
            encryptionKey: encryptionKey
        )
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: configURL.path
        )
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseDirectory.path
        )
        return status()
    }
}
