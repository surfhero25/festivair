import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    private var chatViewModel: ChatViewModel {
        appState.chatViewModel
    }

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    private var currentUserEmoji: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if chatViewModel.isLoading {
                    ProgressView("Loading messages...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chatViewModel.messages.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No messages yet")
                            .font(.headline)
                        Text("Start a conversation with your squad")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(chatViewModel.messages, id: \.id) { message in
                                    ChatBubble(
                                        message: message,
                                        isMe: message.senderId.uuidString == currentUserId,
                                        currentUserEmoji: currentUserEmoji
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: chatViewModel.messages.count) { _, _ in
                            if let lastMessage = chatViewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            if let lastMessage = chatViewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Error banner
                if let error = chatViewModel.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.red)
                        .clipShape(Capsule())
                        .padding(.bottom, 4)
                }

                // Input bar
                ChatInputBar(
                    text: $messageText,
                    isFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
            .navigationTitle("Squad Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionIndicator()
                }
            }
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Haptics.light()
        let text = messageText
        messageText = ""

        Task {
            await chatViewModel.sendMessage(text: text)
        }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage
    let isMe: Bool
    let currentUserEmoji: String // Kept for backward compatibility but not used

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe {
                Spacer(minLength: 60)
            } else {
                // Profile photo with initials fallback
                ProfilePhotoView(
                    assetId: nil, // Would come from user lookup
                    displayName: message.senderName,
                    size: 32,
                    isOnline: true
                )
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? .purple : .secondary.opacity(0.2))
                    .foregroundStyle(isMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isMe {
                        if message.isSynced {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else if message.isDelivered {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !isMe {
                Spacer(minLength: 60)
            }
        }
    }

    private var formattedTime: String {
        Formatters.time.string(from: message.timestamp)
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused(isFocused)
                .lineLimit(1...4)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(text.isEmpty ? .secondary : .purple)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Send message")
            .accessibilityHint(text.isEmpty ? "Enter a message first" : "Double tap to send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Connection Indicator
struct ConnectionIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(appState.meshManager.connectedPeers.isEmpty ? .orange : .green)
                .frame(width: 8, height: 8)

            if appState.gatewayManager.hasInternetAccess {
                Image(systemName: "wifi")
                    .font(.caption)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}
