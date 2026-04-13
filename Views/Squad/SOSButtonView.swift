import SwiftUI

/// SOS emergency button — long press to activate, tap to cancel when active.
struct SOSButtonView: View {
    @ObservedObject var sosManager: SOSManager
    @State private var isLongPressing = false
    @State private var longPressProgress: CGFloat = 0

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

                    Image(systemName: sosManager.isSOSActive ? "sos" : "sos")
                        .font(.title3)
                        .fontWeight(.semibold)
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
                        sosManager.activate()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.warning)
                    }
                }
        )
        .onChange(of: isLongPressing) { _, newValue in
            if !newValue {
                withAnimation { longPressProgress = 0 }
            }
        }
    }
}
