import SwiftUI
import AVFoundation
import CoreMedia

struct TranscriptView: View {
    @Bindable var player: PlayerModel
    @Namespace private var scrollNamespace
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(player.transcription) { segment in
                        Text(segment.text)
                            .font(.body)
                            .padding(8)
                            .background(isActive(segment) ? Color.accentColor.opacity(0.3) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                player.seek(toSeconds: segment.startTime)
                            }
                            .id(segment.id)
                    }
                }
                .padding()
                .onChange(of: player.progressFraction) {
                    if let active = activeSegment {
                        withAnimation {
                            proxy.scrollTo(active.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    private var activeSegment: PlayerModel.TranscriptionSegment? {
        let currentTime = player.player?.currentTime().seconds ?? 0
        return player.transcription.first { currentTime >= $0.startTime && currentTime <= $0.endTime }
    }
    
    private func isActive(_ segment: PlayerModel.TranscriptionSegment) -> Bool {
        activeSegment?.id == segment.id
    }
}
