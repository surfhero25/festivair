import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let squadCode: String
    let squadName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Share this QR code with your squad")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                // QR Code
                if let qrImage = generateQRCode(from: "festivair://squad/\(squadCode)") {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding(20)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 10)
                }

                // Squad info
                VStack(spacing: 8) {
                    Text(squadName)
                        .font(.title2.bold())

                    Text("Join Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(squadCode)
                        .font(.system(.title, design: .monospaced).bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                // Share button
                ShareLink(
                    item: "Join my squad on FestivAir! Code: \(squadCode)\n\nDownload: https://festivair.app",
                    subject: Text("Join \(squadName) on FestivAir"),
                    message: Text("Use code \(squadCode) to join my squad!")
                ) {
                    Label("Share Code", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)

                // Copy button
                Button {
                    UIPasteboard.general.string = squadCode
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                        .font(.headline)
                        .foregroundStyle(.purple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Invite to Squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - UIKit Bridge
#if canImport(UIKit)
import UIKit

extension UIPasteboard {
    // Extension already available in UIKit
}
#endif

#Preview {
    QRCodeView(squadCode: "ABC123", squadName: "Bass Drop Crew")
}
