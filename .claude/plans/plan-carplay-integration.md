# Plan: CarPlay Integration ✅ DONE (2026-05-18)

## Summary

Add full CarPlay support for the audiobook player, including Now Playing integration with steering wheel controls, a chapter/bookmark browser, and proper entitlement configuration.

## Current State

- **Zero CarPlay** — no entitlements, no framework references, no `Info.plist` entries
- `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are already integrated in `PlayerModel.swift` (lines 1557-1665)
- `UIBackgroundModes` already includes `audio` and `fetch`
- The existing `MPRemoteCommandCenter` handlers cover: play, pause, toggle, skip forward, skip backward, next track, previous track, change playback position, change playback rate
- No `CPTemplateApplicationScene` or `CarPlay.framework` usage

## Implementation Steps

### 1. Entitlements & Info.plist

Add the CarPlay entitlement:
```xml
<key>com.apple.developer.carplay-audio</key>
<true/>
```

Add to `Info.plist`:
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

### 2. CarPlay Scene Delegate

```swift
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var playerModel: PlayerModel?
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        
        // Set root template: tab bar with Now Playing + Browse tabs
        let tabTemplate = CPTabBarTemplate(templates: [
            createBrowseTemplate(),
            createNowPlayingTemplate()
        ])
        interfaceController.setRootTemplate(tabTemplate, animated: false)
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }
}
```

### 3. Browse Template

A `CPListTemplate` showing:
- **Now Playing** — current track with chapter
- **Chapters** — list of chapters in the current book (or aggregated from folder)
- **Bookmarks** — user's bookmarks for the current book

Each list item uses `CPListImageRowItem` or `CPListItem` with a tap handler that seeks to the corresponding position.

### 4. Now Playing Deep Integration

The existing `MPNowPlayingInfoCenter` setup already drives CarPlay's Now Playing screen. Ensure:

- **Album art** is the correct size (CarPlay expects up to 400x400)
- **Chapter title** is included in `MPNowPlayingInfoPropertyChapterTitle` (or as subtitle)
- **Progress** updates at a reasonable interval (already on 0.25s timer via AudioEngine)
- **Duration** is accurate
- **Playback rate** is updated on speed changes

The existing `MPRemoteCommandCenter` handlers (already registered in `setupRemoteTransportControls()`) will automatically work with CarPlay's steering wheel and dashboard controls.

### 5. Watch Connectivity Bridge

When CarPlay is connected, the watch app may still be active. Ensure commands from BOTH sources don't conflict:
- Use a serial command queue in `PlayerModel`
- CarPlay remote commands and Watch commands both go through the same `handleCommand(_:)` entry point

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/CarPlay/CarPlaySceneDelegate.swift` |
| Create | `OrbitAudioBooks/CarPlay/CarPlayBrowseTemplate.swift` |
| Modify | `OrbitAudioBooks/Info.plist` — CarPlay scene config |
| Modify | `Orbit Audiobooks.entitlements` — add `carplay-audio` |
| Modify | `OrbitAudioBooks/Orbit_AudioBooksApp.swift` — scene configuration |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` — ensure Now Playing info includes chapter titles |
| Modify | `Orbit Audiobooks.xcodeproj/project.pbxproj` — add CarPlay framework |

## Dependencies

- **Blocked by:**
  - Plan A1 (PlayerModel decomposition) — CarPlay's `CarPlaySceneDelegate` needs a reference to the playback controller. The extracted `NowPlayingController` + `PlaybackController` are the right targets.
  - Plan A6 (AudioEngine encapsulation) — CarPlay remote commands route through AudioEngine API
  - Plan Phase 2 (M4B folders) — CarPlay chapter browser must show aggregated chapters
- **Conflicts with:** None significant. CarPlay is additive — it adds a scene, it doesn't modify existing views.

## Complexity

**Large.** Entitlements, scene delegate, CarPlay framework integration, template UI, and thorough testing (requires CarPlay simulator or real CarPlay head unit). The Now Playing integration is mostly done; the template UI is the new work.
