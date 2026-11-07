import Foundation

/// The state of one open file: its text, dirty flag, autosave and outside-change detection.
/// Not UI-bound; the editor view drives it from the main actor.
@MainActor
public final class OpenFileSession {
    public enum ExternalChange: Equatable, Sendable {
        /// The file changed on disk and was reloaded (no unsaved edits).
        case reloaded
        /// The file changed on disk while there are unsaved edits; the user must choose.
        case conflict
        /// The file was deleted on disk.
        case deleted
    }

    public let url: URL
    public private(set) var text: String
    public private(set) var isDirty = false
    /// Loaded-from-disk fingerprint, used to ignore our own writes.
    private var diskText: String?
    private var diskModified: Date?

    public var autosaveDelay: Duration
    public var onExternalChange: ((ExternalChange) -> Void)?
    public var onSaveError: ((Error) -> Void)?

    private var autosaveTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]

    public init(url: URL, autosaveDelay: Duration = .milliseconds(800)) throws {
        self.url = url
        self.autosaveDelay = autosaveDelay
        let loaded = try Self.read(url)
        text = loaded
        diskText = loaded
        diskModified = Self.modified(url)
    }

    deinit { autosaveTask?.cancel() }

    // MARK: Editing

    /// Called by the editor whenever the user changes the text.
    public func textDidChange(_ new: String) {
        guard new != text else { return }
        text = new
        isDirty = (new != diskText)
        for c in continuations.values { c.yield(new) }
        scheduleAutosave()
    }

    /// A stream of the current text, then every change. Feeds the preview pipeline (Phase 5).
    public func changes() -> AsyncStream<String> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(text)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    // MARK: Saving

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isDirty else { return }
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Saves immediately (used on file switch, window close, and by autosave).
    @discardableResult
    public func save() -> Bool {
        autosaveTask?.cancel()
        guard isDirty else { return true }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            diskText = text
            diskModified = Self.modified(url)
            isDirty = false
            return true
        } catch {
            onSaveError?(error)
            return false
        }
    }

    // MARK: Outside changes

    /// Call when the project watcher reports changes. Compares the file on disk with what we last read/wrote.
    @discardableResult
    public func checkForExternalChange() -> ExternalChange? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return report(.deleted)
        }
        guard let onDisk = try? Self.read(url), onDisk != diskText else {
            diskModified = Self.modified(url)
            return nil
        }
        if isDirty { return report(.conflict) }
        adopt(onDisk)
        return report(.reloaded)
    }

    /// Resolve a conflict by taking the disk version.
    public func reloadFromDisk() {
        autosaveTask?.cancel()
        if let onDisk = try? Self.read(url) { adopt(onDisk) }
    }

    /// Resolve a conflict by keeping the editor version (overwrites the disk).
    public func keepEditorVersion() {
        diskText = nil
        isDirty = true
        save()
    }

    private func adopt(_ onDisk: String) {
        text = onDisk
        diskText = onDisk
        diskModified = Self.modified(url)
        isDirty = false
        for c in continuations.values { c.yield(onDisk) }
    }

    private func report(_ change: ExternalChange) -> ExternalChange {
        onExternalChange?(change)
        return change
    }

    // MARK: IO

    private static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let s = String(data: data, encoding: .utf8) else {
            throw ProjectError.operationFailed("“\(url.lastPathComponent)” is not a UTF-8 text file.")
        }
        return s
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
