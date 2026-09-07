import SwiftUI

enum AppTheme {
    static let header = Color(red: 1.00, green: 0.79, blue: 0.47)
    static let headerSoft = Color(red: 1.00, green: 0.84, blue: 0.61)
    static let accent = Color(red: 0.56, green: 0.15, blue: 0.05)
    static let title = Color(red: 0.24, green: 0.07, blue: 0.03)
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let muted = Color(red: 0.72, green: 0.66, blue: 0.58)
}

struct ToolRowButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    var artworkName: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Group {
                    if let artworkName {
                        Image(artworkName)
                            .resizable()
                            .scaledToFill()
                    } else {
                        GameIcon(systemName: systemImage, size: 28)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(disabled ? Color.secondary : iconColor)
                    }
                }
                .frame(width: 58, height: 58)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                GameIcon(systemName: disabled ? "lock.fill" : "chevron.right", size: 20)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(18)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .opacity(disabled ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct LargePageHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(AppTheme.title)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .bottomLeading)
            .background(AppTheme.header.ignoresSafeArea(edges: .top))
    }
}

extension View {
    func appCard() -> some View {
        background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
