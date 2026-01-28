import Foundation
import CoreBluetooth
import Combine

// MARK: - Debug info (for UI)

struct BLEDebugInfo: Equatable {
    var lastChunksReceived: Int
    var lastChunksExpected: Int
    var lastTransferAt: Date?
    var lastError: String?
    var lastEvent: String  // e.g. "END", "timeout", "straggler_fail", "assembled"
}

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
    @Published private(set) var debugInfo = BLEDebugInfo(lastChunksReceived: 0, lastChunksExpected: 0, lastTransferAt: nil, lastError: nil, lastEvent: "—")

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
            central.scanForPeripherals(withServices: [BLEConstants.serviceUUID], options: nil)
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
        // Reset storage and mark inactive to ignore any chunks still in transit from failed/cancelled session
        bleChunkStorage.reset(activate: false)
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
        bleQueue.asyncAfter(deadline: .now() + BLEConstants.receiveTimeoutSeconds, execute: item)
    }

    private func receiveTimedOut() {
        debugInfo = BLEDebugInfo(lastChunksReceived: bleChunkStorage.receivedCount(), lastChunksExpected: 0, lastTransferAt: Date(), lastError: "Timeout", lastEvent: "timeout")
        cancelReceive()
        errorMessage = "Recording timed out (no data)"
        showError = true
    }

    private func handleControlMessage(_ message: String) {
        if message.hasPrefix("START:") {
            print("🔵 BLE: Control START -> expecting audio chunks")
            // Cancel any pending work and reset storage (clears isActive flag)
            cancelReceive()
            let parts = message.dropFirst(6).split(separator: ":")
            if parts.count >= 2, let rate = Int(parts[1]) {
                controlStartSampleRate = rate
                bleChunkStorage.reset(sampleRate: rate)
            } else {
                bleChunkStorage.reset(sampleRate: controlStartSampleRate)
            }
            // reset() sets isActive = true, so chunks arriving after START are accepted
            // Chunks are filtered by expectedCount range once END sets it
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
            bleChunkStorage.setExpected(total)
            let have = bleChunkStorage.receivedCount()
            debugInfo = BLEDebugInfo(lastChunksReceived: have, lastChunksExpected: total, lastTransferAt: Date(), lastError: nil, lastEvent: "END")
            print("🔵 BLE: END received, have \(have)/\(total) chunks")
            tryAssembleAndNotify()
            if have < total {
                scheduleStragglerWait(expected: total)
            }
            return
        }
        if message.hasPrefix("ERROR:") {
            let err = String(message.dropFirst(6))
            debugInfo = BLEDebugInfo(lastChunksReceived: bleChunkStorage.receivedCount(), lastChunksExpected: 0, lastTransferAt: Date(), lastError: err, lastEvent: "ERROR")
            cancelReceive()
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
        bleQueue.asyncAfter(deadline: .now() + BLEConstants.stragglerWaitSeconds, execute: item)
    }

    private func checkStragglersAndAssemble(expected: Int) {
        stragglerWorkItem = nil
        let have = bleChunkStorage.receivedCount()
        print("🔵 BLE: straggler check: \(have)/\(expected) chunks")
        if have >= expected {
            tryAssembleAndNotify()
        } else {
            let missing = bleChunkStorage.missingCount(expected: expected)
            let errMsg = "\(have)/\(expected) chunks received"
            debugInfo = BLEDebugInfo(lastChunksReceived: have, lastChunksExpected: expected, lastTransferAt: Date(), lastError: errMsg, lastEvent: "straggler_fail")
            print("🔴 BLE: still missing \(missing) chunks after \(Int(BLEConstants.stragglerWaitSeconds))s wait")
            errorMessage = "\(errMsg). iOS may be dropping BLE notifications — try moving the phone closer or reducing recording length."
            showError = true
            cancelReceive()
        }
    }

    private func tryAssembleAndNotify() {
        guard let result = bleChunkStorage.takeIfComplete() else { return }
        debugInfo = BLEDebugInfo(lastChunksReceived: (result.pcm.count / 510) + 1, lastChunksExpected: (result.pcm.count + 509) / 510, lastTransferAt: Date(), lastError: nil, lastEvent: "assembled")
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
        guard name.hasPrefix(BLEConstants.deviceNamePrefix) else { return }
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
        peripheral.discoverServices([BLEConstants.serviceUUID])
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
            // cancelReceive() already marks storage inactive, but ensure it's cleared
            self?.cancelReceive()
            self?.connectionState = .disconnected
            self?.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([BLEConstants.audioCharUUID, BLEConstants.controlCharUUID, BLEConstants.statusCharUUID], for: svc)
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
        var foundAudio: CBCharacteristic?
        var foundControl: CBCharacteristic?
        var foundStatus: CBCharacteristic?
        for c in chars {
            let uuidStr = c.uuid.uuidString
            let props = BLEConstants.characteristicPropertiesString(c.properties)
            print("🔵 BLE:   \(uuidStr) properties=\(props)")
            if c.uuid == BLEConstants.audioCharUUID { foundAudio = c }
            if c.uuid == BLEConstants.controlCharUUID { foundControl = c }
            if c.uuid == BLEConstants.statusCharUUID { foundStatus = c }
        }
        // Subscribe to notifications – Audio must be enabled for chunk delivery
        if let a = foundAudio {
            print("🔵 BLE: enabling notify on AUDIO characteristic \(a.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: a)
        } else {
            print("🔴 BLE: AUDIO characteristic not found (expected \(BLEConstants.audioCharUUID.uuidString))")
        }
        if let c = foundControl {
            print("🔵 BLE: enabling notify on CONTROL characteristic \(c.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: c)
        }
        if let s = foundStatus {
            peripheral.setNotifyValue(true, for: s)
        }
        let audioCharToSet = foundAudio
        let controlCharToSet = foundControl
        let statusCharToSet = foundStatus
        Task { @MainActor [weak self] in
            self?.audioChar = audioCharToSet
            self?.controlChar = controlCharToSet
            self?.statusChar = statusCharToSet
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuidStr = characteristic.uuid.uuidString
        if let err = error {
            print("🔴 BLE: notify state failed for \(uuidStr): \(err)")
            return
        }
        let name = characteristic.uuid == BLEConstants.audioCharUUID ? "AUDIO" : (characteristic.uuid == BLEConstants.controlCharUUID ? "CONTROL" : "STATUS")
        print("🔵 BLE: notify \(characteristic.isNotifying ? "ON" : "OFF") for \(name) (\(uuidStr))")
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("🔴 BLE: didUpdateValueFor error: \(err)")
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == BLEConstants.controlCharUUID {
            if let msg = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.handleControlMessage(msg)
                }
            }
        } else if characteristic.uuid == BLEConstants.audioCharUUID {
            // Store synchronously on callback thread. No Task = no MainActor queue flood, fewer drops.
            // Copy immediately; characteristic.value is a reused buffer.
            // addChunk() now filters stale chunks internally (checks isActive and expectedCount)
            let dataCopy = Data(data)
            bleChunkStorage.addChunk(dataCopy)
        }
    }
}

