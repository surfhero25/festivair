import SwiftUI

/// Map annotation for a stale (not recently updated) squad member location.
struct StaleAnnotationView: View {
    let emoji: String
    let displayName: String
    let ageText: String  // "5 min ago"
    let opacity: Double  // 0.4 for stale, 0.0 for expired

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 40, height: 40)

                Text(emoji)
                    .font(.title3)
            }
            .opacity(opacity)

            VStack(spacing: 0) {
                Text(displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(ageText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .opacity(opacity)
        }
    }
}
