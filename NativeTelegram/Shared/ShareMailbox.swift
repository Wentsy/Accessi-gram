import Foundation

/// Shared with the iOS Share Extension. All writes are atomic so extension
/// termination cannot leave a half-written recipient list or queued share.
struct ShareRecipient: Codable, Identifiable {
    let id: String
    let title: String
    let chatID: String?
    let userID: String?
}

struct ShareAttachment: Codable {
    let relativePath: String
    let kind: String
}

struct PendingShare: Codable, Identifiable {
    let id: String
    let target: ShareRecipient
    let caption: String
    let attachments: [ShareAttachment]
}

enum ShareMailbox {
    static let appGroup = "group.org.accessigram.native"

    static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func saveRecipients(_ items: [ShareRecipient]) {
        guard let root else { return }
        let data = try! JSONEncoder().encode(items)
        try! data.write(to: root.appendingPathComponent("recipients.json"), options: .atomic)
    }

    static func recipients() -> [ShareRecipient] {
        guard let root,
              let data = try? Data(contentsOf: root.appendingPathComponent("recipients.json")),
              let items = try? JSONDecoder().decode([ShareRecipient].self, from: data)
        else { return [] }
        return items
    }

    static func stageFile(_ source: URL, name: String, id: String) throws -> ShareAttachment {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let folder = root.appendingPathComponent("shared-uploads", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        let destination = folder.appendingPathComponent(UUID().uuidString + "-" + safeName)
        try FileManager.default.copyItem(at: source, to: destination)
        let ext = destination.pathExtension.lowercased()
        let kind = ["jpg", "jpeg", "png", "heic", "webp"].contains(ext)
            ? "photo" : ["mp4", "mov", "m4v"].contains(ext) ? "video" : "document"
        return ShareAttachment(relativePath: "shared-uploads/\(id)/\(destination.lastPathComponent)",
                               kind: kind)
    }

    static func enqueue(_ draft: PendingShare) throws {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let folder = root.appendingPathComponent("pending-shares", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to: folder.appendingPathComponent(draft.id + ".json"), options: .atomic)
    }

    static func pending() -> [PendingShare] {
        guard let root else { return [] }
        let folder = root.appendingPathComponent("pending-shares", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return names.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(PendingShare.self, from: data)
        }
    }

    static func url(for attachment: ShareAttachment) -> URL? {
        root?.appendingPathComponent(attachment.relativePath)
    }

    static func discardFiles(for draft: PendingShare) {
        guard let root else { return }
        let directory = root.appendingPathComponent("shared-uploads", isDirectory: true)
            .appendingPathComponent(draft.id, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    static func complete(_ draft: PendingShare) {
        guard let root else { return }
        let file = root.appendingPathComponent("pending-shares")
            .appendingPathComponent(draft.id + ".json")
        try? FileManager.default.removeItem(at: file)
    }
}
