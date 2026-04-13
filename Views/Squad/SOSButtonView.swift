import SwiftUI

/// SOS emergency button — hold for 3 seconds to fill ring, then confirmation alert.
/// Uses DragGesture(minimumDistance: 0) for proper finger-down/up tracking.
struct SOSButtonView: View {
    @ObservedObject var sosManager: SOSManager
    @State private var isPressing = false
    @State private var pressStartTime: Date?
    @State private var holdProgress: CGFloat = 0
    @State private var showConfirmation = false
    @State private var holdTimer: Timer?

    private let holdDuration: TimeInterval = 3.0  // 3 seconds to fill

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .fill(sosManager.isSOSActive ? Color.red : Color.red.opacity(0.15))
                    .frame(width: 56, height: 56)

                // Progress ring — only visible while holding
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Text("SOS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(sosManager.isSOSActive ? .white : .red)
            }

            Text(sosManager.isSOSActive ? "Cancel" : "Hold")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(sosManager.isSOSActive ? .red : .secondary)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if sosManager.isSOSActive {
                        return  // Tap to cancel handled separately
                    }
                    guard !isPressing else { return }  // Already tracking
                    startHold()
                }
                .onEnded { _ in
                    if sosManager.isSOSActive && sosManager.sosActiveMember == nil {
                        // Tap to cancel active SOS
                        sosManager.deactivate()
                        return
                    }
                    cancelHold()
                }
        )
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

    // MARK: - Hold Logic

    private func startHold() {
        isPressing = true
        pressStartTime = Date()
        holdProgress = 0

        // Update progress every 50ms (smooth animation)
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                guard let start = pressStartTime, isPressing else {
                    cancelHold()
                    return
                }

                let elapsed = Date().timeIntervalSince(start)
                let progress = min(elapsed / holdDuration, 1.0)

                withAnimation(.linear(duration: 0.05)) {
                    holdProgress = CGFloat(progress)
                }

                if progress >= 1.0 {
                    // Hold complete — show confirmation
                    holdTimer?.invalidate()
                    holdTimer = nil
                    isPressing = false
                    holdProgress = 0
                    showConfirmation = true

                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                }
            }
        }
    }

    private func cancelHold() {
        isPressing = false
        pressStartTime = nil
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }
}
