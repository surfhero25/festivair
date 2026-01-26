import SwiftUI
import CoreLocation

/// Sheet for creating a new meetup pin
struct MeetupPinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let coordinate: CLLocationCoordinate2D
    let onPinCreated: (MeetupPin) -> Void

    @State private var selectedPreset: MeetupPinPreset = .meetHere
    @State private var customName = ""
    @State private var useCustomName = false
    @State private var expirationMinutes = 30
    @FocusState private var isCustomFocused: Bool

    private let expirationOptions = [15, 30, 60, 120] // minutes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Location preview
                    LocationPreviewCard(coordinate: coordinate)

                    // Pin name section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pin Message")
                            .font(.headline)

                        // Preset options
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                            ForEach(MeetupPinPreset.allCases, id: \.self) { preset in
                                PresetPinButton(
                                    preset: preset,
                                    isSelected: selectedPreset == preset && !useCustomName
                                ) {
                                    selectedPreset = preset
                                    useCustomName = false
                                }
                            }
                        }

                        // Custom name toggle
                        Divider()

                        Toggle(isOn: $useCustomName) {
                            Text("Custom message")
                        }
                        .onChange(of: useCustomName) { _, isOn in
                            if isOn {
                                isCustomFocused = true
                            }
                        }

                        if useCustomName {
                            TextField("Enter message", text: $customName)
                                .textFieldStyle(.roundedBorder)
                                .focused($isCustomFocused)
                        }
                    }

                    // Expiration section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Expires After")
                            .font(.headline)

                        Picker("Duration", selection: $expirationMinutes) {
                            ForEach(expirationOptions, id: \.self) { minutes in
                                Text(formatDuration(minutes)).tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Drop Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Drop") {
                        createPin()
                    }
                    .fontWeight(.semibold)
                    .disabled(useCustomName && customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private var pinName: String {
        if useCustomName {
            return customName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedPreset.rawValue
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        return "\(hours) hr"
    }

    private func createPin() {
        guard let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId),
              let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) else {
            return
        }

        Haptics.success()

        let pin = MeetupPin.create(
            at: coordinate,
            name: pinName,
            creatorId: userId,
            creatorName: displayName,
            expiresIn: TimeInterval(expirationMinutes * 60)
        )

        onPinCreated(pin)
        dismiss()
    }
}

// MARK: - Location Preview Card
private struct LocationPreviewCard: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pin Location")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preset Pin Button
private struct PresetPinButton: View {
    let preset: MeetupPinPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(preset.emoji)
                Text(preset.rawValue)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .purple : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MeetupPinSheet(
        coordinate: CLLocationCoordinate2D(latitude: 36.2697, longitude: -115.0078)
    ) { pin in
        print("Created pin: \(pin.name)")
    }
    .environmentObject(AppState())
}
