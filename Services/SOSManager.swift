import Foundation
import UserNotifications
import Combine

/// Manages SOS emergency broadcasts. Overrides all battery and tier settings.
@MainActor
final class SOSManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isSOSActive: Bool = false
    @Published private(set) var sosActiveMember: String?    // userId of member in SOS (nil if us)
    @Published private(set) var sosLocation: (lat: Double, lng: Double)?

    // MARK: - Dependencies

    private let meshManager: MeshNetworkManager
    private let locationManager: LocationManager

    // MARK: - Internal

    private var broadcastTimer: Timer?
    private var messageSigner: MessageSignerProtocol?
    var onLocalSOSActivated: (() -> Void)?
    var onLocalSOSDeactivated: (() -> Void)?

    // MARK: - Init

    init(meshManager: MeshNetworkManager, locationManager: LocationManager) {
        self.meshManager = meshManager
        self.locationManager = locationManager
    }

    func configure(signer: MessageSignerProtocol) {
        self.messageSigner = signer
    }

    // MARK: - Activate / Deactivate

    /// Activates SOS mode — broadcasts precise GPS every 3 seconds
    func activate() {
        guard !isSOSActive else { return }
        isSOSActive = true
        sosActiveMember = nil  // We are the SOS sender

        // Force GPS to best accuracy
        locationManager.applyTier(.navigate)
        onLocalSOSActivated?()

        // Start broadcasting
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.ProtocolV2.sosUpdateInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.broadcastSOS()
            }
        }
        broadcastSOS()  // Immediate first broadcast

        #if DEBUG
        print("[SOS] ACTIVATED — broadcasting every 3 seconds")
        #endif
    }

    /// Deactivates SOS mode
    func deactivate() {
        guard isSOSActive, sosActiveMember == nil else { return }  // Only sender can deactivate
        isSOSActive = false

        broadcastTimer?.invalidate()
        broadcastTimer = nil

        // Send cancellation
        sendSOSCancelled()
        onLocalSOSDeactivated?()

        #if DEBUG
        print("[SOS] DEACTIVATED")
        #endif
    }

    // MARK: - Incoming SOS

    /// Called when we receive an SOS from another squad member
    func handleIncomingSOS(userId: String, latitude: Double, longitude: Double) {
        let isRepeatUpdate = isSOSActive && sosActiveMember == userId

        isSOSActive = true
        sosActiveMember = userId
        sosLocation = (latitude, longitude)

        // SOS packets repeat every few seconds. Notify once, then just refresh the location.
        if !isRepeatUpdate {
            sendSOSNotification(from: userId, lat: latitude, lng: longitude)
        }
    }

    /// Called when we receive an SOS cancellation
    func handleSOSCancelled(userId: String) {
        if sosActiveMember == userId {
            isSOSActive = false
            sosActiveMember = nil
            sosLocation = nil
        }
    }

    // MARK: - Broadcasting

    private func broadcastSOS() {
        guard let userId = KeychainHelper.currentUserId,
              let signer = messageSigner,
              let location = locationManager.currentLocation,
              let joinCode = KeychainHelper.load(.currentJoinCode)
                ?? UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)
        else { return }

        let payload = V2SOSPayload(
            userId: userId,
            latitude: location.latitude,
            longitude: location.longitude,
            heading: locationManager.currentHeading,
            speed: nil
        )

        do {
            let envelope = try V2EnvelopeBuilder.build(
                type: .sos,
                payload: payload,
                originPeerId: userId,
                squadId: joinCode,
                signer: signer
            )
            let data = try envelope.encode()
            meshManager.broadcastRaw(data)
        } catch {
            #if DEBUG
            print("[SOS] Broadcast failed: \(error)")
            #endif
        }
    }

    private func sendSOSCancelled() {
        guard let userId = KeychainHelper.currentUserId,
              let signer = messageSigner,
              let joinCode = KeychainHelper.load(.currentJoinCode)
                ?? UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)
        else { return }

        let payload = V2SOSCancelled(userId: userId)

        do {
            let envelope = try V2EnvelopeBuilder.build(
                type: .sosCancelled,
                payload: payload,
                originPeerId: userId,
                squadId: joinCode,
                signer: signer
            )
            let data = try envelope.encode()
            meshManager.broadcastRaw(data)
        } catch {
            #if DEBUG
            print("[SOS] Cancel broadcast failed: \(error)")
            #endif
        }
    }

    // MARK: - Notifications

    private func sendSOSNotification(from userId: String, lat: Double, lng: Double) {
        let content = UNMutableNotificationContent()
        content.title = "SOS Emergency"
        content.body = "A squad member needs help!"
        content.sound = .defaultCritical  // Plays even in silent mode
        content.interruptionLevel = .critical
        content.categoryIdentifier = "SOS_ALERT"

        let request = UNNotificationRequest(
            identifier: "sos-\(userId)",
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request)
    }
}
