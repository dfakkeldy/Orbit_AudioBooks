import Foundation
import CoreGraphics
import Testing
@testable import Echo

struct NowPlayingLayoutTests {
    @Test func nowPlayingArtworkRendersFullBleed() throws {
        let source = try Self.source(named: "NowPlayingTab.swift")
        let heroSource = try Self.source(named: "Components/AlbumArtHeroView.swift")

        #expect(
            heroSource.contains("isFullBleed"),
            "Album artwork should support full bleed mode to ignore safe areas and take up full width."
        )
        #expect(
            source.contains("isFullBleed: true"),
            "Now Playing should use full bleed album art."
        )
        #expect(
            source.contains("LinearGradient"),
            "Now Playing should use linear gradients to ensure overlaid buttons and text remain readable."
        )
        #expect(
            !source.contains(".padding(.top, NowPlayingLayout.topContentInset)"),
            "Now Playing should not have top padding on the artwork so it goes all the way to the top edge."
        )
    }

    @Test func scrubberKeepsTimeLabelsBelowScrubber() throws {
        let source = try Self.source(named: "PlayerScrubberView.swift")

        #expect(
            source.contains("timeLabelWidth"),
            "Scrubber time labels need stable widths so elapsed and remaining time stay aligned."
        )
        #expect(
            !source.contains("ViewThatFits"),
            "The scrubber should no longer use ViewThatFits to push labels beside the slider, but should place them below it instead."
        )
        #expect(
            source.contains("Spacer()"),
            "The time labels should be spread apart horizontally."
        )
    }

    @Test func nowPlayingUsesOverlayControlsInsteadOfNavigationBar() throws {
        let source = try Self.source(named: "RootTabView.swift")

        #expect(
            source.contains("NowPlayingTopToolbar"),
            "Now Playing top controls should be drawn as an overlay so the navigation bar does not reserve an empty top slab."
        )
        #expect(
            source.contains(".toolbarVisibility(model.selectedTab != .nowPlaying ? .automatic : .hidden, for: .navigationBar)"),
            "The navigation bar should be hidden only on Now Playing."
        )
    }

    private static func source(named fileName: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        while directory.path != "/" {
            let candidate = directory
                .deletingLastPathComponent()
                .appendingPathComponent("EchoCore/Views")
                .appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }

            directory.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }
}
