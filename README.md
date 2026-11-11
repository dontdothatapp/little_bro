# Little Bro

A tiny companion that lives at the top-centre of your Mac's screen — around the
notch, or where a notch would be. It's a pair of white eyes on a black, liquid shape
that grows out of the top edge of the screen.

What it does today:

- **Claude Code (desktop app).** When a session finishes or is waiting on you
  (permission, a question, a plan to approve), Little Bro drops down with a "done" or
  "needs you" animation and the session's title, for about 10 seconds. Click it to jump
  straight into that session. Hover to read Claude's recap. While a session stays
  unseen it comes back every minute (not while you're away from the computer).
- **Idle visits.** When your cursor has been still for a while, it pops by at a random
  moment within 5 minutes: looks around, dozes off, says hi, tilts its head or peeks in
  shyly. Move the cursor while it's out and it startles back into hiding.
- **YouTube peeks.** While you watch a YouTube video, small eyes peek down at it for a
  few seconds every few minutes.
- **App moments** (at most once every 3 hours each, or every time — see the menu):
  - **Spotify** (app or open.spotify.com): headphones on, eyes closed, head-bobbing to the
    song's real tempo. Little Bro listens to Spotify's audio *only* to find the beat — the
    first time, macOS asks for permission; if you say no, it grooves at a standard tempo.
  - **Terminals, editors and IDEs** (Terminal, iTerm2, Warp, Ghostty, Xcode, Cursor, VS Code,
    Sublime Text, Zed, JetBrains…): Hackerman — either pixel shades and a terminal that
    "hacks the mainframe", or green code rain with focused eyes. They take turns.
  - **Games** (Steam, GOG, Epic, itch, Battle.net…, store sites like SteamDB, and games
    themselves): the eyes become paddles and play one real point of paddle ball. The
    all-time score is kept, so you can root for a side.

## Run it

Requires macOS 14.2+ and Xcode (Swift 6).

```bash
./scripts/install.sh
```

That builds `build/Little Bro.app`, copies it to `~/Applications` and starts it. The
eyes icon in the menu bar has everything else: previews of every animation, toggles,
pause, launch at login, quit.

On first launch Little Bro shows a card asking to **connect to Claude Code**. Clicking
it adds Little Bro's hook to `~/.claude/settings.json` (your existing hooks are kept, and
the original file is backed up once as `settings.json.before-littlebro`). Nothing is
changed until you click. You can disconnect from the menu at any time. Sessions started
before connecting may need a restart before their hooks fire.

The first time it needs to, macOS asks whether Little Bro may control your browser —
that's only used to read the front tab's address (to notice YouTube, Spotify and game
stores). If you say no, any video playing in a browser counts as "watching", and web
pages don't trigger moments.

### Handy for testing

```bash
open "littlebro://play/done"        # also: done-reminder, needs, needs-reminder, peek, vibe,
                                    # hacker-shades, hacker-rain, game, idle-lookAround,
                                    # idle-sleepy, idle-hello, idle-curious, idle-shy
open "littlebro://debug/snapshot"   # writes the current frame to ~/Library/Application Support/LittleBro
```

Logs (including frame-pacing stats after every appearance) go to `~/Library/Logs/LittleBro.log`.

## Develop

```bash
swift test                                   # springs, smoothness, Claude events, hooks, planners
swift run -c release littlebro-render done --mp4 --out previews-out
swift run -c release littlebro-render all --mp4 --out previews-out
```

`littlebro-render` plays any animation frame-by-frame through the same scene code the
app uses and writes PNG frames, a contact sheet and an MP4 (needs `ffmpeg`). Options:
`--hover 3-6` (simulate hovering), `--move 2` (move the cursor at 2 s),
`--then needs@2` (interrupt with another act), `--backdrop light|dark|video`, `--fps 120`.
Rendered previews of every animation are in [`previews/`](previews/).

By default the app is signed ad-hoc. To keep macOS permissions across rebuilds, sign with
your own identity (macOS asks once for keychain access):

```bash
LITTLEBRO_SIGN_IDENTITY="Apple Development" ./scripts/install.sh
```

## How it's built

See [docs/design.md](docs/design.md). In short: native Swift (AppKit + Core
Animation). Every moving quantity is a closed-form damped spring stepped on the
display's vsync, so animations can be interrupted and retargeted at any moment without
a snap. Choreography is a set of timed cues per act (`Sources/LittleBroCore/Director`).
