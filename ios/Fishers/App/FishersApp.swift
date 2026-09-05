import SwiftUI
import SwiftData

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
                    await CricketSyncService.shared.configure(container: cricketContainer)
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
        }
    }
}
