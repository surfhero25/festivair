import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePageView(currentPage: $currentPage)
                .tag(0)

            FeaturesPageView(currentPage: $currentPage)
                .tag(1)

            ProfileSetupView()
                .tag(2)
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

            Text("Never lose your squad again")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))

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

// MARK: - Features Page
struct FeaturesPageView: View {
    @Binding var currentPage: Int

    let features = [
        ("person.3.fill", "Squad Tracking", "See your crew on the map in real-time"),
        ("antenna.radiowaves.left.and.right", "Works Offline", "Mesh networking even without service"),
        ("music.note", "Set Alerts", "Never miss your favorite artists"),
        ("battery.100", "Battery Smart", "Optimized to last all day")
    ]

    var body: some View {
        VStack(spacing: 30) {
            Text("How It Works")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .padding(.top, 60)

            ForEach(features, id: \.1) { icon, title, subtitle in
                HStack(spacing: 20) {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundStyle(.purple)
                        .frame(width: 50)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            Button {
                withAnimation {
                    currentPage = 2
                }
            } label: {
                Text("Set Up Profile")
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

// MARK: - Profile Setup
struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var displayName = ""
    @State private var selectedEmoji = "🎧"

    let emojiOptions = ["🎧", "🎤", "🎸", "🎹", "🥁", "🎺", "🎷", "🪗", "🎻", "🪘", "🎵", "🔊"]

    var body: some View {
        VStack(spacing: 30) {
            Text("Your Profile")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .padding(.top, 60)

            // Emoji selector
            Text(selectedEmoji)
                .font(.system(size: 80))
                .padding()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                ForEach(emojiOptions, id: \.self) { emoji in
                    Text(emoji)
                        .font(.title)
                        .padding(8)
                        .background(selectedEmoji == emoji ? Color.white.opacity(0.3) : Color.clear)
                        .clipShape(Circle())
                        .onTapGesture {
                            selectedEmoji = emoji
                        }
                }
            }
            .padding(.horizontal, 40)

            // Name input
            TextField("Your Name", text: $displayName)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
                .background(.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)

            Spacer()

            Button {
                guard !displayName.isEmpty else { return }
                appState.completeOnboarding(displayName: displayName, emoji: selectedEmoji)
            } label: {
                Text("Let's Go!")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(displayName.isEmpty ? .gray : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(displayName.isEmpty)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
