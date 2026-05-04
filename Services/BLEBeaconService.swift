import Foundation
import CoreBluetooth
import Combine

/// Lightweight BLE beacon that keeps FestivAir discoverable in background.
/// Acts as both peripheral (advertiser) and central (scanner).
/// When a peer needs to communicate, the BLE connection event wakes the app.
///
/// This is the "doorbell" — MPC is the "conversation".
final class BLEBeaconService: NSObject, ObservableObject {

    // MARK: - Constants

    /// FestivAir BLE service UUID — unique to this app
    static let serviceUUID = CBUUID(string: "FA57A1A0-BEEF-CAFE-0001-000000000001")
    /// Characteristic for wake-up signals
    static let wakeCharacteristicUUID = CBUUID(string: "FA57A1A0-BEEF-CAFE-0001-000000000002")
    /// Characteristic for status flags (SOS, pending messages)
    static let statusCharacteristicUUID = CBUUID(string: "FA57A1A0-BEEF-CAFE-0001-000000000003")

    // MARK: - Status Flags (advertised in characteristic)

    struct StatusFlags: OptionSet {
        let rawValue: UInt8
        static let none           = StatusFlags([])
        static let sosActive      = StatusFlags(rawValue: 1 << 0)  // SOS emergency
        static let hasPending     = StatusFlags(rawValue: 1 << 1)  // Has pending messages to deliver
        static let needsLocation  = StatusFlags(rawValue: 1 << 2)  // Requesting location from peers
        static let inSquad        = StatusFlags(rawValue: 1 << 3)  // Currently in a squad
    }

    // MARK: - Published State

    @Published private(set) var isAdvertising: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var nearbyBeaconCount: Int = 0
    @Published private(set) var detectedSOSNearby: Bool = false

    // MARK: - Callbacks

    /// Called when a BLE event should wake the MPC mesh
    var onWakeNeeded: (() -> Void)?
    /// Called when a nearby device has SOS active
    var onSOSDetected: ((String?) -> Void)?  // peripheral identifier if available
    /// Called when a peer wants our location
    var onLocationRequested: (() -> Void)?

    // MARK: - Private State

    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var statusFlags: StatusFlags = .inSquad
    private var statusCharacteristic: CBMutableCharacteristic?
    private var wakeCharacteristic: CBMutableCharacteristic?
    private var discoveredPeripherals: Set<UUID> = []  // Track unique nearby devices
    private var cleanupTimer: Timer?

    // MARK: - Init

    override init() {
        super.init()
        // Initialize with background restore identifiers for state restoration
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.festivair.ble.peripheral"),
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.festivair.peripheral"]
        )
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.festivair.ble.central"),
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.festivair.central",
                CBCentralManagerOptionShowPowerAlertKey: false
            ]
        )

        // Clean up stale discovered peripherals every 60 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.discoveredPeripherals.removeAll()
            self?.nearbyBeaconCount = 0
        }
    }

    deinit {
        cleanupTimer?.invalidate()
        stopAdvertising()
        stopScanning()
    }

    // MARK: - Public Control

    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else { return }
        guard !isAdvertising else { return }

        // Create the service with characteristics
        let service = CBMutableService(type: Self.serviceUUID, primary: true)

        let status = CBMutableCharacteristic(
            type: Self.statusCharacteristicUUID,
            properties: [.read, .notify],
            value: nil,  // Dynamic value
            permissions: [.readable]
        )
        self.statusCharacteristic = status

        let wake = CBMutableCharacteristic(
            type: Self.wakeCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        self.wakeCharacteristic = wake

        service.characteristics = [status, wake]
        peripheralManager.add(service)

        // Start advertising — in background, iOS strips the name but keeps the service UUID
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "FA"  // Stripped in background, but used in foreground
        ])

        isAdvertising = true
        #if DEBUG
        print("[BLE] Advertising started")
        #endif
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        guard !isScanning else { return }

        // Scan for FestivAir beacons — allowing duplicates for RSSI updates
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        #if DEBUG
        print("[BLE] Scanning started")
        #endif
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: - Status Flag Management

    /// Update the advertised status flags
    func updateStatus(_ flags: StatusFlags) {
        statusFlags = flags
        // Notify connected centrals of the change
        guard let characteristic = statusCharacteristic else { return }
        let data = Data([flags.rawValue])
        peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
    }

    /// Set SOS flag — makes us visible as SOS to all nearby scanners
    func setSOSActive(_ active: Bool) {
        if active {
            statusFlags.insert(.sosActive)
        } else {
            statusFlags.remove(.sosActive)
        }
        updateStatus(statusFlags)
    }

    /// Set pending messages flag
    func setHasPendingMessages(_ pending: Bool) {
        if pending {
            statusFlags.insert(.hasPending)
        } else {
            statusFlags.remove(.hasPending)
        }
        updateStatus(statusFlags)
    }

    /// Set location request flag
    func setNeedsLocation(_ needs: Bool) {
        if needs {
            statusFlags.insert(.needsLocation)
        } else {
            statusFlags.remove(.needsLocation)
        }
        updateStatus(statusFlags)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEBeaconService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            startAdvertising()
        case .poweredOff, .unauthorized, .unsupported:
            isAdvertising = false
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.statusCharacteristicUUID {
            request.value = Data([statusFlags.rawValue])
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == Self.wakeCharacteristicUUID {
                // Someone is writing to our wake characteristic — they need us awake
                DispatchQueue.main.async { [weak self] in
                    self?.onWakeNeeded?()
                }
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .writeNotPermitted)
            }
        }
    }

    // State restoration — iOS recreates our manager after app is terminated
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        #if DEBUG
        print("[BLE] Peripheral state restored")
        #endif
        // Re-start advertising after restoration
        if peripheral.state == .poweredOn {
            startAdvertising()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBeaconService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff, .unauthorized, .unsupported:
            isScanning = false
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Track unique nearby FestivAir devices
        discoveredPeripherals.insert(peripheral.identifier)
        DispatchQueue.main.async { [weak self] in
            self?.nearbyBeaconCount = self?.discoveredPeripherals.count ?? 0
        }

        // Connect to read status flags (SOS detection, pending messages)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Connection failed — not critical, we'll retry on next scan
    }

    // State restoration — iOS recreates our manager after app is terminated
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        #if DEBUG
        print("[BLE] Central state restored")
        #endif
        if central.state == .poweredOn {
            startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate (for reading remote status)

extension BLEBeaconService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [Self.statusCharacteristicUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == Self.statusCharacteristicUUID {
            peripheral.readValue(for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.statusCharacteristicUUID,
              let data = characteristic.value,
              let flagByte = data.first else { return }

        let flags = StatusFlags(rawValue: flagByte)

        DispatchQueue.main.async { [weak self] in
            // SOS detection — if any nearby device has SOS active, alert immediately
            if flags.contains(.sosActive) {
                self?.detectedSOSNearby = true
                self?.onSOSDetected?(peripheral.identifier.uuidString)
                self?.onWakeNeeded?()  // Wake the mesh to receive SOS details
            }

            // If they need location, wake our mesh to send
            if flags.contains(.needsLocation) {
                self?.onLocationRequested?()
                self?.onWakeNeeded?()
            }

            // If they have pending messages, wake to receive
            if flags.contains(.hasPending) {
                self?.onWakeNeeded?()
            }
        }

        // Disconnect after reading — we don't need a persistent connection
        centralManager.cancelPeripheralConnection(peripheral)
    }
}
