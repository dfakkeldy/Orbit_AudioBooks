import SwiftUI

struct ArtworkTranscriptOverlayView: View {
    @Bindable var model: PlayerModel
    @Environment(StoreManager.self) private var storeManager

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork

            if storeManager.hasUnlockedPro, !model.transcription.isEmpty {
                TranscriptView(player: model)
                    .frame(maxHeight: 160)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .padding(12)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.25), value: model.currentDisplayArtworkVersion)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = model.currentDisplayArtwork ?? model.thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .id(model.currentDisplayArtworkVersion)
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
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
        }
    }
}
