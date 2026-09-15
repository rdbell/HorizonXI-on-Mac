import Foundation
import CryptoKit

/// Installs one shared, environment-gated hook without changing individual addons.
enum MemoryScan {
    static let scriptVariable = "FFXI_ON_MAC_SCAN_SCRIPT"
    static let libraryVariable = "FFXI_ON_MAC_SCAN_DLL"
    static let marker = "-- FFXI_ON_MAC_MEMORY_SCAN_V1"
    static let shim = """
    \(marker)
    do
        local script = os.getenv('FFXI_ON_MAC_SCAN_SCRIPT');
        local library = os.getenv('FFXI_ON_MAC_SCAN_DLL');
        if script and script ~= '' and library and library ~= ''
            and os.getenv('FFXI_ON_MAC_DISABLE_SCAN') ~= '1' then
            local ok, result = pcall(function() return dofile(script)(library); end);
            if not ok or not result then
                print('[FFXI on Mac] Shared memory scanner unavailable; using original search.');
            end
        end
    end
    -- FFXI_ON_MAC_MEMORY_SCAN_END

    """

    /// A missing or unfamiliar common library leaves the original search active.
    static func prepare(common: URL, resources: URL, driveC: URL,
                        log: (String) -> Void = { _ in }) -> [String: String] {
        let fm = FileManager.default
        let script = resources.appendingPathComponent("scan.lua")
        let library = resources.appendingPathComponent("ximac-scan.dll")
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: library.path) else {
            log("==> shared memory scanner not bundled; using original search")
            return [:]
        }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self,
                from: Data(contentsOf: resources.appendingPathComponent("build.json")))
            guard manifest.abi == 1, Set(manifest.files.keys) == Set(["scan.lua", "ximac-scan.dll"])
            else {
                log("==> shared memory scanner: unsupported package manifest")
                return [:]
            }
            for (name, expected) in manifest.files {
                guard Self.digest(try Data(contentsOf: resources.appendingPathComponent(name))) == expected
                else {
                    log("==> shared memory scanner: package checksum mismatch for \(name)")
                    return [:]
                }
            }
            let properties = try common.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
                log("==> shared memory scanner: common library is not a regular file")
                return [:]
            }
            let bytes = try Data(contentsOf: common)
            guard String(data: bytes, encoding: .utf8) != nil else {
                log("==> shared memory scanner: common library is not UTF-8")
                return [:]
            }
            // Foundation's file/string decoder strips a UTF-8 BOM. Preserve it as a byte.
            let text = String(decoding: bytes, as: UTF8.self)
            let ending = TextFile.terminator(of: text)
            let hook = shim.replacingOccurrences(of: "\n", with: ending)
            if !text.contains(hook) {
                let anchor = "-- Extension Libraries"
                guard !text.contains(marker), text.components(separatedBy: anchor).count == 2 else {
                    log("==> shared memory scanner: unfamiliar common library; using original search")
                    return [:]
                }
                let attributes = try fm.attributesOfItem(atPath: common.path)
                var backup = common.appendingPathExtension("before-ximac-scan")
                // Keep an exact rollback when an upstream update replaces common.lua.
                // A pre-existing rollback belongs to the user or an earlier launch.
                if fm.fileExists(atPath: backup.path), try Data(contentsOf: backup) != bytes {
                    backup = common.appendingPathExtension("before-ximac-scan." + Self.digest(bytes))
                }
                if !fm.fileExists(atPath: backup.path) {
                    try bytes.write(to: backup, options: .withoutOverwriting)
                    if let mode = attributes[.posixPermissions] {
                        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: backup.path)
                    }
                }
                guard try Data(contentsOf: backup) == bytes else {
                    log("==> shared memory scanner: rollback verification failed")
                    return [:]
                }
                let patched = text.replacingOccurrences(of: anchor, with: hook + anchor)
                try Data(patched.utf8).write(to: common, options: .atomic)
                if let mode = attributes[.posixPermissions] {
                    try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: common.path)
                }
                log("==> installed shared memory scanner hook (original library preserved)")
            }
            return [scriptVariable: Install.winePath(script, driveC: driveC),
                    libraryVariable: Install.winePath(library, driveC: driveC)]
        } catch {
            log("==> shared memory scanner unavailable: \(error.localizedDescription)")
            return [:]
        }
    }

    private struct Manifest: Decodable {
        let abi: Int
        let files: [String: String]
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
