//
//  OrbitAudioBooksTests.swift
//  OrbitAudioBooksTests
//
//  Created by Dan Fakkeldy on 2026-04-19.
//

import Testing
import Foundation
@testable import Orbit_Audiobooks

@MainActor
struct OrbitAudioBooksTests {

    @Test func playerDeepLinkParsesPlayURLWithoutTime() throws {
        let link = try #require(PlayerDeepLink(url: URL(string: "orbitaudio://play")!))

        #expect(link == .play(time: nil))
    }

    @Test func playerDeepLinkParsesPlayURLWithTime() throws {
        let link = try #require(PlayerDeepLink(url: URL(string: "orbitaudio://play?time=30")!))

        #expect(link == .play(time: 30))
    }

    @Test func playerDeepLinkRejectsUnregisteredScheme() {
        #expect(PlayerDeepLink(url: URL(string: "orbitaudiobooks://play?time=30")!) == nil)
    }

    @Test func bookmarkMarkdownUsesCanonicalDeepLinkScheme() {
        let bookmarks = [
            Bookmark(title: "Note", timestamp: 42.5, note: "Interesting", voiceMemoFileName: nil)
        ]

        let markdown = Bookmark.markdownExport(for: bookmarks)

        #expect(markdown.contains("[Play in App](orbitaudio://play?time=42.5)"))
        #expect(!markdown.contains("orbitaudiobooks://"))
    }

    @Test func bookmarkSidecarURLUsesFolderNameForDirectoryBooks() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sidecar = Bookmark.sidecarURL(for: folder)

        #expect(sidecar == folder.appendingPathComponent("\(folder.lastPathComponent).json"))
    }

    @Test func bookmarkSidecarURLUsesAudioBasenameForSingleFileBooks() {
        let file = URL(fileURLWithPath: "/tmp/Example Book.m4b")

        let sidecar = Bookmark.sidecarURL(for: file)

        #expect(sidecar.path == "/tmp/Example Book.json")
    }

    @Test func bookmarkDecodingTreatsImageFileNameAsOptionalForLegacyJSON() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "timestamp": 12.5,
          "isEnabled": true
        }
        """

        let bookmark = try JSONDecoder().decode(Bookmark.self, from: Data(json.utf8))

        #expect(bookmark.bookmarkImageFileName == nil)
    }

    @Test func bookmarkImageURLPrefersAudiobookDirectory() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let imageURL = folder.appendingPathComponent("bookmark-image.jpg")
        try Data("image".utf8).write(to: imageURL)

        let bookmark = Bookmark(timestamp: 10, bookmarkImageFileName: "bookmark-image.jpg")

        #expect(bookmark.bookmarkImageURL(in: folder) == imageURL)
    }

    @Test func activeArtworkBookmarkUsesMostRecentEnabledImageBookmarkAtOrBeforePlaybackTime() {
        let trackId = "track-a"
        let bookmarks = [
            Bookmark(title: "Early", trackId: trackId, timestamp: 5, bookmarkImageFileName: "early.jpg"),
            Bookmark(title: "Later", trackId: trackId, timestamp: 12, bookmarkImageFileName: "later.jpg"),
            Bookmark(title: "Future", trackId: trackId, timestamp: 30, bookmarkImageFileName: "future.jpg"),
            Bookmark(title: "Other Track", trackId: "track-b", timestamp: 20, bookmarkImageFileName: "other.jpg"),
            Bookmark(title: "No Image", trackId: trackId, timestamp: 22)
        ]

        let active = PlayerModel.activeArtworkBookmark(from: bookmarks, at: 24, trackId: trackId)

        #expect(active?.title == "Later")
    }

    @Test func settingsRegisterLexendAsDefaultFont() {
        let suiteName = "settings-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsManager.registerDefaults(defaults: defaults, appGroupDefaults: defaults)

        #expect(defaults.string(forKey: "appFont") == "Lexend")
    }

    @Test func settingsNormalizeLegacyHelveticaToSystemFont() {
        #expect(SettingsManager.normalizedAppFont("Helvetica") == SettingsManager.systemFontName)
    }

}
