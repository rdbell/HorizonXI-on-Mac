import Foundation

/// Switch the pinned Wine display driver before launch, with an exact byte-for-byte rollback.
enum WineNativeHost {
    struct Manifest: Codable {
        var original: String
        var replacement: String
        var runtime: String = WineRuntime.version
    }

    static let filename = "winemac.so"
    static let ownershipFilename = "winemac-native-host-v1.json"

    /// Both sides of an atomic swap remain recognizable if launch stops during installation.
    struct Ownership: Codable {
        var version = 1
        var runtime: String
        var original: String
        var previous: String
        var replacement: String
    }

    private static func ownership(at url: URL, manifest: Manifest) -> Ownership? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 4097), data.count <= 4096,
              let record = try? JSONDecoder().decode(Ownership.self, from: data),
              record.version == 1, record.runtime == manifest.runtime,
              record.original == manifest.original,
              [record.original, record.previous, record.replacement].allSatisfy({ digest in
                  digest.utf8.count == 64 && digest.utf8.allSatisfy {
                      (48...57).contains($0) || (97...102).contains($0)
                  }
              }) else { return nil }
        return record
    }

    static func resources() -> URL {
        // Development callers pass a package explicitly. A shipped app must never
        // borrow binaries from the machine that compiled it.
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("wine-native-host")
    }

    static func configure(enabled: Bool, wine: URL, bundle: URL = resources(),
                          log: (String) -> Void) throws {
        let manifestURL = bundle.appendingPathComponent("build.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            if enabled { throw WineRuntime.Err("The native game window package is missing. Reinstall the app or turn off Native game window.") }
            return
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.runtime == WineRuntime.version else {
            throw WineRuntime.Err("The native game window package does not match this Wine runtime.")
        }
        let target = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/wine/x86_64-unix/\(filename)")
        guard FileManager.default.fileExists(atPath: target.path) else {
            if enabled { throw WineRuntime.Err("Native game window requires the bundled Intel Wine runtime.") }
            return
        }
        let current = try Data(contentsOf: target)
        let hash = WineLocaleFix.digest(current)
        let expected = enabled ? manifest.replacement : manifest.original
        // Enabling requires a verified recovery path even when this driver is
        // already installed. Disabling needs only the original so a damaged
        // candidate cannot prevent recovery.
        func verified(_ name: String, _ digest: String) throws -> Data {
            let data = try Data(contentsOf: bundle.appendingPathComponent(name))
            guard WineLocaleFix.digest(data) == digest else {
                throw WineRuntime.Err("Native game window package failed verification; the Wine driver was preserved.")
            }
            return data
        }
        var candidate: Data?
        if enabled {
            _ = try verified("original/\(filename)", manifest.original)
            candidate = try verified(filename, manifest.replacement)
        }
        let ownershipURL = target.deletingLastPathComponent().appendingPathComponent(ownershipFilename)
        let record = ownership(at: ownershipURL, manifest: manifest)
        guard hash == manifest.original || hash == manifest.replacement
                || hash == record?.previous || hash == record?.replacement else {
            if enabled {
                throw WineRuntime.Err("This Wine display driver has not been validated for Native game window. Turn that option off to keep using your current runtime.")
            }
            return
        }
        if hash == expected {
            // Adopt a verified installation from an older launcher that did not write a marker.
            if enabled && record?.previous != hash && record?.replacement != hash {
                let intent = Ownership(runtime: manifest.runtime, original: manifest.original,
                                       previous: hash, replacement: expected)
                try JSONEncoder().encode(intent).write(to: ownershipURL, options: .atomic)
            }
            return
        }
        let replacement = try candidate ?? verified("original/\(filename)", manifest.original)
        // Publish intent before replacing the driver. A later app can recover either
        // side of an interrupted swap, but cannot adopt an unrelated custom driver.
        let intent = Ownership(runtime: manifest.runtime, original: manifest.original,
                               previous: hash, replacement: expected)
        try JSONEncoder().encode(intent).write(to: ownershipURL, options: .atomic)
        // Atomic replacement leaves already mapped images intact.
        try replacement.write(to: target, options: .atomic)
        do {
            guard try WineLocaleFix.digest(Data(contentsOf: target)) == expected else {
                throw WineRuntime.Err("The installed native window driver failed verification.")
            }
        } catch {
            let updateError = error
            do {
                try current.write(to: target, options: .atomic)
                guard try WineLocaleFix.digest(Data(contentsOf: target)) == hash else {
                    throw WineRuntime.Err("The restored Wine driver failed verification.")
                }
            } catch {
                throw WineRuntime.Err("Native game window update and rollback failed: \(error)")
            }
            throw updateError
        }
        log(enabled ? "Native game window enabled; original Wine driver retained in the app package."
                    : "Native game window disabled; original Wine driver restored.")
    }
}
