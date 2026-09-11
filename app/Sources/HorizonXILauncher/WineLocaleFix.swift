import CryptoKit
import Foundation

/// The locale correction built against the pinned Wine release. Only UCRT changes;
/// the Wine loader, x87 support, and renderer retain their existing binaries.
enum WineLocaleFix {
    static let files = ["i386-windows/ucrtbase.dll", "x86_64-windows/ucrtbase.dll"]
    static let backupDirectory = "locale-fix-v1-originals"

    struct Manifest: Decodable {
        let runtime: String
        let files: [String: String]
        let originals: [String: String]
    }

    static func resources() -> URL {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("wine-locale-fix"),
           FileManager.default.fileExists(atPath: resource.path) { return resource }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vendor/wine-locale-fix")
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Validate the entire pair before writing. Atomic file replacement preserves mapped
    /// images; a failed update restores every changed file. Repeated launches do no writes.
    static func apply(to runtime: URL, bundle: URL = resources(), log: (String) -> Void) throws {
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: bundle.appendingPathComponent("build.json")))
        guard manifest.runtime == WineRuntime.version,
              Set(manifest.files.keys) == Set(files), Set(manifest.originals.keys) == Set(files) else {
            throw WineRuntime.Err("The bundled locale fix does not match this Wine runtime.")
        }
        var changes: [(name: String, target: URL, original: Data, replacement: Data)] = []
        for name in files {
            let replacement = try Data(contentsOf: bundle.appendingPathComponent(name))
            guard digest(replacement) == manifest.files[name] else {
                throw WineRuntime.Err("The bundled locale fix failed verification: \(name).")
            }
            let target = runtime.appendingPathComponent("wine/lib/wine/\(name)")
            let original = try Data(contentsOf: target)
            let hash = digest(original)
            if hash == manifest.files[name] { continue }
            guard hash == manifest.originals[name] else {
                throw WineRuntime.Err("Wine has an unrecognized C runtime; preserving it: \(target.path).")
            }
            changes.append((name, target, original, replacement))
        }
        guard !changes.isEmpty else { return }

        let fm = FileManager.default
        for change in changes {
            let backup = runtime.appendingPathComponent("\(backupDirectory)/\(change.name)")
            if fm.fileExists(atPath: backup.path) {
                guard try digest(Data(contentsOf: backup)) == manifest.originals[change.name] else {
                    throw WineRuntime.Err("Wine locale rollback verification failed: \(backup.path).")
                }
            } else {
                try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try change.original.write(to: backup, options: .atomic)
            }
        }
        var changed: [(URL, Data)] = []
        do {
            for change in changes {
                try change.replacement.write(to: change.target, options: .atomic)
                changed.append((change.target, change.original))
            }
        } catch {
            for (target, original) in changed.reversed() {
                do { try original.write(to: target, options: .atomic) }
                catch { throw WineRuntime.Err("Wine locale update and rollback failed at \(target.path): \(error)") }
            }
            throw error
        }
        log("Wine locale fix installed; originals saved in \(runtime.appendingPathComponent(backupDirectory).path)")
    }
}
