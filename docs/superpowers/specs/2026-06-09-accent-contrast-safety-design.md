# Accent Contrast Safety Net — Design

**Date:** 2026-06-09
**Status:** Approved for planning
**Area:** `EchoCore` — dynamic artwork accent colour pipeline (iOS player)

## 1. Problem

Echo derives the player's accent tint from cover artwork via
`DominantColorExtractor.extract(from:)`, surfaced as
`PlayerModel.artworkAccentColor` and applied across the Now Playing UI
(scrubber, dock, toolbar, header) and synced to the Watch as a hex string.

For most covers this is delightful. But for *The Programmer's Brain* (a
navy/white cover whose only vivid hue is a muted gold) the extracted gold
rendered the transport controls nearly invisible in **light mode**.

### Root cause

The extractor picks a reasonable *hue* but is **blind to the surface the tint
will be painted on**. It clamps lightness into a fixed `0.38–0.60` band, but
"mid lightness" is only safe *relative to a background*. Measured WCAG contrast
of the gold accent against the blurred-beige player surface:

| Surface | Contrast | Verdict |
|---|---|---|
| Light mode (the bug) | **1.78 : 1** | fails (needs ≥ 3:1 for controls) |
| Dark mode (same accent) | **7.21 : 1** | passes comfortably |

The failure is therefore **theme-dependent** and cannot be fixed from the
artwork alone — the rescue must know the rendering surface.

## 2. Goal & non-goals

**Goal:** A tightly-scoped safety net that rescues an accent **only** when it
would be genuinely illegible, while leaving every cover that works today
**100% untouched**. Keep the "colours from the cover" feel — including in the
hard cases.

**Non-goals:**
- No blanket re-tinting or WCAG enforcement that alters working covers.
- No change to the background gradient's look (only its caching).
- No Watch-side rescue (the Watch surface is always dark; it keeps the raw
  vivid hue). Listed as future work.

## 3. The trigger: a two-gate model

A single metric cannot separate "broken" from "fine." Sampling the rendered
accent vs. page surface across five real covers (hand-sampled hex, so treat the
*shape* as reliable and the exact numbers as approximate):

| Cover | OK? | WCAG | ΔE76 (chroma) |
|---|---|---|---|
| Clean Coder | fine | 3.38 | 50.9 |
| Kill It with Fire | fine | 2.94 | 61.2 |
| Pragmatic Programmer | fine | 2.63 | 44.7 |
| Emotional Design | fine | **1.86** | 57.3 |
| Programmer's Brain | **BROKEN** | **1.78** | 49.0 |

No single column isolates the broken cover (Emotional Design's luminance is
basically tied with Brain; Pragmatic's ΔE is *lower* than Brain). But **two
gates together** do: a control is legible if it clears **either**

- a **luminance gate** (WCAG ≥ `luminanceGate`) — saves Clean Coder, Kill It,
  Pragmatic, **or**
- a **chroma gate** (ΔE76 ≥ `chromaGate`) — saves Emotional Design's vivid
  orange.

Programmer's Brain is the only cover failing **both** → the rescue fires for it
alone. This is the "fails both → invisible" corner.

## 4. The rescue: A → B → C ladder

When an accent fails both gates, escalate progressively (mirrors the existing
`AutoAlignmentService` progressive-tier philosophy):

- **A — Nudge in place.** Keep hue + saturation, move lightness toward the
  contrast floor (darker on a light surface, lighter on a dark one). Accept if
  the lightness shift stays within `distortionBudget`. *Gold → `#8C7027`,
  3.49:1, ΔL ≈ 0.16.*
- **B — Re-pick a cover hue.** If A would distort the winner past the budget,
  walk the remaining ranked cover hues; use the first that is already legible
  (or becomes legible within budget). *Gold → cover navy `#34459B`, 6.29:1.*
- **C — Brand fallback.** If no cover hue works, use `Color.accentColor`,
  itself nudged to clear the floor. Always legible. *Note: raw brand
  `#F0982C` is only 1.68:1 on this surface, so even the fallback must be
  nudged — the nudge is the irreducible primitive.*

## 5. Architecture — fix once, at the source

`artworkAccentColor` feeds ~15 consumers plus the Watch hex. Patching call
sites would be fragile; instead the **source property becomes the safe colour**
and every consumer inherits safety with zero edits.

```
Cover artwork (currentDisplayArtwork ?? thumbnail)
   │
   ▼
DominantColorExtractor.extractPalette()            ← one cached pass
   → { rawAccent, candidates[], background[] }
   │                                   │
   │                                   ▼
   │                          AdaptiveBackground (reads palette.background;
   │                          no longer re-extracts every redraw)
   ▼
AccentSafetyNet.resolve(rawAccent, candidates, surface, brand)
   gates → A nudge → B re-pick → C brand        (+ colorScheme & surface estimate)
   │
   ▼
PlayerModel.artworkAccentColor  =  SAFE colour     ← single source of truth
   cached by (artworkVersion, colorScheme)
   ├── ~15 consumers (scrubber, dock, toolbar, header, Settings) — unchanged
   └── artworkAccentColorHex = RAW → Watch          — unchanged (dark surface)
```

### New units (pure — no UIKit/SwiftUI, fully unit-testable)

**`EchoCore/Utilities/ColorMetrics.swift`**
- `relativeLuminance(_:) -> Double`, `contrastRatio(_:_:) -> Double` (WCAG)
- `lab(_:) -> (L, a, b)`, `deltaE76(_:_:) -> Double`
- `isLegible(_ accent: Color, on surface: Color) -> Bool`
  = `contrastRatio ≥ luminanceGate || deltaE76 ≥ chromaGate`
- `nudged(_ color: Color, toClear floor: Double, against surface: Color)
   -> (color: Color, lightnessShift: Double)`
  — HSL lightness binary-search; direction from surface luminance; reports |ΔL|.

**`EchoCore/Services/AccentSafetyNet.swift`**
```swift
enum Tier { case original, nudged, repicked, brand }
struct Resolution { let color: Color; let tier: Tier }

static func resolve(rawAccent: Color, candidates: [Color],
                    surface: Color, brand: Color) -> Resolution {
    if ColorMetrics.isLegible(rawAccent, on: surface) {
        return .init(color: rawAccent, tier: .original)          // most covers
    }
    let a = ColorMetrics.nudged(rawAccent, toClear: contrastFloor, against: surface)
    if a.lightnessShift <= distortionBudget {
        return .init(color: a.color, tier: .nudged)              // A
    }
    for c in candidates where c != rawAccent {                   // B
        if ColorMetrics.isLegible(c, on: surface) {
            return .init(color: c, tier: .repicked)
        }
        let b = ColorMetrics.nudged(c, toClear: contrastFloor, against: surface)
        if b.lightnessShift <= distortionBudget {
            return .init(color: b.color, tier: .repicked)
        }
    }
    let c = ColorMetrics.nudged(brand, toClear: contrastFloor, against: surface)
    return .init(color: c.color, tier: .brand)                   // C — always legible
}

// representativeSurface(background:scheme:) -> Color
// = blend(average(background), schemeBase, materialWeight)
```

`Tier` is returned for debug logging and test assertions (which path fired),
matching the AutoAlignment debug-log convention.

### Thresholds — named, documented constants

| Constant | Value | Rationale |
|---|---|---|
| `luminanceGate` | 2.4 : 1 | under Pragmatic (2.63), over Emotional (1.86) |
| `chromaGate` (ΔE76) | 52 | over Brain (49), under Emotional (57) |
| `contrastFloor` | 3.0 : 1 | Apple/WCAG minimum for UI controls |
| `distortionBudget` | 0.22 (\|ΔL\|) | gold's 0.16 passes A; neon escalates to B |
| `materialWeight` | 0.70 | two `.ultraThinMaterial` layers ≈ mostly scheme base |

Doc comment on all: *"Tuned from a 5-cover sample. Bias toward leaving accents
untouched; revisit as the library grows."*

## 6. Changed files (contained)

- **`DominantColorExtractor.swift`** — add `extractPalette(from:) -> ArtworkPalette`
  (`{ rawAccent: Color?, candidates: [Color], background: [Color] }`) computed in
  a single downsample pass; refactor `extract` / `extractColors` to share it.
- **`PlayerModel.swift`** —
  - cache `artworkPalette` by `currentDisplayArtworkVersion` (input is
    `currentDisplayArtwork ?? thumbnailImage`);
  - add observable `var uiColorScheme: ColorScheme = .light`;
  - `artworkAccentColor`: `nil` iff `palette.rawAccent == nil` (greyscale / no
    image — **preserves SettingsView's nil contract**); otherwise
    `AccentSafetyNet.resolve(...)` result, cached by `(version, scheme)`;
  - `artworkAccentColorHex`: derived from `palette.rawAccent` (**raw**, Watch).
- **`AdaptiveBackground.swift`** — read `model.artworkPalette.background`
  instead of calling `extractColors` directly.
- **`RootTabView.swift`** — `@Environment(\.colorScheme)` +
  `.onChange(of: colorScheme, initial: true) { model.uiColorScheme = $1 }`.

## 7. Tests

**`ColorMetricsTests`**
- Known-pair contrast (gold/beige ≈ 1.78) and ΔE sanity values.
- `nudged` result clears `contrastFloor`; direction flips with surface
  luminance; reports a plausible |ΔL|.

**`AccentSafetyNetTests`** (the behavioural contract)
- Emotional-Design orange on peach → `.original` (chroma gate; **no
  over-correction**).
- Programmer's-Brain gold on beige → `.nudged`, result ≥ `contrastFloor`,
  |ΔL| ≤ `distortionBudget`.
- Pathological neon (very light, un-nudgeable in budget) → `.repicked` when a
  safe candidate exists, else `.brand`.
- Gold on a dark surface → `.original` (passes luminance gate).
- Empty candidates + failing winner → `.brand`, legible.

## 8. Risks & mitigations

- **Surface estimate accuracy.** The gates depend on a modelled surface colour,
  not the true composited pixels. Mitigation: gates are biased toward *not*
  rescuing (a working cover is never altered); `materialWeight` and gate
  thresholds are tunable constants; the result is deterministic and tested.
- **Threshold overfit (5 samples).** The two-gate *shape* is trustworthy; exact
  numbers are not. Mitigation: documented as provisional; `Tier` logging lets us
  observe real-library behaviour and retune.

## 9. Documentation to update (per CLAUDE.md doc-sync rule)

- **`ARCHITECTURE.md`** — new "Accent Contrast Safety" subsection: the
  two-gate trigger, the A→B→C ladder, and the single-source-of-truth flow.
- **Dynamic-accent feature note** wherever the artwork-accent feature is
  described (README/ARCHITECTURE).

## 10. Future work (out of scope)

- Watch-side rescue against the Watch's own surface.
- Tuning thresholds / surface model from telemetry once `Tier` data exists.
- Optional: expose the resolved `Tier` in a debug view, like
  `AutoAlignmentProgressView`.
