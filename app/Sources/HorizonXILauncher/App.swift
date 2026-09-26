import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Quitting the launcher kills every download and install it started, because they are its child
/// processes. Silently, and with the UI reverting to its "nothing installed yet" state -- so the
/// only evidence a 6 GB download ever happened was the folder on disk. Ask first.
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app in Finder while playing restores the existing window.
        // Returning false prevents SwiftUI from opening an extra WindowGroup window.
        !LauncherVisibility.shared.reopen()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Runner.workInFlight else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "A download or install is still running."
        a.informativeText = "Quitting stops it. It is resumable — pressing Download again picks "
                          + "up where it left off — but nothing more will download until you do."
        a.addButton(withTitle: "Quit anyway")
        a.addButton(withTitle: "Keep running")
        a.alertStyle = .warning
        return a.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main
struct HorizonXILauncherApp: App {
    @NSApplicationDelegateAdaptor(LauncherDelegate.self) private var delegate
    init() { Headless.runIfAsked() }

    var body: some Scene {
        WindowGroup("FFXI on Mac") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 674)
                .preferredColorScheme(.dark)
                // Otherwise every checkbox, picker and default button is macOS blue, which is
                // the one colour this palette does not have anywhere in it.
                .tint(Vana.jade)
        }
        .windowResizability(.contentMinSize)
        // The traffic lights sit over the navigation rail; there is no title bar to speak of.
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Palette
//
// Charcoal and jade. The launcher used to be indigo, crystal-blue and FFXI's menu gold, which is
// the game's own palette but reads as neon once the window is dark. This is the other half of
// Vana'diel: the warm nocturnal green of a Ronfaure night. Surfaces are neutral charcoal --
// never black, because a crushed-black panel loses every hairline it has -- the accent is a
// muted jade, and the only saturated thing on screen is the button that starts the game.

enum Vana {
    static let night   = Color(hex: 0x191E20)   // window background
    static let side    = Color(hex: 0x14191B)   // navigation rail
    static let raised  = Color(hex: 0x252D2E)   // cards, fields, anything lifted off the page
    static let panel   = Color(hex: 0x1D2325)   // the column behind the raised things
    static let stroke  = Color(hex: 0x384143)   // hairline divider

    static let text    = Color(hex: 0xEDF0E9)   // warm off-white
    static let muted   = Color(hex: 0xB6C0BD)   // secondary text, still readable on `night`
    static let muted2  = Color(hex: 0x7E8A85)   // captions and section labels

    /// The accent: section labels, the selected rail item, anything the eye should land on.
    static let jade    = Color(hex: 0x8BC4AA)
    static let jadeDim = Color(hex: 0x6E9986)

    /// Play, and nothing else. White text clears contrast on this; on `jade` it does not.
    static let forest     = Color(hex: 0x2F6249)
    static let forestDeep = Color(hex: 0x23503A)

    /// Something is wrong (`ember`) or worth a second look (`sand`). Both are deliberately
    /// desaturated: a pure red beside a caution reads as an error even when it is not one.
    static let ember   = Color(hex: 0xCE8A6F)
    static let sand    = Color(hex: 0xC9AC7C)

    /// Flat, not a gradient. The old blue-violet wash with two radial glows was doing the work
    /// of artwork the app does not ship; a plain charcoal lets the one hero band carry it.
    static var backdrop: some View { night.ignoresSafeArea() }
}

/// A tall six-sided gem: point at the top, widest a third of the way down, tapering to a base.
struct CrystalShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.32))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.32))
        p.closeSubpath()
        return p
    }
}

extension Color {
    /// 0xRRGGBB, so the values above can be read against the design notes they came from.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The four screens, in the order the rail lists them.
///
/// Graphics and Add-ons used to be modal sheets hung off two small buttons beside Play. They are
/// the two things a player opens most often, so they are places you navigate to now rather than
/// dialogues that take the window over; and the front screen is no longer carrying every control
/// in the app at once.
private enum Page: String, CaseIterable, Identifiable {
    case play, graphics, addons, setup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .play:     return "Play"
        case .graphics: return "Graphics"
        case .addons:   return "Add-ons"
        case .setup:    return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .play:     return "play"
        case .graphics: return "display"
        case .addons:   return "puzzlepiece.extension"
        case .setup:    return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var installs: [Install] = []
    @State private var selected: Install?
    /// The wrapper/prefix in `selected`, pointed at the chosen world's game folder.
    private var active: Install? {
        guard let i = selected else { return nil }
        return i.forServer(store.selected ?? Server.builtins[0])
    }
    @State private var checks: [Check] = []
    @State private var perf = PerfSettings.load()
    @StateObject private var runner = Runner()

    @StateObject private var store = ServerStore()
    @StateObject private var local = LocalServer()
    @StateObject private var feeds = ServerFeeds()
    @StateObject private var updater = Updater()
    @State private var bannerIndex = 0
    /// One timer for the life of the view. Built inline in `newsBanner`'s body it was a *new*
    /// publisher on every body evaluation, so any re-render (hovering the window, a population
    /// refresh, changing world) restarted the 7-second countdown and the banner could sit on one
    /// item indefinitely -- watched it stay frozen for 28 seconds straight after a world change.
    private let bannerTick = Timer.publish(every: 7, on: .main, in: .common).autoconnect()
    @State private var worldHover = false
    @State private var forceSetup = false
    @State private var newServer = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newProfile = ""

    /// Which screen the rail is showing.
    @State private var page: Page = .play

    @State private var user = Credentials.username
    @State private var pass = ""
    @State private var remember = Credentials.remember
    @State private var graphics = GraphicsSettings.load(world: nil)
    @State private var locating = false
    @State private var locateHits: [Locator.Hit] = []
    @State private var locateFor: Server? = nil
    @State private var addonItems: [AddonSuite.Item] = []
    @State private var installingExtra = ""
    @State private var addonWarning = ""
    @State private var notice = ""
    /// One update attempt per Play press chain; a second Play retries.
    @State private var updateChecked = false
    @State private var scanning = false
    @State private var showSetup = false
    // Starts open when FFXI_ON_MAC_SHOW_SIGNUPS=1, so this project can screenshot the expanded
    // list without driving a synthetic click into the window (see docs/SERVERS-WORKLOG.md).
    @State private var showAllSignups =
        ProcessInfo.processInfo.environment["FFXI_ON_MAC_SHOW_SIGNUPS"] == "1"

    private var blocked: Bool { checks.contains { $0.state == .bad } }

    /// This world cannot be played out of the files that are on disk: either there is no client
    /// at all, or it would be run out of HorizonXI's folder, which is what earns "The game's data
    /// has been updated" from a server that is not HorizonXI.
    private var needsGameData: Bool {
        guard let i = active, let s = store.selected else { return false }
        return !i.hasGame || (s.dataPath.isEmpty && !s.local && s.name != "HorizonXI")
    }

    private var statusText: String {
        if scanning { return "looking for your install…" }
        if selected == nil { return "nothing installed yet" }
        if let i = active, !i.hasGame { return "wine is ready — \(store.selected?.name ?? "the game")'s data is not installed" }
        return blocked ? "setup incomplete" : "ready to play"
    }

    var body: some View {
        ZStack {
            Vana.backdrop
            HStack(spacing: 0) {
                navRail
                Rectangle().fill(Vana.stroke).frame(width: 1)
                VStack(spacing: 0) {
                    Group {
                        switch page {
                        case .play:     playPage
                        case .graphics: graphicsPage
                        case .addons:   addonsPage
                        case .setup:    setupPage
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    noticeStrip
                    switch page {
                    case .play:     playFooter
                    case .graphics: graphicsFooter
                    case .addons:   addonsFooter
                    case .setup:    footer {
                        Text("Measured on this Mac with Metal/DXVK: correct at 4K with every setting at maximum — see docs/MAX4K.md.")
                            .lineLimit(1)
                    } right: { updateBanner }
                    }
                }
            }
        }
        .sheet(isPresented: $newServer) { addServerSheet }
        .sheet(isPresented: Binding(get: { locateFor != nil },
                                    set: { if !$0 { locateFor = nil } })) { locateSheet }
        .sheet(isPresented: $showSetup) { SetupSheet { refresh() } }
        .onAppear {
            if store.selected?.local == true { local.refresh() }
            // Off the main actor out of habit from when this was a Keychain read that could
            // block on a system prompt (see Credentials.swift for why it no longer is).
            if let name = store.selected?.name, store.selected?.local != true {
                user = Credentials.username(forWorld: name)
            }
            guard remember, !user.isEmpty else { return }
            let account = user
            let install = selected
            let profile = store.selected?.bootProfile ?? "horizonxi.ini"
            let worldName = store.selected?.name ?? ""
            Task.detached(priority: .userInitiated) {
                if let i = install {
                    Credentials.adoptPasswordFromProfile(user: account, install: i, profile: profile)
                }
                let found = Credentials.password(for: account, world: worldName)
                await MainActor.run { pass = found }
            }
        }
        .onChange(of: runner.loginFailure) { f in
            guard !f.isEmpty else { return }
            notice = "\(store.selected?.name ?? "The server") said: \(f)"
                + (f.contains("Invalid") ? " Check the account name and password — accounts are created on the server's own site or through its loader, not here." : "")
        }
        .onChange(of: store.selectedID) { _ in
            if store.selected?.local == true { local.refresh() }
            // Recall the account last used on this world — accounts are per server, so the
            // HorizonXI login is wrong the moment CatsEye (or any other world) is picked.
            if let name = store.selected?.name, store.selected?.local != true {
                user = Credentials.username(forWorld: name)
                pass = remember ? Credentials.password(for: user, world: name) : ""
            }
            // The preflight checks are per world now (each has its own game folder): CatsEye's
            // "no client" verdict must not keep Play grey after switching back to HorizonXI.
            recheck()
            // Graphics and add-ons are per world too, and both screens stay open across a world
            // change -- showing the previous world's list until something forces a reload.
            if page == .graphics { loadGraphics() }
            if page == .addons { loadAddons() }
        }
        // Keep the players-online line current: on launch, whenever the world changes, and
        // every two minutes while the window is open. The fetch is three tiny GETs and silent
        // on failure, so this costs nothing when offline.
        .task { await feeds.refreshPopulations() }
        .onReceive(Timer.publish(every: 120, on: .main, in: .common).autoconnect()) { _ in
            Task { await feeds.refreshPopulations() }
        }
        // Discovery walks /Volumes, and an external drive can make that take tens of seconds.
        // Doing it on the main thread means the window never appears at all — which looked
        // exactly like the app failing to launch. Scan off the main actor and fill the UI in.
        .task {
            // `--play` used to wait for the full volume scan below. After the game data moved
            // to the x10 (2.4 TB, spinning), that scan can run for many minutes, and the
            // launcher sat with no window and no log line — "it says it's running but it's
            // not". The remembered install is enough to play with; the scan only refreshes the
            // picker. So: fast path first, Play immediately, full scan afterwards.
            if selected == nil, let remembered = Install.remembered() {
                selected = remembered
                installs = [remembered]
            }
            // Press Play as soon as the install is known. For Shortcuts/Stream Deck users, and
            // for this project's own unattended tests (see docs/SERVERS-WORKLOG.md).
            let args = CommandLine.arguments
            if let w = args.firstIndex(of: "--world"), w + 1 < args.count,
               let srv = store.servers.first(where: { $0.name == args[w + 1] }) { store.select(srv) }
            if args.contains("--play") {
                if selected == nil { runner.appendLine("!! --play: no install found yet") }
                else if runner.running { runner.appendLine("!! --play: already running") }
                else {
                    if remember, !user.isEmpty, pass.isEmpty { pass = Credentials.password(for: user, world: store.selected?.name ?? "") }
                    await recheckAsync()
                    if store.selected?.local == true {
                        // A refresh may already be in flight from onAppear; either way, wait
                        // for a verdict (bounded) rather than refusing on a status that is nil.
                        await local.refreshAsync()
                        for _ in 0..<60 where local.status == nil {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                    runner.appendLine("==> --play: \(store.selected?.name ?? "?") as \(user.isEmpty ? "(no account)" : user)")
                    play()
                    if !notice.isEmpty { runner.appendLine("!! \(notice)") }
                }
            }
            await refreshAsync()
            // Pick up each server's own published addon list, so the app's compiled-in snapshot
            // does not go stale between releases. Silent on failure -- offline must still launch.
            await feeds.refreshAsync(servers: store.servers)
            // Check GitHub Releases and, if there is a newer build, download it automatically.
            // The update is only *applied* when the user presses Restart (updateBanner).
            updater.start()
        }
    }

    // MARK: - Left: where you are

    /// Brand, the three places you go, and Settings pinned to the bottom. The title bar is hidden,
    /// so the traffic lights sit over the top of this column and the brand starts below them.
    private var navRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                crystal.frame(width: 17, height: 27)
                Text("FFXI on Mac").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Vana.text)
            }
            .padding(.leading, 22).padding(.top, 50).padding(.bottom, 26)

            VStack(spacing: 4) { navItem(.play); navItem(.graphics); navItem(.addons) }
                .padding(.horizontal, 12)

            Spacer(minLength: 16)

            Rectangle().fill(Vana.stroke).frame(height: 1).padding(.horizontal, 20)
            navItem(.setup).padding(.horizontal, 12).padding(.vertical, 12)
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Vana.side)
    }

    private func navItem(_ p: Page) -> some View {
        Button { go(p) } label: {
            HStack(spacing: 12) {
                Image(systemName: p.icon).font(.system(size: 15)).frame(width: 20)
                Text(p.title).font(.system(size: 15, weight: page == p ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(page == p ? Vana.jade : Vana.muted)
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(page == p ? Vana.jade.opacity(0.13) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Graphics reads the boot profile and Add-ons rescans the game folder on the way in, so both
    /// screens open on what is on disk rather than on whatever this app wrote last.
    private func go(_ p: Page) {
        switch p {
        case .graphics: loadGraphics()
        case .addons:   loadAddons()
        default:        break
        }
        page = p
    }

    /// The crystal: a tall gem, drawn. The one piece of FFXI iconography the launcher can put on
    /// screen without touching Square Enix's artwork.
    private var crystal: some View {
        CrystalShape()
            .fill(LinearGradient(colors: [Color(hex: 0xA9E3C4), Vana.jade, Vana.forest],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(CrystalShape().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Vana.jade.opacity(0.45), radius: 6)
    }

    // MARK: - Page chrome

    /// Title on the left, the one-line state of things on the right.
    private func pageHeader(_ title: String, status: String, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(Vana.text)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(tone).frame(width: 8, height: 8)
                Text(status).font(.system(size: 15)).foregroundStyle(Vana.muted)
            }
        }
        .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 4)
    }

    private var statusTone: Color {
        if scanning { return Vana.sand }
        if selected == nil || blocked || needsGameData { return Vana.sand }
        return Vana.jade
    }

    /// Section caption over a card of rows. Every settings screen is a few of these.
    private func section<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Vana.muted2).padding(.leading, 4)
            VStack(spacing: 0) { rows() }
                .background(RoundedRectangle(cornerRadius: 12).fill(Vana.raised.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Vana.stroke))
        }
    }

    /// One row: what it is on the left, the control on the right, a hairline underneath.
    private func row<C: View>(_ label: String, _ detail: String = "",
                              @ViewBuilder control: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 15)).foregroundStyle(Vana.text)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 13)).foregroundStyle(Vana.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 48)
            Rectangle().fill(Vana.stroke).frame(height: 1).padding(.leading, 16)
        }
    }

    /// A row whose content is a block rather than a label/control pair (a list, a set of buttons).
    private func block<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(Vana.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What is in the footer depends on the page; the footer itself is always the same strip.
    private func footer<L: View, R: View>(@ViewBuilder left: () -> L,
                                          @ViewBuilder right: () -> R) -> some View {
        HStack(spacing: 12) {
            left()
            Spacer(minLength: 12)
            right()
        }
        .font(.system(size: 14))
        .foregroundStyle(Vana.muted)
        .padding(.horizontal, 32)
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(Vana.stroke).frame(height: 1) }
    }

    /// Whatever the launcher last had to say, above the footer on whichever page you are on.
    @ViewBuilder private var noticeStrip: some View {
        if !notice.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(Vana.jade)
                Text(notice).font(.system(size: 13)).foregroundStyle(Vana.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button { notice = "" } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                    .buttonStyle(.borderless).foregroundStyle(Vana.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Vana.jade.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Vana.jade.opacity(0.25)))
            .padding(.horizontal, 32).padding(.bottom, 14)
        }
    }

    // MARK: - Play

    private var playPage: some View {
        VStack(spacing: 0) {
            pageHeader("Play", status: statusText, tone: statusTone)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero.padding(.top, 14)

                    // The one thing standing between the player and the game, when there is
                    // one: the world's files, or the local server. Otherwise nothing sits here.
                    VStack(spacing: 16) {
                        if needsGameData, let i = active, let s = store.selected {
                            gameDataCard(for: s, install: i)
                        }
                        localServerCard
                    }
                    .frame(maxWidth: 640)
                    .padding(.top, 24)

                    launchFields.padding(.top, 24)

                    primaryButton.frame(width: 340).padding(.top, 30)

                    Group {
                        if !perf.renderer.playable {
                            Label("\(perf.renderer.title) is experimental — \(perf.renderer.blurb)",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Vana.ember)
                        } else {
                            Text(nextStepHelp)
                        }
                    }
                    .font(.system(size: 13)).foregroundStyle(Vana.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 32).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The world you are about to enter, named in the game's own typeface over the landscape.
    private var hero: some View {
        ZStack(alignment: .leading) {
            if let art = heroArt {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Vana.forestDeep, Vana.night],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // A scrim on the left so the title reads, thinning to nothing so the painting shows.
            LinearGradient(stops: [.init(color: Color(hex: 0x0A100C).opacity(0.85), location: 0),
                                   .init(color: Color(hex: 0x0A100C).opacity(0.55), location: 0.45),
                                   .init(color: .clear, location: 0.8)],
                           startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                Text(heroEyebrow)
                    .font(.system(size: 11, weight: .semibold)).tracking(3.2)
                    .foregroundStyle(Vana.jade)
                Text((store.selected?.name ?? "FINAL FANTASY XI").uppercased())
                    .font(.system(size: 44, weight: .light, design: .serif)).tracking(6)
                    .foregroundStyle(Color(hex: 0xF6F2E6))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 2)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(heroSubtitle).font(.system(size: 15)).foregroundStyle(Vana.text.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            .padding(.leading, 30).padding(.trailing, 60)
        }
        .frame(height: 228)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            crystal.frame(width: 20, height: 32).padding(.top, 22).padding(.trailing, 28)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06)))
    }

    private var heroEyebrow: String {
        guard let s = store.selected else { return "FINAL FANTASY XI ON APPLE SILICON" }
        if s.local { return "FINAL FANTASY XI · YOUR OWN SERVER" }
        return "FINAL FANTASY XI · PRIVATE SERVER"
    }

    /// Era and, when the world publishes a counter, how many people are on right now.
    private var heroSubtitle: String {
        var parts: [String] = []
        if let era = store.selected?.era, !era.isEmpty { parts.append(era) }
        if let name = store.selected?.name, let n = feeds.populations[name] {
            parts.append("\(n.formatted()) adventurers online")
        }
        if parts.isEmpty { parts.append("Running natively on Apple Silicon — no virtual machine") }
        return parts.joined(separator: "  ·  ")
    }

    /// Ships in the bundle (see bundle.sh). Under `swift run` there is no bundle and the band is
    /// a plain gradient; nothing else changes.
    private var heroArt: NSImage? {
        guard let url = Bundle.main.url(forResource: "hero", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// World on the left, account on the right. Choosing a world and typing the account that
    /// logs into it are one decision, so they sit on one line.
    private var launchFields: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("World")
                worldMenu
                worldNote
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Account")
                // The local server auto-creates its own account on first login (see
                // LocalServer.swift) -- there is no real account to type here.
                field("Account name", text: $user, secure: false, disabled: store.selected?.local == true)
                field("Password", text: $pass, secure: true, disabled: store.selected?.local == true)
                HStack(spacing: 14) {
                    Toggle("Remember me", isOn: $remember)
                        .toggleStyle(.checkbox).font(.system(size: 13)).foregroundStyle(Vana.muted)
                        .help("Stored in the macOS Keychain, never in a file in this project.")
                    Spacer(minLength: 0)
                    accountLinks
                }
                if installs.count > 1 {
                    Picker("", selection: Binding(
                        get: { selected?.id ?? "" },
                        set: { id in selected = installs.first { $0.id == id }; recheck() })
                    ) {
                        ForEach(installs) { i in
                            Text("\(i.wrapper.lastPathComponent) · \(i.prefixName)").tag(i.id)
                        }
                    }
                    .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 760)
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(Vana.muted)
    }

    /// Under the world: what the launcher actually holds about it. The rotating banner used to
    /// carry this; it is the server's own note, its addon rules, or whether this project has
    /// tested it. Nothing is invented to fill the space.
    @ViewBuilder private var worldNote: some View {
        if let s = store.selected, !s.local, s.host.isEmpty {
            Text("No login host set for \(s.name) — add it under Settings.")
                .font(.system(size: 13)).foregroundStyle(Vana.ember)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            newsBanner
        }
    }

    /// Where to get an account. Every world runs its own account database, and some have no web
    /// signup at all -- the account is typed into the loader console on first launch. So this
    /// says the actual route for the selected world, and links to it. See `Server.accountHow`.
    @ViewBuilder private var accountLinks: some View {
        if let s = store.selected, !s.local {
            HStack(spacing: 12) {
                if let u = URL(string: s.accountURL), !s.accountURL.isEmpty {
                    Button { NSWorkspace.shared.open(u) } label: {
                        Label(Self.signupVerb(for: s), systemImage: "arrow.up.forward")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Vana.jade)
                    .help(s.accountHow.isEmpty ? u.absoluteString : s.accountHow)
                } else if s.accountHow.contains("loader window") {
                    Text("Account is created in the loader window")
                        .font(.system(size: 13)).foregroundStyle(Vana.muted)
                        .help(s.accountHow)
                }
                if let d = URL(string: s.discordURL), !s.discordURL.isEmpty, s.discordURL != s.accountURL {
                    Button { NSWorkspace.shared.open(d) } label: { Text("Discord") }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Vana.jade)
                        .help(d.absoluteString)
                }
            }
        }
    }

    /// The footer under Play: the three things that have to be true, then whatever the updater
    /// is doing. While an install runs, the last line of its log takes the left side.
    @ViewBuilder private var playFooter: some View {
        footer {
            if runner.busy, let last = runner.log.split(separator: "\n").last {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(last)).font(.system(size: 13, design: .monospaced)).lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: statusTone == Vana.jade ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(statusTone)
                    Text(footerFacts.joined(separator: "  ·  ")).lineLimit(1)
                }
            }
        } right: {
            updateBanner
        }
    }

    private var footerFacts: [String] {
        guard let i = selected else { return [scanning ? "Looking for your install…" : "Wine not installed yet"] }
        var out = ["Wine ready · \(i.prefixName)"]
        if let a = active, a.hasGame { out.append(needsGameData ? "Game files need attention" : "Game files ready") }
        else { out.append("Game files not installed") }
        out.append(perf.renderer.title)
        return out
    }

    /// One dropdown for every server. HorizonXI is pinned to the top; the rest are ordered by
    /// community size, which is metadata the user never has to see or maintain.
    private var worldMenu: some View {
        // `.borderlessButton` renders a custom Menu label as bare text (no pill, no border, no
        // hover), which is why the world name never looked clickable. A plain-styled button
        // menu draws the label exactly as declared.
        Menu {
            ForEach(store.ordered) { s in
                Button { store.select(s) } label: {
                    if s.era.isEmpty { Text(s.name) }
                    else { Text("\(s.name)  ·  \(s.era)") }
                }
            }
            Divider()
            Button("Add a server…") { newServer = true }
        } label: {
            worldRow
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// What the selected server permits. See `AddonPolicy` for why an unsourced policy shows
    /// everything rather than guessing at a list. A list fetched from the server's own page this
    /// launch beats the snapshot compiled into the app.
    private var addonPolicy: AddonPolicy {
        guard let s = store.selected else { return .unknown }
        return AddonPolicies.policy(for: s, fetched: feeds.fetchedAddonLists)
    }

    /// Why the narration toggle is on, off, or greyed out. The addon-rules case is the one
    /// that matters: VanaVoice is on nobody's published allowlist, and on a server that runs
    /// one -- HorizonXI, CatsEyeXI -- loading it risks the account, so the launcher will not
    /// offer it there at all.
    private var narrationHelp: String {
        if !Narration.isAvailable {
            return "Install VanaVoice.app to use this: github.com/danielalanbates/vanavoice"
        }
        if !Narration.allowed(by: addonPolicy) {
            return "\(store.selected?.name ?? "This server") allows only the addons on its "
                 + "published list, and VanaVoice is not on it. Running it there risks your "
                 + "account, so the launcher will not install it."
        }
        return "Installs VanaVoice's addon into this world and starts the narrator, which "
             + "reads NPC and cutscene dialogue aloud in a neural voice."
    }

    /// A rotating strip of what the launcher knows about the selected world.
    ///
    /// Every line here is something the launcher actually holds -- the server's era, its own
    /// note, the state of its addon rules, whether this project has tested it. **Nothing is
    /// invented to fill the space.** No FFXI private server publishes a news feed a launcher can
    /// read (see `ServerFeeds` for what was checked), so there are no headlines to rotate; the
    /// moment one does, fetched items appear here first and are marked as such.
    /// Shown only when an update has finished downloading and is staged: one line and a Restart
    /// button. While a download is in flight it shows quiet progress; otherwise it renders nothing,
    /// so the normal launcher is undisturbed.
    @ViewBuilder private var updateBanner: some View {
        switch updater.state {
        case .ready(let release):
            HStack(spacing: 10) {
                Text("Update \(release.version) is ready").foregroundStyle(Vana.text)
                Button("Restart") { updater.restartToUpdate() }
                    .buttonStyle(.borderedProminent).tint(Vana.forest).controlSize(.small)
                    .help("Restart to finish installing it.")
            }
        case .downloading(let frac):
            HStack(spacing: 8) {
                ProgressView(value: frac).frame(width: 90)
                Text("Downloading update… \(Int(frac * 100))%")
            }
        case .staging:
            Text("Preparing update…")
        case .failed(let msg):
            // Only worth showing when it is about an update that exists, not routine offline noise.
            if msg.contains("available") {
                Text(msg).foregroundStyle(Vana.ember).lineLimit(1).help(msg)
            }
        case .idle, .checking:
            EmptyView()
        }
    }

    @ViewBuilder
    private var newsBanner: some View {
        let items = feeds.bannerItems(for: store.selected, policy: addonPolicy)
        if items.isEmpty {
            Text("Running natively — no virtual machine")
                .font(.system(size: 13)).foregroundStyle(Vana.muted)
        } else {
            let item = items[min(bannerIndex, items.count - 1) % items.count]
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13)).foregroundStyle(Vana.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = item.url {
                    Link("Open", destination: url).font(.system(size: 13)).foregroundStyle(Vana.jade)
                }
            }
            // Tall enough for the longest item: sized to the two-line items, the whole page
            // nudged up and down as the banner rotated onto a three-line one.
            .frame(minHeight: 50, alignment: .top)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.45), value: bannerIndex)
            .onReceive(bannerTick) { _ in
                bannerIndex = (bannerIndex + 1) % max(items.count, 1)
            }
        }
    }

    // Built outside the view body: as interpolated expressions inline, the type-checker gave up
    // on them ("unable to type-check this expression in reasonable time").
    private static func unknownPolicyNote(_ server: String) -> String {
        "This server's addon rules are not published anywhere this launcher could source them, "
        + "so nothing below is filtered. Check what \(server) allows before you use it — on most "
        + "private servers an unapproved addon is a bannable offence."
    }

    private static func allowlistNote(_ server: String, hidden: Int, source: String) -> String {
        var s = "Showing only what \(server) approves"
        if hidden > 0 {
            let noun = hidden == 1 ? "item is" : "items are"
            s += " — \(hidden) installed \(noun) hidden because they are not on the list"
        }
        return s + ". Source: \(source)."
    }

    /// Why the addon list came back empty. Named paths, because the answer is usually a folder
    /// that is not there.
    private var emptyAddonReason: String {
        let world = store.selected?.name ?? "this world"
        guard let i = active else {
            return "No install is selected, so there is nothing to scan."
        }
        let dir = i.gameDir.path
        if !FileManager.default.fileExists(atPath: dir) {
            return "\(world) has no client here yet: \(dir) does not exist. Download the world's "
                 + "client, or point the launcher at the folder you already have it in."
        }
        return "Nothing installed under \(dir) — no plugins/*.dll and no addons/<name>/<name>.lua. "
             + "If that folder is on a drive that is not mounted, mount it and press Addons… again."
    }

    /// Said once, above the unlisted section, rather than per row.
    private var unlistedNote: String {
        let world = store.selected?.name ?? "This server"
        return "\(world) has not approved these, and on most private servers running an "
             + "unapproved addon is a bannable offence. They are listed because they are "
             + "installed and they are yours to manage — not because they are allowed."
    }

    @ViewBuilder
    private var addonPolicyNote: some View {
        let policy = addonPolicy
        let serverName = store.selected?.name ?? "this server"
        let hidden = addonItems.filter { !policy.allows($0.name) }.count
        switch policy {
        case .unknown:
            Text(Self.unknownPolicyNote(serverName))
                .font(.caption2).foregroundStyle(Vana.ember)
                .fixedSize(horizontal: false, vertical: true)
        case let .unrestricted(reason):
            Text(reason).font(.caption2).foregroundStyle(Vana.muted)
                .fixedSize(horizontal: false, vertical: true)
        case let .allowlist(_, source):
            Text(Self.allowlistNote(serverName, hidden: hidden, source: source))
                .font(.caption2).foregroundStyle(Vana.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Graphics

    /// FFXI's own graphics settings, written into the selected world's boot profile. See
    /// `GraphicsSettings` for why this is not a wrapper around Config.exe.
    private var graphicsPage: some View {
        VStack(spacing: 0) {
            pageHeader("Graphics", status: "Applies next launch", tone: Vana.sand)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Preset").font(.system(size: 15)).foregroundStyle(Vana.text)
                            Text(presetBlurb).font(.system(size: 13)).foregroundStyle(Vana.muted)
                        }
                        Spacer()
                        Picker("", selection: presetBinding) {
                            Text("Low").tag(Preset.low)
                            Text("Balanced").tag(Preset.balanced)
                            Text("Max 4K").tag(Preset.max4K)
                            Text("Custom").tag(Preset.custom)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 320)
                    }
                    .padding(.horizontal, 4)

                    section("Rendering") {
                        row("Resolution", "The world is drawn at this size.") {
                            Picker("", selection: Binding(
                                get: { "\(graphics.width)x\(graphics.height)" },
                                set: { id in
                                    let parts = id.split(separator: "x").compactMap { Int($0) }
                                    if parts.count == 2 { graphics.width = parts[0]; graphics.height = parts[1] }
                                })) {
                                ForEach(GraphicsSettings.resolutions, id: \.0) { r in
                                    Text(r.0).tag("\(r.1)x\(r.2)")
                                }
                            }
                            .labelsHidden().frame(width: 190)
                        }
                        row("Texture resolution") {
                            Picker("", selection: $graphics.textureResolution) {
                                ForEach([512, 1024, 2048, 4096], id: \.self) { Text(String($0)).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                        }
                        row("Mip mapping") {
                            Picker("", selection: $graphics.mipMapping) {
                                ForEach(0...4, id: \.self) { Text($0 == 0 ? "Off" : String($0)).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                        }
                        row("Textures") {
                            Picker("", selection: $graphics.textureCompression) {
                                Text("Uncompressed").tag(0)
                                Text("Compressed").tag(2)
                            }
                            .labelsHidden().frame(width: 160)
                        }
                        row("Bump mapping") {
                            Toggle("", isOn: $graphics.bumpMapping).toggleStyle(.switch).labelsHidden()
                        }
                        row("Environmental animation") {
                            Toggle("", isOn: $graphics.environmentAnimation).toggleStyle(.switch).labelsHidden()
                        }
                    }

                    // "Interface resolution" is FFXI's own name for this and it explains nothing:
                    // the number goes *down* to make the menus bigger, the opposite of every other
                    // resolution control on the screen. Say what it changes.
                    section("Interface") {
                        row("Menu and text size",
                            graphics.uiFollowsResolution
                                ? "Drawn at the render resolution, which at 4K is unreadably small."
                                : "Drawn at \(graphics.uiWidth) × \(graphics.uiHeight) and scaled up. A lower number means bigger menus and text.") {
                            Picker("", selection: uiSizeBinding) {
                                Text("Match render").tag("match")
                                ForEach(GraphicsSettings.uiResolutions, id: \.0) { r in
                                    Text(r.0).tag("\(r.1)x\(r.2)")
                                }
                            }
                            .labelsHidden().frame(width: 200)
                        }
                        row("Remember window size",
                            "The next Play opens at whatever size you left the window. FFXI cannot redraw at a new size while running, so a window enlarged mid-game is stretched until then.") {
                            Toggle("", isOn: $graphics.rememberWindowSize).toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
            }
        }
    }

    private enum Preset: Hashable { case low, balanced, max4K, custom }

    /// Which preset the current settings *are*, if any. Nothing is stored: a Custom that matches
    /// Balanced exactly is Balanced.
    private var presetBinding: Binding<Preset> {
        Binding(get: {
            if graphics == .lowSpec { return .low }
            if graphics == .balanced { return .balanced }
            if graphics == .max4K { return .max4K }
            return .custom
        }, set: { p in
            switch p {
            case .low:      graphics = .lowSpec
            case .balanced: graphics = .balanced
            case .max4K:    graphics = .max4K
            case .custom:   break
            }
        })
    }

    private var presetBlurb: String {
        switch presetBinding.wrappedValue {
        case .low:      return "For the local world and older Macs."
        case .balanced: return "Right for most Apple Silicon Macs."
        case .max4K:    return "Everything at maximum, drawn at 4K."
        case .custom:   return "Your own mix of the settings below."
        }
    }

    private var uiSizeBinding: Binding<String> {
        Binding(get: {
            graphics.uiFollowsResolution ? "match" : "\(graphics.uiWidth)x\(graphics.uiHeight)"
        }, set: { id in
            if id == "match" { graphics.uiFollowsResolution = true; return }
            let parts = id.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { return }
            graphics.uiFollowsResolution = false
            graphics.uiWidth = parts[0]; graphics.uiHeight = parts[1]
        })
    }

    private var graphicsFooter: some View {
        footer {
            Text("Written into \(store.selected?.bootProfile ?? "the boot profile") for "
                 + "\(store.selected?.name ?? "this world") the next time you press Play.")
                .lineLimit(1)
        } right: {
            Button("Revert") { loadGraphics() }
            Button("Apply") { applyGraphics() }
                .buttonStyle(.borderedProminent).tint(Vana.forest)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func applyGraphics() {
        graphics.save(world: store.selected?.name)
        guard let i = selected, let s = store.selected else {
            notice = "Saved. There is no install selected yet, so nothing was written to a boot "
                   + "profile — it will be written the first time you play."
            return
        }
        Credentials.ensureProfile(s.bootProfile, in: i)
        graphics.write(to: i, profile: s.bootProfile)
        notice = "Graphics written to \(s.bootProfile). They take effect the next time you press Play."
    }

    // MARK: - Add-ons

    /// Ashita's plugins and Lua addons, the same set HorizonXI's own launcher manages.
    private var addonsPage: some View {
        VStack(spacing: 0) {
            pageHeader("Add-ons", status: "Applies next launch", tone: Vana.sand)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        addonPolicyNote
                        if !addonWarning.isEmpty {
                            Text(addonWarning).font(.system(size: 13)).foregroundStyle(Vana.ember)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if addonItems.isEmpty {
                            Text(emptyAddonReason).font(.system(size: 13)).foregroundStyle(Vana.ember)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 4)

                    // Extras this project can fetch for the local world. Never shown for a live
                    // server — nothing here is on any published approved list.
                    if case .unrestricted = addonPolicy, let i = active {
                        let missing = LocalWorldAddons.all.filter { !LocalWorldAddons.isInstalled($0, in: i) }
                        if !missing.isEmpty {
                            section("Available for this world") {
                                ForEach(missing, id: \.name) { e in extraAddonRow(e, install: i) }
                            }
                        }
                    }

                    let plugins = $addonItems.filter { $0.wrappedValue.isPlugin && addonPolicy.allows($0.wrappedValue.name) }
                    let addons  = $addonItems.filter { !$0.wrappedValue.isPlugin && addonPolicy.allows($0.wrappedValue.name) }
                    let unlisted = $addonItems.filter { !addonPolicy.allows($0.wrappedValue.name) }
                    if !plugins.isEmpty { section("Plugins") { ForEach(plugins) { $item in addonRow($item) } } }
                    if !addons.isEmpty { section("Add-ons") { ForEach(addons) { $item in addonRow($item) } } }
                    // Shown, not hidden. An allowlist is the server's list of what it has approved,
                    // which is not the same as a list of everything that exists: an addon the
                    // player wrote themselves is on nobody's list and used to vanish from this
                    // screen with no way to manage it. The rules still get stated plainly, and
                    // nothing here is enabled by "Enable all" -- the choice is the player's.
                    if !unlisted.isEmpty {
                        section("Not on \(store.selected?.name ?? "this server")'s approved list") {
                            block {
                                Text(unlistedNote).font(.system(size: 13)).foregroundStyle(Vana.ember)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Rectangle().fill(Vana.stroke).frame(height: 1).padding(.leading, 16)
                            ForEach(unlisted) { $item in addonRow($item) }
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
            }
        }
    }

    /// One addon, with what it says about itself underneath. The description comes out of the
    /// addon's own Lua header (see `AddonSuite.metadata`), so it always matches what is installed.
    private func addonRow(_ item: Binding<AddonSuite.Item>) -> some View {
        let detail = item.wrappedValue.desc
        let byline = item.wrappedValue.byline
        let sub = detail.isEmpty ? byline : (byline.isEmpty ? detail : "\(detail)  ·  \(byline)")
        return row(item.wrappedValue.name, sub) {
            Toggle("", isOn: item.enabled).toggleStyle(.switch).labelsHidden()
        }
    }

    /// One of this project's own extras for the local world, with the button that fetches it.
    private func extraAddonRow(_ e: LocalWorldAddons.Entry, install i: Install) -> some View {
        row(e.title, e.blurb) {
            Button(installingExtra == e.name ? "Installing…" : "Get") {
                installingExtra = e.name
                Task {
                    let ok = await LocalWorldAddons.install(e, into: i) { line in
                        Task { @MainActor in runner.appendLine(line) }
                    }
                    await MainActor.run {
                        installingExtra = ""
                        if ok {
                            addonItems = AddonSuite.scan(i)
                            if let idx = addonItems.firstIndex(where: {
                                !$0.isPlugin && $0.name.lowercased() == e.name }) {
                                addonItems[idx].enabled = true
                            }
                            notice = "\(e.title) installed — press Apply to load it next Play."
                        } else {
                            notice = "\(e.title) could not be installed; see the log under Settings."
                        }
                    }
                }
            }
            .disabled(!installingExtra.isEmpty)
        }
    }

    private var addonsFooter: some View {
        footer {
            // "All" means all the ones this server permits. Enabling something the server
            // forbids is not a convenience, it is a ban.
            Button("Enable all") {
                for i in addonItems.indices where addonPolicy.allows(addonItems[i].name) {
                    addonItems[i].enabled = true
                }
            }
            Button("Disable all") { for i in addonItems.indices { addonItems[i].enabled = false } }
        } right: {
            Button("Revert") { loadAddons() }
            Button("Apply") { applyAddons() }
                .buttonStyle(.borderedProminent).tint(Vana.forest)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func applyAddons() {
        // Refuse to write a block that would disable everything.
        //
        // On 2026-08-22 a broken fetch made the policy reject every installed addon (see
        // ServerFeeds.resembles). The screen went blank, Apply wrote an empty managed block,
        // and the cursor fix -- which lived in an addon on nobody's published list -- vanished
        // from scripts/default.txt with it. A player pressing Apply is asking to save a list,
        // never to lose one, so a policy that permits *nothing* is treated as a broken policy
        // rather than obeyed.
        let permitted = addonItems.filter { addonPolicy.allows($0.name) }
        if !addonItems.isEmpty && permitted.isEmpty {
            notice = "Not saving: this server's addon list came back empty, so every addon you "
                   + "have would be switched off. Nothing was written."
            return
        }
        // Belt and braces: a hidden row cannot be toggled on, but the list on disk
        // may already have named something this server forbids, and pressing Apply
        // must not write it back out.
        for i in addonItems.indices where !addonPolicy.allows(addonItems[i].name) {
            addonItems[i].enabled = false
        }
        // What is enabled here is what gets written, including anything from the unlisted
        // section. Force-disabling those behind the player's back is what removed the cursor fix
        // on 2026-08-22, and now that they are visible and individually toggled, switching them
        // off would be overriding a choice rather than preventing an accident. It is said out
        // loud instead.
        let unapproved = addonItems.filter { $0.enabled && !addonPolicy.allows($0.name) }
        if let i = active, !AddonSuite.write(addonItems, to: i) {
            notice = "Could not write scripts/default.txt — its launcher markers are missing."
        } else if !unapproved.isEmpty, addonPolicy.isRestricting {
            notice = "Addon list saved, including \(unapproved.count) "
                   + "\(store.selected?.name ?? "this server") does not approve: "
                   + unapproved.map(\.name).joined(separator: ", ") + "."
        } else {
            notice = "Addon list saved. It takes effect the next time you press Play."
        }
    }

    // MARK: - Settings

    /// Everything that is not a per-world game setting: what preflight found, which renderer, how
    /// the wrapper behaves while the game runs, the maintenance actions, and the log.
    private var setupPage: some View {
        VStack(spacing: 0) {
            pageHeader("Settings", status: statusText, tone: statusTone)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if !checks.isEmpty {
                        section("What \(store.selected?.name ?? "this world") needs") {
                            block {
                                statusList
                                if checks.contains(where: { $0.id == "fda" && $0.state == .bad }) {
                                    Button("Open Full Disk Access settings…") {
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                                    }
                                    .buttonStyle(.borderedProminent).tint(Vana.forest)
                                }
                            }
                        }
                    }

                    section("Renderer") {
                        row("Renderer", perf.renderer.blurb) {
                            Picker("", selection: $perf.renderer) {
                                ForEach(Renderer.allCases) { r in Text(r.title).tag(r) }
                            }
                            .labelsHidden().frame(width: 220)
                            .onChange(of: perf.renderer) { _ in perf.save() }
                        }
                        if perf.renderer == .mtld3d {
                            row("Native game window",
                                "Use macOS window controls. Press Command-comma while playing for graphics settings. Applies on the next launch.") {
                                Toggle("", isOn: $perf.nativeGameHost).toggleStyle(.switch).labelsHidden()
                                    .onChange(of: perf.nativeGameHost) { _ in perf.save() }
                            }
                        }
                    }

                    // The host and boot-profile fields are the two things that can be wrong in a
                    // way no amount of pressing Play will fix, so they are editable — but here,
                    // not beside the world picker, where they read as something to fill in.
                    if let s = store.selected, !s.local {
                        section("Server connection · \(s.name)") { block { serverConnectionFields(s) } }
                    }

                    section("While the game runs") { perfToggles }

                    section("Maintenance") { block { maintenance } }

                    section("Accounts on other worlds") {
                        block {
                            ForEach(store.ordered.filter { $0.name != store.selected?.name }) { other in
                                signupRow(other)
                            }
                        }
                    }

                    section("Log") { logView }
                }
                .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
            }
        }
    }

    private func serverConnectionFields(_ s: Server) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            field("Login host", text: Binding(
                get: { s.host }, set: { var c = s; c.host = $0; store.update(c) }), secure: false)
            field("Boot profile (.ini)", text: Binding(
                get: { s.bootProfile },
                set: { var c = s; c.bootProfile = $0; store.update(c) }), secure: false)
            if !Server.builtins.contains(where: { $0.name == s.name }) {
                Button(role: .destructive) { store.remove(s) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(Vana.ember)
                    .padding(.bottom, 9)
                    .help("Remove \(s.name) from the world list.")
            }
        }
    }

    private var perfToggles: some View {
        Group {
            row("Fast synchronisation (msync)") { Toggle("", isOn: $perf.msync).toggleStyle(.switch).labelsHidden() }
            row("Silence wine debug channels") { Toggle("", isOn: $perf.silenceWineDebug).toggleStyle(.switch).labelsHidden() }
            row("Keep awake (no App Nap)") { Toggle("", isOn: $perf.disableAppNap).toggleStyle(.switch).labelsHidden() }
            row("Follow the Mac's sound output",
                "Switch headphones, speakers or a Bluetooth device while the game is running and the sound moves with it.") {
                Toggle("", isOn: $perf.followSoundOutput).toggleStyle(.switch).labelsHidden()
            }
            row("Read cutscenes aloud (VanaVoice)", narrationHelp) {
                Toggle("", isOn: $perf.narrateCutscenes).toggleStyle(.switch).labelsHidden()
                    .disabled(!Narration.isAvailable || !Narration.allowed(by: addonPolicy))
            }
            row("Large address aware") { Toggle("", isOn: $perf.largeAddressAware).toggleStyle(.switch).labelsHidden() }
            row("Fast lens flares (skip occlusion wait) — glitches",
                "Roughly doubles the frame rate, but NPCs blink in and out about once a second. Off until that is fixed properly.") {
                Toggle("", isOn: $perf.flareReadbackNoWait).toggleStyle(.switch).labelsHidden()
            }
            row("Show frame rate (Metal HUD)") { Toggle("", isOn: $perf.metalHUD).toggleStyle(.switch).labelsHidden() }
        }
        .onChange(of: perf.msync) { _ in perf.save() }
        .onChange(of: perf.silenceWineDebug) { _ in perf.save() }
        .onChange(of: perf.disableAppNap) { _ in perf.save() }
        .onChange(of: perf.followSoundOutput) { _ in perf.save() }
        .onChange(of: perf.largeAddressAware) { _ in perf.save() }
        .onChange(of: perf.narrateCutscenes) { _ in perf.save() }
        .onChange(of: perf.metalHUD) { _ in perf.save() }
    }

    @ViewBuilder private var maintenance: some View {
        HStack(spacing: 8) {
            Button("Repair") {
                if let i = active { runner.repair(i) { _ in recheck() } }
            }
            .disabled(runner.busy)
            if store.selected?.name == "HorizonXI" {
                Button("Update HorizonXI…") {
                    if let i = active { runner.updateHorizon(i) { _ in recheck() } }
                }
                .disabled(runner.busy)
                .help("""
                    Only press this when HorizonXI have actually published an \
                    update and the game is refusing to let you in. It is not \
                    routine maintenance: it rewrites files in a working install, \
                    takes an hour or more over BitTorrent, and can leave the \
                    client mid-update if it stalls. A working install does not \
                    need it. Play stays available either way — HorizonXI's login \
                    server accepts an install that is a version or two behind.
                    """)
            }
            if store.selected?.name == "CatsEyeXI" {
                Button("CatsEyeXI installer…") { if let i = active, let s = store.selected { runner.runCatsEyeLauncher(i, dataPath: s.dataPath) } }
                    .disabled(runner.busy)
                    .help("Runs CatsEyeXI's own launcher inside the wrapper to install or update their client (their storage is private, so only their launcher can fetch it).")
            }
            if let s = store.selected, !s.local {
                Button("Run installer…") { if let i = active { runLocalInstaller(for: s, install: i) } }
                    .disabled(runner.busy)
                    .help("Run a Windows installer or launcher (.exe or .zip) you already downloaded for \(s.name), inside the wrapper. It installs into C:\\Games\\\(s.name), which is \(s.dataPath.isEmpty ? "the folder you choose" : s.dataPath).")
            }
            if runner.busy {
                Button("Stop install") { if let i = active { runner.cancelInstaller(i) } }
                    .help("Kills whatever is running in the installer prefix.")
            }
            // Also reachable when an install already exists: a wrapper can be broken past what
            // Repair fixes, and rebuilding a fresh one beside it is faster than diagnosing wine
            // by hand.
            Button("Install wine…") { showSetup = true }
            Button { refresh() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .help("Rescan for installs")
            Button { chooseInstall() } label: { Label("Choose install…", systemImage: "folder") }
                .help("Point at the wrapper app if it lives somewhere the scan does not look, such as Downloads")
        }
        .lineLimit(1)

        // Said out loud, not just in a tooltip. Chasing client updates that the game does not
        // need is a good way to break a working install: the fetch is a multi-hour torrent, it
        // rewrites files in place, and a stall leaves the client half-updated. Being a version
        // behind is normal and playable.
        note("Don't update the client unless the world has actually published an update and the "
             + "game is turning you away. A working install does not need one — being a version "
             + "or two behind is normal, and Play still works. Updating rewrites a working "
             + "install over a multi-hour download.")
    }

    private var logView: some View {
        ScrollViewReader { sp in
            ScrollView {
                Text(runner.log.isEmpty ? "ready." : runner.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Vana.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .id("end")
            }
            .frame(height: 180)
            .onChange(of: runner.log) { _ in sp.scrollTo("end", anchor: .bottom) }
        }
    }

    private var addServerSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a server").font(.headline).foregroundStyle(Vana.text)
            field("Name", text: $newName, secure: false)
            field("Login host", text: $newHost, secure: false)
            field("Boot profile (.ini)", text: $newProfile, secure: false)
            HStack {
                Spacer()
                Button("Cancel") { newServer = false }
                Button("Add") {
                    store.add(name: newName, host: newHost, profile: newProfile)
                    newName = ""; newHost = ""; newProfile = ""; newServer = false
                }
                .buttonStyle(.borderedProminent).tint(Vana.forest)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 360)
        .background(Vana.backdrop)
    }

    /// Shown only for the local world. Selecting it means building an FFXI server on this Mac, so
    /// this says what that will cost and what is left to do before Play can work.
    @ViewBuilder private var localServerCard: some View {
        if store.selected?.local == true {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Your own server", systemImage: "internaldrive")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Vana.text)
                    Spacer()
                    if local.busy {
                        ProgressView().controlSize(.small)
                        Text(local.activity).font(.caption2).foregroundStyle(Vana.muted)
                    }
                }

                if let s = local.status {
                    // Disk first: it is the one thing the user has to fix outside this app, and
                    // finding out 20 minutes into a build is far worse than finding out here.
                    // Once the server is built the space warning is about the *next* build, not
                    // this one, so state the number without dressing it as a problem.
                    HStack(spacing: 6) {
                        Image(systemName: (s.spaceOK || s.ready)
                              ? "checkmark.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle((s.spaceOK || s.ready) ? Vana.jade : Vana.ember)
                        Text(s.ready
                             ? String(format: "%.1f GB free on this disk", s.freeGB)
                             : String(format: "%.1f GB free · about %.0f GB needed",
                                      s.freeGB, s.needGB))
                            .font(.caption)
                            .foregroundStyle((s.spaceOK || s.ready) ? Vana.text : Vana.ember)
                    }

                    if !s.spaceOK && !s.ready {
                        Text(s.belowFloor
                             ? "Not enough room to install a server. It needs roughly \(Int(s.needGB)) GB — "
                               + "about 5 GB of source, 3 GB of build output, and headroom for the "
                               + "database and the compiler. Free up space, then set up."
                             : "Below the recommended \(Int(s.needGB)) GB but above the "
                               + "\(Int(s.floorGB)) GB minimum. Setup will run, and may run tight.")
                            .font(.caption2).foregroundStyle(Vana.ember)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if s.ready {
                        row("Server", s.running
                            ? "running · \(s.up.count) of 4 processes"
                            : "built and ready — Play will start it")
                    } else {
                        row("Still to do", s.todo)
                        Text("Setting up downloads Homebrew packages and the LandSandBoat source, "
                             + "imports the game database and compiles the server. Budget half an "
                             + "hour or more the first time; it can be re-run if it stops.")
                            .font(.caption2).foregroundStyle(Vana.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    row("Location", s.root)

                    HStack(spacing: 8) {
                        if !s.ready {
                            Button(s.source ? "Continue setup" : "Set up server") {
                                local.setup(force: s.belowFloor && forceSetup,
                                            log: { runner.appendLine($0) })
                            }
                            .disabled(local.busy || (s.belowFloor && !forceSetup))
                            if s.belowFloor {
                                Toggle("Set up anyway", isOn: $forceSetup)
                                    .toggleStyle(.checkbox).font(.caption2)
                                    .foregroundStyle(Vana.muted)
                            }
                        }
                        if s.ready {
                            Button(s.running ? "Stop server" : "Start server") {
                                if s.running { local.stop(log: { runner.appendLine($0) }) }
                                else { local.start(log: { runner.appendLine($0) }) }
                            }
                            .disabled(local.busy)
                        }
                        Button("Refresh") { local.refresh() }.disabled(local.busy)
                    }
                    .padding(.top, 2)
                } else {
                    Text("checking what is installed…")
                        .font(.caption2).foregroundStyle(Vana.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Vana.raised.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Vana.stroke))
        }
    }

    /// A world with no signup link at all still gets a row, saying so — a missing row reads as
    /// "the launcher forgot this one".
    @ViewBuilder
    private func signupRow(_ other: Server) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(other.name).font(.system(size: 14)).foregroundStyle(Vana.text)
                .frame(width: 130, alignment: .leading)
            if let u = URL(string: other.accountURL), !other.accountURL.isEmpty {
                Link(Self.signupVerb(for: other), destination: u)
                    .font(.system(size: 13)).foregroundStyle(Vana.jade)
                    .help(other.accountHow.isEmpty ? u.absoluteString : other.accountHow)
            } else {
                Text(other.accountHow.contains("loader window")
                     ? "in the loader window" : "no signup published")
                    .font(.system(size: 13)).foregroundStyle(Vana.muted)
                    .help(other.accountHow)
            }
            Spacer(minLength: 0)
            if let d = URL(string: other.discordURL), !other.discordURL.isEmpty,
               other.discordURL != other.accountURL {
                Link("Discord", destination: d).font(.system(size: 13)).foregroundStyle(Vana.jade)
            }
        }
    }

    /// Say what the link actually does. Some of these lead to a wiki page or a control panel
    /// rather than a registration form, and calling that "Create account" would be a lie. A
    /// world with no signup page gets no button at all: its account is created in the loader
    /// window at Play time, so there is nowhere to send the player.
    private static func signupVerb(for s: Server) -> String {
        guard !s.accountURL.isEmpty else { return "" }
        if s.accountURL.contains("register") { return "Create account" }
        if s.accountURL.contains("fandom.com") || s.accountURL.contains("wordpress.com") {
            return "How to get one"
        }
        return "Account page"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Vana.muted2).frame(width: 90, alignment: .leading)
            Text(v).font(.system(size: 13)).foregroundStyle(Vana.text)
            Spacer()
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(checks) { c in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color(c.state)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.system(size: 14)).foregroundStyle(Vana.text)
                        Text(c.detail).font(.system(size: 12)).foregroundStyle(Vana.muted)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool,
                       disabled: Bool = false) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .disabled(disabled)
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(Vana.raised))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Vana.stroke))
        .foregroundStyle(disabled ? Vana.muted : Vana.text)
        .opacity(disabled ? 0.5 : 1)
    }

    /// The visible world picker row (see the ZStack in the sidebar for why it is separate).
    private var worldRow: some View {
        HStack(spacing: 8) {
            Text(store.selected?.name ?? "Choose a world")
                .font(.system(size: 15)).foregroundStyle(Vana.text).lineLimit(1)
            if store.selected?.verified == true {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 11))
                    .foregroundStyle(Vana.jade)
                    .help("This project logs into this server successfully.")
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Vana.muted)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(worldHover ? Vana.raised : Vana.raised.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(worldHover ? Vana.jade.opacity(0.6) : Vana.stroke))
        .contentShape(Rectangle())
        .onHover { hovering in
            worldHover = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    /// Shown when the chosen world's game files are not where the launcher expects them. Two
    /// answers, both one click: point at a folder that already has them, or get them from the
    /// world's own source. The location is the user's to choose — external drives welcome — and
    /// is remembered per world in servers.json.
    private func gameDataCard(for s: Server, install i: Install) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before you can play").font(.system(size: 15, weight: .semibold)).foregroundStyle(Vana.text)
            Text(s.dataPath.isEmpty
                 ? (i.hasGame ? "\(s.name) has no folder of its own yet — Play would use HorizonXI's files, which \(s.name)'s login server may reject."
                              : "\(s.name)'s game files are not installed yet.")
                 : "Nothing playable at \(s.dataPath).")
                .font(.system(size: 13)).foregroundStyle(Vana.muted).fixedSize(horizontal: false, vertical: true)
            if !s.installNote.isEmpty {
                Text(s.installNote).font(.system(size: 13)).foregroundStyle(Vana.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Three buttons never fit this panel's width: they rendered as "Downloa…",
            // "Choose fold…", "Run installer…" -- the primary action unreadable. The action that
            // matters gets its own full-width row; the alternatives share the one below.
            VStack(alignment: .leading, spacing: 6) {
                if s.installKind != .none {
                    // The button used to read "Download…" whether or not a download was already
                    // going, and a second press was silently ignored -- so a download that had
                    // been killed (quitting the launcher kills its child processes) and one that
                    // was running looked exactly the same. It now says which it is.
                    Button { downloadGameData(for: s, install: i) } label: {
                        Label(runner.busy ? "Downloading…" : "Download…",
                              systemImage: runner.busy ? "arrow.down.circle.dotted" : "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent).tint(Vana.forest)
                    .disabled(runner.busy || runner.running)
                    .help(runner.busy
                          ? "Another download or install is running — watch the log on the left. It resumes where it left off if it is interrupted."
                          : "Downloads are resumable: if this is interrupted, press Download again and it continues.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                Button(locating ? "Looking…" : "Locate…") { locate(s) }
                    .disabled(locating)
                    .help("Search this Mac for a \(s.name) client instead of hunting for the folder yourself.")
                Button("Choose folder…") { chooseGameData(for: s) }
                if !s.local {
                    Button("Run installer…") { runLocalInstaller(for: s, install: i) }
                        .help("Already have \(s.name)'s installer? Run it inside the wrapper.")
                }
                if s.name == "HorizonXI" {
                    Button("Install into wrapper…") { showSetup = true }
                        .help("The classic route: run HorizonXI's installer inside the wrapper.")
                }
                }
            }.lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Vana.raised.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Vana.stroke))
    }

    /// What "Locate…" found, with the reason it thinks so. The reason is shown because a
    /// wrong guess here is not cosmetic: pointing a world at another world's client launches
    /// and plays *that* world's data (Install.clientAmbiguity), so the player gets to judge.
    private var locateSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clients found for \(locateFor?.name ?? "this world")").font(.headline)
            if locateHits.isEmpty {
                Text("Nothing on this Mac looks like an FFXI client for that world. If it is on "
                     + "a drive that is not plugged in, plug it in and try again; otherwise use "
                     + "Choose folder… and point at it yourself.")
                    .font(.caption).foregroundStyle(Vana.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Pick the one that is that world's client. The launcher will look inside it "
                     + "for Ashita and the game data.")
                    .font(.caption).foregroundStyle(Vana.muted)
                    .fixedSize(horizontal: false, vertical: true)
                List(locateHits) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        Button(hit.dataPath.path) { use(hit) }
                            .buttonStyle(.plain).font(.caption).lineLimit(2)
                        Text(hit.why).font(.caption2).foregroundStyle(Vana.muted)
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 240)
            }
            HStack {
                Spacer()
                Button("Cancel") { locateFor = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 520)
    }

    private func locate(_ s: Server) {
        locating = true
        Task.detached(priority: .userInitiated) {
            let hits = Locator.candidates(for: s)
            await MainActor.run {
                locating = false
                locateHits = hits
                locateFor = s
                runner.appendLine("==> locate \(s.name): \(hits.count) candidate(s)")
            }
        }
    }

    private func use(_ hit: Locator.Hit) {
        guard let s = locateFor else { return }
        var c = s; c.dataPath = hit.dataPath.path; store.update(c)
        locateFor = nil
        notice = "\(s.name) now points at \(hit.dataPath.path)."
        recheck()
    }

    /// Ask where this world's files are (or should go). Defaults to ~/Games/FFXI/<world>, and
    /// the user can pick any drive. The choice is stored on the server entry.
    private func chooseGameData(for s: Server) {
        let panel = NSOpenPanel()
        panel.title = "Game data for \(s.name)"
        panel.message = "Choose the folder that holds (or will hold) \(s.name)'s game files. Any drive is fine; the launcher finds Ashita-cli.exe and SquareEnix inside it, however \(s.name)'s installer laid them out."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        let def = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games/FFXI/\(s.name)")
        try? FileManager.default.createDirectory(at: def, withIntermediateDirectories: true)
        panel.directoryURL = def
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var c = s; c.dataPath = url.path; store.update(c)
        recheck()
    }

    /// The user already has the world's installer (their site, Discord, a friend's USB stick).
    /// Run it in the wrapper, pointed at the world's data folder.
    private func runLocalInstaller(for s: Server, install i: Install) {
        if s.dataPath.isEmpty {
            chooseGameData(for: s)
            guard let again = store.servers.first(where: { $0.name == s.name }), !again.dataPath.isEmpty else { return }
            runLocalInstaller(for: again, install: i.forServer(again)); return
        }
        let panel = NSOpenPanel()
        panel.title = "Installer for \(s.name)"
        panel.message = "Pick \(s.name)'s Windows installer or launcher (.exe, or a .zip holding one). It runs inside the wrapper; when it asks where to install, use C:\\Games\\\(s.name) — that is \(s.dataPath)."
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.exe, .zip]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = "Run in wrapper"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runner.runLocalInstaller(url, in: i, dataPath: s.dataPath, name: s.name)
    }

    /// Where a world's own download page is, for when a direct installer link has gone stale.
    static let homePages: [String: String] = [
        "Eden": "https://edenxi.com", "FFEra": "https://ffera.com/login.php?guide=install",
        "ValhallaXI": "https://valhalla.group/site/connect.html", "Gaia XI": "https://gaiaxi.com",
        "CatsEyeXI": "https://catseyexi.com/download",
    ]

    /// Get the world's client the way that world distributes it. Nothing here redistributes
    /// Square Enix data: each route runs or opens the server's own installer.
    private func downloadGameData(for s: Server, install i: Install) {
        if s.dataPath.isEmpty && s.name != "HorizonXI" {
            chooseGameData(for: s)
            guard let again = store.servers.first(where: { $0.name == s.name }), !again.dataPath.isEmpty else { return }
            downloadGameData(for: again, install: i.forServer(again)); return
        }
        switch s.installKind {
        case .catseyeLauncher:
            runner.runCatsEyeLauncher(i, dataPath: s.dataPath)
        case .horizonTorrent:
            runner.installHorizon(i) { _ in recheck() }
        case .installerExe:
            guard let u = URL(string: s.installURL) else { return }
            runner.installPageFallback = Self.homePages[s.name].flatMap(URL.init(string:))
            // An NSIS script may ignore /D= and install wherever it likes (Eden's does). Take
            // the folder the installer actually used rather than assuming the one we asked for —
            // a dataPath that does not hold the world's client is what made "Play Eden" launch
            // the HorizonXI client in the first place.
            runner.onClientInstalled = { found in
                guard var c = store.servers.first(where: { $0.name == s.name }) else { return }
                if c.dataPath != found.path {
                    c.dataPath = found.path; store.update(c)
                    runner.appendLine("==> \(s.name)'s game data folder set to \(found.path)")
                }
                recheck()
            }
            runner.runInstaller(from: u, in: i, dataPath: s.dataPath, name: s.name)
        case .clientZip:
            guard let u = URL(string: s.installURL) else { return }
            runner.installPageFallback = Self.homePages[s.name].flatMap(URL.init(string:))
            runner.installClientZip(from: u, into: s.dataPath, name: s.name)
        case .retail:
            runner.installRetail(for: s, in: i)
        case .website:
            if let u = URL(string: s.installURL) { NSWorkspace.shared.open(u) }
            notice = "\(s.name)'s download page is open in your browser. Save their installer, then use Run installer… (Setup & Diagnostics) or install into \(s.dataPath.isEmpty ? "the folder you choose" : s.dataPath) and press ↻."
        case .none:
            notice = "\(s.name) publishes no client download this launcher knows about."
        }
    }

    /// What to do next, said on the button rather than left for the player to work out.
    ///
    /// A first run used to show a greyed-out PLAY and nothing else: the one state where the
    /// launcher knows exactly what is missing was also the state where it said the least. So the
    /// button *is* the next step — install wine, fetch the world's files, go and read what
    /// preflight found, or play. It is only ever grey while something is genuinely in flight.
    private enum NextStep {
        case scanning, installing, setUp, getData, chooseData, fixSetup, running, play
    }

    private var nextStep: NextStep {
        if runner.running { return .running }
        if runner.busy { return .installing }
        if selected == nil { return scanning ? .scanning : .setUp }
        if needsGameData {
            // A world with no download route of its own cannot be fetched from here; the only
            // thing that can move it forward is pointing the launcher at files already on disk.
            if let s = store.selected, s.installKind == .none { return .chooseData }
            return .getData
        }
        if blocked { return .fixSetup }
        return .play
    }

    private var nextStepLabel: String {
        let world = store.selected?.name ?? "the game"
        switch nextStep {
        case .scanning:   return "Looking for your install…"
        case .installing: return "Working — see the log below"
        case .setUp:      return "Set up FFXI on Mac"
        case .getData:    return "Get \(world)'s game files"
        case .chooseData: return "Choose \(world)'s game folder…"
        case .fixSetup:   return "Finish setting up \(world)"
        case .running:    return "Running"
        case .play:       return "Play \(world)"
        }
    }

    private var nextStepHelp: String {
        switch nextStep {
        case .scanning:   return "Looking through /Applications and /Volumes for a wrapper."
        case .installing: return "A download or install is running in the wrapper. It is resumable."
        case .setUp:      return "Installs Rosetta 2 and Wine, and creates the Windows drive FFXI installs into."
        case .getData:    return "Gets this world's client the way that world distributes it."
        case .chooseData: return "Point the launcher at the folder that holds this world's game files."
        case .fixSetup:   return "Opens Settings, which lists what is blocking this world."
        case .running:    return "The game is running."
        case .play:       return "Launches the client and logs in."
        }
    }

    private func doNextStep() {
        switch nextStep {
        case .scanning, .installing, .running:
            return
        case .setUp:
            showSetup = true
        case .getData:
            if let s = store.selected, let i = active { downloadGameData(for: s, install: i) }
        case .chooseData:
            if let s = store.selected { chooseGameData(for: s) }
        case .fixSetup:
            page = .setup
        case .play:
            play()
        }
    }

    private var primaryButton: some View {
        let step = nextStep
        let waiting = step == .scanning || step == .installing || step == .running
        return Button(action: doNextStep) {
            HStack(spacing: 12) {
                if waiting {
                    ProgressView().controlSize(.small)
                } else if step == .play {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                }
                Text(nextStepLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if step == .play {
                    Text("Return ↵")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25)))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(
                LinearGradient(colors: waiting ? [Vana.raised, Vana.raised]
                                               : [Vana.forest, Vana.forestDeep],
                               startPoint: .top, endPoint: .bottom))
            .foregroundStyle(waiting ? Vana.muted : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(waiting ? Vana.stroke : Vana.jade.opacity(0.35)))
            .shadow(color: waiting ? .clear : Vana.forest.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(waiting)
        .help(nextStepHelp)
    }

    // MARK: - Actions

    private func play() {
        guard let i = active else { return }
        if runner.busy {
            notice = "An install or update is running in the wrapper. Play would stop it — wait for it to finish (or cancel it from Setup & Diagnostics)."
            runner.appendLine("!! " + notice)
            return
        }
        notice = ""
        updateChecked = false
        Credentials.setUsername(user, forWorld: store.selected?.name ?? "")
        Credentials.remember = remember
        if remember { Credentials.savePassword(pass, for: user, world: store.selected?.name ?? "") }
        else { Credentials.savePassword("", for: user, world: store.selected?.name ?? "") }

        let server = store.selected ?? Server.builtins[0]
        guard !server.host.isEmpty else {
            notice = "\(server.name) has no login host set."
            runner.appendLine("!! " + notice)
            return
        }

        // The local world has to be running before the client can reach it. Start it here rather
        // than making the user press two buttons in the right order — but never build from Play,
        // because a first build is a half-hour job the user should be choosing deliberately.
        if server.local {
            guard let s = local.status, s.ready else {
                notice = local.status == nil
                    ? "Still checking the local server."
                    : "The local server is not set up yet — press “Set up server”."
                return
            }
            if !s.running {
                local.start(log: { runner.appendLine($0) }) { ok in
                    if ok { launchClient(i, server: server) }
                    else { notice = "The local server did not start — see the log." }
                }
                return
            }
        }
        launchClient(i, server: server)
    }

    private func launchClient(_ i: Install, server: Server) {
        // Two servers on the list publish no login host anywhere this project could find. Ashita
        // would take `--server ` with nothing after it and fail somewhere less obvious, so say
        // what is actually missing instead.
        if server.host.trimmingCharacters(in: .whitespaces).isEmpty {
            notice = "\(server.name) has no login host set. Get it from that server's own "
                   + "launcher or setup guide and put it in the server's Host field."
            runner.appendLine("!! " + notice)
            return
        }
        // A world the install has no boot profile for — the local one, on every machine — needs
        // that file to exist before anything can be written into it.
        if !Credentials.ensureProfile(server.bootProfile, in: i) {
            notice = "Could not create config/boot/\(server.bootProfile)."
            runner.appendLine("!! " + notice)
            return
        }
        // The client was installed by HorizonXI and carries their logo in its own data. On any
        // other world, show the stock title screen instead. See Branding.swift.
        Branding.apply(stockBranding: Branding.wantsStockBranding(server), to: i)

        // Pre-game version check. The login server does this anyway and answers "The game's
        // data has been updated" — better to say so here, name the versions, and (for HorizonXI,
        // whose updates are public) fix it before launching.
        let installedVer = ClientVersion.installed(in: i)
        let requiredVer = feeds.requiredClients[server.name] ?? server.requiredClient
        if let have = installedVer, !requiredVer.isEmpty, ClientVersion.isOlder(have, than: requiredVer) {
            notice = "\(server.name) needs client \(requiredVer) or newer; this install is at "
                   + "\(have). Its login server will refuse with “The game's data has been updated”. "
                   + (server.name == "CatsEyeXI"
                      ? "Open Setup & Diagnostics › CatsEyeXI installer… to update it with their own launcher."
                      : "Update the client first.")
            runner.appendLine("!! " + notice)
            runner.appendLine("!! version check: \(server.name) requires \(requiredVer), installed \(have)")
            return
        }
        // HorizonXI publishes its updates, but being behind is not a reason to refuse Play:
        // HorizonXI's login server accepts this client as-is (verified daily), and the torrent
        // fetch can take an hour. Mention it and carry on; the update itself is a button
        // (Setup & Diagnostics › Update HorizonXI…) and runs only when nothing else is.
        if server.name == "HorizonXI",
           let hv = ClientVersion.horizonVersion(in: i), let latest = feeds.horizonLatest, hv != latest {
            runner.appendLine("i  HorizonXI \(latest) is published; this install is \(hv). "
                              + "You do not need to do anything: the login server accepts this "
                              + "client and the game plays normally. Only run Setup & Diagnostics "
                              + "\u{203A} Update HorizonXI\u{2026} if you are actually turned away.")
        }

        if !user.isEmpty, !pass.isEmpty {
            if !Credentials.apply(user: user, password: pass, to: i,
                                  profile: server.bootProfile, server: server.host) {
                notice = "Could not write config/boot/\(server.bootProfile) — launching with its existing account."
                runner.appendLine("!! " + notice)
            }
        }
        // A world may need a different renderer than the global preference (Gaia XI: DXVK kills
        // its client, OpenGL boots it). Applied here rather than by mutating the user's setting,
        // so switching worlds never silently rewrites what they chose.
        var effective = perf
        if !server.msync, effective.msync {
            effective.msync = false
            runner.appendLine("i  \(server.name) runs with msync off — its client exits about a "
                              + "second after login with it on.")
        }
        if let r = server.renderer, r != perf.renderer {
            effective.renderer = r
            runner.appendLine("i  \(server.name) is pinned to the \(r.title) renderer "
                              + "(your setting, \(perf.renderer.title), is left alone). "
                              + "Clear it in the server's settings to override.")
        }
        runner.launch(i, perf: effective, profile: server.bootProfile, useX87: server.x87,
                      world: server.name, addonPolicy: addonPolicy)
    }

    private func refresh() { Task { await refreshAsync() } }

    /// Point the launcher at a wrapper the scan cannot reach. Choosing it through a panel is
    /// also what grants access to a TCC-gated location such as Downloads, so this is the whole
    /// reason the scan itself does not need to go there.
    private func chooseInstall() {
        let panel = NSOpenPanel()
        panel.title = "Choose your HorizonXI wrapper"
        panel.message = "Pick the wrapper app that contains the game — usually siku.app."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let found = Install.installs(inWrapper: url)
        guard !found.isEmpty else {
            notice = "No HorizonXI install inside \(url.lastPathComponent)."
            return
        }
        for i in found where !installs.contains(where: { $0.id == i.id }) { installs.append(i) }
        selected = found.first
        selected?.remember()
        recheck()
    }

    private func refreshAsync() async {
        // Use the install we used last time straight away. Scanning /Volumes can take a long
        // time on a slow external drive — long enough that the launcher never became usable —
        // and there is no reason to make the user wait for a path we already know.
        if selected == nil, let remembered = Install.remembered() {
            selected = remembered
            installs = [remembered]
            await recheckAsync()
        }

        scanning = true
        let found = await Task.detached(priority: .userInitiated) { Install.discover() }.value
        scanning = false
        guard !found.isEmpty else { return }
        installs = found
        if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
            selected = found.first
        }
        selected?.remember()
        await recheckAsync()
    }

    private func recheck() { Task { await recheckAsync() } }

    private func recheckAsync() async {
        guard let i = active else { checks = []; return }
        let profile = store.selected?.bootProfile ?? "horizonxi.ini"
        checks = await Task.detached(priority: .userInitiated) { Preflight.run(i, profile: profile) }.value
    }

    /// Read whatever the profile actually says, not this app's last write — the boot .ini is
    /// a plain text file the user may well have edited by hand. Also the Revert button.
    private func loadGraphics() {
        // Prefer what the profile actually says; fall back to this world's stored value, not
        // to a value some other world last wrote.
        if let s = store.selected {
            graphics = GraphicsSettings.load(world: s.name)
            if let i = active, let onDisk = GraphicsSettings.read(from: i, profile: s.bootProfile) {
                graphics = onDisk
            }
        }
    }

    /// Rescan the world's game folder. No install means an empty list rather than a refusal:
    /// the screen explains an empty list for itself (see `emptyAddonReason`), and the button
    /// that silently did nothing was indistinguishable from a broken one.
    private func loadAddons() {
        guard let i = active else { addonItems = []; addonWarning = ""; return }
        addonItems = AddonSuite.scan(i)
        let bad = AddonSuite.mismatchedPlugins(i)
        addonWarning = bad.isEmpty ? "" :
            "Ashita refused these plugins on the last run because they are built for a different "
            + "interface version than this Ashita core: \(bad.joined(separator: ", ")). "
            + (bad.contains { $0.lowercased() == "addons" }
               ? "That includes the Lua host, so no addon below can run until it is fixed."
               : "")
    }

    private func color(_ s: Check.State) -> Color {
        switch s {
        case .ok: return Vana.jade
        case .warn: return Vana.sand
        case .bad: return Vana.ember
        }
    }
}
