# Flick Pong

An iPhone is the paddle, a Mac is the table. Tilt the phone to move your paddle and swing it toward the screen to hit. The spec lives in Claude Docs: Flick Pong MVP Spec.

## Layout

| Path | What it is |
| --- | --- |
| `FlickCore/` | Swift package with all hardware-free logic: swing detection and paddle mapping, the binary protocol and links, the 240 Hz game engine, the computer opponent, the match session (lobby, pauses, reconnects), the second-Mac viewer, and the referee's commentary. `FlickTestSupport` holds the fakes (`ManualClock`, `LoopbackNetwork`). `FixtureTools` and the `flick-fixtures` command check and split the motion dataset. |
| `Apps/FlickHost/` | Mac app (macOS 26+): the 3D table, keyboard input, sound, the voice referee, and the iPhone Paddles window. It can also act as Player B's screen for another Mac. |
| `Apps/FlickPaddle/` | iPhone paddle (iOS 18+): pairs with the Mac, calibrates, sends tilt at 60 Hz and swings as they happen, and plays haptics |
| `Apps/FlickRecorder/` | iPhone app that records labelled motion data for the swing detector |
| `Apps/Shared/` | Core Motion wrapper shared by the iPhone apps |
| `Apps/Link/` | MultipeerConnectivity transport shared by the paddle and the Mac |
| `Apps/Style/` | Player names and colours shared by the paddle and the Mac |
| `Assets/Lighting/` | Studio HDRI from Poly Haven (CC0) used to light the table |
| `Assets/Sounds/` | Paddle, table and crowd sounds cut from CC0 Freesound recordings; sources in [CREDITS.md](Assets/Sounds/CREDITS.md) |
| `Fixtures/` | Recorded motion data, once recorded: `recordings/` as exported, then `tuning/` (70%) and `holdout/` (30%) |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |

Design decisions and their references are in [DESIGN.md](DESIGN.md).

## Build and run

```bash
brew install xcodegen
```

```bash
xcodegen generate && open FlickPong.xcodeproj
```

Run the FlickHost scheme on "My Mac" and the FlickPaddle scheme on an iPhone. The signing team is set once in `project.yml` (`DEVELOPMENT_TEAM`); change it there to build with another account.

For a first run on an iPhone: sign in to Xcode with your Apple ID, connect the phone, turn on Developer Mode (Settings › Privacy & Security), and with a free account trust yourself under Settings › General › VPN & Device Management. Allow Local Network access on the phone and the Mac when asked.

## Tests

```bash
swift test --package-path FlickCore
```

Two benchmarks only run in an optimized build. The AI balance benchmark plays 1,000 games per difficulty against a scripted average player. The soak test plays 30 simulated minutes of two phones and Player B's screen over a lossy link, dropping a phone, pausing and losing the screen along the way, and checks every recovery, every result and memory growth under 5 MB:

```bash
swift test --package-path FlickCore -c release --filter "AIBalanceBenchmarkTests|SoakTests"
```

## Playing

FlickHost opens on the table against the computer. File › New Game… (⌘N) picks the opponent (the computer or another player) and the computer's difficulty; the choice is kept for the next launch.

On the iPhone, hold it upright pointing at the screen and tap Calibrate. Tilt about 30° either way to cross the table (12°, 20° and 30° are offered), and swing toward the screen to hit. The phone buzzes on a hit (harder for harder swings), a miss, a point and the win. Without a phone, Player A uses A and D to move and W to swing, and a keyboard Player B uses ← → and ↑. Holding a direction while swinging aims the return.

Esc pauses, ⌘1–3 switch between Player A's end, Player B's end and the side view, ⌘0 opens the iPhone Paddles window, and Help › Controls shows the controls again.

### Two players

Choose File › New Game… › Another Player. Each iPhone that joins takes the next free side and shows its side and colour. Calibrate each phone and tap Ready on it; the match starts 3 seconds after both are ready. A round trip above 40 ms gets a warning, and above 100 ms a phone can't be counted as ready. Game › Swap Sides swaps the phones before the start; Start Now starts at once, with the keyboard playing any side without a phone.

With one Mac the camera switches to the side view. To give Player B their own end view, open Flick Pong on a second Mac on the same Wi‑Fi, choose File › Use as Player B's Screen, and put the Macs back to back.

During a match:

- A phone that drops out pauses the game and its player has 30 s to reconnect before they forfeit. With both gone, whoever left first forfeits first. A waiting phone can take the empty side once the Mac allows it.
- A player can pause from their phone; only that phone or the Mac can resume.
- A swing that tips the phone back keeps the paddle in place; if the phone stays tilted for 0.75 s it asks to be held upright. A paddle dims when its phone stops sending tilt for a quarter of a second, and the game pauses after 2 s.
- Three serve timeouts in a row from one player pause the game and ask if they are still playing.
- If Player B's screen disconnects, the game pauses until it comes back, or until both players tap Continue to play on with the side view.
- The game pauses while the Mac sleeps, its screen is locked, Flick Pong is in the background or the New Game sheet is open, and resumes when you come back.

On an iPhone without motion sensors (the simulator), drag along the bar to move and swipe up to swing.

### Referee

The Mac calls the score out loud: one line per point, plus a highlight for a rally of 10, a smash winner, deuce or match point. Against the computer, the computer answers back in its own voice now and then: a taunt after a smash, a groan after a lucky edge, nerves at match point. Game › Commentary turns both off. They use the Mac's system voices; for the best sound, download Premium English voices in System Settings › Accessibility › Spoken Content.

## Recording the motion dataset

1. Run FlickRecorder on an iPhone. Pick the participant and the activity, then tap Start recording.
2. For swings, keep your thumb anywhere on the screen during each swing and lift it after. Every press is one labelled swing. For everything else, just do the activity until the timer passes the target.
3. Export with the share button (AirDrop to the Mac), or copy the files from the iPhone in Finder. Put them in `Fixtures/recordings/`.
4. Check progress against the targets: 17 swings per participant, stroke and strength (306 in total), 3 minutes of each non-swing activity, and 3 minutes holding still.

```bash
swift run --package-path FlickCore flick-fixtures summary Fixtures/recordings
```

5. When the summary says complete, split once. Every recording is cut at 70% of its length, moved to the nearest gap between swings. After the split, `swift test` also runs the sensing benchmarks on `Fixtures/holdout` (swing recall and precision, detection delay and paddle jitter); until then they show as skipped.

```bash
swift run --package-path FlickCore flick-fixtures split Fixtures/recordings Fixtures
```

## Measuring on real devices

| Target | Where to read it |
| --- | --- |
| Pairing in 5 s or less | The phone shows how long it took to pair after opening |
| Round trip p95 at most 15 ms, tilt updates at least 55 a second | The iPhone Paddles window (⌘0), each with a pass or fail mark |
| 99% of frames under 8.3 ms, none dropped over 60 s | View › Show Frame Times (⌥⌘F), with a Release build in front on a 120 Hz display |
| Player B's screen within 15 ms of the host (95%) | Show Frame Times on the second Mac |
| Swing to the game p95, Mac CPU at most 20% of a core, memory growth under 5 MB | Show Frame Times; values over budget turn orange |
| iPhone CPU at most 15%, battery at most 8% per 30 min | The footer of the paddle app; battery shows while unplugged |
| Commentary within 1.5 s of the play (95%) | Show Frame Times, once the referee has spoken |
| Engine step p99 under 0.1 ms | `EngineBenchmarkTests`, part of the test run |
