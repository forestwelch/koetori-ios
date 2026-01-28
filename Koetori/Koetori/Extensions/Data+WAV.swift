import Foundation

extension Data {
    /// Creates a 44-byte WAV header for 16-bit mono PCM at the given sample rate.
    /// - Parameters:
    ///   - dataSize: Size of the raw PCM payload in bytes.
    ///   - sampleRate: Sample rate (default 16000 for M5 stick).
    /// - Returns: 44-byte WAV header to prepend to PCM data.
    static func wavHeader(dataSize: Int, sampleRate: Int = 16000) -> Data {
        let byteRate = sampleRate * 2  // 16-bit mono
        let fileSize = dataSize + 44 - 8  // ChunkSize = file size - 8

        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])  // "RIFF"
        var u32 = UInt32(fileSize).littleEndian
        Swift.withUnsafeBytes(of: &u32) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])  // "WAVE"
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])  // "fmt "
        u32 = 16; Swift.withUnsafeBytes(of: &u32) { header.append(contentsOf: $0) }
        var u16 = UInt16(1).littleEndian
        Swift.withUnsafeBytes(of: &u16) { header.append(contentsOf: $0) }   // AudioFormat PCM
        Swift.withUnsafeBytes(of: &u16) { header.append(contentsOf: $0) }   // NumChannels mono
        u32 = UInt32(sampleRate).littleEndian
        Swift.withUnsafeBytes(of: &u32) { header.append(contentsOf: $0) }
        u32 = UInt32(byteRate).littleEndian
        Swift.withUnsafeBytes(of: &u32) { header.append(contentsOf: $0) }
        u16 = 2; Swift.withUnsafeBytes(of: &u16) { header.append(contentsOf: $0) }   // BlockAlign
        u16 = 16; Swift.withUnsafeBytes(of: &u16) { header.append(contentsOf: $0) }  // BitsPerSample
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])  // "data"
        u32 = UInt32(dataSize).littleEndian
        Swift.withUnsafeBytes(of: &u32) { header.append(contentsOf: $0) }
        return header
    }
}
