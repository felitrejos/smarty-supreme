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
| `Apps/FlickHost/` | Mac host (macOS 15+). For now a lobby showing each paired phone's round trip, clock offset, pointer rate, position and swings |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |
| `Design/flick-pong-table.html` | 3D table and camera study the renderer follows |

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
