import SwiftUI

/// View for selecting and setting user status
struct StatusPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var selectedPreset: StatusPreset?
    @State private var customText = ""
    @State private var showCustomInput = false
    @FocusState private var isCustomFocused: Bool

    var onStatusSet: ((UserStatus) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current status
                    if let current = currentStatus, current.isActive {
                        CurrentStatusSection(status: current) {
                            clearStatus()
                        }
                    }

                    // Preset categories
                    ForEach(StatusCategory.allCases, id: \.self) { category in
                        CategorySection(
                            category: category,
                            selectedPreset: selectedPreset
                        ) { preset in
                            selectPreset(preset)
                        }
                    }

                    // Custom status
                    CustomStatusSection(
                        customText: $customText,
                        showInput: $showCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        setCustomStatus()
                    }
                }
                .padding()
            }
            .navigationTitle("Set Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Current User Status

    private var currentStatus: UserStatus? {
        // This would come from AppState or UserDefaults
        UserDefaults.standard.codable(forKey: "FestivAir.CurrentUserStatus")
    }

    // MARK: - Actions

    private func selectPreset(_ preset: StatusPreset) {
        Haptics.selection()
        selectedPreset = preset

        let status = UserStatus.preset(preset, expiresIn: 3600) // 1 hour default
        saveAndBroadcast(status)
        dismiss()
    }

    private func setCustomStatus() {
        guard !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Haptics.selection()
        let status = UserStatus.custom(customText, expiresIn: 3600)
        saveAndBroadcast(status)
        dismiss()
    }

    private func clearStatus() {
        Haptics.light()
        let status = UserStatus.cleared()
        saveAndBroadcast(status)
        dismiss() // Dismiss after clearing (consistent with selecting preset)
    }

    private func saveAndBroadcast(_ status: UserStatus) {
        // Save locally first (always works)
        UserDefaults.standard.setCodable(status, forKey: "FestivAir.CurrentUserStatus")

        // Broadcast to squad
        if let userId = KeychainHelper.currentUserId,
           let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) {

            // Check if we have mesh peers
            let hasPeers = !appState.meshManager.connectedPeers.isEmpty
            if !hasPeers {
                #if DEBUG
                print("[Status] No mesh peers connected - status saved locally only")
                #endif
                // Status is saved locally, will be visible when peers connect
            }

            // Get current squad join code for filtering
            let joinCode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)

            let message = MeshMessagePayload.statusUpdate(userId: userId, displayName: displayName, status: status, joinCode: joinCode)
            appState.meshManager.broadcast(message)
        } else {
            #if DEBUG
            print("[Status] Missing user ID or display name - cannot broadcast")
            #endif
        }

        onStatusSet?(status)
    }
}

// MARK: - Current Status Section
private struct CurrentStatusSection: View {
    let status: UserStatus
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                StatusDetailView(status: status)

                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Category Section
private struct CategorySection: View {
    let category: StatusCategory
    let selectedPreset: StatusPreset?
    let onSelect: (StatusPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(category.presets, id: \.self) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: selectedPreset == preset,
                        onTap: { onSelect(preset) }
                    )
                }
            }
        }
    }
}

// MARK: - Preset Button
private struct PresetButton: View {
    let preset: StatusPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.body)
                    .frame(width: 20)

                Text(preset.displayText)
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? categoryColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? categoryColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? categoryColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch preset.category {
        case .moving: return .blue
        case .activity: return .orange
        case .needs: return .red
        case .squad: return .purple
        case .waiting: return .gray
        }
    }
}

// MARK: - Custom Status Section
private struct CustomStatusSection: View {
    @Binding var customText: String
    @Binding var showInput: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showInput {
                HStack {
                    TextField("What's happening?", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .focused(isFocused)
                        .submitLabel(.done)
                        .onSubmit(onSubmit)

                    Button("Set") {
                        onSubmit()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    showInput = true
                    isFocused.wrappedValue = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Write custom status...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    StatusPickerView()
        .environmentObject(AppState())
}
