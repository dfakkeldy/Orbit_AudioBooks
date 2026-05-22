import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(PlayerModel.self) private var model
    @Environment(SettingsManager.self) private var settings
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasingPro = false
    @State private var isRestoringPurchases = false
    @State private var isRetryingProducts = false
    @State private var showingDeckImporter = false
    @State private var importAlert: (title: String, message: String)?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Display") {
                    NavigationLink("Appearance") {
                        Form {
                            Section {
                                Toggle("Dark Mode", isOn: $settings.isDarkMode)
                            }
                            Section("Typography") {
                                Picker("Font", selection: $settings.appFont) {
                                    Text("Lexend (Default)").tag("Lexend")
                                    Text("OpenDyslexic").tag("OpenDyslexic")
                                    Text("System").tag(SettingsManager.systemFontName)
                                }
                            }
                        }
                        .navigationTitle("Appearance")
                    }
                }

                Section("Store") {
                    NavigationLink("Pro Transcripts") {
                        ProTranscriptsSettingsView(
                            isPurchasingPro: $isPurchasingPro,
                            isRestoringPurchases: $isRestoringPurchases,
                            isRetryingProducts: $isRetryingProducts
                        )
                    }
                }

                Section("Watch") {
                    NavigationLink("Watch App") {
                        WatchAppSettingsView()
                    }
                }

                Section("Playback") {
                    Toggle("Volume Boost", isOn: Binding(
                        get: { model.isVolumeBoostEnabled },
                        set: { model.setVolumeBoost(enabled: $0) }
                    ))
                    NavigationLink("Smart Rewind") {
                        SmartRewindSettingsView()
                    }
                }

                Section {
                    Toggle("Play Bookmarks Inline", isOn: $settings.playBookmarksInline)
                } footer: {
                    Text("When enabled, voice memos attached to bookmarks are played automatically when the audiobook reaches that timestamp.")
                }

                Section("Flashcards") {
                    Button {
                        showingDeckImporter = true
                    } label: {
                        Label("Import Deck", systemImage: "square.and.arrow.down")
                    }
                }

                Section {
                    NavigationLink("Help") {
                        HelpView()
                            .navigationTitle("Help")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.font, settings.appFont == SettingsManager.systemFontName ? .body : .custom(settings.appFont, size: 17, relativeTo: .body))
        .fileImporter(
            isPresented: $showingDeckImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, let db = model.databaseService else { return }
                let importer = DeckImportService()
                do {
                    let count = try importer.importDeck(from: url, db: db.writer)
                    importAlert = ("Import Complete", "Imported \(count) cards successfully.")
                } catch {
                    importAlert = ("Import Failed", error.localizedDescription)
                }
            case .failure(let error):
                importAlert = ("Import Failed", error.localizedDescription)
            }
        }
        .alert(importAlert?.title ?? "", isPresented: Binding(
            get: { importAlert != nil },
            set: { if !$0 { importAlert = nil } }
        )) {
            Button("OK") { importAlert = nil }
        } message: {
            if let message = importAlert?.message {
                Text(message)
            }
        }
        .preferredColorScheme(settings.isDarkMode ? .dark : .light)
    }
}

private struct ProTranscriptsSettingsView: View {
    @Environment(StoreManager.self) private var storeManager
    @Binding var isPurchasingPro: Bool
    @Binding var isRestoringPurchases: Bool
    @Binding var isRetryingProducts: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(storeManager.hasUnlockedPro ? String(localized: "Unlocked") : String(localized: "Locked"))
                        .foregroundStyle(storeManager.hasUnlockedPro ? .green : .secondary)
                }

                if let product = storeManager.proUnlockProduct, !storeManager.hasUnlockedPro {
                    Button {
                        Task { await purchasePro() }
                    } label: {
                        if isPurchasingPro {
                            ProgressView()
                        } else {
                            Text(String(localized: "Unlock for \(product.displayPrice)"))
                        }
                    }
                    .disabled(isPurchasingPro || isRestoringPurchases)
                } else if !storeManager.hasUnlockedPro {
                    Button {
                        Task { await retryProducts() }
                    } label: {
                        if isRetryingProducts {
                            ProgressView()
                        } else {
                            Text("Retry Loading Purchase")
                        }
                    }
                    .disabled(isRetryingProducts || isPurchasingPro || isRestoringPurchases)
                }

                Button {
                    Task { await restorePurchases() }
                } label: {
                    if isRestoringPurchases {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(isPurchasingPro || isRestoringPurchases)
            } footer: {
                Text("Unlock transcript overlays for audiobooks with transcript sidecars.")
            }

            if let lastStoreError = storeManager.lastStoreError {
                Section {
                    Text(lastStoreError)
                        .foregroundStyle(.red)
                } header: {
                    Text("StoreKit Error")
                }
            }
        }
        .navigationTitle("Pro Transcripts")
        .task {
            if storeManager.proUnlockProduct == nil {
                await storeManager.requestProducts()
            }
        }
    }

    private func purchasePro() async {
        isPurchasingPro = true
        defer { isPurchasingPro = false }
        do {
            try await storeManager.purchaseProUnlock()
        } catch {
            storeManager.recordStoreError(error)
        }
    }

    private func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        await storeManager.restorePurchases()
    }

    private func retryProducts() async {
        isRetryingProducts = true
        defer { isRetryingProducts = false }
        await storeManager.requestProducts()
    }
}
