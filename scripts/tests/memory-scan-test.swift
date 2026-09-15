import Foundation
import CryptoKit
// Standalone test, matching the repository's Command Line Tools test workflow.
enum Install {
    static func winePath(_ url: URL, driveC: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \(expected), got \(actual)")
}
func checkTrue(_ actual: Bool) { precondition(actual) }
func checkFalse(_ actual: Bool) { precondition(!actual) }

final class MemoryScanTests {
    private func fixture(_ body: String) throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let common = root.appendingPathComponent("common.lua")
        try Data(body.utf8).write(to: common)
        for name in ["scan.lua", "ximac-scan.dll"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let digest = SHA256.hash(data: Data("fixture".utf8)).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = ["abi": 1, "files": ["scan.lua": digest, "ximac-scan.dll": digest]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("build.json"))
        return (root, common, root.appendingPathComponent("drive_c"))
    }

    func testHookPreservesBytesLineEndingsPermissionsAndRollback() throws {
        for ending in ["\n", "\r\n"] {
            let original = "\u{FEFF}-- custom text" + ending + "-- Extension Libraries" + ending + "return {}"
            let (root, common, drive) = try fixture(original)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: common.path)
            let environment = MemoryScan.prepare(common: common, resources: root, driveC: drive)
            checkEqual(environment.count, 2)
            checkTrue(environment[MemoryScan.scriptVariable]!.hasPrefix("Z:"))
            let patched = try String(decoding: Data(contentsOf: common), as: UTF8.self)
            let hook = MemoryScan.shim.replacingOccurrences(of: "\n", with: ending)
            checkEqual(patched.replacingOccurrences(of: hook, with: ""), original)
            checkEqual(try Data(contentsOf: common.appendingPathExtension("before-ximac-scan")), Data(original.utf8))
            checkEqual((try FileManager.default.attributesOfItem(atPath: common.path))[.posixPermissions] as? Int, 0o640)
            checkEqual(MemoryScan.prepare(common: common, resources: root, driveC: drive), environment)
            checkEqual(try String(decoding: Data(contentsOf: common), as: UTF8.self), patched)
        }
    }

    func testUnfamiliarLayoutOrMarkerIsUntouched() throws {
        for body in ["return {}", "-- Extension Libraries\n-- Extension Libraries",
                     MemoryScan.marker + "\n-- Extension Libraries"] {
            let (root, common, drive) = try fixture(body)
            defer { try? FileManager.default.removeItem(at: root) }
            checkTrue(MemoryScan.prepare(common: common, resources: root, driveC: drive).isEmpty)
            checkEqual(try String(decoding: Data(contentsOf: common), as: UTF8.self), body)
        }
    }

    func testMissingResourceAndSymlinkLeaveCommonUntouched() throws {
        let (root, common, drive) = try fixture("-- Extension Libraries")
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link.lua")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: common)
        checkTrue(MemoryScan.prepare(common: link, resources: root, driveC: drive).isEmpty)
        try FileManager.default.removeItem(at: root.appendingPathComponent("ximac-scan.dll"))
        checkTrue(MemoryScan.prepare(common: common, resources: root, driveC: drive).isEmpty)
        checkEqual(try String(decoding: Data(contentsOf: common), as: UTF8.self), "-- Extension Libraries")
    }

    func testExistingRollbackIsNeverReplaced() throws {
        let (root, common, drive) = try fixture("-- Extension Libraries")
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = common.appendingPathExtension("before-ximac-scan")
        try Data("older user backup".utf8).write(to: backup)
        checkFalse(MemoryScan.prepare(common: common, resources: root, driveC: drive).isEmpty)
        checkEqual(try String(decoding: Data(contentsOf: backup), as: UTF8.self), "older user backup")
        let backups = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("common.lua.before-ximac-scan.") }
        checkEqual(backups.count, 1)
        checkEqual(try Data(contentsOf: backups[0]), Data("-- Extension Libraries".utf8))
    }

    func testCorruptPackageLeavesCommonUntouched() throws {
        for name in ["scan.lua", "ximac-scan.dll", "build.json"] {
            let (root, common, drive) = try fixture("-- Extension Libraries")
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("corrupt".utf8).write(to: root.appendingPathComponent(name))
            checkTrue(MemoryScan.prepare(common: common, resources: root, driveC: drive).isEmpty)
            checkEqual(try Data(contentsOf: common), Data("-- Extension Libraries".utf8))
            checkFalse(FileManager.default.fileExists(atPath: common.appendingPathExtension("before-ximac-scan").path))
        }
    }
}

@main
struct MemoryScanTest {
    static func main() throws {
        let suite = MemoryScanTests()
        try suite.testHookPreservesBytesLineEndingsPermissionsAndRollback()
        try suite.testUnfamiliarLayoutOrMarkerIsUntouched()
        try suite.testMissingResourceAndSymlinkLeaveCommonUntouched()
        try suite.testExistingRollbackIsNeverReplaced()
        try suite.testCorruptPackageLeavesCommonUntouched()
        print("PASS shared memory scanner staging and rollback tests")
    }
}
