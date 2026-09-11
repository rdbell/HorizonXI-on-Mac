// Runs with Command Line Tools; XCTest requires the full Xcode SDK.
import Foundation

@main
struct WineLocaleFixTests {
    static func main() throws {
        let tests = Self()
        try tests.testInstallPreservesOriginalsAndDoesNotRewriteOnSecondLaunch()
        try tests.testCorruptSecondResourceLeavesBothInstalledFilesUntouched()
        try tests.testUnrecognizedInstalledRuntimeIsPreserved()
        try tests.testInvalidRollbackCopyPreventsUpdate()
        print("4 Wine locale installation tests passed")
    }

    private struct Failure: Error { let message: String }
    private func checkEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected { throw Failure(message: "Expected \(expected), got \(actual)") }
    }
    private func checkThrows(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw Failure(message: "Expected rejection")
    }

    private func fixture() throws -> (root: URL, runtime: URL, bundle: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runtime = root.appendingPathComponent("runtime")
        let bundle = root.appendingPathComponent("bundle")
        var originals: [String: String] = [:], files: [String: String] = [:]
        for name in WineLocaleFix.files {
            let target = runtime.appendingPathComponent("wine/lib/wine/\(name)")
            let source = bundle.appendingPathComponent(name)
            for file in [target, source] {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            let original = Data("original \(name)".utf8), patched = Data("patched \(name)".utf8)
            try original.write(to: target)
            try patched.write(to: source)
            originals[name] = WineLocaleFix.digest(original)
            files[name] = WineLocaleFix.digest(patched)
        }
        let manifest: [String: Any] = ["runtime": WineRuntime.version, "files": files, "originals": originals]
        try JSONSerialization.data(withJSONObject: manifest).write(to: bundle.appendingPathComponent("build.json"))
        return (root, runtime, bundle)
    }

    func testInstallPreservesOriginalsAndDoesNotRewriteOnSecondLaunch() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var messages: [String] = []
        try WineLocaleFix.apply(to: f.runtime, bundle: f.bundle) { messages.append($0) }
        var dates: [String: Date] = [:]
        for name in WineLocaleFix.files {
            let target = f.runtime.appendingPathComponent("wine/lib/wine/\(name)")
            try checkEqual(try Data(contentsOf: target), Data("patched \(name)".utf8))
            try checkEqual(try Data(contentsOf: f.runtime.appendingPathComponent("\(WineLocaleFix.backupDirectory)/\(name)")),
                           Data("original \(name)".utf8))
            dates[name] = try target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        try WineLocaleFix.apply(to: f.runtime, bundle: f.bundle) { messages.append($0) }
        try checkEqual(messages.count, 1)
        for name in WineLocaleFix.files {
            let target = f.runtime.appendingPathComponent("wine/lib/wine/\(name)")
            try checkEqual(try target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, dates[name])
        }
    }

    func testCorruptSecondResourceLeavesBothInstalledFilesUntouched() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try Data("corrupt".utf8).write(to: f.bundle.appendingPathComponent(WineLocaleFix.files[1]))
        try checkThrows { try WineLocaleFix.apply(to: f.runtime, bundle: f.bundle) { _ in } }
        for name in WineLocaleFix.files {
            try checkEqual(try Data(contentsOf: f.runtime.appendingPathComponent("wine/lib/wine/\(name)")),
                           Data("original \(name)".utf8))
        }
    }

    func testUnrecognizedInstalledRuntimeIsPreserved() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let target = f.runtime.appendingPathComponent("wine/lib/wine/\(WineLocaleFix.files[1])")
        try Data("custom build".utf8).write(to: target)
        try checkThrows { try WineLocaleFix.apply(to: f.runtime, bundle: f.bundle) { _ in } }
        try checkEqual(try Data(contentsOf: target), Data("custom build".utf8))
        let name = WineLocaleFix.files[0]
        try checkEqual(try Data(contentsOf: f.runtime.appendingPathComponent("wine/lib/wine/\(name)")), Data("original \(name)".utf8))
    }

    func testInvalidRollbackCopyPreventsUpdate() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let backup = f.runtime.appendingPathComponent("\(WineLocaleFix.backupDirectory)/\(WineLocaleFix.files[1])")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("wrong backup".utf8).write(to: backup)
        try checkThrows { try WineLocaleFix.apply(to: f.runtime, bundle: f.bundle) { _ in } }
        for name in WineLocaleFix.files {
            try checkEqual(try Data(contentsOf: f.runtime.appendingPathComponent("wine/lib/wine/\(name)")), Data("original \(name)".utf8))
        }
    }
}
