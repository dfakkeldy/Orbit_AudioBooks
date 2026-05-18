# Plan B12: MPVolumeView Hidden Slider Cleanup ✅ DONE (2026-05-15)

## Summary

Replace the off-screen `MPVolumeView` hack that reaches into internal `UISlider` to set system volume with a proper, App Review-safe approach.

## Current State

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` lines 257-262

```swift
@ObservationIgnored private var _volumeView: MPVolumeView?
// ...
let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 0, height: 0))
```

A hidden `MPVolumeView` at offscreen coordinates is used to traverse its subview hierarchy and find an internal `UISlider` to set system volume programmatically. This is a known App Review rejection vector — Apple considers it private API usage.

## Proposed Fix

Use `MPVolumeView` as a legitimate view in the hierarchy, or use `AVAudioSession` output volume APIs where supported.

### Recommended Approach

Replace the hidden view hack with a proper `MPVolumeView` in the toolbar view hierarchy:

1. Remove the hidden `_volumeView` property and all volume-setting methods that traverse its subviews from `PlayerModel`.
2. Add a standard `MPVolumeView` in `BottomToolbarView.swift` as part of the transport controls. `MPVolumeView` natively provides an AirPlay route picker and a volume slider.
3. For programmatic volume fade (sleep timer fade-out, voice memo ducking), use `AVAudioSession`:
   - `AVAudioSession.sharedInstance().outputVolume` (read, iOS 17+)
   - or a system volume slider via `MPVolumeView` that the user can interact with
4. If programmatic volume setting is required for the sleep timer fade, use `AVAudioPlayerNode.volume` on the `AVAudioEngine` chain instead of system volume.

### Alternative

Use `MPMusicPlayerController.applicationMusicPlayer` (deprecated) or the `AVAudioSession` route. The cleanest approach for audiobook fade-out is to fade the `AVAudioPlayerNode` gain, not the system volume.

## Files to Modify

| File | Change |
|------|--------|
| `OrbitAudioBooks/ViewModels/PlayerModel.swift` | Remove `_volumeView`, hidden view setup, and subview traversal |
| `OrbitAudioBooks/Views/BottomToolbarView.swift` | Add standard `MPVolumeView` to toolbar |

## Dependencies

- **Depends on:** Nothing
- **Blocked by:** Nothing
- **Conflicts with:** Plan A6 (AudioEngine encapsulation) — both touch volume control path; coordinate so A6's audio engine API exposes a `setGain(_:)` method that B12 uses for fade-out instead of system volume

## Complexity

**Small.** Two files, removal of ~15 lines, addition of ~5 lines of `MPVolumeView` in toolbar.
