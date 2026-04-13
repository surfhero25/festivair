import SwiftUI

/// V2 chat input bar with urgent/regular message toggle.
struct ChatInputBarV2: View {
    @Binding var messageText: String
    let isUrgentMode: Bool
    let urgentRemaining: Int
    let canSendUrgent: Bool
    let onSend: () -> Void
    let onToggleUrgent: () -> Void

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Urgent mode indicator
            if isUrgentMode {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text("Urgent — delivers instantly (\(urgentRemaining) remaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                // Urgent toggle
                Button(action: onToggleUrgent) {
                    Image(systemName: isUrgentMode ? "bolt.fill" : "bolt")
                        .font(.body)
                        .foregroundStyle(isUrgentMode ? .red : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canSendUrgent && !isUrgentMode)

                // Text field
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Send button
                Button(action: onSend) {
                    Image(systemName: isUrgentMode ? "arrow.up.circle.fill" : "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? (isUrgentMode ? .red : .purple) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: isUrgentMode)
    }
}
