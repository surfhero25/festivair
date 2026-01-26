import SwiftUI
import AVFoundation
import VisionKit

struct JoinSquadView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var squadCode = ""
    @State private var squadName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    private var squadViewModel: SquadViewModel {
        appState.squadViewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Mode", selection: $selectedTab) {
                    Text("Join Squad").tag(0)
                    Text("Create Squad").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    JoinSquadContent(
                        squadCode: $squadCode,
                        isLoading: isLoading,
                        onJoin: joinSquad,
                        onScan: handleScan
                    )
                } else {
                    CreateSquadContent(
                        squadName: $squadName,
                        isLoading: isLoading,
                        onCreate: createSquad
                    )
                }
            }
            .navigationTitle(selectedTab == 0 ? "Join Squad" : "Create Squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func joinSquad() {
        guard squadCode.count == 6 else {
            errorMessage = "Please enter a 6-character code"
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                try await squadViewModel.joinSquad(code: squadCode.uppercased())
                await MainActor.run {
                    Haptics.success()
                    isLoading = false
                    dismiss()
                }
            } catch let error as SquadError {
                await MainActor.run {
                    Haptics.error()
                    isLoading = false
                    errorMessage = error.errorDescription ?? "Failed to join squad"
                    showError = true
                }
            } catch {
                await MainActor.run {
                    Haptics.error()
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let scan):
            if scan.string.hasPrefix("festivair://squad/") {
                let code = scan.string.replacingOccurrences(of: "festivair://squad/", with: "")
                squadCode = code
                joinSquad()
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func createSquad() {
        guard !squadName.isEmpty else {
            errorMessage = "Please enter a squad name"
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                try await squadViewModel.createSquad(name: squadName)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch let error as SquadError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.errorDescription ?? "Failed to create squad"
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Join Squad Content
struct JoinSquadContent: View {
    @Binding var squadCode: String
    let isLoading: Bool
    let onJoin: () -> Void
    let onScan: (Result<ScanResult, ScanError>) -> Void
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 24) {
            // QR Scanner button
            Button {
                showScanner = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 60))
                    Text("Scan QR Code")
                        .font(.headline)
                }
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal)

            // Divider
            HStack {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(height: 1)
                Text("or enter code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal)

            // Code input
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    CodeDigitView(
                        digit: index < squadCode.count ? String(squadCode[squadCode.index(squadCode.startIndex, offsetBy: index)]) : ""
                    )
                }
            }
            .padding(.horizontal)

            // Hidden text field for input
            TextField("", text: $squadCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: squadCode) { _, newValue in
                    squadCode = String(newValue.prefix(6)).uppercased()
                }

            Spacer()

            // Join button
            Button(action: onJoin) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Join Squad")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(squadCode.count == 6 && !isLoading ? .purple : .gray)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(squadCode.count != 6 || isLoading)
            .padding()
        }
        .sheet(isPresented: $showScanner) {
            CodeScannerView(codeTypes: [.qr], completion: onScan)
        }
    }
}

// MARK: - Code Digit View
struct CodeDigitView: View {
    let digit: String

    var body: some View {
        Text(digit.isEmpty ? " " : digit)
            .font(.title.monospaced())
            .frame(width: 44, height: 56)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.purple.opacity(digit.isEmpty ? 0.3 : 1), lineWidth: 2)
            )
    }
}

// MARK: - Create Squad Content
struct CreateSquadContent: View {
    @Binding var squadName: String
    let isLoading: Bool
    let onCreate: () -> Void
    @FocusState private var isNameFieldFocused: Bool
    @State private var previewCode: String = ""

    var body: some View {
        VStack(spacing: 24) {
            // Squad name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Squad Name")
                    .font(.headline)

                TextField("e.g. Bass Drop Crew", text: $squadName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if !squadName.isEmpty && !isLoading {
                            onCreate()
                        }
                    }
            }
            .padding()

            // Preview code
            VStack(spacing: 8) {
                Text("Your join code will be:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(previewCode)
                    .font(.title.monospaced().bold())
                    .foregroundStyle(.purple)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()

            // Create button
            Button(action: onCreate) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Create Squad")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(!squadName.isEmpty && !isLoading ? .purple : .gray)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(squadName.isEmpty || isLoading)
            .padding()
        }
        .onAppear {
            // Generate code once when view appears
            previewCode = Squad.generateJoinCode()
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            isNameFieldFocused = false
        }
    }
}

// MARK: - QR Scanner Types
struct ScanResult {
    let string: String
}

enum ScanError: Error, LocalizedError {
    case badInput
    case permissionDenied
    case notSupported

    var errorDescription: String? {
        switch self {
        case .badInput:
            return "Could not read QR code"
        case .permissionDenied:
            return "Camera permission denied"
        case .notSupported:
            return "QR scanning not supported on this device"
        }
    }
}

enum CodeType {
    case qr
}

// MARK: - QR Code Scanner using VisionKit
struct CodeScannerView: View {
    let codeTypes: [CodeType]
    let completion: (Result<ScanResult, ScanError>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(completion: { result in
                completion(result)
                dismiss()
            })
            .ignoresSafeArea()
        } else {
            // Fallback for unsupported devices or simulator
            VStack(spacing: 20) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)

                Text("QR Scanner Unavailable")
                    .font(.title2)

                Text("QR scanning requires a device with a camera")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Manual code entry reminder
                Button("Enter Code Manually") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                #if DEBUG
                // Debug: Simulate scan for testing
                Button("Simulate Scan (Debug)") {
                    completion(.success(ScanResult(string: "festivair://squad/TEST99")))
                    dismiss()
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding()
        }
    }
}

// MARK: - DataScanner UIKit Wrapper
struct DataScannerRepresentable: UIViewControllerRepresentable {
    let completion: (Result<ScanResult, ScanError>) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let completion: (Result<ScanResult, ScanError>) -> Void
        private var hasReported = false

        init(completion: @escaping (Result<ScanResult, ScanError>) -> Void) {
            self.completion = completion
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !hasReported else { return }

            switch item {
            case .barcode(let barcode):
                if let payload = barcode.payloadStringValue {
                    hasReported = true
                    dataScanner.stopScanning()
                    completion(.success(ScanResult(string: payload)))
                }
            default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReported else { return }

            // Auto-capture first QR code found
            for item in addedItems {
                switch item {
                case .barcode(let barcode):
                    if let payload = barcode.payloadStringValue {
                        hasReported = true
                        dataScanner.stopScanning()
                        completion(.success(ScanResult(string: payload)))
                        return
                    }
                default:
                    break
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !hasReported else { return }
            hasReported = true
            completion(.failure(.notSupported))
        }
    }
}

#Preview {
    JoinSquadView()
}
