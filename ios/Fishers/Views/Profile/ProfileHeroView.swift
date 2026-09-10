import PhotosUI
import SwiftUI

/// The band across the top of a player's own page.
///
/// Laid out the way a cricket profile is read rather than the way the record
/// is stored: the photo, the name set as a scorecard sets it — given name
/// light, family name heavy and upper — then the club, the standard and the
/// position. The same shape as the dashboard, so the two feel like one product.
struct ProfileHeroView: View {
    let user: PublicUser
    /// Whichever club they have played the most for, worked out by the caller
    /// from the seasons on record.
    var club: String?
    var onPhotoChanged: (PublicUser) -> Void

    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    private var main: SportProfile? {
        user.profiles.first { $0.sport == user.primarySport } ?? user.profiles.first
    }

    private var names: (first: String, last: String) {
        let parts = user.name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard parts.count > 1 else { return ("", user.name) }
        return (parts.dropLast().joined(separator: " "), parts[parts.count - 1])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FishersTheme.space2) {
            HStack(alignment: .center, spacing: FishersTheme.space2) {
                photo
                VStack(alignment: .leading, spacing: 0) {
                    if !names.first.isEmpty {
                        Text(names.first)
                            .font(.system(.title, design: .rounded).weight(.light))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    Text(names.last.uppercased())
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }

            // Flowing, not a fixed row: a long club name and a long position
            // together overflow a phone otherwise.
            HStack(spacing: FishersTheme.space1) {
                if let club {
                    Text(club).foregroundStyle(.white.opacity(0.82))
                }
                if let level = main?.skillLevel?.capitalized {
                    Text("·").foregroundStyle(.white.opacity(0.5))
                    Text(level).foregroundStyle(.white.opacity(0.82))
                }
                if let position = main?.position, !position.isEmpty {
                    Text(position)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(FishersTheme.gold.opacity(0.25), in: Capsule())
                        .overlay(Capsule().strokeBorder(FishersTheme.gold.opacity(0.55)))
                        .foregroundStyle(.white)
                }
            }
            .font(FishersTheme.subhead)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let error {
                Text(error)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.sagePale)
            }
        }
        .padding(FishersTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [FishersTheme.sage900, FishersTheme.sage700],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await send(item) }
        }
    }

    private var photo: some View {
        AvatarView(name: user.name, initials: user.initials,
                   urlString: user.avatarUrl, size: 96)
            .overlay(Circle().strokeBorder(FishersTheme.gold, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        Circle().fill(FishersTheme.gold)
                        if uploading {
                            ProgressView().tint(FishersTheme.sage900)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FishersTheme.sage900)
                        }
                    }
                    .frame(width: 30, height: 30)
                    // The visual circle is 30pt; the tap target is not.
                    .padding(7)
                    .contentShape(Circle())
                }
                .disabled(uploading)
                .accessibilityLabel(user.avatarUrl == nil ? "Add a photo" : "Change your photo")
            }
    }

    private func send(_ item: PhotosPickerItem) async {
        uploading = true
        error = nil
        defer {
            uploading = false
            picked = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = "That photo could not be read."
                return
            }
            onPhotoChanged(try await FishersAPI.uploadAvatar(data, mimeType: mimeType(of: data)))
        } catch let failure {
            error = (failure as? APIError)?.friendlyMessage ?? "That picture would not upload."
        }
    }

    /// From the bytes, not from the picker: the server sniffs them too, and a
    /// mismatch there is a rejection the person cannot act on.
    private func mimeType(of data: Data) -> String {
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return "image/jpeg"
    }
}
