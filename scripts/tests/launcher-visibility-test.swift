// Compile with app/Sources/HorizonXILauncher/LauncherVisibility.swift, then run
// on a logged-in macOS desktop. This opens only a temporary native test window.
import AppKit

@main
struct LauncherVisibilityTest {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 160),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Launcher visibility test"
        window.makeKeyAndOrderFront(nil)
        let visibility = LauncherVisibility()
        var step = 0
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            MainActor.assumeIsolated {
                switch step {
                case 0:
                    visibility.gameEnded() // Failed launch before any game window.
                    precondition(window.isVisible && app.activationPolicy() == .regular)
                    visibility.gameWindowAppeared()
                case 1:
                    precondition(!window.isVisible && app.activationPolicy() == .accessory)
                    precondition(NSRunningApplication.current.activationPolicy == .accessory)
                    precondition(visibility.reopen())
                case 2:
                    precondition(window.isVisible && app.activationPolicy() == .regular)
                    visibility.gameWindowAppeared() // A later poll must not hide a manual reopen.
                    precondition(window.isVisible)
                    visibility.gameEnded()
                    visibility.gameWindowAppeared() // Next game gets automatic hiding again.
                case 3:
                    precondition(!window.isVisible && app.activationPolicy() == .accessory)
                    visibility.gameEnded()
                case 4:
                    precondition(window.isVisible && app.activationPolicy() == .regular)
                    precondition(!visibility.isHiddenForGame)
                    precondition(!visibility.reopen())
                    timer.invalidate()
                    print("PASS: hide window and Dock presence, manual reopen, next run, exit and failed launch")
                    app.terminate(nil)
                default: fatalError("Unexpected step")
                }
                step += 1
            }
        }
        app.run()
    }
}
