import Foundation
import CoreBluetooth

// MARK: - BLE constants (in separate file so they are nonisolated for use from BLE delegate callbacks)

enum BLEConstants {
    static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let audioCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    static let controlCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A9")
    static let statusCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AA")
    static let deviceNamePrefix = "Koetori-M5-"
    static let receiveTimeoutSeconds: TimeInterval = 60  // allow ~38s for 30s recording at 50 chunks/s
    static let stragglerWaitSeconds: TimeInterval = 5   // wait for late notifications after END
    static let audioChunkPayloadSize = 510

    static func characteristicPropertiesString(_ p: CBCharacteristicProperties) -> String {
        var s: [String] = []
        if p.contains(.read) { s.append("Read") }
        if p.contains(.write) { s.append("Write") }
        if p.contains(.notify) { s.append("Notify") }
        if p.contains(.indicate) { s.append("Indicate") }
        return s.joined(separator: ",")
    }
}

// MARK: - Thread-safe chunk storage (used from BLE callback without MainActor)

/// Stores audio chunks from BLE. Call from any thread; uses lock. Avoids flooding MainActor with tasks.
final class ChunkStorage {
    private let lock = NSLock()
    private var chunks: [UInt16: Data] = [:]
    private var expectedCount: Int?
    private var sampleRate: Int = 16000
    private var isActive: Bool = false  // True when we have an active session (between START and completion)

    func reset(sampleRate: Int = 16000, activate: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        chunks.removeAll(keepingCapacity: true)
        expectedCount = nil
        isActive = activate  // true for new START, false for cancellation
        self.sampleRate = sampleRate
    }

    /// Called from BLE delegate; minimal work, no async. Logs every 50 chunks to avoid flood.
    /// IGNORES chunks if no active session. If expectedCount is set, also validates index is in range.
    func addChunk(_ data: Data) {
        guard data.count >= 2 else { return }
        let index = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let payload = Data(data.dropFirst(2))
        lock.lock()
        // CRITICAL: Ignore chunks if no active session
        guard isActive else {
            lock.unlock()
            return  // Stale chunk from previous session - silently ignore
        }
        // If expectedCount is set (END arrived), validate index is in range
        // If expectedCount is nil (chunks arriving before END), accept all chunks
        if let expected = expectedCount, Int(index) >= expected {
            lock.unlock()
            return  // Index out of range - ignore
        }
        chunks[index] = payload
        let total = chunks.count
        let log = (total == 1 || total % 50 == 0)
        lock.unlock()
        if log { print("🔵 BLE: audio chunks received: \(total)") }
    }

    func setExpected(_ n: Int) {
        lock.lock()
        expectedCount = n
        lock.unlock()
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
    }

    /// Returns (ordered PCM, sampleRate) if all chunks present, else nil. Clears storage on success.
    func takeIfComplete() -> (pcm: Data, sampleRate: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let expected = expectedCount, expected > 0, chunks.count >= expected else { return nil }
        var missing: [UInt16] = []
        for i in 0..<expected {
            if chunks[UInt16(i)] == nil { missing.append(UInt16(i)) }
        }
        if !missing.isEmpty {
            return nil
        }
        var ordered: [Data] = []
        for i in 0..<expected {
            ordered.append(chunks[UInt16(i)]!)
        }
        chunks.removeAll()
        expectedCount = nil
        isActive = false  // Mark inactive after successful assembly
        let pcm = ordered.reduce(Data(), +)
        let rate = sampleRate
        return (pcm, rate)
    }

    func missingCount(expected: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var n = 0
        for i in 0..<expected {
            if chunks[UInt16(i)] == nil { n += 1 }
        }
        return n
    }

    func receivedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
    }

    func setInactive() {
        lock.lock()
        defer { lock.unlock() }
        isActive = false
    }
}

// Connection-state storage shared with BLEManager (used from BLE callback without MainActor)
let bleChunkStorage = ChunkStorage()
