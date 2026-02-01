import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePageView(currentPage: $currentPage)
                .tag(0)

            SquadTrackingPageView(currentPage: $currentPage)
                .tag(1)

            OfflineModePageView(currentPage: $currentPage)
                .tag(2)

            SetAlertsPageView(currentPage: $currentPage)
                .tag(3)

            AgeVerificationPageView(currentPage: $currentPage)
                .tag(4)

            ProfileSetupView()
                .tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.8), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Welcome Page
struct WelcomePageView: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("FestivAir")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Find your squad at the festival")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation {
                    currentPage = 1
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Squad Tracking Page
struct SquadTrackingPageView: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.3.fill")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            Text("Squad Tracking")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("See your crew on the map in real-time. Know where everyone is so you can meet up after getting food or using the restroom.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation {
                    currentPage = 2
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Offline Mode Page
struct OfflineModePageView: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            Text("Works Offline")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Uses Bluetooth mesh networking to share locations even when cell service is spotty. The more people using the app nearby, the better it works.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Bluetooth range: 30-100 feet in crowded conditions")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Button {
                withAnimation {
                    currentPage = 3
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Set Alerts Page
struct SetAlertsPageView: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            Text("Set Alerts")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Get notified before your favorite artists go on stage. Never miss a set you wanted to see.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation {
                    currentPage = 4
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Age Verification Page
struct AgeVerificationPageView: View {
    @Binding var currentPage: Int
    @State private var ageConfirmed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            Text("Age Verification")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("FestivAir includes party features and social connections. You must be 18 or older to use this app.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Age confirmation toggle
            Button {
                ageConfirmed.toggle()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: ageConfirmed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(ageConfirmed ? .purple : .white.opacity(0.6))

                    Text("I confirm that I am 18 years of age or older")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()

            Button {
                // Save age confirmation
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.ageConfirmed)
                withAnimation {
                    currentPage = 5
                }
            } label: {
                Text("Set Up Profile")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ageConfirmed ? .white : .gray)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!ageConfirmed)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Profile Setup
struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var appleAuth = AppleAuthService()
    @State private var displayName = ""
    @State private var selectedIcon = "👤"
    @State private var isSigningIn = false
    @State private var showManualEntry = false
    @State private var errorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    // Generic person icons - not music emojis
    let iconOptions = ["👤", "👦", "👧", "👨", "👩", "🧑", "👱‍♂️", "👱‍♀️", "🧔", "👴", "👵", "🧓"]

    var body: some View {
        VStack(spacing: 24) {
            Text("Your Profile")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .padding(.top, 60)

            if !showManualEntry {
                // Sign in with Apple flow
                appleSignInView
            } else {
                // Manual name entry (after Apple sign in or skip)
                manualEntryView
            }
        }
        .onTapGesture {
            isNameFieldFocused = false
        }
    }

    // MARK: - Apple Sign In View
    private var appleSignInView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            Text("Sign in with Apple for a seamless experience. Your identity persists even if you reinstall the app.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }

            // Sign in with Apple Button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)
            .disabled(isSigningIn)

            // Skip option
            Button {
                showManualEntry = true
            } label: {
                Text("Continue without Apple ID")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 60)

            if isSigningIn {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    // MARK: - Manual Entry View
    private var manualEntryView: some View {
        VStack(spacing: 24) {
            // Icon selector
            Text(selectedIcon)
                .font(.system(size: 80))
                .padding()

            Text("Choose an icon for your map marker")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Text(icon)
                        .font(.system(size: 32))
                        .frame(width: 50, height: 50)
                        .background(selectedIcon == icon ? Color.white.opacity(0.3) : Color.clear)
                        .clipShape(Circle())
                        .onTapGesture {
                            selectedIcon = icon
                        }
                }
            }
            .padding(.horizontal, 24)

            // Name input
            TextField("Your Name", text: $displayName)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
                .background(.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    completeSetup()
                }

            Spacer()

            Button {
                completeSetup()
            } label: {
                Text("Let's Go!")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Actions

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid credential"
                return
            }

            isSigningIn = true

            // Store Apple ID in Keychain
            KeychainHelper.save(credential.user, for: .appleUserIdentifier)

            if let email = credential.email {
                KeychainHelper.save(email, for: .appleEmail)
            }

            // Get name from credential (only provided on first sign in)
            if let fullName = credential.fullName {
                let firstName = fullName.givenName ?? ""
                let lastName = fullName.familyName ?? ""
                let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                if !name.isEmpty {
                    displayName = name
                }
            }

            print("[AppleAuth] Sign in success - user: \(credential.user)")

            isSigningIn = false
            showManualEntry = true  // Show emoji picker

        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                // User cancelled - not an error
                print("[AppleAuth] User cancelled sign in")
            } else {
                errorMessage = error.localizedDescription
                print("[AppleAuth] Sign in failed: \(error)")
            }
        }
    }

    private func completeSetup() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        appState.completeOnboarding(displayName: trimmedName, emoji: selectedIcon)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
