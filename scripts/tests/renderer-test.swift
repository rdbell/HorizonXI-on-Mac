import Foundation

// Only the renderer and preference path are under test. Do not discover a real sidecar or
// inject the sound helper into a test fixture. This runs with Command Line Tools, no XCTest.
enum X87Sidecar { static func coopBinary() -> URL? { nil } }
enum AudioFollow { static func dylib() -> URL? { nil } }
enum Preflight {
    struct Check { enum State { case ok }; var state: State }
    static func run(_ install: Install) -> [Check] { [] }
}

// swiftc app/Sources/HorizonXILauncher/{Renderer,Settings,Install,Servers}.swift \
//   scripts/tests/renderer-test.swift -o /tmp/renderer-test && /tmp/renderer-test
@main
struct RendererTest {
    static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() throws {
        try savedSettings()
        try missingShim()
        try repeatedInstall()
        print("PASS: renderer settings, incomplete-package protection, repeat install and builtin preservation")
    }

    static func savedSettings() throws {
        let saved = Data(#"{"renderer":"metal","msync":false,"followSoundOutput":false,"extraEnv":"USER_SETTING=kept"}"#.utf8)
        var settings = try JSONDecoder().decode(PerfSettings.self, from: saved)
        settings.renderer = .mtld3d
        var restored = try JSONDecoder().decode(PerfSettings.self,
                                               from: JSONEncoder().encode(settings))
        expect(restored.renderer == .mtld3d && !restored.msync && !restored.followSoundOutput
               && restored.extraEnv == "USER_SETTING=kept", "renderer choice reset unrelated settings")

        let install = Install(wrapper: URL(fileURLWithPath: "/tmp/test-wrapper.app"), prefixName: "prefix10")
        let env = restored.environment(for: install, x87: false)
        expect(env["MTLD3D_CONFIG"]?.contains("render.mergePasses=true") == true, "pass merging is off")
        expect(env["MTLD3D_CONFIG"]?.contains("render.submitDraws=0") == true, "early submission is on")
        expect(env["DXVK_CONFIG_FILE"] == nil && env["USER_SETTING"] == "kept", "wrong renderer environment")
        expect(Renderer.mtld3d.iniOverrides["behaviorflags.fpu_preserve"] == "1", "missing FPU preservation")
        restored.renderer = .metal
        let fallback = restored.environment(for: install, x87: false)
        expect(fallback["MTLD3D_CONFIG"] == nil && fallback["WINEDLLPATH"] == nil
               && fallback["DXVK_CONFIG_FILE"] != nil, "DXVK fallback retained mtld3d environment")
    }

    static func fixture() throws -> (root: URL, install: Install, bundle: URL, converter: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hxi-renderer-\(UUID().uuidString)")
        let install = Install(wrapper: root.appendingPathComponent("wrapper.app"),
                              prefixName: "prefix10", gameDirOverride: root.appendingPathComponent("game"))
        let bundle = root.appendingPathComponent("mtld3d")
        for name in RendererSetup.mtld3dFiles {
            let file = bundle.appendingPathComponent(name)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: file)
        }
        for path in ["windows/syswow64", "windows/system32"] {
            try fm.createDirectory(at: install.driveC.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        for path in ["bootloader", "SquareEnix/PlayOnlineViewer", "SquareEnix/FINAL FANTASY XI"] {
            try fm.createDirectory(at: install.gameDir.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let converter = root.appendingPathComponent("d3d8to9.dll")
        try Data("converter".utf8).write(to: converter)
        return (root, install, bundle, converter)
    }

    static func missingShim() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let installed = f.install.gameDir.appendingPathComponent("d3d9.dll")
        try Data("existing DXVK".utf8).write(to: installed)
        try FileManager.default.removeItem(at: f.bundle.appendingPathComponent("wine/x86_64-unix/mtld3d.so"))
        do {
            try RendererSetup.installMTLD3DFiles(to: f.install, bundle: f.bundle, converter: f.converter)
            expect(false, "incomplete package was accepted")
        } catch RendererSetup.SetupError.missingResource { }
        expect(try String(contentsOf: installed, encoding: .utf8) == "existing DXVK", "incomplete package replaced the renderer")
    }

    static func repeatedInstall() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let builtin = f.root.appendingPathComponent("builtin.dll")
        try Data("Wine builtin".utf8).write(to: builtin)
        let syswow = f.install.driveC.appendingPathComponent("windows/syswow64")
        try FileManager.default.createSymbolicLink(at: syswow.appendingPathComponent("d3d9.dll"),
                                                   withDestinationURL: builtin)
        for _ in 0..<2 {
            try RendererSetup.installMTLD3DFiles(to: f.install, bundle: f.bundle, converter: f.converter)
            for dir in [syswow, f.install.gameDir, f.install.bootLoaderDir,
                        f.install.squareEnix.appendingPathComponent("PlayOnlineViewer"),
                        f.install.squareEnix.appendingPathComponent("FINAL FANTASY XI")] {
                expect(try String(contentsOf: dir.appendingPathComponent("d3d9.dll"), encoding: .utf8) == "native/i386-windows/d3d9.dll",
                       "native D3D9 missing from \(dir.lastPathComponent)")
                expect(try String(contentsOf: dir.appendingPathComponent("d3d8.dll"), encoding: .utf8) == "converter", "converter missing")
            }
            for bits in ["syswow64", "system32"] {
                let marker = f.install.driveC.appendingPathComponent("windows/\(bits)/mtld3d.dll")
                expect(try String(contentsOf: marker, encoding: .utf8) == "prefix-markers/\(bits)/mtld3d.dll", "wrong prefix marker")
            }
        }
        expect(try String(contentsOf: builtin, encoding: .utf8) == "Wine builtin", "overwrote the Wine runtime through a symlink")
    }
}
