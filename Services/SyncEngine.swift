import Foundation
import SwiftData
import Combine

/// Handles offline-first sync between local storage and CloudKit
final class SyncEngine: ObservableObject {

    // MARK: - Published State
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingChangesCount = 0
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncError: Error?

    // MARK: - Dependencies
    private var modelContext: ModelContext?
    private var gatewayManager: GatewayManager?
    private var meshManager: MeshNetworkManager?
    private let cloudKit = CloudKitService.shared

    // MARK: - Pending Changes Queue
    private var pendingChanges: [SyncChange] = []
    private let pendingChangesKey = "FestivAir.PendingChanges"

    // MARK: - Init
    init() {
        loadPendingChanges()
    }

    func configure(
        modelContext: ModelContext,
        gatewayManager: GatewayManager,
        meshManager: MeshNetworkManager
    ) {
        self.modelContext = modelContext
        self.gatewayManager = gatewayManager
        self.meshManager = meshManager
    }

    // MARK: - Public API

    /// Queue a change for sync
    func queueChange(_ change: SyncChange) {
        pendingChanges.append(change)
        pendingChangesCount = pendingChanges.count
        savePendingChanges()

        // If we're the gateway, sync immediately
        if gatewayManager?.isGateway == true {
            Task { await syncToCloud() }
        }
    }

    /// Sync pending changes to CloudKit (only gateway should call this)
    func syncToCloud() async {
        guard gatewayManager?.isGateway == true else {
            print("[Sync] Not gateway, skipping cloud sync")
            return
        }

        guard !isSyncing else { return }
        guard !pendingChanges.isEmpty else { return }
        guard cloudKit.isAvailable else {
            print("[Sync] CloudKit not available")
            return
        }

        await MainActor.run { isSyncing = true }

        do {
            // Process each pending change
            let syncedCount = pendingChanges.count
            for change in pendingChanges {
                try await uploadChange(change)
            }

            // Clear synced changes
            await MainActor.run {
                pendingChanges.removeAll()
                pendingChangesCount = 0
                lastSyncTime = Date()
                syncError = nil
            }
            savePendingChanges()

            print("[Sync] Successfully synced \(syncedCount) changes")

        } catch {
            await MainActor.run {
                syncError = error
            }
            print("[Sync] Error: \(error)")
        }

        await MainActor.run { isSyncing = false }
    }

    /// Pull updates from CloudKit and distribute via mesh
    func pullFromCloud() async {
        guard gatewayManager?.isGateway == true else { return }
        guard cloudKit.isAvailable else { return }

        do {
            // Fetch updates (squad locations, messages, etc.)
            if let squadId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentSquadId) {
                let locations = try await cloudKit.getSquadLocations(squadId: squadId)

                // Broadcast to mesh peers
                if let meshManager = meshManager {
                    let syncLocations = locations.map { loc in
                        SyncLocationData(userId: loc.userId, lat: loc.latitude, lon: loc.longitude)
                    }
                    let syncData = try JSONEncoder().encode(syncLocations)
                    meshManager.broadcast(MeshMessagePayload.syncResponse(data: syncData))
                }
            }

        } catch {
            print("[Sync] Pull error: \(error)")
        }
    }

    /// Handle sync data received from gateway via mesh
    func handleSyncResponse(data: Data) async {
        guard let modelContext = modelContext else {
            print("[Sync] No model context configured")
            return
        }

        do {
            // Decode sync locations from gateway
            let syncLocations = try JSONDecoder().decode([SyncLocationData].self, from: data)
            print("[Sync] Received \(syncLocations.count) location updates from gateway")

            // Update local SwiftData with remote locations
            for syncLoc in syncLocations {
                // Find user in local database by firebaseId (which stores the userId string)
                let userIdString = syncLoc.userId
                let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.firebaseId == userIdString })

                if let existingUsers = try? modelContext.fetch(descriptor),
                   let user = existingUsers.first {
                    // Update location if remote is newer (we don't have timestamp, so always update for now)
                    user.latitude = syncLoc.lat
                    user.longitude = syncLoc.lon
                    user.locationTimestamp = Date()
                    user.locationSource = LocationSource.gateway.rawValue
                }
            }

            try modelContext.save()
            print("[Sync] Updated \(syncLocations.count) user locations from gateway")

        } catch {
            print("[Sync] Failed to process sync response: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func uploadChange(_ change: SyncChange) async throws {
        switch change.entityType {
        case "Location":
            if let payload = try? JSONDecoder().decode(LocationPayload.self, from: change.payload) {
                try await cloudKit.updateLocation(
                    squadId: payload.squadId,
                    userId: payload.userId,
                    latitude: payload.latitude,
                    longitude: payload.longitude,
                    accuracy: payload.accuracy
                )
            }

        case "Message":
            if let payload = try? JSONDecoder().decode(MessagePayload.self, from: change.payload) {
                _ = try await cloudKit.sendMessage(
                    squadId: payload.squadId,
                    senderId: payload.senderId,
                    senderName: payload.senderName,
                    text: payload.text
                )
            }

        default:
            print("[Sync] Unknown entity type: \(change.entityType)")
        }
    }

    // MARK: - Persistence

    private func loadPendingChanges() {
        guard let data = UserDefaults.standard.data(forKey: pendingChangesKey),
              let changes = try? JSONDecoder().decode([SyncChange].self, from: data) else {
            return
        }
        pendingChanges = changes
        pendingChangesCount = changes.count
    }

    private func savePendingChanges() {
        guard let data = try? JSONEncoder().encode(pendingChanges) else { return }
        UserDefaults.standard.set(data, forKey: pendingChangesKey)
    }
}

// MARK: - Sync Types

struct SyncChange: Codable {
    let id: UUID
    let type: ChangeType
    let entityType: String
    let entityId: String
    let payload: Data
    let timestamp: Date

    enum ChangeType: String, Codable {
        case create
        case update
        case delete
    }
}

// MARK: - Payload Types

private struct LocationPayload: Codable {
    let squadId: String
    let userId: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
}

private struct MessagePayload: Codable {
    let squadId: String
    let senderId: String
    let senderName: String
    let text: String
}

struct SyncLocationData: Codable {
    let userId: String
    let lat: Double
    let lon: Double
}

// MARK: - Conflict Resolution

extension SyncEngine {

    /// Last-write-wins for locations, merge for favorites
    func resolveConflict(local: SyncChange, remoteTimestamp: Date) -> ConflictResolution {
        switch local.entityType {
        case "Location":
            return local.timestamp > remoteTimestamp ? .keepLocal : .keepRemote
        case "Favorite":
            return .merge
        default:
            return local.timestamp > remoteTimestamp ? .keepLocal : .keepRemote
        }
    }

    enum ConflictResolution {
        case keepLocal
        case keepRemote
        case merge
    }
}
