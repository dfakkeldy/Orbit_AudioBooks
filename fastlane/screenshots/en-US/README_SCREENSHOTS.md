# App Store Screenshots

Drop your screenshots into this directory following the naming convention below.
Fastlane `deliver` will automatically upload them to App Store Connect.

## Naming Convention

Use numbered prefixes to control sort order, a descriptive slug, and the device type:

```
1_Player_iPhone.png
2_Library_iPhone.png
3_Search_iPhone.png
1_Player_Mac.png
2_Library_Mac.png
1_NowPlaying_Watch.png
```

## Required Sizes

| Device | Resolution |
|---|---|
| iPhone 16 Pro Max | 1320 x 2868 |
| iPhone 16 Pro | 1206 x 2622 |
| iPad Pro 13" | 2064 x 2752 |
| Mac | 2880 x 1800 |
| Apple Watch Ultra | 410 x 502 |

## Notes

- Screenshots are gitignored by default (see `.gitignore` Fastlane rules).
- To version-control screenshots, remove the `fastlane/screenshots/**/*.png` entry from `.gitignore`.
- Use `fastlane snapshot` to automate screenshot capture across multiple device simulators.
