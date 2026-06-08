import Foundation

/// Manages security-scoped resource access grants for folder and file URLs.
/// Used by PlayerModel to maintain access to user-selected files outside the app sandbox.
final class SecurityScopeManager {
    private var hasSelectionAccess: Bool = false
    private var selectionURL: URL?

    private var hasFileAccess: Bool = false
    private var fileURL: URL?

    deinit {
        stopAll()
    }

    /// Starts accessing the security-scoped resource for the given selection URL.
    /// - Returns: `true` if access was granted, `false` otherwise (bookmark stale,
    ///            entitlements mismatch, or resource unavailable).
    @discardableResult
    func startSelection(url: URL) -> Bool {
        if hasSelectionAccess {
            if selectionURL == url { return true }
            stopSelection()
        }
        selectionURL = url
        hasSelectionAccess = url.startAccessingSecurityScopedResource()
        return hasSelectionAccess
    }

    /// Stops the selection security-scoped access and optionally starts a new one.
    func stopSelection() {
        guard hasSelectionAccess, let url = selectionURL else { return }
        url.stopAccessingSecurityScopedResource()
        hasSelectionAccess = false
        selectionURL = nil
    }

    /// Starts accessing the security-scoped resource for the given file URL.
    /// - Returns: `true` if access was granted, `false` otherwise.
    @discardableResult
    func startFile(url: URL) -> Bool {
        if hasFileAccess {
            if fileURL == url { return true }
            stopFile()
        }
        fileURL = url
        hasFileAccess = url.startAccessingSecurityScopedResource()
        return hasFileAccess
    }

    /// Stops the current file security-scoped access.
    func stopFile() {
        guard hasFileAccess, let url = fileURL else { return }
        url.stopAccessingSecurityScopedResource()
        hasFileAccess = false
        fileURL = nil
    }

    /// Stops both selection and file security-scoped access grants.
    func stopAll() {
        stopFile()
        stopSelection()
    }
}
