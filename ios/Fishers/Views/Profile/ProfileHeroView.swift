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

    @State private var coverPicked: PhotosPickerItem?
    @State private var coverBusy = false

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
                        .background(FishersTheme.accent400.opacity(0.25), in: Capsule())
                        .overlay(Capsule().strokeBorder(FishersTheme.accent400.opacity(0.55)))
                        .foregroundStyle(.white)
                }
            }
            .font(FishersTheme.subhead)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let error {
                Text(error)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.primaryPale)
            }
        }
        .padding(FishersTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .center) { backdrop }
        .overlay(alignment: .topTrailing) { coverTools }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await send(item) }
        }
        .onChange(of: coverPicked) { _, item in
            guard let item else { return }
            Task { await sendCover(item) }
        }
    }

    /// The cover photograph, with the brand gradient over it.
    ///
    /// The gradient is not replaced by the picture — it is laid on top of it.
    /// White type over an arbitrary photograph fails contrast at the first
    /// bright sky, and the name is the point of this header while the cover is
    /// decoration. Without a cover the gradient is simply the whole of it,
    /// which is what it has always been.
    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            if let cover = user.coverUrl, let url = URL(string: cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipped()
            }
            LinearGradient(
                colors: user.coverUrl == nil
                    ? [FishersTheme.primary900, FishersTheme.primary700]
                    // Over a photograph it thins out, enough to keep the type
                    // readable without hiding what the picture is of.
                    : [FishersTheme.primary900.opacity(0.88), FishersTheme.primary700.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Add, change or take off the cover.
    private var coverTools: some View {
        HStack(spacing: 6) {
            if user.coverUrl != nil {
                Button {
                    Task { await removeCover() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(7)
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.42), in: Circle())
                .foregroundStyle(.white)
                .disabled(coverBusy)
                .accessibilityLabel(t("pro.remove_cover_photo"))
            }
            PhotosPicker(selection: $coverPicked, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if coverBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
                .padding(4)
                .background(.black.opacity(0.42), in: Circle())
                .foregroundStyle(.white)
                .contentShape(Circle())
            }
            .disabled(coverBusy)
            .accessibilityLabel(
                user.coverUrl == nil ? t("pro.add_a_cover_photo") : t("pro.change_cover_photo")
            )
        }
        .padding(FishersTheme.space2)
    }

    private func sendCover(_ item: PhotosPickerItem) async {
        coverBusy = true
        error = nil
        defer {
            coverBusy = false
            coverPicked = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = tr("That photo could not be read.")
                return
            }
            // Checked here as well as on the server, so somebody who picks a
            // 20MB photograph is told before they wait for all of it to go up.
            guard data.count <= 6 * 1024 * 1024 else {
                error = t("pro.cover_too_big")
                return
            }
            onPhotoChanged(try await FishersAPI.uploadCover(data, mimeType: mimeType(of: data)))
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? t("pro.cover_would_not_upload")
        }
    }

    private func removeCover() async {
        coverBusy = true
        error = nil
        defer { coverBusy = false }
        do {
            onPhotoChanged(try await FishersAPI.removeCover())
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? t("pro.cover_would_not_upload")
        }
    }

    private var photo: some View {
        AvatarView(name: user.name, initials: user.initials,
                   urlString: user.avatarUrl, size: 96)
            .overlay(Circle().strokeBorder(FishersTheme.accent400, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        Circle().fill(FishersTheme.accent400)
                        if uploading {
                            ProgressView().tint(FishersTheme.primary900)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FishersTheme.primary900)
                        }
                    }
                    .frame(width: 30, height: 30)
                    // The visual circle is 30pt; the tap target is not.
                    .padding(7)
                    .contentShape(Circle())
                }
                .disabled(uploading)
                .accessibilityLabel(user.avatarUrl == nil ? tr("Add a photo") : tr("Change your photo"))
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
                error = tr("That photo could not be read.")
                return
            }
            onPhotoChanged(try await FishersAPI.uploadAvatar(data, mimeType: mimeType(of: data)))
        } catch let failure {
            error = (failure as? APIError)?.friendlyMessage ?? tr("That picture would not upload.")
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
