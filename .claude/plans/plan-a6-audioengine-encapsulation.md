# Plan A6: AudioEngine Volume Control API ✅ DONE (2026-05-16)

## Summary

Added `setGain(_:)` and `fadeGain(to:duration:)` to AudioEngine. The existing `setVolumeBoost(enabled:)` now delegates to `setGain(_:)` for a unified gain control path.

## Current State (updated after code review)

**File:** `OrbitAudioBooks/Services/AudioEngine.swift` — 389 lines

The AVAudioEngine migration (commit `ef91c5b`) already made the engine well-encapsulated:
- `playerNode`, `engine`, `eqNode`, `varispeedNode`, `audioFile` are all `private`
- Public API: `isPlaying`, `currentTime`, `duration`, `speed`, `isVolumeBoostEnabled`, `isItemLoaded`, `configureAudioSession()`, `seek(to:completion:)`, `playImmediately(atRate:)`, `pause()`, `cleanup()`

**What's missing:** There's no public API to adjust the EQ node's `globalGain`. The sleep timer fade-out and volume boost toggle currently can't control gain through AudioEngine.

## Proposed Change

Add two methods to AudioEngine:

```swift
/// Set the output gain of the EQ node. Range typically -96 to 24 dB.
/// 0.0 = unity gain, 9.0 = +9 dB boost.
func setGain(_ gain: Float) {
    eqNode?.globalGain = gain
}

/// Smoothly fade gain to a target value over the specified duration.
/// Uses a Timer that steps gain in small increments.
func fadeGain(to targetGain: Float, duration: TimeInterval) {
    guard let eqNode = eqNode else { return }
    let startGain = eqNode.globalGain
    let steps = Int(duration / 0.05)  // 20 steps per second
    let gainDelta = (targetGain - startGain) / Float(steps)
    var currentStep = 0
    
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
        currentStep += 1
        if currentStep >= steps {
            eqNode.globalGain = targetGain
            timer.invalidate()
        } else {
            eqNode.globalGain = startGain + gainDelta * Float(currentStep)
        }
    }
}
```

Remove `setSystemVolume(_:)`, `_volumeView`, and all MPVolumeView-related code from `PlayerModel` (moved to B12 plan — this plan just provides the API B12 needs).

## Files Modified

| File | Change | Status |
|------|--------|--------|
| `OrbitAudioBooks/Services/AudioEngine.swift` | Add `setGain(_:)`, `fadeGain(to:duration:)`; refactor `setVolumeBoost` to delegate to `setGain` | ✅ |

## Implementation Notes

- `setGain(_:)` is a simple passthrough to `eqNode?.globalGain`
- `fadeGain(to:duration:)` uses a repeating Timer at ~50ms intervals (20 steps/sec), with a guard for `steps > 0`
- `setVolumeBoost(enabled:)` now calls `setGain(enabled ? 9.0 : 0.0)` instead of directly setting `eqNode?.globalGain` — all gain changes go through the new API

## Dependencies

- **Depends on:** Nothing
- **Blocked by:** Nothing
- **Conflicts with:** None. This is additive — two new methods, no existing API changes.

## Complexity

**Small.** ~30 lines of new code in one file. The old scope (fix encapsulation) is already done.
