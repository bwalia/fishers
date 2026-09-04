import SwiftUI

/// Top-level destinations — HIG recommends 3–5 tabs.
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem { Label("Home", systemImage: "house") }
            AvailabilityCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ChatListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            ClubsTeamsView()
                .tabItem { Label("Clubs", systemImage: "person.3") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(FishersTheme.accent)
    }
}
