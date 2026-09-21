import SwiftUI
import SwiftData
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct FishersApp: App {
    /// SwiftUI has no hook for the APNs device token, so a UIKit delegate
    /// supplies one. See `PushRegistrar`.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    @StateObject private var session = SessionStore()
    @StateObject private var cart = CartStore()
    @StateObject private var clubContext = ClubContextStore()

    private let cricketContainer: ModelContainer = {
        let schema = Schema([LocalCricketMatch.self, LocalScoringEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback for simulator wipe / migration issues — in-memory keeps scoring usable.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        FishersTheme.applyNavigationChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(cart)
                .environmentObject(clubContext)
                .modelContainer(cricketContainer)
                .tint(FishersTheme.accent)
                .task {
                    // The sync service is @MainActor now, so this is a plain call.
                    CricketSyncService.shared.configure(container: cricketContainer)
                    if session.isAuthenticated {
                        await clubContext.bootstrap()
                        // Only once there is an account behind it: iOS shows
                        // the permission prompt once and never again, so
                        // spending it on the launch screen wastes it.
                        await PushRegistrar.shared.start()
                    }
                }
                .onChange(of: session.isAuthenticated) { _, signedIn in
                    if signedIn {
                        Task {
                            await clubContext.bootstrap()
                            await PushRegistrar.shared.start()
                        }
                    } else {
                        clubContext.clear()
                        // A shared phone must stop buzzing with the last
                        // person's club the moment they sign out of it.
                        Task { await PushRegistrar.shared.unregister() }
                    }
                }
                // Google's OAuth redirect lands here; without this the sheet
                // never closes after the user picks an account.
                // Coming back to the app is the other moment a stranded
                // match gets its chance — the scorer drove home and is on
                // wifi, and no path change happened while they were away.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { CricketSyncService.shared.requestFlush() }
                }
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
    }
}
