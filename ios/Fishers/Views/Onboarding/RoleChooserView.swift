import SwiftUI

/// "I run a club" or "I play for a club".
///
/// Two uses. On the signup form nothing is saved yet — there is no account —
/// so it only binds a choice. On Home, for somebody who was never asked, a
/// tap saves it straight away and the getting-started guide takes over.
struct RoleChooserView: View {
    @Binding var selection: RoleIntent?
    var compact = false
    /// Present on Home: save as soon as it is picked.
    var onPick: ((RoleIntent) async -> Void)?

    @State private var busy: RoleIntent?

    var body: some View {
        VStack(spacing: FishersTheme.space1) {
            ForEach(RoleIntent.allCases) { role in
                Button {
                    selection = role
                    guard let onPick else { return }
                    busy = role
                    Task {
                        await onPick(role)
                        busy = nil
                    }
                } label: {
                    row(role)
                }
                .buttonStyle(.plain)
                .disabled(busy != nil)
                .accessibilityAddTraits(selection == role ? .isSelected : [])
            }
        }
    }

    private func row(_ role: RoleIntent) -> some View {
        let selected = selection == role
        return HStack(alignment: compact ? .center : .top, spacing: 12) {
            Image(systemName: role.systemImage)
                .font(compact ? .body : .title3)
                .frame(width: compact ? 32 : 40, height: compact ? 32 : 40)
                .foregroundStyle(selected ? Color.white : FishersTheme.pitch)
                .background(
                    selected ? FishersTheme.pitch : FishersTheme.raised,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(busy == role ? "Saving…" : role.title)
                    .font(FishersTheme.headline)
                    .foregroundStyle(.primary)
                if !compact {
                    Text(role.detail)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? FishersTheme.pitch : Color.secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: FishersTheme.minTap)
        .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? FishersTheme.pitch : FishersTheme.hairline, lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}
