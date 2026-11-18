# Flick Pong

An iPhone is the paddle, a Mac is the table. The spec lives in Claude Docs: Flick Pong MVP Spec.

## Layout

| Path | What it is |
| --- | --- |
| `FlickCore/` | Swift package with all hardware-free logic. `FlickTestSupport` holds the fakes (`ManualClock`, `LoopbackNetwork`). `FixtureTools` and the `flick-fixtures` command check and split the sensor dataset. |
| `Apps/FlickPaddle/` | iPhone paddle (iOS 18+): finds the Mac, pairs, calibrates, and sends tilt at 60 Hz and swings as they happen |
| `Apps/Shared/` | Core Motion wrapper shared by the iPhone apps |
| `Apps/Link/` | MultipeerConnectivity transport shared by the paddle and the Mac |
| `Apps/FlickRecorder/` | iPhone app that records labelled motion data for the swing detector |
| `Fixtures/` | Recorded motion data: `recordings/` as exported, then `tuning/` (70%) and `holdout/` (30%) |
| `Apps/FlickHost/` | Mac host (macOS 15+): the 3D table with a two-player keyboard game, and an iPhone Paddles window showing each paired phone's round trip, tilt updates, calibration and swings |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |
| `Design/flick-pong-table.html` | First 3D table and camera study |
| `Assets/Lighting/` | Studio HDRI from Poly Haven (CC0) used to light the table |

## Run

```bash
swift test --package-path FlickCore
```

```bash
brew install xcodegen
```

```bash
xcodegen generate && open FlickPong.xcodeproj
```

To run on a real iPhone, pick your team under Signing & Capabilities for the app.

## Recording the motion dataset

1. Run FlickRecorder on an iPhone. Pick the participant and the activity, then tap Start recording.
2. For swings, keep your thumb anywhere on the screen during each swing and lift it after. Every press is one labelled swing. For everything else, just do the activity until the timer passes the target.
3. Export with the share button (AirDrop to the Mac), or copy the files from the iPhone in Finder. Put them in `Fixtures/recordings/`.
4. Check progress against the targets: 17 swings per participant, stroke and strength (306 in total), 3 minutes of each non-swing activity, and 3 minutes holding still.

```bash
swift run --package-path FlickCore flick-fixtures summary Fixtures/recordings
```

5. When the summary says complete, split once. After the split, `swift test` also runs the sensing benchmarks on `Fixtures/holdout`: swing recall and precision, detection delay and paddle jitter. Until then they show as skipped. Every recording is cut at 70% of its length, moved to the nearest gap between swings.

```bash
swift run --package-path FlickCore flick-fixtures split Fixtures/recordings Fixtures
```

## Checking the link on real devices (M3)

1. Run FlickHost on the Mac and FlickPaddle on one or two iPhones on the same Wi-Fi. Allow Local Network access on both when asked.
2. The phone shows how long it took to pair after opening (target: 5 s or less).
3. Calibrate the phone and leave it running for 10 minutes. The Mac's lobby shows the round trip p95 (target: 15 ms or less) and the pointer rate (target: at least 55 per second), each with a pass or fail mark.

## Playing (M4, M5)

FlickHost opens on the table against the computer. File › New Game… (⌘N) picks the opponent, the computer or a second player on this keyboard, and the computer's difficulty. The choice is kept for the next launch.

Player A is the first iPhone that joins, once it is calibrated: tilt it to move, swing it toward the screen to hit. It buzzes on a hit, a miss, a point and the win. If that phone drops out mid-game, the game pauses. Without a phone, Player A uses A and D to move and W to swing. A keyboard Player B uses ← and → to move and ↑ to swing. Holding a direction while swinging aims the return. Esc pauses, ⌘1–3 switch between Player A's end, Player B's end and the side view, ⌘0 opens the iPhone Paddles window, and Help › Controls shows the controls again.

The AI balance benchmark plays 1,000 games per difficulty against a scripted average player. It only runs in an optimized build:

```bash
swift test --package-path FlickCore -c release --filter AIBalanceBenchmarkTests
```

The engine benchmark runs with the tests (`EngineBenchmarkTests`, p99 under 0.1 ms per step). The render target (99% of frames under 8.3 ms, none dropped over 60 s) needs a Release build, the window in front and a 120 Hz display; View › Show Frame Times (⌥⌘F) shows the last 60 s.

Design decisions and their references are in [DESIGN.md](DESIGN.md).
