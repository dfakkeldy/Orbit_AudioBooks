# Architecture Overview

<!-- ⚠️  AUTO-GENERATED — do not edit directly. -->
<!-- Regenerate with: `make architecture`                        -->

**Last generated:** 2026-05-13 22:58:24

This document maps the source-tree layout of the three Xcode targets in the
Orbit Audiobooks project. Folders are shown in the order returned by the
filesystem; only source, configuration, and metadata files are included
(build artifacts, asset catalogs, and media files are filtered out).

---

## OrbitAudioBooks (iOS)

```
AppGroupDefaults.swift
Info.plist
MockMediaProvider.swift
Orbit_AudioBooksApp.swift
ViewModels/PlayerModel.swift
Views/Bookmarks.swift
Views/ContentView.swift
Views/PlayerScrubberView.swift
Views/TranscriptView.swift
```

## Orbit Audiobooks macOS

```
Info.plist
Orbit_Audiobooks_macOS.entitlements
Orbit_Audiobooks_macOSApp.swift
Views/MacContentView.swift
Views/MacPlayerModel.swift
Views/TranscriptionManager.swift
Views/TranscriptPane.swift
Views/TranscriptStore.swift
```

## Orbit Audiobooks Watch App

```
Info.plist
OrbitAudioBooksWatchApp.swift
Views/Bookmarks.swift
Views/ContentView.swift
```

