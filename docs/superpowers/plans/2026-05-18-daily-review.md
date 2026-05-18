# Daily Review UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire orphaned FlashcardReviewCard/FlashcardReviewSession views into the app with a ViewModel, snippet player, and three navigation entry points (dashboard card, timeline row, review tab).

**Architecture:** New `DailyReviewViewModel` (@Observable) wraps `FlashcardDAO` + `SpacedRepetitionService`. New `SnippetPlayer` follows the proven BookmarkStore voice memo pattern (separate AVAudioEngine, pause/resume main player). Three navigation entry points converge on a `.sheet` presenting `FlashcardReviewSession`.

**Tech Stack:** SwiftUI, Observation, AVFoundation, GRDB (FlashcardDAO)

---

### Task 1: Create SnippetPlayer

**Files:**
- Create: `OrbitAudioBooks/Services/SnippetPlayer.swift`

- [ ] **Step 1: Write SnippetPlayer**

```swift
import AVFoundation

/// Plays a segment of an audio file using a separate AVAudioEngine instance,
/// following the same pattern as BookmarkStore voice memo playback.
final class SnippetPlayer {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var progressTimer: Timer?

    var isPlaying: Bool = false
    var onPlaybackWillStart: (() -> Void)?
    var onPlaybackDidEnd: (() -> Void)?

    func play(url: URL, startTime: TimeInterval, endTime: TimeInterval) {
        stop()

        guard let file = try? AVAudioFile(forReading: url) else { return }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, startTime * sampleRate))
        let endFrame = AVAudioFramePosition(min(Double(file.length), endTime * sampleRate))
        let framesToPlay = AVAudioFrameCount(endFrame - startFrame)
        guard framesToPlay > 0 else { return }

        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: file.processingFormat)

        do {
            try eng.start()
        } catch {
            return
        }

        onPlaybackWillStart?()

        node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesToPlay, at: nil) { [weak self] in
            DispatchQueue.main.async { self?.handlePlaybackEnded() }
        }
        node.play()

        engine = eng
        playerNode = node
        isPlaying = true
    }

    func stop() {
        playerNode?.stop()
        engine?.stop()
        engine?.reset()
        progressTimer?.invalidate()
        progressTimer = nil
        playerNode = nil
        engine = nil
        isPlaying = false
    }

    private func handlePlaybackEnded() {
        stop()
        onPlaybackDidEnd?()
    }
}
```

- [ ] **Step 2: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 3: Commit**

```bash
git add OrbitAudioBooks/Services/SnippetPlayer.swift
git commit -m "feat(anki): add SnippetPlayer for flashcard media snippet playback"
```

---

### Task 2: Create DailyReviewViewModel

**Files:**
- Create: `OrbitAudioBooks/ViewModels/DailyReviewViewModel.swift`

- [ ] **Step 1: Write DailyReviewViewModel**

```swift
import Foundation
import Observation

@Observable
final class DailyReviewViewModel {
    var dueCards: [Flashcard] = []
    var currentIndex: Int = 0
    var isRevealed: Bool = false
    var isPlayingSnippet: Bool = false
    var snippetPlayer: SnippetPlayer?

    private let db: DatabaseWriter
    private let folderURL: URL?
    var onRequestSnippetPlay: ((URL, TimeInterval, TimeInterval) -> Void)?

    var currentCard: Flashcard? {
        guard dueCards.indices.contains(currentIndex) else { return nil }
        return dueCards[currentIndex]
    }

    var progress: (current: Int, total: Int) {
        (min(currentIndex + 1, dueCards.count), dueCards.count)
    }

    var isComplete: Bool {
        currentIndex >= dueCards.count
    }

    init(db: DatabaseWriter, folderURL: URL?) {
        self.db = db
        self.folderURL = folderURL
    }

    func loadDueCards() {
        do {
            let dao = FlashcardDAO(db: db)
            dueCards = try dao.allDueCards()
            currentIndex = 0
            isRevealed = false
        } catch {
            dueCards = []
        }
    }

    func reveal() {
        isRevealed = true
        guard let card = currentCard,
              let end = card.endTimestamp,
              end > card.mediaTimestamp,
              let url = constructSourceURL(for: card.audiobookID) else { return }
        onRequestSnippetPlay?(url, card.mediaTimestamp, end)
    }

    func gradeCard(_ grade: Int) {
        guard let card = currentCard else { return }
        snippetPlayer?.stop()
        isPlayingSnippet = false
        do {
            let dao = FlashcardDAO(db: db)
            try dao.grade(cardID: card.id, grade: grade)
            logFlashcardReviewed(card: card, grade: grade)
        } catch {}
        advance()
    }

    func advance() {
        snippetPlayer?.stop()
        isPlayingSnippet = false
        currentIndex += 1
        isRevealed = false
    }

    private func constructSourceURL(for audiobookID: String) -> URL? {
        guard let folder = folderURL else { return nil }
        return URL(fileURLWithPath: audiobookID, relativeTo: folder)
    }

    private func logFlashcardReviewed(card: Flashcard, grade: Int) {
        let dao = RealTimeEventDAO(db: db)
        let meta = try? JSONEncoder().encode(["cardId": card.id, "grade": grade])
        let metaJSON = meta.flatMap { String(data: $0, encoding: .utf8) }
        try? dao.log(
            id: UUID().uuidString,
            eventType: "flashcardReviewed",
            audiobookID: card.audiobookID,
            mediaTimestamp: card.mediaTimestamp,
            startedAt: Date(),
            endedAt: nil,
            title: card.frontText,
            subtitle: "Grade: \(grade)",
            metadataJSON: metaJSON,
            sourceItemID: card.id,
            sourceItemType: "flashcard"
        )
    }
}
```

- [ ] **Step 2: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 3: Commit**

```bash
git add OrbitAudioBooks/ViewModels/DailyReviewViewModel.swift
git commit -m "feat(anki): add DailyReviewViewModel with SM-2 grading and timeline logging"
```

---

### Task 3: Update FlashcardReviewCard with grade labels

**Files:**
- Modify: `OrbitAudioBooks/Views/FlashcardReviewCard.swift`

- [ ] **Step 1: Add labels to middle grade buttons**

Replace the grade button labels (lines 42-64) with labeled variants:

```swift
if isRevealed {
    HStack(spacing: 8) {
        ForEach(0..<6) { grade in
            Button {
                onGrade(grade)
            } label: {
                VStack(spacing: 2) {
                    Text("\(grade)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(gradeLabel(grade))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(gradeColor(grade).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.top, 8)
    .transition(.opacity)
}
```

Add the `gradeLabel` helper next to the existing `gradeColor`:

```swift
private func gradeLabel(_ grade: Int) -> String {
    switch grade {
    case 0: return "Again"
    case 1, 2: return "Hard"
    case 3, 4: return "Good"
    case 5: return "Easy"
    default: return ""
    }
}
```

- [ ] **Step 2: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 3: Commit**

```bash
git add OrbitAudioBooks/Views/FlashcardReviewCard.swift
git commit -m "feat(anki): add grade labels to FlashcardReviewCard buttons"
```

---

### Task 4: Integrate FlashcardReviewSession with ViewModel

**Files:**
- Modify: `OrbitAudioBooks/Views/FlashcardReviewSession.swift`

- [ ] **Step 1: Rewrite FlashcardReviewSession**

Replace the entire file with the ViewModel-driven version:

```swift
import SwiftUI

struct FlashcardReviewSession: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: DailyReviewViewModel

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isComplete {
                    ContentUnavailableView(
                        "All Done",
                        systemImage: "checkmark.circle.fill",
                        description: Text("You've reviewed all due flashcards.")
                    )
                } else if let card = viewModel.currentCard {
                    HStack {
                        Text("Card \(viewModel.progress.current) of \(viewModel.progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    ProgressView(value: Double(viewModel.progress.current), total: Double(viewModel.progress.total))
                        .padding(.horizontal, 20)

                    Spacer()

                    FlashcardReviewCard(
                        frontText: card.frontText,
                        backText: card.backText,
                        onGrade: { grade in
                            viewModel.gradeCard(grade)
                        }
                    )

                    Spacer()
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.snippetPlayer?.stop()
                        dismiss()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 3: Commit**

```bash
git add OrbitAudioBooks/Views/FlashcardReviewSession.swift
git commit -m "feat(anki): integrate FlashcardReviewSession with DailyReviewViewModel"
```

---

### Task 5: Make UpcomingReviewsModuleView tappable

**Files:**
- Modify: `OrbitAudioBooks/Views/UpcomingReviewsModuleView.swift`

- [ ] **Step 1: Add tap handler**

Change the body to wrap in a Button:

```swift
import SwiftUI

struct UpcomingReviewsModuleView: View {
    @Environment(PlayerModel.self) private var model

    @State private var dueCount: Int = 0
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("Reviews Due", systemImage: "rectangle.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(dueCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(dueCount > 0 ? .purple : .secondary)

                Text(dueCount == 0 ? "all caught up" : "tap to review")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 120)
            .background(.purple.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onAppear { loadDueCount() }
    }

    private func loadDueCount() {
        guard let db = model.databaseService else { return }
        do {
            let dao = FlashcardDAO(db: db.writer)
            dueCount = try dao.allDueCards().count
        } catch {
            dueCount = 0
        }
    }
}
```

- [ ] **Step 2: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 3: Commit**

```bash
git add OrbitAudioBooks/Views/UpcomingReviewsModuleView.swift
git commit -m "feat(anki): make UpcomingReviewsModuleView tappable with onTap handler"
```

---

### Task 6: Wire snippet callbacks in PlayerModel

**Files:**
- Modify: `OrbitAudioBooks/ViewModels/PlayerModel.swift`

- [ ] **Step 1: Add SnippetPlayer property and callbacks**

Add the snippet player property near the other service properties (near line 140):

```swift
let snippetPlayer = SnippetPlayer()
```

Wire callbacks in `init()`, near the voice memo callbacks (near line 264):

```swift
snippetPlayer.onPlaybackWillStart = { [weak self] in
    self?.prepareAudioForVoiceMemo()
}
snippetPlayer.onPlaybackDidEnd = { [weak self] in
    guard let self else { return }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [])
    try? session.setActive(true)
    if self.isPlaying {
        self.audioEngine.playImmediately(atRate: self.speed)
        self.playbackController.applySpeedToCurrentItem()
        self.updateNowPlayingInfo(isPaused: false)
    }
}
```

- [ ] **Step 2: Add pass-through property**

Near the bookmark/voice memo pass-throughs (near line 164):

```swift
var isPlayingSnippet: Bool { snippetPlayer.isPlaying }
```

- [ ] **Step 3: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 4: Commit**

```bash
git add OrbitAudioBooks/ViewModels/PlayerModel.swift
git commit -m "feat(anki): wire SnippetPlayer callbacks in PlayerModel"
```

---

### Task 7: Wire navigation entry points (DashboardShelf, TimelineTab, RootTabView)

**Files:**
- Modify: `OrbitAudioBooks/Views/DashboardShelf.swift`
- Modify: `OrbitAudioBooks/Views/TimelineTab.swift`
- Modify: `OrbitAudioBooks/Views/RootTabView.swift`

- [ ] **Step 1: DashboardShelf — pass onTap to UpcomingReviewsModuleView**

Replace `UpcomingReviewsModuleView()` at line 36 with:

```swift
UpcomingReviewsModuleView(onTap: onReviewTap)
```

The `UpcomingReviewsModuleView` init needs the `onTap` parameter to be optional with a default — already handled in Task 5's code.

Actually, since `onTap` defaults to `nil`, we only need to pass it when we want the tappable version. For DashboardShelf, we need the tap. Add a property and pass it:

In `DashboardShelf`, add:

```swift
var onReviewTap: (() -> Void)?
```

And change line 36 to:

```swift
UpcomingReviewsModuleView(onTap: onReviewTap)
```

- [ ] **Step 2: TimelineTab — add due-row**

Add below `DashboardShelf()` (line 27):

```swift
if dueCount > 0 {
    Button {
        showingReview = true
    } label: {
        HStack {
            Label("\(dueCount) cards due for review", systemImage: "rectangle.stack.fill")
                .font(.caption)
                .foregroundStyle(.purple)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
}
```

Add state and binding near the top of `TimelineTab`:

```swift
@State private var dueCount: Int = 0
@Binding var showingReview: Bool
```

Update init:

```swift
init(showingReview: Binding<Bool> = .constant(false)) {
    _showingReview = showingReview
}
```

Load `dueCount` in the existing `onAppear` (add to the one at line 39):

```swift
dueCount = (try? FlashcardDAO(db: db.writer).allDueCards().count) ?? 0
```

- [ ] **Step 3: RootTabView — add review sheet + view model**

Add state at the top:

```swift
@State private var showingReview = false
@State private var reviewViewModel: DailyReviewViewModel?
```

Add review tab (after LibraryTab, before closing TabView):

```swift
if reviewDueCount > 0 {
    Button {
        launchReview()
    } label: {
        EmptyView()
    }
    .tabItem {
        Label("Review", systemImage: "rectangle.stack.fill")
    }
    .badge(reviewDueCount)
    .tag(3)
}
```

Add `@State private var reviewDueCount = 0`.

Add `launchReview` helper:

```swift
private func launchReview() {
    guard let db = model.databaseService else { return }
    let vm = DailyReviewViewModel(db: db.writer, folderURL: model.folderURL)
    vm.snippetPlayer = model.snippetPlayer
    vm.onRequestSnippetPlay = { [weak model] url, start, end in
        model?.snippetPlayer.play(url: url, startTime: start, endTime: end)
    }
    vm.loadDueCards()
    reviewViewModel = vm
    showingReview = true
}
```

Add sheet modifier (after the existing sheets):

```swift
.sheet(isPresented: $showingReview) {
    if let vm = reviewViewModel {
        FlashcardReviewSession(viewModel: vm)
    }
}
```

Update `DashboardShelf()` call in `TimelineTab` to pass the binding:

```swift
DashboardShelf(onReviewTap: { launchReview() })
```

Update `TimelineTab()` call:

```swift
TimelineTab(showingReview: $showingReview)
```

Add `onAppear` or `.task` to refresh `reviewDueCount`:

```swift
.task {
    if let db = model.databaseService {
        reviewDueCount = (try? FlashcardDAO(db: db.writer).allDueCards().count) ?? 0
    }
}
```

- [ ] **Step 4: Build**

Build from Xcode — verify no compile errors.

- [ ] **Step 5: Commit**

```bash
git add OrbitAudioBooks/Views/DashboardShelf.swift OrbitAudioBooks/Views/TimelineTab.swift OrbitAudioBooks/Views/RootTabView.swift
git commit -m "feat(anki): add review navigation (dashboard card, timeline row, tab)"
```

---

## Verification

1. Build compiles without errors
2. When `Flashcard` records exist with `next_review_date <= now`, the "Reviews Due" dashboard card shows the count
3. Tapping the dashboard card opens `FlashcardReviewSession` as a sheet
4. TimelineTab shows "N cards due for review" row when count > 0, hidden when 0
5. RootTabView shows 4th "Review" tab with badge when due cards exist, hidden when 0
6. Card front text displays, tap reveals back text + grade buttons with labels
7. Tapping a grade button advances to next card
8. Snippet player plays source audio segment when card has valid `mediaTimestamp`/`endTimestamp`
9. Main player pauses during snippet, resumes after grading
10. Session dismisses after last card, due count refreshes
11. Timeline shows `flashcardReviewed` events after grading
