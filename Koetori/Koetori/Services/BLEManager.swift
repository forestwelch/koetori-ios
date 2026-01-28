import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE constants

private let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
private let audioCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
private let controlCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A9")
private let statusCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AA")
private let deviceNamePrefix = "Koetori-M5-"
private let receiveTimeoutSeconds: TimeInterval = 60  // allow ~38s for 30s recording at 50 chunks/s
private let stragglerWaitSeconds: TimeInterval = 5   // wait for late notifications after END
private let audioChunkPayloadSize = 510

// MARK: - Thread-safe chunk storage (used from BLE callback without MainActor)

/// Stores audio chunks from BLE. Call from any thread; uses lock. Avoids flooding MainActor with tasks.
private final class ChunkStorage {
    private let lock = NSLock()
    private var chunks: [UInt16: Data] = [:]
    private var expectedCount: Int?
    private var sampleRate: Int = 16000

    func reset(sampleRate: Int = 16000) {
        lock.lock()
        defer { lock.unlock() }
        chunks.removeAll(keepingCapacity: true)
        expectedCount = nil
        self.sampleRate = sampleRate
    }

    /// Called from BLE delegate; minimal work, no async. Logs every 50 chunks to avoid flood.
    func addChunk(_ data: Data) {
        guard data.count >= 2 else { return }
        let index = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let payload = Data(data.dropFirst(2))
        lock.lock()
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
}

// Connection-state storage shared with delegate (written from BLE callback without MainActor)
private let chunkStorage = ChunkStorage()

// MARK: - Connection state

enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected(name: String)
    case receiving(name: String)
}

// MARK: - BLE Manager

@MainActor
final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    @Published private(set) var connectionState: BLEConnectionState = .disconnected
    @Published private(set) var errorMessage: String?
    @Published var showError = false

    /// Called when audio has been fully received and assembled into a WAV file URL.
    var onAudioAssembled: ((URL) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var audioChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    private var controlStartSampleRate: Int = 16000
    private var receiveTimeoutWorkItem: DispatchWorkItem?
    private var stragglerWorkItem: DispatchWorkItem?
    private let bleQueue = DispatchQueue(label: "koetori.ble")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)  // nil = main queue
    }

    func startScanning() {
        central.delegate = self
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            connectionState = .scanning
            errorMessage = nil
        case .poweredOff, .unauthorized, .unsupported, .resetting:
            connectionState = .disconnected
            errorMessage = "Bluetooth is unavailable"
            showError = true
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func stopScanning() {
        central.stopScan()
        if peripheral == nil, case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func disconnect() {
        cancelReceive()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        audioChar = nil
        controlChar = nil
        statusChar = nil
        connectionState = .disconnected
    }

    /// Write a string to the Control characteristic (e.g. "SUCCESS:category:0.95").
    func writeToControl(_ message: String) {
        guard let char = controlChar,
              let p = peripheral,
              let data = message.data(using: .utf8) else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    // MARK: - Receive state

    private func cancelReceive() {
        receiveTimeoutWorkItem?.cancel()
        receiveTimeoutWorkItem = nil
        stragglerWorkItem?.cancel()
        stragglerWorkItem = nil
        chunkStorage.reset()
        if case .receiving = connectionState, let name = peripheral?.name {
            connectionState = .connected(name: name)
        }
    }

    private func scheduleReceiveTimeout() {
        receiveTimeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.receiveTimedOut()
            }
        }
        receiveTimeoutWorkItem = item
        bleQueue.asyncAfter(deadline: .now() + receiveTimeoutSeconds, execute: item)
    }

    private func receiveTimedOut() {
        cancelReceive()
        errorMessage = "Recording timed out (no data)"
        showError = true
    }

    private func handleControlMessage(_ message: String) {
        if message.hasPrefix("START:") {
            print("🔵 BLE: Control START -> expecting audio chunks")
            cancelReceive()
            let parts = message.dropFirst(6).split(separator: ":")
            if parts.count >= 2, let rate = Int(parts[1]) {
                controlStartSampleRate = rate
                chunkStorage.reset(sampleRate: rate)
            } else {
                chunkStorage.reset(sampleRate: controlStartSampleRate)
            }
            if let name = peripheral?.name {
                connectionState = .receiving(name: name)
            }
            scheduleReceiveTimeout()
            return
        }
        if message.hasPrefix("END:") {
            receiveTimeoutWorkItem?.cancel()
            receiveTimeoutWorkItem = nil
            let countStr = String(message.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let total = Int(countStr), total > 0 else {
                cancelReceive()
                errorMessage = "Invalid END message"
                showError = true
                return
            }
            chunkStorage.setExpected(total)
            let have = chunkStorage.receivedCount()
            print("🔵 BLE: END received, have \(have)/\(total) chunks")
            tryAssembleAndNotify()
            if have < total {
                scheduleStragglerWait(expected: total)
            }
            return
        }
        if message.hasPrefix("ERROR:") {
            cancelReceive()
            let err = String(message.dropFirst(6))
            errorMessage = "M5 error: \(err)"
            showError = true
        }
    }

    private func scheduleStragglerWait(expected: Int) {
        stragglerWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.checkStragglersAndAssemble(expected: expected)
            }
        }
        stragglerWorkItem = item
        bleQueue.asyncAfter(deadline: .now() + stragglerWaitSeconds, execute: item)
    }

    private func checkStragglersAndAssemble(expected: Int) {
        stragglerWorkItem = nil
        let have = chunkStorage.receivedCount()
        print("🔵 BLE: straggler check: \(have)/\(expected) chunks")
        if have >= expected {
            tryAssembleAndNotify()
        } else {
            let missing = chunkStorage.missingCount(expected: expected)
            print("🔴 BLE: still missing \(missing) chunks after \(Int(stragglerWaitSeconds))s wait")
            errorMessage = "\(have)/\(expected) chunks received. iOS may be dropping BLE notifications — try moving the phone closer or reducing recording length."
            showError = true
            cancelReceive()
        }
    }

    private func tryAssembleAndNotify() {
        guard let result = chunkStorage.takeIfComplete() else { return }
        let header = Data.wavHeader(dataSize: result.pcm.count, sampleRate: result.sampleRate)
        let wav = header + result.pcm
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ble_recording_\(Date().timeIntervalSince1970).wav")
        do {
            try wav.write(to: fileURL)
        } catch {
            errorMessage = "Failed to save WAV: \(error.localizedDescription)"
            showError = true
            cancelReceive()
            return
        }
        cancelReceive()
        onAudioAssembled?(fileURL)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if case .disconnected = connectionState {
                    startScanning()
                }
            case .poweredOff, .unauthorized, .unsupported, .resetting:
                connectionState = .disconnected
                errorMessage = "Bluetooth unavailable"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.hasPrefix(deviceNamePrefix) else { return }
        central.stopScan()
        peripheral.delegate = self
        Task { @MainActor [weak self] in
            self?.peripheral = peripheral
            self?.connectionState = .connecting
        }
        central.connect(peripheral, options: nil)
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "M5"
        Task { @MainActor [weak self] in
            self?.connectionState = .connected(name: name)
        }
        peripheral.discoverServices([serviceUUID])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.peripheral = nil
            self?.connectionState = .disconnected
            self?.errorMessage = error?.localizedDescription ?? "Connection failed"
            self?.showError = true
            self?.startScanning()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.peripheral = nil
            self?.audioChar = nil
            self?.controlChar = nil
            self?.statusChar = nil
            if case .receiving = self?.connectionState {
                self?.errorMessage = "Disconnected during recording"
                self?.showError = true
            }
            self?.cancelReceive()
            self?.connectionState = .disconnected
            self?.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([audioCharUUID, controlCharUUID, statusCharUUID], for: svc)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            print("🔴 BLE: didDiscoverCharacteristicsFor error: \(err)")
            return
        }
        guard let chars = service.characteristics else {
            print("🔴 BLE: no characteristics in service")
            return
        }
        print("🔵 BLE: discovered \(chars.count) characteristics")
        var audio: CBCharacteristic?
        var control: CBCharacteristic?
        var status: CBCharacteristic?
        for c in chars {
            let uuidStr = c.uuid.uuidString
            let props = characteristicPropertiesString(c.properties)
            print("🔵 BLE:   \(uuidStr) properties=\(props)")
            if c.uuid == audioCharUUID { audio = c }
            if c.uuid == controlCharUUID { control = c }
            if c.uuid == statusCharUUID { status = c }
        }
        // Subscribe to notifications – Audio must be enabled for chunk delivery
        if let a = audio {
            print("🔵 BLE: enabling notify on AUDIO characteristic \(a.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: a)
        } else {
            print("🔴 BLE: AUDIO characteristic not found (expected \(audioCharUUID.uuidString))")
        }
        if let c = control {
            print("🔵 BLE: enabling notify on CONTROL characteristic \(c.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: c)
        }
        if let s = status {
            peripheral.setNotifyValue(true, for: s)
        }
        Task { @MainActor [weak self] in
            self?.audioChar = audio
            self?.controlChar = control
            self?.statusChar = status
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuidStr = characteristic.uuid.uuidString
        if let err = error {
            print("🔴 BLE: notify state failed for \(uuidStr): \(err)")
            return
        }
        let name = characteristic.uuid == audioCharUUID ? "AUDIO" : (characteristic.uuid == controlCharUUID ? "CONTROL" : "STATUS")
        print("🔵 BLE: notify \(characteristic.isNotifying ? "ON" : "OFF") for \(name) (\(uuidStr))")
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("🔴 BLE: didUpdateValueFor error: \(err)")
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == controlCharUUID {
            if let msg = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.handleControlMessage(msg)
                }
            }
        } else if characteristic.uuid == audioCharUUID {
            // Store synchronously on callback thread. No Task = no MainActor queue flood, fewer drops.
            // Copy immediately; characteristic.value is a reused buffer.
            let dataCopy = Data(data)
            chunkStorage.addChunk(dataCopy)
        }
    }
}

private func characteristicPropertiesString(_ p: CBCharacteristicProperties) -> String {
    var s: [String] = []
    if p.contains(.read) { s.append("Read") }
    if p.contains(.write) { s.append("Write") }
    if p.contains(.notify) { s.append("Notify") }
    if p.contains(.indicate) { s.append("Indicate") }
    return s.joined(separator: ",")
}
