# Plan A5: Protocol Extraction for Testability

## Summary

Extract protocols for services to enable unit testing. Account for the fact that PlayerModel uses `@Observable` (iOS 17+ Observation framework) which does not support protocol-typed environment injection with automatic change tracking.

## Current State

17 views inject concrete types via `@Environment(\.self)`:

```swift
@Environment(PlayerModel.self) private var model
@Environment(SettingsManager.self) private var settings
@Environment(StoreManager.self) private var storeManager
```

## Critical Constraint: @Observable + Protocols

**Code review finding:** SwiftUI's Observation framework (iOS 17+) tracks property reads through the concrete `@Observable` type used as the environment key. You CANNOT replace `@Environment(PlayerModel.self)` with a protocol-typed environment value and retain automatic view invalidation.

```swift
// This does NOT work with Observation:
@Environment(PlayerModelProtocol.self) private var model
// Views won't re-render when properties change because Observation
// can't track reads through a protocol existential.
```

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

### For SettingsManager and StoreManager: Protocols via Environment

These are NOT `@Observable` — they use `@Published` or are simple value types. They CAN be protocol-typed in the environment:

```swift
// Define custom environment keys
struct SettingsManagerKey: EnvironmentKey {
    static let defaultValue: SettingsManagerProtocol = SettingsManager()
}

struct StoreManagerKey: EnvironmentKey {
    static let defaultValue: StoreManagerProtocol = StoreManager()
}

extension EnvironmentValues {
    var settings: SettingsManagerProtocol {
        get { self[SettingsManagerKey.self] }
        set { self[SettingsManagerKey.self] = newValue }
    }
    var storeManager: StoreManagerProtocol {
        get { self[StoreManagerKey.self] }
        set { self[StoreManagerKey.self] = newValue }
    }
}
```

Views then use:
```swift
@Environment(\.settings) private var settings
@Environment(\.storeManager) private var storeManager
```

### Component Protocols (NOT environment-facing)

These protocols are used internally by PlayerModel, not by views:

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

## Migration Strategy

1. Define component protocols (`BookmarkStoreProtocol`, `PlaybackControllerProtocol`, etc.)
2. Define `SettingsManagerProtocol` and `StoreManagerProtocol` + environment keys
3. Update `SettingsManager` and `StoreManager` to conform
4. Update views to use `@Environment(\.settings)` and `@Environment(\.storeManager)`
5. Create mock implementations in test targets
6. Add initial unit tests for PlayerModel with mock services
7. (Later, during A1) Extract components behind the already-defined protocols

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Protocols/PlayerModelComponentProtocols.swift` |
| Create | `OrbitAudioBooks/Protocols/SettingsManagerProtocol.swift` |
| Create | `OrbitAudioBooks/Protocols/StoreManagerProtocol.swift` |
| Create | `OrbitAudioBooks/Environment/SettingsEnvironmentKey.swift` |
| Create | `OrbitAudioBooks/Environment/StoreManagerEnvironmentKey.swift` |
| Modify | `OrbitAudioBooks/Services/SettingsManager.swift` (add conformance) |
| Modify | `OrbitAudioBooks/Services/StoreManager.swift` (add conformance) |
| Modify | `OrbitAudioBooks/Orbit_AudioBooksApp.swift` (register environment keys) |
| Modify | 17 views: `@Environment(SettingsManager.self)` → `@Environment(\.settings)` |
| Modify | 17 views: `@Environment(StoreManager.self)` → `@Environment(\.storeManager)` |
| Create | `OrbitAudioBooksTests/Mocks/MockBookmarkStore.swift` |
| Create | `OrbitAudioBooksTests/Mocks/MockPlaybackController.swift` |
| Create | `OrbitAudioBooksTests/Mocks/MockSettingsManager.swift` |
| Create | `OrbitAudioBooksTests/Mocks/MockStoreManager.swift` |

## Dependencies

- **Blocked by:** Nothing — can be done independently and should go FIRST
- **Blocks:** Plan A1 (PlayerModel decomposition) — protocols define the boundaries components must conform to

## Complexity

**Medium.** Protocol definitions are straightforward. The SettingsManager/StoreManager environment migration is mechanical (17 views, find-and-replace). PlayerModel stays concrete in views — no view changes needed for the PlayerModel path.
