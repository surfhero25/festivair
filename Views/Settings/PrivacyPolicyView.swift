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

                        Text("Last updated: January 26, 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Introduction
                    Text("FestivAir (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our mobile application.")
                        .foregroundStyle(.secondary)

                    // Information We Collect
                    PolicySection(title: "Information We Collect") {
                        VStack(alignment: .leading, spacing: 16) {
                            PolicySubsection(title: "Location Data") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("FestivAir collects your precise location data to enable core functionality:")
                                    BulletPoint("Showing your location to squad members on the map")
                                    BulletPoint("Calculating distance and direction to other squad members")
                                    BulletPoint("Identifying nearby facilities at event venues")
                                    Text("Location data is shared only with members of squads you explicitly join. Location sharing can be paused at any time within the app.")
                                        .padding(.top, 4)
                                }
                            }

                            PolicySubsection(title: "Bluetooth Data") {
                                Text("We use Bluetooth to create a peer-to-peer mesh network that allows the app to function without cellular connectivity. This data is used solely for routing messages between devices and is not stored or transmitted to our servers.")
                            }

                            PolicySubsection(title: "Account Information") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("We collect minimal account information:")
                                    BulletPoint("Display name (chosen by you)")
                                    BulletPoint("Profile photo (optional)")
                                    BulletPoint("Squad memberships")
                                }
                            }

                            PolicySubsection(title: "Usage Data") {
                                Text("We may collect anonymous usage statistics to improve the app, such as feature usage and crash reports. This data cannot be used to identify individual users.")
                            }
                        }
                    }

                    // How We Use Your Information
                    PolicySection(title: "How We Use Your Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("To provide core app functionality (location sharing, messaging, navigation)")
                            BulletPoint("To improve and optimize the app experience")
                            BulletPoint("To send you notifications you've opted into (set time alerts, squad updates)")
                        }
                    }

                    // Data Sharing
                    PolicySection(title: "Data Sharing") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("We do not sell your personal information. Your location is shared only with:")
                            BulletPoint("Members of squads you have joined")
                            BulletPoint("Other FestivAir users via the mesh network (anonymized, for routing purposes only)")
                        }
                    }

                    // Data Retention
                    PolicySection(title: "Data Retention") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("Location data:")
                                    .fontWeight(.medium)
                                Text("Stored locally on your device. Not retained on our servers.")
                            }
                            HStack(alignment: .top) {
                                Text("Chat messages:")
                                    .fontWeight(.medium)
                                Text("Stored locally and synced via iCloud (if enabled). We do not have access to message content.")
                            }
                            HStack(alignment: .top) {
                                Text("Account data:")
                                    .fontWeight(.medium)
                                Text("Retained until you delete your account.")
                            }
                        }
                    }

                    // Your Rights
                    PolicySection(title: "Your Rights") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You can:")
                            BulletPoint("Pause location sharing at any time")
                            BulletPoint("Leave any squad to stop sharing data with its members")
                            BulletPoint("Delete your account and all associated data")
                            BulletPoint("Request a copy of your data")
                        }
                    }

                    // Security
                    PolicySection(title: "Security") {
                        Text("We implement industry-standard security measures including encryption in transit and at rest. Mesh network communications are encrypted end-to-end.")
                    }

                    // Children's Privacy
                    PolicySection(title: "Children's Privacy") {
                        Text("FestivAir is not intended for children under 13. We do not knowingly collect information from children under 13.")
                    }

                    // Changes
                    PolicySection(title: "Changes to This Policy") {
                        Text("We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the \"Last updated\" date.")
                    }

                    // Contact
                    PolicySection(title: "Contact Us") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you have questions about this Privacy Policy, please contact us at:")
                            Text("privacy@festivair.app")
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
