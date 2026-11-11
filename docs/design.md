# Little Bro — design (v0.1)

A tiny companion that lives at the top-centre of the Mac screen ("around the notch",
also on Macs without one). The character is a pair of white eyes on a black,
liquid-feeling shape that grows out of the top edge of the screen.

## What it does now

1. **Claude Code (desktop app) sessions.** When a session finishes a turn, or is waiting
   on you (permission prompt, a question, a plan to approve), Little Bro drops down,
   plays a "done" or "needs you" animation, shows the session title and stays ~10 s.
   Click → opens that exact session in the Claude desktop app. If the session is still
   unseen, it comes back every 60 s until you have looked at it.
2. **Idle visits.** When the cursor has been still, Little Bro picks a random moment
   within the next 5 minutes to pop by (look around, doze off, say hi, tilt its head,
   peek in shyly). Moving the cursor while it is out startles it back into hiding.
3. **YouTube peeks.** While a YouTube video plays, every few minutes a smaller pair of
   eyes peeks down at the video for a few seconds.

4. **App moments.** Opening (switching to) certain apps or sites plays a short moment,
   at most once per 3 hours per category by default ("every time" for testing):
   - Spotify (app or web) → **vibe**: headphones, blissful closed eyes, bobbing and swaying
     to the real tempo (Core Audio process tap on Spotify's audio → spectral-flux onsets →
     autocorrelation tempo + bass-weighted beat phase → a phase-locked `BeatClock`). Waits up
     to a minute for music to start. No permission → a standard 112 BPM groove.
   - Terminals, editors, IDEs, dev tools → **Hackerman**, alternating between *shades*
     (pixel shades + a terminal typing a random "hack" and a progress bar) and *rain*
     (green code rain behind focused, green-tinted eyes).
   - Game stores, launchers, games (bundle ids, `public.app-category.*games`, Steam's
     `steamapps/common`) and store sites → **paddle ball**: the eyes become paddles and play
     one real, randomly-decided point (`PaddleRally`); the all-time score persists and pops
     when it changes.
   Claude cards always take priority; a moment that can't show within 15 s is dropped.

## Decisions (made autonomously while the owner was away)

| Area | Decision | Why |
|---|---|---|
| Platform | Native Swift, AppKit + Core Animation, SwiftPM package, macOS 14+ | Best possible smoothness; no web views. |
| Rendering | Every frame is driven by a `CADisplayLink`; all motion comes from closed-form damped springs (exact and stable at any frame time). Paths are rebuilt per frame and pushed into `CAShapeLayer`s with implicit animations disabled. | Liquid, interruptible motion: any animation can be retargeted mid-flight without a snap. |
| Look | Pure black shape (`#000`) with concave "ears" where it meets the top edge, soft bottom corners and a slight droplet bulge while moving. Eyes are white rounded rectangles with a soft glow; expressions come from lid cuts and a "happy" crescent cut (CGPath boolean ops). Colour only for "needs you" (warm Claude-ish orange glow + status text). | "Mostly black and white, colours sometimes." |
| Text | Session title + one status line next to the eyes; hovering reveals Claude's end-of-turn recap. | The eyes carry the emotion; text says *which* session. |
| Claude signal | Claude Code hooks in `~/.claude/settings.json` (confirmed to fire for desktop-app sessions) call a tiny shell script that drops the hook JSON into `~/Library/Application Support/LittleBro/inbox`. The app watches that folder. | Documented, fast, never blocks Claude. Works even if Little Bro isn't running. |
| "Seen" detection | The desktop app's own per-session files (`~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`) give title, recap, `lastFocusedAt`, and map hook session ids to desktop ids. A session counts as seen when you focus it, reply to it, click Little Bro, or when Claude is frontmost showing it. | Undocumented files — treated as best-effort enrichment; hooks remain the source of truth. |
| Open session | `claude://code/continue?session=local_<id>` (found in the desktop app bundle), falling back to activating Claude. | Lands exactly on the session. |
| Needs-input debounce | A "needs you" state must persist 1.2 s before it shows. | Auto-approved permissions shouldn't flash. |
| Reminders | Shown ≤ every 60 s while unseen; paused while you're away (no input for 5 min), the screen is locked or asleep; shown right away when you come back. | Avoid animating to an empty room. |
| YouTube detection | Cheap check first: a browser process holding a "prevent display sleep" power assertion (= video playing). Then confirm the URL via AppleScript (Chrome-family + Safari). If AppleScript is refused, any browser video counts. | No Screen Recording / Accessibility permissions needed. |
| Priority | needs-you > done > YouTube peek > idle visit. Higher priority morphs the current shape instead of hiding first. | Fluidity. |
| Menu bar | Small eyes icon: pending sessions, preview every animation, pause 1 h, toggles, launch at login, install/remove Claude hooks, quit. | A way to control and preview. |
| Hook install | Opt-in: on first launch a "connect me to Claude Code" card appears; clicking it merges Little Bro's hooks into existing ones (never touching others) and backs the original up once to `settings.json.before-littlebro`. Removable from the menu. | Little Bro never edits Claude's global config without an explicit click. |
| Launch at login | Off by default; a menu toggle. | It's a persistent system change, so it's the owner's call. |
| Signing | Ad-hoc by default; `LITTLEBRO_SIGN_IDENTITY` to sign with a real identity. | Signing with a keychain identity needs a one-time keychain prompt. |

## Decisions for app moments (made with the owner)

| Area | Decision |
|---|---|
| Frequency | Per category, at most once every 3 hours (no daily cap); a menu setting switches to "every time". |
| Spotify look | Black-and-white headphones, no floating notes. |
| Hackerman | Both directions, taking turns. |
| Gaming | Paddles playing a real point; score kept forever (resettable from the menu); previews don't count. |
| Sizes | Cards and idle visits 40 pt tall, the YouTube peek 25 pt. |
| Rendering | Acts add `Overlay`s (headphones, shades/terminal, code rain, court) that draw extra shapes and text into the scene on three planes (behind the eyes, in front, over the body), each fading with its own presence spring. |

## Non-goals (v0.1)

Codex or other agents; Claude Code in the terminal; sound; settings window; notarised
distribution.

## Layout of the code

- `Sources/LittleBroCore` — pure logic + geometry: springs, expressions, character
  model, choreography (`Director`), scene → bitmap renderer, hook event parsing,
  attention tracking, idle/peek planners, hook installer. Unit-tested.
- `Sources/LittleBro` — the app: notch panel, display-link view, layer renderer,
  Claude bridge, activity + video watchers, status menu.
- `Sources/LittleBroRender` — offline renderer: plays any act frame-by-frame into PNGs,
  contact sheets and MP4s, used to inspect the animation.
