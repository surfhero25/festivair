import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Last updated: January 25, 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Introduction
                    PolicySection(title: "Introduction") {
                        Text("FestivAir (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.")
                    }

                    // Information We Collect
                    PolicySection(title: "Information We Collect") {
                        VStack(alignment: .leading, spacing: 12) {
                            PolicySubsection(title: "Location Data") {
                                Text("We collect your device's location to show your position to squad members on the map. Location data is shared only with members of squads you've joined. You can disable location sharing in your device settings at any time.")
                            }

                            PolicySubsection(title: "Profile Information") {
                                Text("We collect information you provide when creating your profile, including your display name, profile photo, and emoji avatar. This information is visible to other users in your squads.")
                            }

                            PolicySubsection(title: "Device Information") {
                                Text("We collect device identifiers and battery level information to facilitate mesh networking and gateway election features.")
                            }

                            PolicySubsection(title: "Usage Data") {
                                Text("We collect anonymous usage statistics to improve the app experience, including feature usage patterns and crash reports.")
                            }
                        }
                    }

                    // How We Use Your Information
                    PolicySection(title: "How We Use Your Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("Enable location sharing within your squads")
                            BulletPoint("Facilitate peer-to-peer mesh networking")
                            BulletPoint("Provide festival schedule and map features")
                            BulletPoint("Send notifications about set times and squad activity")
                            BulletPoint("Improve and optimize the app")
                            BulletPoint("Provide customer support")
                        }
                    }

                    // Data Sharing
                    PolicySection(title: "Data Sharing") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("We do not sell your personal information. Your data may be shared in the following circumstances:")

                            BulletPoint("With squad members: Your location and profile are visible to members of squads you join")
                            BulletPoint("Via mesh network: Location data may be relayed through nearby devices to reach squad members")
                            BulletPoint("Service providers: We use Apple CloudKit for cloud sync, which is subject to Apple's privacy policy")
                            BulletPoint("Legal requirements: We may disclose information when required by law")
                        }
                    }

                    // Mesh Networking
                    PolicySection(title: "Mesh Networking Privacy") {
                        Text("FestivAir uses Bluetooth and local WiFi to create a mesh network for offline communication. Your device may relay messages from other users, but relayed messages are encrypted and cannot be read by relay devices. Only the intended recipients can decrypt messages.")
                    }

                    // Data Retention
                    PolicySection(title: "Data Retention") {
                        Text("Location data is kept for 24 hours to enable offline sync. Chat messages are retained for 7 days. You can delete your account and associated data at any time through the app settings.")
                    }

                    // Your Rights
                    PolicySection(title: "Your Rights") {
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("Access your personal data")
                            BulletPoint("Request correction of inaccurate data")
                            BulletPoint("Request deletion of your data")
                            BulletPoint("Opt out of location sharing")
                            BulletPoint("Disable notifications")
                        }
                    }

                    // Security
                    PolicySection(title: "Security") {
                        Text("We implement industry-standard security measures to protect your information. Data transmitted via mesh network is encrypted end-to-end. Cloud-synced data is protected by Apple's CloudKit security infrastructure.")
                    }

                    // Children's Privacy
                    PolicySection(title: "Children's Privacy") {
                        Text("FestivAir is not intended for users under 13 years of age. We do not knowingly collect personal information from children under 13. If you believe we have collected information from a child, please contact us.")
                    }

                    // Changes
                    PolicySection(title: "Changes to This Policy") {
                        Text("We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy in the app and updating the \"Last updated\" date.")
                    }

                    // Contact
                    PolicySection(title: "Contact Us") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you have questions about this Privacy Policy, please contact us:")
                            Text("Email: privacy@festivair.app")
                                .foregroundStyle(.purple)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
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
}

// MARK: - Helper Views

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            content
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PolicySubsection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
    }
}

private struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
