import SwiftUI

struct RootTabView: View {
    @Binding var pendingDeepLink: PlayerDeepLink?
    @Environment(PlayerModel.self) private var model
    @Environment(SettingsManager.self) private var settings
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.displayScale) private var displayScale

    @State private var selectedTab = 0
    @State private var showingFolderPicker = false
    @State private var showingPlaylist = false
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var newBookmarkDraft: BookmarkDraft? = nil
    @State private var editingBookmarkID: UUID? = nil
    @State private var isTranscriptExpanded = false
    @State private var showingReview = false
    @State private var reviewViewModel: DailyReviewViewModel?
    @State private var reviewDueCount = 0

    init(pendingDeepLink: Binding<PlayerDeepLink?> = .constant(nil)) {
        _pendingDeepLink = pendingDeepLink
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                NowPlayingTab(
                    showingPlaylist: $showingPlaylist,
                    newBookmarkDraft: $newBookmarkDraft,
                    editingBookmarkID: $editingBookmarkID,
                    isTranscriptExpanded: $isTranscriptExpanded
                )
                .tabItem {
                    Label("Now Playing", systemImage: "play.circle")
                }
                .tag(0)

                TimelineTab(onReviewTap: { [weak model] in launchReview() })
                    .tabItem {
                        Label("Timeline", systemImage: "rectangle.split.2x1")
                    }
                    .tag(1)

                LibraryTab()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(2)

                PlannerTab()
                    .tabItem {
                        Label("Planner", systemImage: "calendar")
                    }
                    .tag(3)

                if reviewDueCount > 0 {
                    Color.clear
                        .tabItem {
                            Label("Review", systemImage: "rectangle.stack.fill")
                        }
                        .badge(reviewDueCount)
                        .tag(4)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(Text("Open folder"))
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel(Text("Help"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker { url in
                    showingFolderPicker = false
                    model.loadFolder(url)
                }
            }
            .sheet(isPresented: $showingPlaylist) {
                PlaylistView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingHelp) {
                NavigationStack {
                    HelpView()
                        .navigationTitle("Help")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingHelp = false }
                            }
                        }
                }
            }
            .sheet(item: Binding(
                get: { editingBookmarkID.map { IdentifiableUUID(id: $0) } },
                set: { editingBookmarkID = $0?.id }
            )) { wrapper in
                EditBookmarkView(bookmarkID: wrapper.id, draft: nil)
            }
            .sheet(item: $newBookmarkDraft) { draft in
                EditBookmarkView(bookmarkID: nil, draft: draft)
            }
            .sheet(isPresented: $showingReview) {
                if let vm = reviewViewModel {
                    FlashcardReviewSession(viewModel: vm)
                }
            }
            .onAppear {
                model.setSettingsManager(settings)
                model.setDisplayScale(displayScale)
                model.restoreLastSelectionIfPossible()
                applyPendingDeepLinkIfNeeded()
                refreshDueCount()
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 4 {
                    launchReview()
                    selectedTab = 0
                }
            }
            .onChange(of: pendingDeepLink) { _, _ in
                applyPendingDeepLinkIfNeeded()
            }
            .task {
                await storeManager.requestProducts()
            }
            .preferredColorScheme(settings.isDarkMode ? .dark : .light)
        }
    }

    private func launchReview() {
        guard let db = model.databaseService else { return }
        let vm = DailyReviewViewModel(db: db.writer, folderURL: model.folderURL, snippetPlayer: model.snippetPlayer)
        vm.onRequestSnippetPlay = { [weak model] url, start, end in
            model?.snippetPlayer.play(url: url, startTime: start, endTime: end)
        }
        vm.loadDueCards()
        reviewViewModel = vm
        showingReview = true
    }

    private func refreshDueCount() {
        guard let db = model.databaseService else { return }
        reviewDueCount = (try? FlashcardDAO(db: db.writer).allDueCards().count) ?? 0
    }

    private func applyPendingDeepLinkIfNeeded() {
        guard let pendingDeepLink else { return }
        model.handleDeepLink(pendingDeepLink)
        self.pendingDeepLink = nil
    }
}
