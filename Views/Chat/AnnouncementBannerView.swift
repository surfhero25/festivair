import SwiftUI

/// Pinned squad announcement banner displayed at the top of chat.
struct AnnouncementBannerView: View {
    let senderName: String
    let text: String
    let hasPin: Bool
    let onTapPin: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "megaphone.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)

                Text(senderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if hasPin {
                Button {
                    onTapPin?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                        Text("View on Map")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
