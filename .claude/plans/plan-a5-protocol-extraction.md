# Plan A5: Protocol Extraction for Testability ✅ DONE (2026-05-16)

## Summary

Extracted protocols for services to enable unit testing. The environment key migration for SettingsManager/StoreManager was intentionally skipped — both use `@Observable`, which loses automatic view invalidation through a protocol existential. Protocols are still defined for mock injection in PlayerModel tests.

## Current State

17 views inject concrete types via `@Environment(\.self)`:

```swift
@Environment(PlayerModel.self) private var model
@Environment(SettingsManager.self) private var settings
@Environment(StoreManager.self) private var storeManager
```

## Critical Constraint: @Observable + Protocols (VALIDATED)

**Confirmed during implementation:** SwiftUI's Observation framework (iOS 17+) tracks property reads through the concrete `@Observable` type. Both SettingsManager and StoreManager ARE `@Observable` (not `@Published` as the original plan assumed). Views use `@Bindable` for two-way bindings (e.g., `$settings.isDarkMode`), which requires the concrete `@Observable` type.

Environment key migration for SettingsManager/StoreManager was **skipped** — it would silently break view reactivity and binding support.

## Revised Approach

### For PlayerModel: Composition, Not Substitution

Keep `PlayerModel` as the single `@Observable` type in the environment. Views continue to use `@Environment(PlayerModel.self)`. But PlayerModel internally delegates to protocol-conforming components:

```swift
@Observable
final class PlayerModel {
    // Injected via init — mockable in tests
    let bookmarkStore: BookmarkStoreProtocol
    let playbackController: PlaybackControllerProtocol
    let sleepTimerManager: SleepTimerManagerProtocol
    
    // These are set via .environment() in the app entry point
    var settingsManager: SettingsManagerProtocol
    var storeManager: StoreManagerProtocol
    
    // Computed pass-throughs for views
    var bookmarks: [Bookmark] { bookmarkStore.bookmarks }
    var isPlaying: Bool { playbackController.isPlaying }
    // ...
    
    init(
        bookmarkStore: BookmarkStoreProtocol = BookmarkStore(),
        playbackController: PlaybackControllerProtocol = PlaybackController(),
        sleepTimerManager: SleepTimerManagerProtocol = SleepTimerManager()
    ) {
        self.bookmarkStore = bookmarkStore
        self.playbackController = playbackController
        self.sleepTimerManager = sleepTimerManager
    }
}
```

In tests:
```swift
let mockStore = MockBookmarkStore()
let mockPlayback = MockPlaybackController()
let model = PlayerModel(bookmarkStore: mockStore, playbackController: mockPlayback)
```

### For SettingsManager and StoreManager: Protocols Only, No Environment Migration

Both are `@Observable` — they STAY as concrete types in the environment. The protocols exist solely for:
- Mock objects in unit tests
- Future PlayerModel composition (A1 can take `SettingsManagerProtocol` in its init)

Views continue using the existing pattern:
```swift
@Environment(SettingsManager.self) private var settings
@Environment(StoreManager.self) private var storeManager
```

### Component Protocols (internal — used by PlayerModel, not views)

```swift
protocol BookmarkStoreProtocol {
    var bookmarks: [Bookmark] { get }
    var currentTrackBookmarks: [Bookmark] { get }
    func addBookmark(at time: TimeInterval, note: String?) async -> Bookmark
    func deleteBookmark(id: UUID)
    func jumpToBookmark(_ bookmark: Bookmark)
    var onBookmarksChanged: (() -> Void)? { get set }
}

protocol PlaybackControllerProtocol {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval? { get }
    var speed: Float { get set }
    func play()
    func pause()
    func togglePlayPause()
    func skipForward()
    func skipBackward()
    func seek(to: TimeInterval)
}

protocol SleepTimerManagerProtocol {
    var mode: SleepTimerMode { get }
    var secondsRemaining: TimeInterval { get }
    func setTimer(minutes: Int)
    func setEndOfChapter()
    func cancel()
}

protocol SettingsManagerProtocol {
    var font: AppFont { get set }
    var smartRewindEnabled: Bool { get set }
    var sleepTimerFadeOut: Bool { get set }
    var watchLayout: String { get set }
}

protocol StoreManagerProtocol {
    var hasUnlockedPro: Bool { get }
    var proUnlockProduct: Product? { get }
    func purchase() async throws
    func restore() async throws
}
```

## Implementation Done (2026-05-16)

1. ✅ Defined component protocols (`BookmarkStoreProtocol`, `PlaybackControllerProtocol`, `SleepTimerManagerProtocol`)
2. ✅ Defined `SettingsManagerProtocol` and `StoreManagerProtocol` (NO environment keys — @Observable conflict)
3. ✅ Updated `SettingsManager` and `StoreManager` to conform
4. ⏭️ Skipped view environment migration (would break @Observable tracking and @Bindable)
5. ✅ Created mock implementations in test target (`MockBookmarkStore`, `MockPlaybackController`, etc.)
6. ✅ Added 8 unit tests for mocks and PlayerModel init — all passing
7. 🔜 (Later, during A1) Extract components behind the already-defined protocols

## Files Created/Modified

| Action | File | Status |
|--------|------|--------|
| Create | `OrbitAudioBooks/Protocols/PlayerModelComponentProtocols.swift` | ✅ |
| Create | `OrbitAudioBooks/Protocols/SettingsManagerProtocol.swift` | ✅ |
| Create | `OrbitAudioBooks/Protocols/StoreManagerProtocol.swift` | ✅ |
| ~~Create~~ | ~~Environment key files~~ | ❌ Skipped — @Observable incompatible |
| Modify | `OrbitAudioBooks/Services/SettingsManager.swift` (add conformance) | ✅ |
| Modify | `OrbitAudioBooks/Services/StoreManager.swift` (add conformance) | ✅ |
| ~~Modify~~ | ~~17 views / app entry point~~ | ❌ Skipped — @Observable incompatible |
| Create | `Orbit AudiobooksTests/Mocks/MockBookmarkStore.swift` | ✅ |
| Create | `Orbit AudiobooksTests/Mocks/MockPlaybackController.swift` | ✅ |
| Create | `Orbit AudiobooksTests/Mocks/MockSleepTimerManager.swift` | ✅ |
| Create | `Orbit AudiobooksTests/Mocks/MockSettingsManager.swift` | ✅ |
| Create | `Orbit AudiobooksTests/Mocks/MockStoreManager.swift` | ✅ |
| Create | `Orbit AudiobooksTests/PlayerModelTests.swift` | ✅ (8 tests passing) |

## Dependencies

- **Blocked by:** Nothing — can be done independently and should go FIRST
- **Blocks:** Plan A1 (PlayerModel decomposition) — protocols define the boundaries components must conform to

## Complexity

**Medium.** Protocol definitions are straightforward. The SettingsManager/StoreManager environment migration is mechanical (17 views, find-and-replace). PlayerModel stays concrete in views — no view changes needed for the PlayerModel path.
