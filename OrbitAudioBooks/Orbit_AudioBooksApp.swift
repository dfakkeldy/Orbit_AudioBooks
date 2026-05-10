//
//  Orbit_AudioBooksApp.swift
//  Orbit Audiobooks
//
//  Created by Dan Fakkeldy on 2026-04-19.
//

import SwiftUI

@main
struct Orbit_AudioBooksApp: App {
    init() {
        #if DEBUG && targetEnvironment(simulator)
        MockMediaProvider.seedSampleAudiobookIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
