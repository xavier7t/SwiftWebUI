import Testing
import Foundation
@testable import SwiftWebUICore

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swu-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

@Suite struct ProjectTests {
    @Test func createAndLoad() throws {
        let dir = try makeTempDir()
        let created = try Project.create(name: "Site", in: dir)
        let loaded = try Project.load(at: created.root)
        #expect(loaded.manifest == ProjectManifest(name: "Site"))
        #expect(FileManager.default.fileExists(atPath: loaded.sourcesURL.appendingPathComponent("ContentView.swift").path))
    }

    @Test func createRejectsInvalidAndExisting() throws {
        let dir = try makeTempDir()
        #expect(throws: ProjectError.self) { try Project.create(name: "a/b", in: dir) }
        try Project.create(name: "Site", in: dir)
        #expect(throws: ProjectError.alreadyExists(dir.appendingPathComponent("Site"))) {
            try Project.create(name: "Site", in: dir)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Plain"), withIntermediateDirectories: true)
        #expect(throws: ProjectError.nameCollision("Plain")) { try Project.create(name: "Plain", in: dir) }
    }

    @Test func missingManifest() throws {
        let dir = try makeTempDir()
        #expect(throws: ProjectError.missingManifest(dir)) { try Project.load(at: dir) }
        let message = ProjectError.missingManifest(dir).errorDescription ?? ""
        #expect(message.contains("swiftwebui.json"))
    }

    @Test func invalidManifest() throws {
        let dir = try makeTempDir()
        try "{ nope".write(to: dir.appendingPathComponent("swiftwebui.json"), atomically: true, encoding: .utf8)
        #expect(throws: ProjectError.self) { try Project.load(at: dir) }
        try #"{"name":"x","sources":"../out","entryView":"V"}"#
            .write(to: dir.appendingPathComponent("swiftwebui.json"), atomically: true, encoding: .utf8)
        #expect(throws: ProjectError.self) { try Project.load(at: dir) }
    }

    @Test func missingSourcesFolder() throws {
        let dir = try makeTempDir()
        try #"{"name":"x","sources":"Sources","entryView":"V"}"#
            .write(to: dir.appendingPathComponent("swiftwebui.json"), atomically: true, encoding: .utf8)
        #expect(throws: ProjectError.missingSourcesFolder(dir)) { try Project.load(at: dir) }
    }

    @Test func nameValidation() {
        for bad in ["", " ", "a/b", "a:b", "..", ".", " lead", "trail "] {
            #expect(throws: ProjectError.self) { try FileNameValidator.validate(bad) }
        }
        #expect(throws: Never.self) { try FileNameValidator.validate("Hero.swift") }
    }
}

@Suite struct FileOperationsTests {
    private func makeOps() throws -> FileOperations {
        FileOperations(project: try Project.create(name: "P", in: try makeTempDir()))
    }

    @Test func createFileAndFolderAndTreeOrder() throws {
        let ops = try makeOps()
        let src = ops.project.sourcesURL
        try ops.createFile(named: "b.swift", in: src)
        try ops.createFolder(named: "Views", in: src)
        try ops.createFile(named: "Card.swift", in: src.appendingPathComponent("Views"))
        let tree = try ops.tree()
        #expect(tree.map(\.name) == ["Views", "b.swift", "ContentView.swift"].sorted { a, b in
            // folders first, then localized order
            a == "Views" || (b != "Views" && a.localizedStandardCompare(b) == .orderedAscending)
        })
        #expect(tree.first?.children?.map(\.name) == ["Card.swift"])
    }

    @Test func collisions() throws {
        let ops = try makeOps()
        let src = ops.project.sourcesURL
        #expect(throws: ProjectError.nameCollision("ContentView.swift")) {
            try ops.createFile(named: "ContentView.swift", in: src)
        }
        // case-insensitive collision
        #expect(throws: ProjectError.nameCollision("contentview.swift")) {
            try ops.createFile(named: "contentview.swift", in: src)
        }
        let a = try ops.createFile(named: "a.swift", in: src)
        try ops.createFile(named: "b.swift", in: src)
        #expect(throws: ProjectError.nameCollision("b.swift")) { try ops.rename(a, to: "b.swift") }
    }

    @Test func invalidNames() throws {
        let ops = try makeOps()
        let src = ops.project.sourcesURL
        #expect(throws: ProjectError.self) { try ops.createFile(named: "x/y.swift", in: src) }
        #expect(throws: ProjectError.self) { try ops.createFolder(named: "", in: src) }
    }

    @Test func rename() throws {
        let ops = try makeOps()
        let a = try ops.createFile(named: "a.swift", in: ops.project.sourcesURL, contents: "x")
        let b = try ops.rename(a, to: "b.swift")
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(try String(contentsOf: b, encoding: .utf8) == "x")
    }

    @Test func moveAndGuards() throws {
        let ops = try makeOps()
        let src = ops.project.sourcesURL
        let folder = try ops.createFolder(named: "F", in: src)
        let file = try ops.createFile(named: "a.swift", in: src)
        let moved = try ops.move(file, into: folder)
        #expect(moved.deletingLastPathComponent().lastPathComponent == "F")
        #expect(throws: ProjectError.self) { try ops.move(folder, into: folder) }
        let sub = try ops.createFolder(named: "Sub", in: folder)
        #expect(throws: ProjectError.self) { try ops.move(folder, into: sub) }
        try ops.createFile(named: "a.swift", in: src)
        #expect(throws: ProjectError.nameCollision("a.swift")) {
            try ops.move(src.appendingPathComponent("a.swift"), into: folder)
        }
    }

    @Test func trash() throws {
        let ops = try makeOps()
        let a = try ops.createFile(named: "gone.swift", in: ops.project.sourcesURL)
        try ops.trash(a)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(throws: ProjectError.notFound(a)) { try ops.trash(a) }
    }

    @Test func outsideProjectRejected() throws {
        let ops = try makeOps()
        let outside = try makeTempDir().appendingPathComponent("x.swift")
        try "".write(to: outside, atomically: true, encoding: .utf8)
        #expect(throws: ProjectError.outsideProject(outside)) { try ops.trash(outside) }
        #expect(throws: ProjectError.self) { try ops.rename(ops.project.sourcesURL, to: "Other") }
    }
}

@Suite struct ProjectWatcherTests {
    @Test func outsideChangeTriggersRefresh() async throws {
        let dir = try makeTempDir()
        let fired = AsyncStream<Void>.makeStream()
        let watcher = ProjectWatcher(url: dir, latency: 0.05) { fired.continuation.yield() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try "hi".write(to: dir.appendingPathComponent("new.swift"), atomically: true, encoding: .utf8)
        let got = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in fired.stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let r = await group.next() ?? false
            group.cancelAll()
            return r
        }
        #expect(got)
    }
}
