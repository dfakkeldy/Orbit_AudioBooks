# Cover-Derived Tonal Themes — Design

Date: 2026-06-10
Status: Approved (design review with Dan, this session)
Supersedes: the `AccentSafetyNet` rescue-ladder approach

## Problem

The Now Playing theme extracts colors from cover artwork and uses them directly as
UI colors, with `AccentSafetyNet` rescuing illegible accents after the fact. The
rescue trigger in `ColorMetrics.isLegible` accepts an accent if it clears EITHER a
WCAG luminance gate (≥ 2.4:1) OR a ΔE76 chroma gate (≥ 52). Verified against the
real code (2026-06-10): a bright extractor yellow (`#EEC32B`) on the Company of One
beige surface measures 1.06:1 luminance contrast — unreadable — but ΔE76 = 65, so
the chroma gate passes it and the rescue ladder never runs. The relationship is
perverse: higher saturation inflates ΔE76, so the most vivid (most problematic)
yellows are the most certain to bypass rescue. The `saturationFloor` added to the
extractor pushes accents toward this loophole.

Root causes, in order of depth:

1. ΔE76 treats chromatic distance as equivalent to luminance distance, but human
   acuity for fine detail (glyphs, icon strokes) is carried almost entirely by the
   luminance channel. A chroma-only gate can never be trusted for UI legibility.
2. HSL lightness is not perceptual: yellow at HSL L 0.55 is near-white in real
   luminance (~0.59), navy at the same L is dark (~0.13). The extractor's
   lightness clamp (0.38–0.60) therefore means different things per hue.
3. Architecture: colors are extracted-then-validated. Validation can be wrong
   (and was); construction cannot.

## Goal

Every cover yields a legible, beautiful theme — including pale, low-chroma, and
yellow-dominant covers — while staying recognizably derived from the cover's
identity. Contrast is guaranteed by construction and proven by a property test,
not checked by gates.

Aesthetic direction (decided with Dan): backgrounds follow the system scheme —
pale tonal ramps in light mode, immersive deep tones in dark mode.

## Non-goals (deferred, see Future work)

- Animated background drift / `MeshGradient`
- Blurred-artwork backdrop mode
- Accent-gradient progress ring
- Reader/EPUB theming changes

## Architecture

```
UIImage ──> DominantColorExtractor ──> CoverSignature ──> CoverThemeBuilder ──> CoverTheme
            (histogram, unchanged      (identity: hues,    (pure; tone           (role colors)
             sampling core)             weights, chroma)    recipes per scheme)        │
                                                                                       ▼
                                                              PlayerModel.coverTheme (cached)
                                                                │
                            ┌──────────────────┬───────────────┼───────────────────┐
                            ▼                  ▼               ▼                   ▼
                    AdaptiveBackground   NowPlayingTab   artworkAccentColor   Watch hex sync
                    (tonal ramp)         (chip/onAccent) (facade, unchanged   (dark-recipe
                                                          for all callers)     accent)
```

The extractor reports what the cover IS; the builder decides what the UI LOOKS
LIKE. `AccentSafetyNet` is deleted — the failure mode it rescued is
unrepresentable in the new pipeline.

## Components

### 1. `EchoCore/Utilities/OKLCH.swift` (new)

Pure math, no UIKit/SwiftUI imports beyond `Color` bridging kept out of this file.

- `srgbToOKLCH(_:) -> (L: Double, C: Double, H: Double)` and inverse
- `clampedChroma(L:C:H:) -> Double` — largest chroma ≤ C that fits sRGB gamut
  at the given L/H (binary search, ~20 iterations, deterministic)

Why OKLCH: perceptually uniform lightness across hues (fixes root cause 2) with
~80 lines of math. HCT/CAM16 adds viewing-condition machinery this app doesn't
need.

### 2. `DominantColorExtractor` (modified)

Keeps: 100×100 downsample, neutral-pixel filtering, saturation²-weighted hue
histogram with centre bias. Changes:

- Output becomes `CoverSignature`:

  ```swift
  struct CoverSignature {
      struct HueCandidate {
          let hue: Double      // OKLCH hue angle, degrees, from bucket's weighted mean RGB
          let chroma: Double   // mean OKLCH chroma of the bucket
          let weight: Double   // saturation² × centre-bias coverage score
      }
      let candidates: [HueCandidate]  // ranked by weight, may be empty
      let isNeutral: Bool             // true when vivid coverage < 2% of sampled pixels
  }
  ```

- Removed: `saturationFloor`, lightness-target clamps, `ArtworkPalette`,
  `backgroundDefaults`, `pad`, and the `extract`/`extractColors` convenience
  entry points (PlayerModel is the only production caller; tests migrate).
- Added: minimum-coverage floor (vivid pixels < 2% of sample → `isNeutral`),
  so one stray colored pixel can no longer theme a book.

### 3. `EchoCore/Services/CoverThemeBuilder.swift` (new)

`static func build(from signature: CoverSignature, scheme: ColorScheme) -> CoverTheme`
— pure and unit-testable, like the builder it replaces.

```swift
struct CoverTheme {
    let accent: Color           // interactive tint
    let onAccent: Color         // glyphs inside accent-filled controls
    let secondaryAccent: Color  // gradients, secondary indicators
    let backgroundTop: Color    // AdaptiveBackground ramp
    let backgroundBottom: Color
    let chip: Color             // pills and control circles
    let isNeutralFallback: Bool // drives artworkAccentColor's nil contract
}
```

Tone recipes (OKLCH; hue H comes from the cover, chroma is
`clampedChroma`-limited per hue):

| Role             | Light (pale ramp)    | Dark (immersive)     |
|------------------|----------------------|----------------------|
| backgroundTop    | L 0.96, C 0.025      | L 0.26, C 0.045      |
| backgroundBottom | L 0.93, C 0.040      | L 0.21, C 0.050      |
| chip             | L 0.89, C 0.050      | L 0.32, C 0.060      |
| accent           | L 0.47, C 0.130      | L 0.78, C 0.120      |
| onAccent         | L 0.97, C 0.020      | L 0.22, C 0.040      |

Safety valve: after constructing `accent`, if WCAG contrast vs
`backgroundBottom` < 3.0 (possible only at extreme gamut corners), step accent L
away from the background in 0.01 increments until it clears — bounded,
deterministic, and exercised by the property test so regressions surface in CI.

Role assignment:

- Primary hue = highest-weight candidate.
- `secondaryAccent` hue = first candidate with circular ΔH ≥ 60° from primary
  and weight ≥ 15% of primary's; otherwise primary hue + 30° at the accent
  recipe.
- Neutral covers (`isNeutral` or no candidates): warm-grey ramp (H 80°,
  C 0.010 for backgrounds/chip) with the brand accent (`Color.accentColor`)
  as `accent`; `isNeutralFallback = true`. Replaces today's blue/purple/indigo
  placeholder gradient.

Text: system semantic colors (`.primary`, `.secondary`) remain in use. Light
ramps are pale enough for dark text; in dark scheme the system already supplies
light text over the deep ramp. Dynamic Type and accessibility contrast settings
keep working untouched.

### 4. `PlayerModel` (modified)

- `coverTheme: CoverTheme`, cached per `(currentDisplayArtworkVersion,
  uiColorScheme)` — same pattern as today's `cachedSafeAccent`.
- `artworkAccentColor: Color?` preserved as a facade: returns
  `coverTheme.isNeutralFallback ? nil : coverTheme.accent`. All existing
  `?? .accentColor` call sites (BottomToolbarView, EchoCoreApp, SettingsView,
  NowPlayingTab, Watch) work unchanged on day one.
- `artworkAccentColorHex` (Watch sync) now encodes the DARK-recipe accent —
  Watch surfaces are always dark, so the raw accent was the wrong choice there
  too.
- `artworkPalette` and the safe-accent cache are removed with their consumers.

### 5. `AdaptiveBackground` (rewritten)

`LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)`
— replaces systemBackground + blurred two-layer gradient + `.ultraThinMaterial`.
Cheaper to render (no 50pt blur pass) and produces the designed ramp from the
approved mockups instead of the pastel wash.

### 6. `NowPlayingTab` (+ direct chip surfaces it owns)

Transport circles and pills adopt `theme.chip` as fill with accent glyphs; the
play/pause button becomes accent-filled with `theme.onAccent` glyph. Other
views keep consuming the `artworkAccentColor` facade this iteration.

## Edge cases

| Case | Behavior |
|------|----------|
| No artwork loaded | Neutral theme; retry extraction when artwork appears (existing version-cache pattern) |
| Greyscale cover | `isNeutral` → neutral theme, `artworkAccentColor == nil` |
| Vivid area < 2% | Same as greyscale |
| Single-hue cover | `secondaryAccent` = primary + 30° sibling |
| Extreme gamut corner | Builder's bounded L-step safety valve |
| Scheme flips while playing | Theme cache keyed on scheme; recompute is pure math (no re-extraction) |
| macOS / watchOS | OKLCH + builder are platform-pure; Watch consumes pre-built hex |

## Testing

- `OKLCHTests` (new): round-trips vs known references (white → L 1 C 0; sRGB
  primaries), gamut-clamp monotonicity.
- `CoverThemeBuilderTests` (new): the property sweep — for hue 0…359 × both
  schemes, assert contrast(accent, backgroundTop/Bottom) ≥ 3.0,
  contrast(accent, chip) ≥ 2.5, contrast(onAccent, accent) ≥ 4.5. This test IS
  the "by construction" guarantee. Role-assignment and neutral-fallback cases.
- `DominantColorExtractorTests` (updated): signature output; synthetic
  Company-of-One image (cream field + yellow band + navy shapes) asserting a
  warm-hue primary, navy-family secondary, `isNeutral == false`; coverage-floor
  case (a few vivid pixels on grey → `isNeutral`).
- `ColorMetricsTests` (trimmed): WCAG luminance/contrast functions stay (the
  property test depends on them); two-gate and nudge tests removed.
- `AccentSafetyNetTests`: deleted with the service.

## Build order

1. `OKLCH.swift` + tests
2. Extractor → `CoverSignature` + updated tests
3. `CoverThemeBuilder` + property tests
4. `PlayerModel` theme cache, facade, Watch hex
5. `AdaptiveBackground` rewrite
6. `NowPlayingTab` chip/onAccent adoption
7. Delete `AccentSafetyNet` + its tests; trim `ColorMetrics`; remove
   `UIImage+Color.swift` area-average helpers if grep confirms no callers
8. Docs: `ARCHITECTURE.md` accent-pipeline section, `CHANGELOG.md`,
   `CODE_AUDIT.md` addendum recording the ΔE76 gate bug as found-and-superseded

## Future work (explicitly out of scope)

- Slow gradient drift while playing (`TimelineView`-driven), frozen on pause
- `MeshGradient` background variant (iOS 18+)
- Accent→secondary gradient on the play-button progress ring
- Optional blurred-artwork backdrop mode
