import AppKit

/// Keep the monitor alive while removing only the launcher's windows and Dock tile.
@MainActor
final class LauncherVisibility {
    static let shared = LauncherVisibility()

    private var hidForThisRun = false
    private(set) var isHiddenForGame = false
    private var hiddenWindows: [NSWindow] = []

    func gameWindowAppeared() {
        // Reopening the launcher during a game is an explicit request to keep it visible.
        guard !hidForThisRun else { return }
        hidForThisRun = true
        let app = NSApplication.shared
        hiddenWindows = app.windows.filter { $0.isVisible || $0.isMiniaturized }
        for window in hiddenWindows { window.orderOut(nil) }
        // Unlike Hide or Minimize, accessory policy also removes the running Dock tile
        // and Cmd-Tab entry. Wine owns its own windows and is unaffected.
        if app.setActivationPolicy(.accessory) {
            isHiddenForGame = true
        } else {
            for window in hiddenWindows { window.orderFront(nil) }
            hiddenWindows.removeAll()
        }
    }

    @discardableResult
    func reopen() -> Bool {
        guard isHiddenForGame else { return false }
        let app = NSApplication.shared
        guard app.setActivationPolicy(.regular) else { return false }
        isHiddenForGame = false
        app.unhide(nil)
        for window in hiddenWindows {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        hiddenWindows.removeAll()
        app.activate(ignoringOtherApps: true)
        return true
    }

    func gameEnded() {
        reopen()
        hidForThisRun = false
    }
}
