import SwiftUI

/// One thread. Members talk; a captain can ask the assistant to read the thread
/// and then approve or bin each suggestion.
struct ChatThreadView: View {
    let conversation: ConversationSummary
    @ObservedObject var store: ChatStore

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !store.pendingProposals.isEmpty {
                            proposalsHeader
                        }
                        if let summary = store.agentSummary, store.pendingProposals.isEmpty {
                            Label(summary, systemImage: "sparkles")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: store.messages.count) {
                    if let last = store.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FishersTheme.unavailable)
            }

            composer
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.askAssistant() }
                } label: {
                    if store.isThinking {
                        ProgressView()
                    } else {
                        Label("Ask assistant", systemImage: "sparkles")
                    }
                }
                .disabled(store.isThinking)
            }
        }
        .task { await store.open(conversation) }
    }

    private var proposalsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(store.pendingProposals) { proposal in
                ProposalCard(
                    proposal: proposal,
                    onApply: { Task { await store.apply(proposal) } },
                    onDismiss: { Task { await store.dismiss(proposal) } }
                )
            }
        }
        .padding(.horizontal)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                let body = draft
                draft = ""
                Task { await store.send(body) }
            } label: {
                if store.isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(store.isSending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(.bar)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if message.isFromAgent {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(FishersTheme.accent)
                }
                Text(message.authorLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.isFromAgent ? FishersTheme.accent : .secondary)
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.body)
                .font(.body)
                .padding(10)
                .background(
                    message.isFromAgent
                        ? FishersTheme.accent.opacity(0.12)
                        : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

/// An assistant suggestion, with why it thinks so and the two buttons that
/// decide it. Nothing happens until one is tapped.
private struct ProposalCard: View {
    let proposal: AgentProposal
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: proposal.proposalKind?.systemImage ?? "sparkles")
                    .foregroundStyle(FishersTheme.accent)
                Text(proposal.proposalKind?.label ?? proposal.kind.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(proposal.confidence)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(confidenceColor)
            }
            Text(proposal.payload.summary)
                .font(.callout)
            Text(proposal.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(FishersTheme.mist, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(FishersTheme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var confidenceColor: Color {
        switch proposal.confidence {
        case "high": return FishersTheme.available
        case "low": return FishersTheme.unavailable
        default: return FishersTheme.maybe
        }
    }
}
