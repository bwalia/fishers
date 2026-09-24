import SwiftUI
import UIKit

/// A player sends their profile to a club secretary, who invites them in.
///
/// One link, sent however the two of them actually talk — most clubs run on a
/// WhatsApp group, so that goes first. The secretary sees a card with no
/// contact details and sends an invite; the player still has to accept it.
struct ShareProfileView: View {
    let userId: UUID
    var onShared: () -> Void = {}

    @State private var link: URL?
    @State private var busy = false
    @State private var copied = false
    @State private var error: String?

    static func sharedKey(_ userId: UUID) -> String { "fishers:profile-shared:\(userId.uuidString)" }

    private func message(_ url: URL) -> String {
        "Hi — I'd like to play for the club. Here's my \(Brand.name) player profile, you can invite me from it: \(url.absoluteString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let link {
                Text(link.absoluteString)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: FishersTheme.space1) {
                    Button {
                        UIPasteboard.general.string = link.absoluteString
                        copied = true
                        shared()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: link, message: Text(message(link))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .simultaneousGesture(TapGesture().onEnded { shared() })
                }

                if let whatsapp = whatsAppURL(link) {
                    Link(destination: whatsapp) {
                        Label("Send on WhatsApp", systemImage: "message")
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.bordered)
                    .simultaneousGesture(TapGesture().onEnded { shared() })
                }
            } else {
                Button {
                    Task { await getLink() }
                } label: {
                    Group {
                        if busy { ProgressView() } else { Label("Get my profile link", systemImage: "link") }
                    }
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }

            if let error {
                Text(error).font(FishersTheme.footnote).foregroundStyle(FishersTheme.unavailable)
            }
        }
        .onChange(of: copied) { _, now in
            guard now else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }

    private func whatsAppURL(_ url: URL) -> URL? {
        var components = URLComponents(string: "https://wa.me/")
        components?.queryItems = [URLQueryItem(name: "text", value: message(url))]
        return components?.url
    }

    private func getLink() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            link = try await FishersAPI.profileShareLink()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "Could not make your link"
        }
    }

    private func shared() {
        UserDefaults.standard.set(true, forKey: Self.sharedKey(userId))
        onShared()
    }
}
