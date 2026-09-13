import Foundation

// Compile with WineNativeHost.swift, WineLocaleFix.swift and WineRuntime.swift.
// This runner works with Command Line Tools, without XCTest or full Xcode.
@main
struct WineNativeHostTests {
    static func main() throws {
        let test = Self()
        try test.testEnableIsIdempotentAndDisableRestoresExactOriginal()
        try test.testUnknownDriverIsPreserved()
        try test.testDamagedCandidateCannotReplaceDriver()
        try test.testDamagedRollbackPreservesWorkingCandidate()
        try test.testEnableRequiresRollbackBeforeFirstWriteAndOnRepeat()
        try test.testRepeatEnableRevalidatesCandidate()
        try test.testDisableSurvivesDamagedCandidate()
        try test.testMissingPackageIsOnlyAllowedWhenDisabled()
        try test.testMismatchedRuntimeIsPreserved()
        try test.testUpgradeEnableAndDisable()
        try test.testInterruptedUpgradeIntent()
        try test.testMalformedAndStaleOwnershipPreservesUnknownDriver()
        try test.testUpgradeStillRequiresVerifiedPackage()
        try test.testOwnershipMustBeWrittenBeforeDriver()
        try test.testMatchingLegacyInstallationGainsOwnership()
        print("15 native host installation and rollback tests passed")
    }
    struct Failure: Error {}
    func equal<T: Equatable>(_ actual: T, _ expected: T) throws {
        guard actual == expected else {throw Failure()}
    }
    func rejects(_ operation: () throws -> Void) throws {
        do {try operation()} catch {return}
        throw Failure()
    }
    private func fixture() throws -> (URL, URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wine = root.appendingPathComponent("wine/bin/wine")
        let driver = root.appendingPathComponent("wine/lib/wine/x86_64-unix/winemac.so")
        let bundle = root.appendingPathComponent("bundle")
        for directory in [driver.deletingLastPathComponent(), bundle.appendingPathComponent("original")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let original = Data("original".utf8), replacement = Data("native-host".utf8)
        try original.write(to: driver)
        try original.write(to: bundle.appendingPathComponent("original/winemac.so"))
        try replacement.write(to: bundle.appendingPathComponent("winemac.so"))
        let manifest = WineNativeHost.Manifest(original: WineLocaleFix.digest(original),
                                              replacement: WineLocaleFix.digest(replacement))
        try JSONEncoder().encode(manifest).write(to: bundle.appendingPathComponent("build.json"))
        return (root, wine, driver, bundle)
    }

    func testEnableIsIdempotentAndDisableRestoresExactOriginal() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        let original = try Data(contentsOf: driver)
        var messages: [String] = []
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { messages.append($0) }
        try equal(try Data(contentsOf: driver), Data("native-host".utf8))
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { messages.append($0) }
        try equal(messages.count, 1)
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { messages.append($0) }
        try equal(try Data(contentsOf: driver), original)
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { messages.append($0) }
        try equal(messages.count, 2)
    }

    func testUnknownDriverIsPreserved() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        let custom = Data("custom-wine".utf8)
        try custom.write(to: driver)
        try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
        try equal(try Data(contentsOf: driver), custom)
    }

    func testDamagedCandidateCannotReplaceDriver() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        try Data("damaged".utf8).write(to: bundle.appendingPathComponent("winemac.so"))
        try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

    func testDamagedRollbackPreservesWorkingCandidate() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
        try Data("damaged".utf8).write(to: bundle.appendingPathComponent("original/winemac.so"))
        try rejects { try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in } }
        try equal(try Data(contentsOf: driver), Data("native-host".utf8))
    }

    func testEnableRequiresRollbackBeforeFirstWriteAndOnRepeat() throws {
        for alreadyEnabled in [false, true] {
            let (root, wine, driver, bundle) = try fixture()
            defer {try? FileManager.default.removeItem(at: root)}
            if alreadyEnabled {
                try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
            }
            let before = try Data(contentsOf: driver)
            try FileManager.default.removeItem(at: bundle.appendingPathComponent("original/winemac.so"))
            try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
            try equal(try Data(contentsOf: driver), before)
        }
    }

    func testRepeatEnableRevalidatesCandidate() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
        try Data("damaged".utf8).write(to: bundle.appendingPathComponent("winemac.so"))
        try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
        try equal(try Data(contentsOf: driver), Data("native-host".utf8))
    }

    func testDisableSurvivesDamagedCandidate() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
        try Data("damaged".utf8).write(to: bundle.appendingPathComponent("winemac.so"))
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

    func testMissingPackageIsOnlyAllowedWhenDisabled() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        try FileManager.default.removeItem(at: bundle)
        try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

    func testMismatchedRuntimeIsPreserved() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        var manifest = try JSONDecoder().decode(WineNativeHost.Manifest.self,
            from: Data(contentsOf: bundle.appendingPathComponent("build.json")))
        manifest.runtime = "other-wine"
        try JSONEncoder().encode(manifest).write(to: bundle.appendingPathComponent("build.json"))
        try rejects { try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in } }
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

    private func updatePackage(_ bundle: URL, candidate: Data) throws {
        let manifestURL = bundle.appendingPathComponent("build.json")
        var manifest = try JSONDecoder().decode(WineNativeHost.Manifest.self,
                                                from: Data(contentsOf: manifestURL))
        manifest.replacement = WineLocaleFix.digest(candidate)
        try candidate.write(to: bundle.appendingPathComponent("winemac.so"))
        try JSONEncoder().encode(manifest).write(to: manifestURL)
    }

    func testUpgradeEnableAndDisable() throws {
        for enabled in [false, true] {
            let (root, wine, driver, bundle) = try fixture()
            defer {try? FileManager.default.removeItem(at: root)}
            try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
            let candidateB = Data("candidate-B".utf8)
            try updatePackage(bundle, candidate: candidateB)
            try WineNativeHost.configure(enabled: enabled, wine: wine, bundle: bundle) { _ in }
            try equal(try Data(contentsOf: driver), enabled ? candidateB : Data("original".utf8))
            try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
            try equal(try Data(contentsOf: driver), Data("original".utf8))
        }
    }

    func testInterruptedUpgradeIntent() throws {
        for swapped in [false, true] {
            for enabled in [false, true] {
                let (root, wine, driver, bundle) = try fixture()
                defer {try? FileManager.default.removeItem(at: root)}
                try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
                let candidateA = try Data(contentsOf: driver)
                let candidateB = Data("candidate-B".utf8), candidateC = Data("candidate-C".utf8)
                let intent = WineNativeHost.Ownership(runtime: WineRuntime.version,
                    original: WineLocaleFix.digest(Data("original".utf8)),
                    previous: WineLocaleFix.digest(candidateA), replacement: WineLocaleFix.digest(candidateB))
                let marker = driver.deletingLastPathComponent().appendingPathComponent(WineNativeHost.ownershipFilename)
                try JSONEncoder().encode(intent).write(to: marker)
                if swapped { try candidateB.write(to: driver) }
                try updatePackage(bundle, candidate: candidateC)
                try WineNativeHost.configure(enabled: enabled, wine: wine, bundle: bundle) { _ in }
                try equal(try Data(contentsOf: driver), enabled ? candidateC : Data("original".utf8))
            }
        }
    }

    func testMalformedAndStaleOwnershipPreservesUnknownDriver() throws {
        let originalHash = WineLocaleFix.digest(Data("original".utf8))
        let custom = Data("custom-wine".utf8), customHash = WineLocaleFix.digest(custom)
        let valid = WineNativeHost.Ownership(runtime: WineRuntime.version, original: originalHash,
                                            previous: originalHash, replacement: customHash)
        var markers = [Data("invalid json".utf8), Data(repeating: 32, count: 4097)]
        for variation in 0..<5 {
            var record = valid
            switch variation {
            case 0: record.version = 2
            case 1: record.runtime = "another-runtime"
            case 2: record.original = customHash
            case 3: record.previous = "invalid digest"
            default: record.replacement = originalHash
            }
            markers.append(try JSONEncoder().encode(record))
        }
        for markerData in markers {
            let (root, wine, driver, bundle) = try fixture()
            defer {try? FileManager.default.removeItem(at: root)}
            try custom.write(to: driver)
            let marker = driver.deletingLastPathComponent().appendingPathComponent(WineNativeHost.ownershipFilename)
            try markerData.write(to: marker)
            try rejects {try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }}
            try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
            try equal(try Data(contentsOf: driver), custom)
            try equal(try Data(contentsOf: marker), markerData)
        }
    }

    func testUpgradeStillRequiresVerifiedPackage() throws {
        for damaged in ["winemac.so", "original/winemac.so"] {
            let (root, wine, driver, bundle) = try fixture()
            defer {try? FileManager.default.removeItem(at: root)}
            try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
            let candidateA = try Data(contentsOf: driver)
            try updatePackage(bundle, candidate: Data("candidate-B".utf8))
            try Data("damaged".utf8).write(to: bundle.appendingPathComponent(damaged))
            try rejects {try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }}
            try equal(try Data(contentsOf: driver), candidateA)
            if damaged == "original/winemac.so" {
                try rejects {try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }}
            } else {
                try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
                try equal(try Data(contentsOf: driver), Data("original".utf8))
            }
        }
    }

    func testOwnershipMustBeWrittenBeforeDriver() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        let marker = driver.deletingLastPathComponent().appendingPathComponent(WineNativeHost.ownershipFilename)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        try rejects {try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }}
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

    func testMatchingLegacyInstallationGainsOwnership() throws {
        let (root, wine, driver, bundle) = try fixture()
        defer {try? FileManager.default.removeItem(at: root)}
        let candidateA = try Data(contentsOf: bundle.appendingPathComponent("winemac.so"))
        try candidateA.write(to: driver)
        try WineNativeHost.configure(enabled: true, wine: wine, bundle: bundle) { _ in }
        let marker = driver.deletingLastPathComponent().appendingPathComponent(WineNativeHost.ownershipFilename)
        let record = try JSONDecoder().decode(WineNativeHost.Ownership.self, from: Data(contentsOf: marker))
        try equal(record.replacement, WineLocaleFix.digest(candidateA))
        try updatePackage(bundle, candidate: Data("candidate-B".utf8))
        try WineNativeHost.configure(enabled: false, wine: wine, bundle: bundle) { _ in }
        try equal(try Data(contentsOf: driver), Data("original".utf8))
    }

}
