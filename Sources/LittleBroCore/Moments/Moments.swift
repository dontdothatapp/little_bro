import Foundation

/// Things Little Bro reacts to when you open a certain kind of app or site.
public enum Moment: String, CaseIterable, Codable, Sendable {
    /// Spotify (app or web): headphones on, vibing to the beat.
    case music
    /// Terminals, editors, IDEs, dev tools: Hackerman.
    case hacker
    /// Game stores, launchers and games: paddles.
    case gaming

    public var title: String {
        switch self {
        case .music: "Spotify"
        case .hacker: "Hackerman (terminals & IDEs)"
        case .gaming: "Gaming"
        }
    }
}

/// Which apps and sites trigger which moment.
public enum MomentCatalog {
    /// Exact bundle identifiers.
    static let apps: [String: Moment] = {
        var m: [String: Moment] = ["com.spotify.client": .music]
        for id in [
            // Terminals
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
            "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
            "com.github.wez.wezterm", "co.zeit.hyper", "com.raphaelamorim.rio", "com.termius-dmg.mac",
            // Editors & IDEs
            "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders", "com.vscodium", "com.sublimetext.4", "com.sublimetext.3",
            "dev.zed.Zed", "dev.zed.Zed-Preview", "com.panic.Nova", "com.google.android.studio",
            "com.exafunction.windsurf", "com.barebones.bbedit", "org.vim.MacVim", "org.gnu.Emacs",
            "com.neovide.neovide", "com.trae.app",
            // Dev tools
            "com.github.GitHubClient", "com.fork.Fork", "com.fournova.Tower3", "com.torusknot.SourceTreeNotMAS",
            "com.postmanlabs.mac", "com.insomnia.app", "com.tinyapp.TablePlus", "com.docker.docker",
            "com.apple.Instruments", "com.apple.iphonesimulator", "com.kapeli.dashdoc",
        ] { m[id] = .hacker }
        for id in [
            "com.valvesoftware.steam", "com.gog.galaxy", "com.epicgames.EpicGamesLauncher", "io.itch.mac",
            "net.battle.app", "net.battle.bootstrapper", "com.blizzard.bootstrapper", "com.ea.ea-desktop",
            "com.ubisoft.UbisoftConnect", "com.ubisoft.uplay", "com.heroicgameslauncher.hgl",
            "org.openemu.OpenEmu", "com.mojang.minecraftlauncher", "com.nvidia.gfnpc.mall",
            "com.playstation.RemotePlay", "com.amazon.luna", "org.prismlauncher.PrismLauncher",
            "com.codeweavers.CrossOver", "com.isaacmarovitz.Whisky",
        ] { m[id] = .gaming }
        return m
    }()

    /// Bundle-identifier prefixes (whole families of apps).
    static let prefixes: [(String, Moment)] = [
        ("com.jetbrains.", .hacker),
        ("com.google.android.studio", .hacker),
    ]

    /// Sites, matched against "host/path" (host without "www.").
    static let sites: [(String, Moment)] = [
        ("open.spotify.com", .music),
        ("store.steampowered.com", .gaming), ("steamcommunity.com", .gaming), ("steamdb.info", .gaming),
        ("gog.com", .gaming), ("store.epicgames.com", .gaming), ("epicgames.com/store", .gaming),
        ("itch.io", .gaming), ("xbox.com/play", .gaming), ("xbox.com/en-us/play", .gaming),
        ("humblebundle.com", .gaming), ("store.playstation.com", .gaming), ("nintendo.com/store", .gaming),
        ("isthereanydeal.com", .gaming), ("protondb.com", .gaming),
    ]

    public static func moment(bundleId: String?, bundlePath: String? = nil, category: String? = nil) -> Moment? {
        if let id = bundleId {
            if let m = apps[id] { return m }
            for (p, m) in prefixes where id.hasPrefix(p) { return m }
        }
        if let c = category?.lowercased(), c.contains("games") { return .gaming }
        if let path = bundlePath?.lowercased(), path.contains("/steamapps/common/") { return .gaming }
        return nil
    }

    public static func moment(url: String) -> Moment? {
        guard let comps = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              var host = comps.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let full = host + comps.path.lowercased()
        for (site, m) in sites {
            if full == site || full.hasPrefix(site + "/") || host == site || host.hasSuffix("." + site) { return m }
            if site.contains("/") && full.hasPrefix(site) { return m }
        }
        return nil
    }
}

/// How often each moment may play.
public enum MomentFrequency: String, CaseIterable, Codable, Sendable {
    case everyTime
    case everyThreeHours

    public var interval: TimeInterval {
        switch self {
        case .everyTime: 0
        case .everyThreeHours: 3 * 3600
        }
    }

    public var title: String {
        switch self {
        case .everyTime: "Every time"
        case .everyThreeHours: "At most every 3 hours"
        }
    }
}

/// Remembers when each moment last played and decides whether it may play again.
public struct MomentGate: Codable, Sendable {
    public var frequency: MomentFrequency = .everyThreeHours
    public private(set) var lastPlayed: [Moment: Date] = [:]

    public init(frequency: MomentFrequency = .everyThreeHours) {
        self.frequency = frequency
    }

    public func allows(_ m: Moment, now: Date) -> Bool {
        guard let last = lastPlayed[m] else { return true }
        return now.timeIntervalSince(last) >= frequency.interval
    }

    public mutating func record(_ m: Moment, at date: Date) {
        lastPlayed[m] = date
    }
}
