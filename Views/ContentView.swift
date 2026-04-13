import SwiftUI

extension Notification.Name {
    static let switchToMapTab = Notification.Name("switchToMapTab")
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.isOnboarded {
                MainTabView()
                    .onAppear {
                        appState.startServices()
                    }
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appState.handleEnterForeground()
            case .background:
                appState.handleEnterBackground()
            default:
                break
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                SquadMapView()
                    .tabItem {
                        Label("Squad", systemImage: "person.3.fill")
                    }
                    .tag(0)

                PartiesView()
                    .tabItem {
                        Label("Parties", systemImage: "party.popper.fill")
                    }
                    .tag(1)

                SetTimesView()
                    .tabItem {
                        Label("Set Times", systemImage: "music.note.list")
                    }
                    .tag(2)

                ChatView()
                    .tabItem {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag(3)
                    .badge(appState.notificationManager.unreadChatCount)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(4)
            }
            .tint(.purple)
            .onReceive(NotificationCenter.default.publisher(for: .switchToMapTab)) { _ in
                selectedTab = 0
            }

            // SOS Banner — shows on top of all tabs
            if appState.sosManager.isSOSActive, let memberName = appState.sosManager.sosActiveMember {
                VStack {
                    SOSBannerView(memberName: memberName) {
                        selectedTab = 0  // Switch to map tab
                    }
                    .padding(.top, 4)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: appState.sosManager.isSOSActive)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
