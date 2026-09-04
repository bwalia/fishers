import Foundation
import SwiftUI

/// Chat state: the thread list, the open thread's messages, and the assistant's
/// proposals. Proposals are applied here so the thread refreshes with the note
/// the server posts.
@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var proposals: [AgentProposal] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isThinking = false
    @Published var errorMessage: String?
    @Published var agentSummary: String?

    private var openConversationId: UUID?

    var pendingProposals: [AgentProposal] { proposals.filter(\.isPending) }

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await FishersAPI.conversations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ conversation: ConversationSummary) async {
        openConversationId = conversation.id
        messages = []
        proposals = []
        agentSummary = nil
        await refreshThread()
        // Clearing the badge is best-effort; a failure here shouldn't surface.
        try? await FishersAPI.markRead(conversationId: conversation.id)
        await loadConversations()
    }

    func refreshThread() async {
        guard let id = openConversationId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // The API returns newest first; the thread reads oldest at the top.
            messages = try await FishersAPI.messages(conversationId: id).reversed()
            proposals = try await FishersAPI.proposals(conversationId: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ body: String) async {
        guard let id = openConversationId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await FishersAPI.postMessage(conversationId: id, body: trimmed)
            messages.append(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Captain-only: have the assistant read the thread.
    func askAssistant() async {
        guard let id = openConversationId else { return }
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }
        do {
            let analysis = try await FishersAPI.analyseConversation(id)
            agentSummary = analysis.summary
            proposals = analysis.proposals + proposals.filter { !$0.isPending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func apply(_ proposal: AgentProposal) async {
        await decide(proposal) { try await FishersAPI.applyProposal($0) }
        await refreshThread()
    }

    func dismiss(_ proposal: AgentProposal) async {
        await decide(proposal) { try await FishersAPI.dismissProposal($0) }
    }

    private func decide(
        _ proposal: AgentProposal,
        _ work: (UUID) async throws -> AgentProposal
    ) async {
        do {
            let updated = try await work(proposal.id)
            if let index = proposals.firstIndex(where: { $0.id == updated.id }) {
                proposals[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation(title: String, clubId: UUID?) async {
        do {
            _ = try await FishersAPI.createConversation(title: title, clubId: clubId)
            await loadConversations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
