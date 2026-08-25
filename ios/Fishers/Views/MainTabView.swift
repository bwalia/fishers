import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            AvailabilityCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ClubsTeamsView()
                .tabItem { Label("Clubs", systemImage: "person.3.fill") }
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(FishersTheme.accent)
    }
}
