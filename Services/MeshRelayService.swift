import Foundation
import CryptoKit
import Security
import Combine

/// Universal mesh relay service - every phone helps relay encrypted data for all app users
/// This runs silently in the background - users don't see relay activity
/// The more users at the festival, the better the mesh coverage for everyone
@MainActor
final class MeshRelayService: ObservableObject {

    // MARK: - Singleton
    static let shared = MeshRelayService()

    // MARK: - Dependencies
    private var meshManager: MeshNetworkManager?
    private var cloudKitService: CloudKitService?

    // MARK: - Published State (internal metrics - not shown to users)
    @Published private(set) var isRelayEnabled = true
    @Published private(set) var isGateway = false  // Has internet, sharing with mesh
    @Published private(set) var connectedPeers = 0

    // MARK: - Packet Tracking (prevent loops)
    private var seenPackets: Set<String> = []
    private var packetTimestamps: [String: Date] = [:]
    private let packetTTL: TimeInterval = 300  // 5 min

    // MARK: - Rate Limiting
    private var relayCount = 0
    private var relayCountResetTime = Date()
    private let maxRelaysPerMinute = 500

    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    private init() {}

    // MARK: - Configuration

    func configure(meshManager: MeshNetworkManager, cloudKitService: CloudKitService) {
        self.meshManager = meshManager
        self.cloudKitService = cloudKitService

        // Subscribe to mesh manager peer count
        meshManager.$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.connectedPeers = peers.count
            }
            .store(in: &cancellables)

        // Start gateway monitoring
        startGatewayMonitoring()

        // Start packet cleanup timer
        startPacketCleanup()

        #if DEBUG
        print("[MeshRelay] Configured - universal relay enabled")
        #endif
    }

    // MARK: - Gateway Logic (Share internet with mesh)

    private func startGatewayMonitoring() {
        // Check network status periodically
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateGatewayStatus()
            }
        }
    }

    private func updateGatewayStatus() async {
        // Check if we have internet connectivity
        let hasInternet = await checkInternetConnectivity()

        if hasInternet && !isGateway {
            // We just became a gateway - we can help others!
            isGateway = true
            announceGateway()
            await syncFromCloud()
        } else if !hasInternet && isGateway {
            isGateway = false
        }
    }

    private func checkInternetConnectivity() async -> Bool {
        // Quick connectivity check
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Announce to mesh that we're a gateway (have internet)
    private func announceGateway() {
        guard let meshManager = meshManager else { return }

        let payload = MeshMessagePayload.gatewayAnnounce(
            peerId: currentUserId,
            signalStrength: 75  // Estimated
        )

        meshManager.broadcast(payload)
        #if DEBUG
        print("[MeshRelay] Announced as gateway")
        #endif
    }

    /// Pull recent data from cloud and distribute to local mesh
    private func syncFromCloud() async {
        guard let cloudKit = cloudKitService,
              let squadId = currentSquadId else { return }

        do {
            // Fetch recent squad data from CloudKit
            // This gets updates that came in while we were offline
            // Then broadcasts them to nearby mesh users
            #if DEBUG
            print("[MeshRelay] Gateway sync from cloud started")
            #endif

            // The CloudKitService will handle fetching and notifying
            // observers about new data
        } catch {
            #if DEBUG
            print("[MeshRelay] Gateway sync failed: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    private var currentUserId: String {
        KeychainHelper.currentUserId ?? ""
    }

    private var currentSquadId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentSquadId)
    }

    private func checkRateLimit() -> Bool {
        let now = Date()

        if now.timeIntervalSince(relayCountResetTime) > 60 {
            relayCount = 0
            relayCountResetTime = now
        }

        return relayCount < maxRelaysPerMinute
    }

    // MARK: - Cleanup

    private func startPacketCleanup() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldPackets()
            }
        }
    }

    private func cleanupOldPackets() {
        let now = Date()
        let expiredIds = packetTimestamps.filter { now.timeIntervalSince($0.value) > packetTTL }.keys

        for id in expiredIds {
            seenPackets.remove(id)
            packetTimestamps.removeValue(forKey: id)
        }

        #if DEBUG
        if !expiredIds.isEmpty {
            print("[MeshRelay] Cleaned up \(expiredIds.count) expired packets")
        }
        #endif
    }

    // MARK: - Encryption Helpers

    // MARK: - SquadCrypto

    enum SquadCrypto {
        /// Generates a random 256-bit squad secret.
        static func generateSecret() -> Data {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
            precondition(status == errSecSuccess, "Failed to generate random bytes")
            return Data(bytes)
        }

        /// Encrypts data using AES-GCM with the squad secret.
        static func encrypt(_ data: Data, with secret: Data) throws -> Data {
            let key = SymmetricKey(data: secret)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else {
                throw CryptoError.encryptionFailed
            }
            return combined
        }

        /// Decrypts data using AES-GCM with the squad secret.
        static func decrypt(_ data: Data, with secret: Data) throws -> Data {
            let key = SymmetricKey(data: secret)
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        }

        /// Loads the current squad secret from Keychain.
        static func currentSecret() -> Data? {
            KeychainHelper.loadData(for: .squadSecret)
        }

        /// Saves a squad secret to Keychain.
        static func saveSecret(_ secret: Data) {
            KeychainHelper.saveData(secret, for: .squadSecret)
        }

        /// Removes the squad secret (on squad leave).
        static func clearSecret() {
            KeychainHelper.delete(.squadSecret)
        }

        enum CryptoError: Error, LocalizedError {
            case encryptionFailed
            case noSquadSecret

            var errorDescription: String? {
                switch self {
                case .encryptionFailed: return "AES-GCM encryption failed"
                case .noSquadSecret: return "No squad secret in Keychain"
                }
            }
        }
    }

    /// Get or derive encryption key for a squad
    @available(*, deprecated, message: "Use SquadCrypto instead")
    func getSquadKey(_ squadId: String) -> SymmetricKey {
        // Derive key from squad ID
        // In production, use proper key exchange when joining squad
        let keyData = SHA256.hash(data: Data(squadId.utf8))
        return SymmetricKey(data: Data(keyData))
    }

    /// Encrypt data for a specific squad
    @available(*, deprecated, message: "Use SquadCrypto instead")
    func encrypt(_ data: Data, forSquad squadId: String) -> Data? {
        let key = getSquadKey(squadId)

        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined
        } catch {
            #if DEBUG
            print("[MeshRelay] Encryption failed: \(error)")
            #endif
            return nil
        }
    }

    /// Decrypt data from a squad (returns nil if we don't have the key)
    @available(*, deprecated, message: "Use SquadCrypto instead")
    func decrypt(_ data: Data, forSquad squadId: String) -> Data? {
        // Only decrypt if it's our squad
        guard squadId == currentSquadId else {
            return nil  // Not our squad - we just relay, don't read
        }

        let key = getSquadKey(squadId)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            #if DEBUG
            print("[MeshRelay] Decryption failed: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Network Effect Stats (Internal)

extension MeshRelayService {
    /// Estimate how many users are reachable through the mesh
    /// This is internal - not shown to users
    var estimatedMeshReach: Int {
        // Each connected peer can reach ~4 more on average
        return connectedPeers * 4
    }

    /// Check if mesh has good coverage
    var hasMeshCoverage: Bool {
        return connectedPeers >= 2
    }
}
