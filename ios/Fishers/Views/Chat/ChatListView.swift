import SwiftUI

/// Threads the member belongs to, with unread counts and a badge when the
/// assistant has proposals waiting on a captain.
struct ChatListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store = ChatStore()
    @State private var isCreating = false
    @State private var newTitle = ""
    @State private var clubs: [Club] = []
    @State private var selectedClubId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if let error = store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.unavailable)
                }
                if store.conversations.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "No chats yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a thread for your club — availability and squads get sorted here.")
                    )
                }
                ForEach(store.conversations) { conversation in
                    NavigationLink {
                        ChatThreadView(conversation: conversation, store: store)
                    } label: {
                        row(conversation)
                    }
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                newThreadSheet
            }
            .task {
                await store.loadConversations()
                clubs = (try? await FishersAPI.clubs()) ?? []
                selectedClubId = clubs.first?.id
            }
            .refreshable { await store.loadConversations() }
        }
    }

    private func row(_ conversation: ConversationSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: conversation.systemImage)
                .foregroundStyle(FishersTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.headline)
                if let last = conversation.lastMessageBody {
                    Text(last)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if conversation.pendingProposals > 0 {
                    Label(
                        "\(conversation.pendingProposals) suggestion\(conversation.pendingProposals == 1 ? "" : "s") to review",
                        systemImage: "sparkles"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FishersTheme.accent)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let at = conversation.lastMessageAt {
                    Text(at, format: .relative(presentation: .numeric))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(FishersTheme.accent, in: Capsule())
                }
            }
        }
    }

    private var newThreadSheet: some View {
        NavigationStack {
            Form {
                Section("Thread") {
                    TextField("e.g. 1st XI match chat", text: $newTitle)
                }
                if !clubs.isEmpty {
                    Section("Club") {
                        Picker("Club", selection: $selectedClubId) {
                            ForEach(clubs) { club in
                                Text(club.name).tag(UUID?.some(club.id))
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Create a club first — threads belong to a club so the assistant knows the roster.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isCreating = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newTitle
                        let clubId = selectedClubId
                        isCreating = false
                        newTitle = ""
                        Task { await store.createConversation(title: title, clubId: clubId) }
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedClubId == nil)
                }
            }
        }
    }
}
