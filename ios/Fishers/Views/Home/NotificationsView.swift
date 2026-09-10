import SwiftUI

/// What is waiting for you.
///
/// Filtered, counted and paged on the server. A club generates thousands of
/// these over a season, and pulling the lot down to slice twenty out of them
/// is exactly what a phone connection is worst at — so the filter goes in the
/// query string and pages arrive one at a time as somebody scrolls.
struct NotificationsView: View {
    @State private var items: [AppNotification] = []
    @State private var unread = 0
    @State private var total = 0
    @State private var kinds: [String] = []
    @State private var hasMore = false
    @State private var page = 1

    @State private var kind: String = ""
    @State private var unreadOnly = false
    @State private var search = ""

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var message: String?

    private let perPage = 20

    var body: some View {
        List {
            Section {
                filters
            }

            if items.isEmpty && !isLoading {
                ContentUnavailableView(
                    filtered ? "Nothing matches" : "Nothing waiting",
                    systemImage: "bell",
                    description: Text(
                        filtered
                            ? "Try a different filter."
                            : "You'll be told here when a captain proposes terms or somebody invites you."
                    )
                )
            }

            Section {
                ForEach(items) { item in
                    row(item)
                }

                // The next page loads when the last row appears rather than
                // behind a button: on a phone, scrolling *is* the gesture for
                // "show me more".
                if hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .onAppear { Task { await loadMore() } }
                }
            } header: {
                if total > 0 {
                    Text("\(items.count) of \(total)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unread > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task {
                            try? await FishersAPI.markNotificationRead(id: nil)
                            await reload()
                        }
                    }
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        // Typing sends one request when they stop, not one per keystroke.
        .onChange(of: search) { _, _ in Task { await debouncedReload() } }
        .onChange(of: kind) { _, _ in Task { await reload() } }
        .onChange(of: unreadOnly) { _, _ in Task { await reload() } }
        .alert("Something went wrong", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var filtered: Bool {
        !kind.isEmpty || unreadOnly || search.trimmingCharacters(in: .whitespaces).count >= 2
    }

    @ViewBuilder
    private var filters: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        // Only what this person has actually been sent, so the picker never
        // offers a filter that returns nothing.
        if !kinds.isEmpty {
            Picker("Kind", selection: $kind) {
                Text("Everything").tag("")
                ForEach(kinds, id: \.self) { Text(label(for: $0)).tag($0) }
            }
        }

        Toggle("Unread only", isOn: $unreadOnly)
    }

    private func label(for kind: String) -> String {
        switch kind {
        case "invite": return "Invitations"
        case "selection_published", "squad_promoted": return "Squads"
        case "selection_reconfirm": return "Confirmations"
        case "match_terms_proposed", "match_terms_agreed": return "Match setup"
        case "match_scheduled": return "Fixtures"
        case "availability_request": return "Availability"
        case "fee_reminder": return "Match fees"
        // A kind the app has not been taught about is still readable.
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @ViewBuilder
    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Unread earns a marker rather than a different background.
            Circle()
                .fill(item.isUnread ? FishersTheme.accent : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(label(for: item.type))
                    .font(FishersTheme.overline)
                    .foregroundStyle(FishersTheme.pitch)
                Text(item.line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.sentAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: FishersTheme.minTap)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.isUnread else { return }
            Task {
                try? await FishersAPI.markNotificationRead(id: item.id)
                await reload()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isUnread ? "Unread. \(item.line)" : item.line)
    }

    // MARK: Loading

    /// Back to page one. Every filter change goes through here, because
    /// keeping page 4 while changing the filter shows a page that may not
    /// exist any more.
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        await fetch(replacing: true)
    }

    /// One request after they stop typing, rather than one per keystroke.
    private func debouncedReload() async {
        let typed = search
        try? await Task.sleep(for: .milliseconds(350))
        guard typed == search else { return }
        await reload()
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        do {
            let feed = try await FishersAPI.notifications(
                page: page,
                perPage: perPage,
                kind: kind.isEmpty ? nil : kind,
                unreadOnly: unreadOnly,
                search: search
            )
            items = replacing ? feed.items : items + feed.items
            unread = feed.unread
            total = feed.total
            hasMore = feed.hasMore
            // Only on a full reload: a later page carries the same list, and
            // reassigning it mid-scroll churns the picker for no reason.
            if replacing { kinds = feed.kinds }
        } catch let failure {
            message = (failure as? APIError)?.friendlyMessage ?? failure.localizedDescription
        }
    }
}
