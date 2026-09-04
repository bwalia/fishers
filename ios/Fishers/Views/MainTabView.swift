import SwiftUI

struct MainTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            FishersTopBar()

            TabView {
                HomeFeedView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                AvailabilityCalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                ChatListView()
                    .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                ClubsTeamsView()
                    .tabItem { Label("Clubs", systemImage: "person.3.fill") }
                ShopView()
                    .tabItem { Label("Shop", systemImage: "bag.fill") }
                ProfileView()
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }
            .tint(FishersTheme.accent)
        }
        .background(FishersTheme.cream.ignoresSafeArea(edges: .top))
    }
}
