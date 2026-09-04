import SwiftUI

@main
struct FishersApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var cart = CartStore()

    init() {
        FishersTheme.applyNavigationChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(cart)
                .tint(FishersTheme.accent)
        }
    }
}
