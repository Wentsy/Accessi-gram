import Foundation
import UIKit
import AVFoundation

enum AttachmentPreparation {
    enum Failure: LocalizedError {
        case unreadableFile
        case unsupportedImage
        case videoConversion

        var errorDescription: String? {
            switch self {
            case .unreadableFile: return "無法讀取選取的檔案，請確認檔案已下載到裝置"
            case .unsupportedImage: return "這張圖片無法轉成可傳送的照片"
            case .videoConversion: return "影片轉換失敗"
            }
        }
    }

    /// Copy a security-scoped provider URL into our own sandbox, before TDLib
    /// tries to read it. iCloud/Files URLs must not be passed directly to TDLib.
    static func copyFromFiles(_ source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("accessigram-uploads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(source.lastPathComponent)

            if source.path.hasPrefix(NSHomeDirectory()) {
                // UIDocumentPicker(asCopy: true) has already supplied a
                // readable local copy. NSFileCoordinator is unnecessary here.
                try FileManager.default.copyItem(at: source, to: target)
            } else {
                var coordinatorError: NSError?
                var copyError: Error?
                NSFileCoordinator(filePresenter: nil).coordinate(
                    readingItemAt: source, options: [], error: &coordinatorError
                ) { readableURL in
                    do {
                        try FileManager.default.copyItem(at: readableURL, to: target)
                    } catch {
                        copyError = error
                    }
                }
                if let error = coordinatorError { throw error }
                if let error = copyError { throw error }
            }
            guard FileManager.default.isReadableFile(atPath: target.path) else {
                throw Failure.unreadableFile
            }
            return target
        }.value
    }

    /// PhotosPicker's Data can be HEIC and has no stable local path. Convert to
    /// JPEG so TDLib gets the real extension, and shrink large photos below 10 MB.
    static func photoFromPicker(_ data: Data) throws -> URL {
        guard let image = UIImage(data: data) else { throw Failure.unsupportedImage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("accessigram-uploads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        let photo = image.jpegData(compressionQuality: 0.78)!
        try photo.write(to: target, options: .atomic)
        return target
    }

    /// Telegram video messages should be MP4 rather than the .mov resource
    /// occasionally returned by PhotosPicker. Export off the main thread.
    static func videoForTelegram(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.videoConversion
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("accessigram-uploads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exporter.outputURL = destination
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                if exporter.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: exporter.error ?? Failure.videoConversion)
                }
            }
        }
        return destination
    }
}
