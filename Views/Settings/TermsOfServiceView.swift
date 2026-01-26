import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terms of Service")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Last updated: January 25, 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Agreement
                    TermsSection(title: "Agreement to Terms") {
                        Text("By downloading, installing, or using FestivAir, you agree to be bound by these Terms of Service. If you do not agree to these terms, do not use the app.")
                    }

                    // Use of Service
                    TermsSection(title: "Use of the Service") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FestivAir provides festival coordination tools including:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Location sharing with squad members")
                                TermsBullet("Offline mesh networking for areas without cell service")
                                TermsBullet("Festival schedules and set time tracking")
                                TermsBullet("In-app messaging with squad members")
                                TermsBullet("Meetup pin coordination")
                            }
                        }
                    }

                    // Eligibility
                    TermsSection(title: "Eligibility") {
                        Text("You must be at least 13 years old to use FestivAir. By using the app, you represent that you meet this age requirement. Some features may require you to be 18 or older, particularly those related to events at venues serving alcohol.")
                    }

                    // Account
                    TermsSection(title: "Your Account") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You are responsible for maintaining the security of your device and account. You agree to:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Provide accurate profile information")
                                TermsBullet("Not impersonate other users or public figures")
                                TermsBullet("Keep your device secure")
                                TermsBullet("Notify us of any unauthorized account access")
                            }
                        }
                    }

                    // Acceptable Use
                    TermsSection(title: "Acceptable Use") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You agree NOT to:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Use the app for illegal activities")
                                TermsBullet("Harass, threaten, or harm other users")
                                TermsBullet("Share your location with malicious intent")
                                TermsBullet("Attempt to track users without their consent")
                                TermsBullet("Reverse engineer or tamper with the app")
                                TermsBullet("Spam or flood the mesh network")
                                TermsBullet("Interfere with other users' enjoyment of the service")
                            }
                        }
                    }

                    // Location Sharing
                    TermsSection(title: "Location Sharing") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FestivAir's core functionality involves sharing your location with squad members. By using the app, you understand and agree that:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Your location is visible to members of squads you join")
                                TermsBullet("Location data may be relayed through other devices in the mesh network")
                                TermsBullet("You can disable location sharing at any time through device settings")
                                TermsBullet("You are responsible for managing who you share your location with by choosing which squads to join")
                            }
                        }
                    }

                    // Mesh Network
                    TermsSection(title: "Mesh Network Participation") {
                        Text("When using FestivAir, your device may participate in our mesh network by relaying encrypted messages between other users. This helps maintain connectivity in crowded areas or places without cell service. Relayed messages are encrypted and cannot be read by your device.")
                    }

                    // Premium Services
                    TermsSection(title: "Premium Services") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FestivAir offers premium subscription tiers with additional features:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Basic: Larger squad sizes, profile customization")
                                TermsBullet("VIP: Maximum features, priority support, exclusive badges")
                            }

                            Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage subscriptions in your App Store account settings.")
                                .padding(.top, 8)
                        }
                    }

                    // Content
                    TermsSection(title: "User Content") {
                        Text("You retain ownership of content you create (profile photos, messages, etc.) but grant FestivAir a license to use, store, and transmit this content as necessary to provide the service. You are responsible for ensuring you have the right to share any content you upload.")
                    }

                    // Disclaimers
                    TermsSection(title: "Disclaimers") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("THE SERVICE IS PROVIDED \"AS IS\" WITHOUT WARRANTIES OF ANY KIND.")
                                .fontWeight(.medium)

                            Text("We do not guarantee:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Continuous, uninterrupted service")
                                TermsBullet("Accuracy of location data")
                                TermsBullet("Availability of mesh network connectivity")
                                TermsBullet("Compatibility with all festivals or venues")
                            }

                            Text("Always have a backup plan for meeting your group at festivals.")
                                .italic()
                                .padding(.top, 4)
                        }
                    }

                    // Limitation of Liability
                    TermsSection(title: "Limitation of Liability") {
                        Text("To the maximum extent permitted by law, FestivAir shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the service, including but not limited to: getting separated from your group, missing performances, device battery drain, or any personal injury.")
                    }

                    // Safety
                    TermsSection(title: "Safety") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("While FestivAir helps you stay connected, your safety is your responsibility:")

                            VStack(alignment: .leading, spacing: 8) {
                                TermsBullet("Stay aware of your surroundings")
                                TermsBullet("Don't rely solely on the app for finding your group")
                                TermsBullet("Establish meeting points as backup")
                                TermsBullet("Keep your phone charged")
                                TermsBullet("Follow all festival rules and regulations")
                            }
                        }
                    }

                    // Termination
                    TermsSection(title: "Termination") {
                        Text("We may terminate or suspend your access to the service at any time for violations of these terms or for any other reason. You may stop using the service at any time by deleting the app.")
                    }

                    // Changes
                    TermsSection(title: "Changes to Terms") {
                        Text("We may modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms. We will notify you of material changes through the app.")
                    }

                    // Governing Law
                    TermsSection(title: "Governing Law") {
                        Text("These terms are governed by the laws of the State of California, United States, without regard to conflict of law principles.")
                    }

                    // Contact
                    TermsSection(title: "Contact Us") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you have questions about these Terms, please contact us:")
                            Text("Email: legal@festivair.app")
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

private struct TermsSection<Content: View>: View {
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

private struct TermsBullet: View {
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
    TermsOfServiceView()
}
