import SwiftUI

@main
struct FishersApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var cart = CartStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(cart)
                .preferredColorScheme(.light)
        }
    }
}
