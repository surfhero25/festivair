import Foundation
import SwiftData
import Combine

@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published State
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Dependencies
    private let cloudKit: CloudKitService
    private let meshManager: MeshNetworkManager
    private var notificationManager: NotificationManager?
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // Track if chat view is currently visible (to suppress notifications)
    @Published var isChatVisible = false

    // MARK: - Current User
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    private var currentUserName: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Me"
    }

    // MARK: - Squad
    private var currentSquadId: UUID?
    private var cloudSquadId: String?
    private var joinCode: String?  // Used for mesh message routing (same on all devices)

    // MARK: - Init
    init(cloudKit: CloudKitService = .shared, meshManager: MeshNetworkManager, notificationManager: NotificationManager? = nil) {
        self.cloudKit = cloudKit
        self.meshManager = meshManager
        self.notificationManager = notificationManager
        setupMeshListener()
    }

    func configure(modelContext: ModelContext, squadId: UUID?, cloudSquadId: String?, joinCode: String?, notificationManager: NotificationManager? = nil) {
        self.modelContext = modelContext
        self.currentSquadId = squadId
        self.cloudSquadId = cloudSquadId
        self.joinCode = joinCode
        if let notificationManager = notificationManager {
            self.notificationManager = notificationManager
        }

        // Log configuration for debugging
        DebugLogger.success("Chat configured - squadId: \(squadId?.uuidString ?? "nil"), joinCode: \(joinCode ?? "nil"), cloudId: \(cloudSquadId ?? "nil")", category: "Chat")
        print("[Chat] ✅ Configured with joinCode: \(joinCode ?? "nil")")

        loadMessages()
        Task { await fetchRemoteMessages() }
    }

    /// Check if chat is ready to send/receive messages
    var isReady: Bool {
        currentSquadId != nil && joinCode != nil && !joinCode!.isEmpty
    }

    // MARK: - Message Operations

    func sendMessage(text: String) async {
        guard let squadId = currentSquadId,
              let userId = currentUserId,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DebugLogger.warning("Cannot send - missing squadId or userId", category: "Chat")
            return
        }

        // CRITICAL: Must have joinCode to ensure consistent routing across devices
        guard let routingCode = joinCode, !routingCode.isEmpty else {
            DebugLogger.error("Cannot send - joinCode not set. Chat not properly configured.", category: "Chat")
            self.error = NSError(domain: "Chat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chat not ready. Please wait or rejoin squad."])
            return
        }

        let userIdUUID = UUID(uuidString: userId) ?? UUID()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create local message (delivered immediately since it's local)
        let message = ChatMessage(
            senderId: userIdUUID,
            senderName: currentUserName,
            text: trimmedText,
            squadId: squadId
        )
        message.isDelivered = true
        modelContext?.insert(message)
        do {
            try modelContext?.save()
        } catch {
            DebugLogger.error("Failed to save message locally: \(error)", category: "Chat")
            self.error = error
        }

        messages.append(message)

        // Broadcast via mesh
        let payload = MeshMessagePayload.ChatMessagePayload(
            id: message.id,
            senderId: userIdUUID,
            senderName: currentUserName,
            text: trimmedText,
            squadId: squadId,
            timestamp: message.timestamp
        )

        // Use joinCode ONLY for mesh routing - it's the same on all devices in squad
        // We already validated joinCode exists above
        let routingId = routingCode

        DebugLogger.info("Sending message with routingId: \(routingId)", category: "Chat")

        let meshMessage = MeshMessagePayload(
            type: .chatMessage,
            userId: userId,
            location: nil,
            chat: payload,
            peerId: nil,
            signalStrength: nil,
            squadId: routingId,
            syncData: nil,
            batteryLevel: nil,
            hasService: nil,
            enabled: nil,
            status: nil,
            meetupPin: nil,
            joinCode: routingCode  // Use joinCode for squad filtering
        )

        meshManager.broadcast(meshMessage)

        // Sync to CloudKit
        if let cloudId = cloudSquadId, cloudKit.isAvailable {
            do {
                _ = try await cloudKit.sendMessage(
                    squadId: cloudId,
                    senderId: userId,
                    senderName: currentUserName,
                    text: trimmedText
                )
                message.isSynced = true
                do {
                    try modelContext?.save()
                } catch {
                    DebugLogger.error("Failed to update sync status: \(error)", category: "Chat")
                }
            } catch {
                self.error = error
            }
        }
    }

    func loadMessages() {
        guard let modelContext = modelContext,
              let squadId = currentSquadId else {
            messages = []
            return
        }

        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.squadId == squadId },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            messages = try modelContext.fetch(descriptor)
        } catch {
            self.error = error
        }
    }

    func fetchRemoteMessages() async {
        guard let cloudId = cloudSquadId,
              let squadId = currentSquadId,
              cloudKit.isAvailable else { return }

        do {
            let remoteMessages = try await cloudKit.getMessages(squadId: cloudId)

            for msg in remoteMessages {
                // Skip if we already have this message
                let existingIds = Set(messages.map { $0.id.uuidString })
                guard !existingIds.contains(msg.id) else { continue }

                let message = ChatMessage(
                    id: UUID(uuidString: msg.id) ?? UUID(),
                    senderId: UUID(uuidString: msg.senderId) ?? UUID(),
                    senderName: msg.senderName,
                    text: msg.text,
                    squadId: squadId,
                    timestamp: msg.timestamp,
                    isDelivered: true,
                    isSynced: true
                )

                modelContext?.insert(message)
                messages.append(message)
            }

            messages.sort { $0.timestamp < $1.timestamp }
            do {
                try modelContext?.save()
            } catch {
                DebugLogger.error("Failed to save remote messages: \(error)", category: "Chat")
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Mesh Handling

    private func setupMeshListener() {
        meshManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope, _ in
                self?.handleMeshMessage(envelope)
            }
            .store(in: &cancellables)
    }

    private func handleMeshMessage(_ envelope: Any) {
        guard let meshEnvelope = envelope as? MeshEnvelope else {
            DebugLogger.warning("Received non-MeshEnvelope message", category: "Chat")
            return
        }

        // Log all mesh messages for debugging
        DebugLogger.info("Mesh msg type: \(meshEnvelope.message.type), squadId: \(meshEnvelope.message.squadId ?? "nil")", category: "Chat")

        guard meshEnvelope.message.type == .chatMessage else { return }

        guard let chatPayload = meshEnvelope.message.chat else {
            DebugLogger.warning("Chat message has no payload", category: "Chat")
            return
        }

        guard let squadId = currentSquadId else {
            DebugLogger.warning("No current squad - can't receive messages", category: "Chat")
            return
        }

        // CRITICAL: Use joinCode ONLY for routing - must match sender exactly
        guard let myJoinCode = joinCode, !myJoinCode.isEmpty else {
            DebugLogger.warning("No joinCode set - can't validate incoming messages. Chat not configured.", category: "Chat")
            return
        }

        let messageRoutingId = meshEnvelope.message.squadId ?? ""

        DebugLogger.info("Routing check - mine: \(myJoinCode), msg: \(messageRoutingId)", category: "Chat")

        guard messageRoutingId == myJoinCode else {
            DebugLogger.warning("Squad mismatch - ignoring message (mine: \(myJoinCode), theirs: \(messageRoutingId))", category: "Chat")
            return
        }

        // Skip our own messages
        if let userId = currentUserId,
           chatPayload.senderId.uuidString == userId {
            DebugLogger.info("Skipping own message", category: "Chat")
            return
        }

        // Skip if we already have this message
        let existingIds = Set(messages.map { $0.id })
        guard !existingIds.contains(chatPayload.id) else {
            DebugLogger.info("Already have this message", category: "Chat")
            return
        }

        DebugLogger.success("Received message from \(chatPayload.senderName): \(chatPayload.text.prefix(20))...", category: "Chat")

        let message = ChatMessage(
            id: chatPayload.id,
            senderId: chatPayload.senderId,
            senderName: chatPayload.senderName,
            text: chatPayload.text,
            squadId: squadId,
            timestamp: chatPayload.timestamp,
            isDelivered: true,
            isSynced: false
        )

        modelContext?.insert(message)
        messages.append(message)
        messages.sort { $0.timestamp < $1.timestamp }
        do {
            try modelContext?.save()
        } catch {
            DebugLogger.error("Failed to save mesh message: \(error)", category: "Chat")
        }

        // Send notification if chat is not visible
        DebugLogger.info("Chat visible: \(isChatVisible), notificationManager: \(notificationManager != nil ? "set" : "nil")", category: "Chat")
        if !isChatVisible {
            if let notifMgr = notificationManager {
                Task {
                    await notifMgr.sendNewMessageNotification(
                        senderName: chatPayload.senderName,
                        messageText: chatPayload.text,
                        squadId: squadId.uuidString
                    )
                }
            } else {
                DebugLogger.warning("Cannot send notification - notificationManager is nil", category: "Chat")
            }
        } else {
            DebugLogger.info("Skipping notification - chat is visible", category: "Chat")
        }
    }

    // Call this when chat view appears
    func chatViewAppeared() {
        isChatVisible = true
        DebugLogger.info("Chat view appeared - notifications will be suppressed", category: "Chat")
        notificationManager?.clearChatBadge()
    }

    // Call this when chat view disappears
    func chatViewDisappeared() {
        isChatVisible = false
        DebugLogger.info("Chat view disappeared - notifications will be sent", category: "Chat")
    }
}
