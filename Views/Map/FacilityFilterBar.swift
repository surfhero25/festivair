import SwiftUI

/// Horizontal scrolling filter bar for facility types
struct FacilityFilterBar: View {
    @Binding var selectedTypes: Set<FacilityType>
    var onFilterChange: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All/None toggle
                Button {
                    if selectedTypes.isEmpty {
                        selectedTypes = Set(FacilityType.allCases)
                    } else {
                        selectedTypes.removeAll()
                    }
                    onFilterChange?()
                } label: {
                    Text(selectedTypes.isEmpty ? "Show All" : "Hide All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }

                Divider()
                    .frame(height: 24)

                // Quick access filters
                ForEach(FacilityType.quickAccess, id: \.self) { type in
                    FacilityFilterChip(
                        type: type,
                        isSelected: selectedTypes.contains(type)
                    ) {
                        toggleType(type)
                    }
                }

                // More button for remaining types
                Menu {
                    ForEach(FacilityType.allCases.filter { !FacilityType.quickAccess.contains($0) }, id: \.self) { type in
                        Button {
                            toggleType(type)
                        } label: {
                            HStack {
                                Text(type.emoji)
                                Text(type.displayName)
                                Spacer()
                                if selectedTypes.contains(type) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                        Text("More")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func toggleType(_ type: FacilityType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
        onFilterChange?()
    }
}

// MARK: - Filter Chip
struct FacilityFilterChip: View {
    let type: FacilityType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(type.emoji)
                    .font(.caption)
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? type.color.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? type.color : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? type.color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        FacilityFilterBar(selectedTypes: .constant(Set([.water, .bathroom])))

        FacilityFilterBar(selectedTypes: .constant(Set()))
    }
}
