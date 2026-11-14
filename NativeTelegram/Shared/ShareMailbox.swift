import Foundation

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

/// Stored only inside the Share Extension's own private application sandbox.
enum ShareMailbox {
    static var root: URL { ShareSessionBootstrap.root }

    static func saveRecipients(_ items: [ShareRecipient]) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: root.appendingPathComponent("recipients.json"), options: .atomic)
        }
    }

    static func recipients() -> [ShareRecipient] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("recipients.json"))
        else { return [] }
        return (try? JSONDecoder().decode([ShareRecipient].self, from: data)) ?? []
    }

    static func stageFile(_ source: URL, name: String, id: String) throws -> ShareAttachment {
        let folder = root.appendingPathComponent("shared-uploads", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        // Keep the user's original filename. Telegram uses the staged file's
        // basename as the displayed document name; a UUID prefix would leak
        // the extension's temporary implementation detail into every upload.
        let original = folder.appendingPathComponent(safeName)
        var destination = original
        if FileManager.default.fileExists(atPath: destination.path) {
            let ext = original.pathExtension
            let stem = original.deletingPathExtension().lastPathComponent
            var index = 2
            repeat {
                let candidate = ext.isEmpty
                    ? "\(stem) (\(index))"
                    : "\(stem) (\(index)).\(ext)"
                destination = folder.appendingPathComponent(candidate)
                index += 1
            } while FileManager.default.fileExists(atPath: destination.path)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let ext = destination.pathExtension.lowercased()
        let kind = ["jpg", "jpeg", "png", "heic", "webp"].contains(ext)
            ? "photo" : ["mp4", "mov", "m4v"].contains(ext) ? "video" : "document"
        return ShareAttachment(
            relativePath: "shared-uploads/\(id)/\(destination.lastPathComponent)", kind: kind
        )
    }

    static func url(for attachment: ShareAttachment) -> URL {
        root.appendingPathComponent(attachment.relativePath)
    }

    static func discardFiles(for draft: PendingShare) {
        let directory = root.appendingPathComponent("shared-uploads", isDirectory: true)
            .appendingPathComponent(draft.id, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}
