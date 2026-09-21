import SwiftUI
import SwiftData

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct FishersApp: App {
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
                    }
                }
                .onChange(of: session.isAuthenticated) { _, signedIn in
                    if signedIn {
                        Task { await clubContext.bootstrap() }
                    } else {
                        clubContext.clear()
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
