import SwiftUI

struct AlbumArtHeroView: View {
    let artwork: UIImage?
    let artworkVersion: Int
    let caption: String
    let mainText: String
    let appFont: String

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            artworkView

            VStack(alignment: .center, spacing: 6) {
                if !caption.isEmpty {
                    Text(caption)
                        .customFont(.caption, appFont: appFont)
                        .foregroundStyle(.secondary)
                }
                Text(mainText)
                    .customFont(.title2, weight: .semibold, appFont: appFont)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let image = artwork {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .id(artworkVersion)
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .accessibilityLabel(Text(mainText))
                .accessibilityAddTraits(.isImage)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 80, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .accessibilityLabel(Text(caption))
                .accessibilityAddTraits(.isImage)
        }
    }
}
