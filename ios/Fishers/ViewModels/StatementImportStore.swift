import Foundation
import SwiftUI

/// Import a bank statement: choose the CSV the bank exports, see what each
/// payment in it matches, untick any that look wrong, then apply the rest in
/// one go.
///
/// The statement's text is held here only between choosing the file and
/// applying it (the server reads it again on apply), and dropped as soon as
/// it's applied, another file is chosen or the sheet closes. It holds the
/// club's other banking too, so it is never logged or written to disk.
@MainActor
final class StatementImportStore: ObservableObject {
    @Published private(set) var preview: StatementPreview?
    /// The "Ticked off" lines still ticked, by hash.
    @Published var ticked: Set<String> = []
    @Published private(set) var applied: StatementApplied?
    @Published private(set) var isWorking = false
    /// What went wrong with the last file, beside "Choose another file".
    @Published private(set) var problem: String?
    /// The club's members, for "Two members called SHARMA".
    @Published private(set) var memberNames: [String] = []

    let clubId: UUID
    /// The payments waiting to be checked, for "Said £6, sent £9".
    let waiting: [ClubPayment]
    private let network: NetworkService
    private var csv: String?

    init(clubId: UUID, waiting: [ClubPayment] = [], network: NetworkService = .shared) {
        self.clubId = clubId
        self.waiting = waiting
        self.network = network
    }

    /// How many "Apply" ticks off.
    var tickedCount: Int { preview?.hashes(ticked: ticked).count ?? 0 }

    /// The file from the picker: read, then previewed.
    func read(_ url: URL) async {
        guard !isWorking else { return }
        problem = nil
        isWorking = true
        let data: Data? = await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }.value
        isWorking = false
        guard let data else {
            problem = tr("That file couldn't be opened. Try choosing it again.")
            return
        }
        guard data.count <= StatementFile.maxBytes else {
            problem = StatementFile.tooLong
            return
        }
        guard let text = StatementFile.text(from: data) else {
            problem = StatementFile.unreadable
            return
        }
        await loadPreview(text)
    }

    /// What the server makes of the statement. Its refusals — an empty file,
    /// one with no date or amount column, one too long — are its own
    /// sentences, which say what to do.
    func loadPreview(_ text: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        forget()
        problem = nil
        applied = nil
        do {
            async let names = try? FishersAPI.moneyMembers(clubId: clubId, network: network)
            let fresh = try await FishersAPI.previewStatement(clubId: clubId, csv: text, network: network)
            csv = text
            preview = fresh
            ticked = Set(fresh.toApply.map(\.hash))
            if let names = await names { memberNames = names.map(\.name) }
        } catch {
            problem = StatementFile.problem(error)
        }
    }

    func toggle(_ line: StatementLine, _ on: Bool) {
        if on { ticked.insert(line.hash) } else { ticked.remove(line.hash) }
    }

    /// Ticks off what's still ticked. Applying the same statement twice
    /// changes nothing on the server, so a retry after a failure is safe.
    func apply() async {
        guard let csv, let preview, !isWorking else { return }
        let lines = preview.hashes(ticked: ticked)
        guard !lines.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        problem = nil
        do {
            applied = try await FishersAPI.applyStatement(clubId: clubId, csv: csv, lines: lines, network: network)
            forget()
        } catch {
            problem = StatementFile.problem(error)
        }
    }

    /// Back to choosing a file, holding nothing of the last one.
    func startAgain() {
        forget()
        applied = nil
        problem = nil
    }

    private func forget() {
        csv = nil
        preview = nil
        ticked = []
    }
}
