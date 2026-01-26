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

                        Text("Last updated: January 26, 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Introduction
                    Text("Welcome to FestivAir. By downloading, installing, or using our application, you agree to be bound by these Terms of Service (\"Terms\"). Please read them carefully.")
                        .foregroundStyle(.secondary)

                    // 1. Acceptance of Terms
                    TermsSection(number: 1, title: "Acceptance of Terms") {
                        Text("By accessing or using FestivAir, you agree to these Terms and our Privacy Policy. If you do not agree to these Terms, do not use the app.")
                    }

                    // 2. Eligibility
                    TermsSection(number: 2, title: "Eligibility") {
                        Text("You must be at least 13 years old to use FestivAir. By using the app, you represent that you meet this age requirement. Users under 18 should review these Terms with a parent or guardian.")
                    }

                    // 3. Account Registration
                    TermsSection(number: 3, title: "Account Registration") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To use certain features, you may need to create an account. You agree to:")
                            TermsBullet("Provide accurate information")
                            TermsBullet("Keep your account credentials secure")
                            TermsBullet("Notify us immediately of any unauthorized access")
                            TermsBullet("Be responsible for all activity under your account")
                        }
                    }

                    // 4. Acceptable Use
                    TermsSection(number: 4, title: "Acceptable Use") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You agree not to use FestivAir to:")
                            TermsBullet("Harass, stalk, or intimidate other users")
                            TermsBullet("Share another person's location without their consent")
                            TermsBullet("Transmit harmful, offensive, or illegal content")
                            TermsBullet("Attempt to hack, reverse engineer, or disrupt the service")
                            TermsBullet("Use the app for any illegal purpose")
                            TermsBullet("Impersonate another person or entity")
                            TermsBullet("Spam or send unsolicited messages")
                        }
                    }

                    // 5. Location Sharing
                    TermsSection(number: 5, title: "Location Sharing") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FestivAir enables location sharing with squad members. By using this feature, you:")
                            TermsBullet("Consent to sharing your location with squad members")
                            TermsBullet("Understand that squad members can see your real-time location")
                            TermsBullet("Acknowledge that you can pause location sharing at any time")
                            TermsBullet("Agree not to use location data to harm or stalk others")
                        }
                    }

                    // 6. Mesh Network
                    TermsSection(number: 6, title: "Mesh Network") {
                        Text("FestivAir uses Bluetooth mesh networking to enable offline functionality. By using the app, you consent to your device participating in this mesh network, which may relay anonymized data packets from other users.")
                    }

                    // 7. Premium Services
                    TermsSection(number: 7, title: "Premium Services") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FestivAir may offer premium features through in-app purchases or subscriptions. Premium services are:")
                            TermsBullet("Billed according to your selected plan")
                            TermsBullet("Subject to automatic renewal unless cancelled")
                            TermsBullet("Non-refundable except as required by law")
                            Text("You can manage subscriptions through your App Store account settings.")
                                .padding(.top, 4)
                        }
                    }

                    // 8. Intellectual Property
                    TermsSection(number: 8, title: "Intellectual Property") {
                        Text("FestivAir and its content, features, and functionality are owned by us and are protected by copyright, trademark, and other intellectual property laws. You may not copy, modify, distribute, or create derivative works without our permission.")
                    }

                    // 9. User Content
                    TermsSection(number: 9, title: "User Content") {
                        Text("You retain ownership of content you create (messages, photos, etc.). By sharing content through FestivAir, you grant us a limited license to transmit and display that content to intended recipients.")
                    }

                    // 10. Disclaimer of Warranties
                    TermsSection(number: 10, title: "Disclaimer of Warranties") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FestivAir is provided \"as is\" without warranties of any kind. We do not guarantee:")
                                .fontWeight(.medium)
                            TermsBullet("Uninterrupted or error-free operation")
                            TermsBullet("Accuracy of location data")
                            TermsBullet("Availability of mesh network connectivity")
                            TermsBullet("That the app will meet your specific requirements")
                        }
                    }

                    // 11. Limitation of Liability
                    TermsSection(number: 11, title: "Limitation of Liability") {
                        Text("To the maximum extent permitted by law, FestivAir shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of data, personal injury, or property damage arising from your use of the app.")
                    }

                    // 12. Safety
                    TermsSection(number: 12, title: "Safety") {
                        Text("FestivAir is a tool to help you find friends, but it is not a safety device. Do not rely solely on FestivAir in emergency situations. Always have a backup plan and contact emergency services (911) if you are in danger.")
                            .fontWeight(.medium)
                    }

                    // 13. Termination
                    TermsSection(number: 13, title: "Termination") {
                        Text("We may suspend or terminate your access to FestivAir at any time for violation of these Terms or for any other reason. You may delete your account at any time through the app settings.")
                    }

                    // 14. Changes to Terms
                    TermsSection(number: 14, title: "Changes to Terms") {
                        Text("We may modify these Terms at any time. Continued use of FestivAir after changes constitutes acceptance of the new Terms. We will notify you of material changes through the app or by email.")
                    }

                    // 15. Governing Law
                    TermsSection(number: 15, title: "Governing Law") {
                        Text("These Terms are governed by the laws of the State of Florida, United States, without regard to conflict of law principles.")
                    }

                    // 16. Contact
                    TermsSection(number: 16, title: "Contact") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("For questions about these Terms, contact us at:")
                            Text("legal@festivair.app")
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
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(number). \(title)")
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
