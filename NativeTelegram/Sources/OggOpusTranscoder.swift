import Foundation
import opus

/// Telegram voice messages are usually Ogg/Opus, which AVAudioPlayer cannot
/// decode on iOS. Convert to an ordinary PCM WAV first, then use AVAudioPlayer.
enum OggOpusTranscoder {
    enum ConversionError: LocalizedError {
        case unreadable, decode(Int32)
        var errorDescription: String? {
            switch self {
            case .unreadable: return "無法開啟 OGG Opus 語音檔"
            case .decode(let code): return "語音解碼失敗，錯誤碼 \(code)"
            }
        }
    }

    static func playableURL(for source: URL) throws -> URL {
        let header = try Data(contentsOf: source, options: .mappedIfSafe).prefix(4)
        guard String(data: header, encoding: .ascii) == "OggS" else { return source }

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(source.lastPathComponent.hashValue.magnitude).wav")
        if FileManager.default.fileExists(atPath: target.path) { return target }

        var errorCode: Int32 = 0
        let opusFile = source.path.withCString { op_open_file($0, &errorCode) }
        guard let opusFile else { throw ConversionError.decode(errorCode) }
        defer { op_free(opusFile) }

        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        // 48,000 Hz / stereo / 16-bit little-endian PCM WAV.
        var headerBytes = Data("RIFF".utf8)
        headerBytes.appendLittleEndian(UInt32(0))
        headerBytes.append(Data("WAVEfmt ".utf8))
        headerBytes.appendLittleEndian(UInt32(16))
        headerBytes.appendLittleEndian(UInt16(1))
        headerBytes.appendLittleEndian(UInt16(2))
        headerBytes.appendLittleEndian(UInt32(48_000))
        headerBytes.appendLittleEndian(UInt32(192_000))
        headerBytes.appendLittleEndian(UInt16(4))
        headerBytes.appendLittleEndian(UInt16(16))
        headerBytes.append(Data("data".utf8))
        headerBytes.appendLittleEndian(UInt32(0))
        handle.write(headerBytes)

        var samples = [Int16](repeating: 0, count: 11_520)
        var dataByteCount: UInt32 = 0
        while true {
            let decoded = samples.withUnsafeMutableBufferPointer {
                op_read_stereo(opusFile, $0.baseAddress, Int32($0.count))
            }
            if decoded == 0 { break }
            if decoded < 0 { throw ConversionError.decode(Int32(decoded)) }
            let bytes = Int(decoded) * 2 * MemoryLayout<Int16>.size
            samples.withUnsafeBytes { buffer in
                handle.write(Data(buffer.prefix(bytes)))
            }
            dataByteCount += UInt32(bytes)
        }

        try handle.seek(toOffset: 4)
        var riffSize = Data()
        riffSize.appendLittleEndian(36 + dataByteCount)
        handle.write(riffSize)
        try handle.seek(toOffset: 40)
        var pcmSize = Data()
        pcmSize.appendLittleEndian(dataByteCount)
        handle.write(pcmSize)
        return target
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
