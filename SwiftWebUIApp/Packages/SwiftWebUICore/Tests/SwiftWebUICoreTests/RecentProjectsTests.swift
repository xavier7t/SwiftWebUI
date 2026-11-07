import Testing
import Foundation
@testable import SwiftWebUICore

/// Plain-path bookmarks: the data is the path, and `stale` / `broken` simulate bookmark problems.
private struct FakeBookmarks: BookmarkProvider {
    var stale = false
    var broken = false
    func makeBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        if broken { throw CocoaError(.fileReadCorruptFile) }
        return (URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self)), stale)
    }
}

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "swu-test-\(UUID().uuidString)")!
}

private func makeProject(_ name: String) throws -> Project {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swu-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try Project.create(name: name, in: dir.resolvingSymlinksInPath())
}

@Suite struct RecentProjectsTests {
    @Test func addsNewestFirstAndMovesDuplicatesToTop() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks())
        let a = try makeProject("A"), b = try makeProject("B")
        try store.add(a, now: Date(timeIntervalSince1970: 1))
        try store.add(b, now: Date(timeIntervalSince1970: 2))
        #expect(store.items.map(\.name) == ["B", "A"])
        try store.add(a, now: Date(timeIntervalSince1970: 3))
        #expect(store.items.map(\.name) == ["A", "B"])
        #expect(store.items.first?.lastOpened == Date(timeIntervalSince1970: 3))
    }

    @Test func limitsList() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks(), limit: 3)
        for n in 1...5 { try store.add(try makeProject("P\(n)")) }
        #expect(store.items.map(\.name) == ["P5", "P4", "P3"])
    }

    @Test func removes() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks())
        try store.add(try makeProject("A")); try store.add(try makeProject("B"))
        store.remove(store.items[0])
        #expect(store.items.map(\.name) == ["A"])
        store.removeAll()
        #expect(store.items.isEmpty)
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = makeDefaults()
        try RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks()).add(try makeProject("A"))
        #expect(RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks()).items.map(\.name) == ["A"])
    }

    @Test func resolvesAvailableProject() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks())
        let p = try makeProject("A")
        try store.add(p)
        #expect(store.resolve(store.items[0]) == .available(p.root))
        #expect(!store.isMissing(store.items[0]))
    }

    @Test func missingFolderIsReported() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks())
        let p = try makeProject("A")
        try store.add(p)
        try FileManager.default.removeItem(at: p.root)
        #expect(store.resolve(store.items[0]) == .missing)
        #expect(store.isMissing(store.items[0]))
        store.remove(store.items[0])
        #expect(store.items.isEmpty)
    }

    @Test func folderWithoutManifestIsMissing() throws {
        let store = RecentProjectsStore(defaults: makeDefaults(), bookmarks: FakeBookmarks())
        let p = try makeProject("A")
        try store.add(p)
        try FileManager.default.removeItem(at: p.root.appendingPathComponent(ProjectManifest.fileName))
        #expect(store.resolve(store.items[0]) == .missing)
    }

    @Test func unresolvableBookmarkIsMissing() throws {
        let defaults = makeDefaults()
        try RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks()).add(try makeProject("A"))
        let broken = RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks(broken: true))
        #expect(broken.resolve(broken.items[0]) == .missing)
        #expect(broken.isMissing(broken.items[0]))
    }

    @Test func staleBookmarkIsRenewedAndStillOpens() throws {
        let defaults = makeDefaults()
        let p = try makeProject("A")
        try RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks()).add(p)
        let store = RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks(stale: true))
        #expect(store.resolve(store.items[0]) == .available(p.root))
        #expect(store.items.count == 1)
    }

    @Test func corruptStorageYieldsEmptyList() {
        let defaults = makeDefaults()
        defaults.set(Data("nope".utf8), forKey: "recentProjects")
        #expect(RecentProjectsStore(defaults: defaults, bookmarks: FakeBookmarks()).items.isEmpty)
    }

    @Test func defaultTemplateParsesAndRendersWithoutErrors() {
        let parsed = ViewTreeBuilder.build(source: Project.defaultEntrySource, entryView: "ContentView")
        #expect(!parsed.hasErrors)
        #expect(parsed.diagnostics.isEmpty)
        let tree = try! #require(parsed.tree)
        let out = HTMLRenderer.render(tree)
        #expect(out.html.contains("Hello, SwiftWebUI"))
        #expect(out.diagnostics.isEmpty)
    }
}
