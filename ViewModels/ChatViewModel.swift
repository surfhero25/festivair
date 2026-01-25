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
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Init
    init(cloudKit: CloudKitService = .shared, meshManager: MeshNetworkManager) {
        self.cloudKit = cloudKit
        self.meshManager = meshManager
        setupMeshListener()
    }

    func configure(modelContext: ModelContext, squadId: UUID?, cloudSquadId: String?) {
        self.modelContext = modelContext
        self.currentSquadId = squadId
        self.cloudSquadId = cloudSquadId
        loadMessages()
        Task { await fetchRemoteMessages() }
    }

    // MARK: - Message Operations

    func sendMessage(text: String) async {
        guard let squadId = currentSquadId,
              let userId = currentUserId,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userIdUUID = UUID(uuidString: userId) ?? UUID()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create local message
        let message = ChatMessage(
            senderId: userIdUUID,
            senderName: currentUserName,
            text: trimmedText,
            squadId: squadId
        )
        modelContext?.insert(message)
        try? modelContext?.save()

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

        let meshMessage = MeshMessagePayload(
            type: .chatMessage,
            userId: userId,
            location: nil,
            chat: payload,
            peerId: nil,
            signalStrength: nil,
            squadId: squadId.uuidString,
            syncData: nil,
            batteryLevel: nil,
            hasService: nil,
            enabled: nil
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
                try? modelContext?.save()
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
            try? modelContext?.save()
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
        guard let meshEnvelope = envelope as? MeshEnvelope,
              meshEnvelope.message.type == .chatMessage,
              let chatPayload = meshEnvelope.message.chat,
              let squadId = currentSquadId,
              chatPayload.squadId == squadId else { return }

        // Skip our own messages
        if let userId = currentUserId,
           chatPayload.senderId.uuidString == userId {
            return
        }

        // Skip if we already have this message
        let existingIds = Set(messages.map { $0.id })
        guard !existingIds.contains(chatPayload.id) else { return }

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
        try? modelContext?.save()
    }
}
