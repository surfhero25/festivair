import SwiftUI

/// Map annotation for a cluster of nearby squad members.
struct ClusterAnnotationView: View {
    let memberCount: Int
    let memberEmojis: [String]
    let isNavigatingTo: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Outer ring
                Circle()
                    .fill(.purple.opacity(0.2))
                    .frame(width: 52, height: 52)

                // Inner circle with count
                Circle()
                    .fill(.purple)
                    .frame(width: 40, height: 40)

                // Show emojis if 3 or fewer, otherwise show count
                if memberEmojis.count <= 3 {
                    HStack(spacing: -2) {
                        ForEach(memberEmojis.prefix(3), id: \.self) { emoji in
                            Text(emoji)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("\(memberCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                // Navigation pulse
                if isNavigatingTo {
                    Circle()
                        .stroke(.purple, lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .scaleEffect(isNavigatingTo ? 1.4 : 1.0)
                        .opacity(isNavigatingTo ? 0 : 1)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isNavigatingTo)
                }
            }

            Text("Squad")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}
