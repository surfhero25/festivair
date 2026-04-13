import SwiftUI

/// SOS emergency button — long press fills ring, then confirmation alert before activating.
struct SOSButtonView: View {
    @ObservedObject var sosManager: SOSManager
    @State private var isLongPressing = false
    @State private var longPressProgress: CGFloat = 0
    @State private var showConfirmation = false

    var body: some View {
        Button {
            if sosManager.isSOSActive && sosManager.sosActiveMember == nil {
                sosManager.deactivate()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(sosManager.isSOSActive ? Color.red : Color.red.opacity(0.15))
                        .frame(width: 56, height: 56)

                    // Progress ring for long press
                    if isLongPressing {
                        Circle()
                            .trim(from: 0, to: longPressProgress)
                            .stroke(Color.red, lineWidth: 3)
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                    }

                    Text("SOS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(sosManager.isSOSActive ? .white : .red)
                }

                Text(sosManager.isSOSActive ? "Cancel" : "SOS")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(sosManager.isSOSActive ? .red : .secondary)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 2.0)
                .onChanged { _ in
                    guard !sosManager.isSOSActive else { return }
                    isLongPressing = true
                    withAnimation(.linear(duration: 2.0)) {
                        longPressProgress = 1.0
                    }
                }
                .onEnded { _ in
                    isLongPressing = false
                    longPressProgress = 0
                    if !sosManager.isSOSActive {
                        // Show confirmation instead of activating directly
                        showConfirmation = true
                    }
                }
        )
        .onChange(of: isLongPressing) { _, newValue in
            if !newValue {
                withAnimation { longPressProgress = 0 }
            }
        }
        .alert("Activate SOS?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Send SOS", role: .destructive) {
                sosManager.activate()
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        } message: {
            Text("This will alert all squad members with your live location. Use only for real emergencies.")
        }
    }
}
