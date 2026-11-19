# Development

How Smarty Supreme is put together, built and tested. Design decisions and their references are in [DESIGN.md](../DESIGN.md); ball physics, rules and the phone-as-bat model are in [PHYSICS.md](PHYSICS.md). The spec lives in Claude Docs.

## Layout

| Path | What it is |
| --- | --- |
| `SmartyCore/` | Swift package with all hardware-free logic: swing detection and paddle mapping, the binary protocol and links, the 240 Hz game engine, the computer opponent, the match session (lobby, pauses, reconnects), the second-Mac viewer, and the referee's commentary. `SmartyTestSupport` holds the fakes (`ManualClock`, `LoopbackNetwork`). `FixtureTools` and the `smarty-fixtures` command check and split the motion dataset. |
| `Apps/SmartyHost/` | Mac app (macOS 26+), shipped as Smarty Supreme: the 3D arena, keyboard input, sound, the voices, and the iPhone Paddles window. It can also act as Player B's screen for another Mac. |
| `Apps/SmartyPaddle/` | iPhone paddle (iOS 18+), shipped as Smarty Paddle: pairs with the Mac, calibrates, streams the bat's orientation and blade speed at 100 Hz, and plays haptics |
| `Apps/SmartyRecorder/` | iPhone app that records labelled motion data for the swing detector |
| `Apps/Shared/` | Core Motion wrapper shared by the iPhone apps |
| `Apps/Link/` | MultipeerConnectivity transport shared by the paddle and the Mac |
| `Apps/Style/` | Player names and colours shared by the paddle and the Mac |
| `Assets/Lighting/`, `Assets/Models/`, `Assets/Textures/` | The arena photo, chair model and wood textures from Poly Haven (CC0); credits in [CREDITS.md](../Assets/Lighting/CREDITS.md) |
| `Assets/Crowd/` | Spectator cards rendered from CC0 MakeHuman people |
| `Assets/Voice/` | Every umpire call and computer line, rendered with Kokoro |
| `Assets/Sounds/` | Paddle, table and crowd sounds cut from CC0 Freesound recordings; sources in [CREDITS.md](../Assets/Sounds/CREDITS.md) |
| `Tools/` | `render_voice.py` (re-render the voices), `glb_to_usdz.py` and `render_crowd_sprites.swift` (turn a GLB model into crowd cards) |
| `Fixtures/` | Recorded motion data, once recorded: `recordings/` as exported, then `tuning/` (70%) and `holdout/` (30%) |
| `docs/brand/` | Title card, header, app icon and lockups (SVG and PNG), with the font licences |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |

## Build and run

```bash
brew install xcodegen
```

```bash
xcodegen generate && open SmartySupreme.xcodeproj
```

Run the SmartyHost scheme on "My Mac" and the SmartyPaddle scheme on an iPhone. The signing team is set once in `project.yml` (`DEVELOPMENT_TEAM`); change it there to build with another account.

For a first run on an iPhone: sign in to Xcode with your Apple ID, connect the phone, turn on Developer Mode (Settings › Privacy & Security), and with a free account trust yourself under Settings › General › VPN & Device Management. Allow Local Network access on the phone and the Mac when asked.

## Tests

```bash
swift test --package-path SmartyCore
```

Two benchmarks only run in an optimized build: the AI balance benchmark (1,000 games per difficulty against a scripted player) and a 30-minute soak test of two phones and Player B's screen over a lossy link.

```bash
swift test --package-path SmartyCore -c release --filter "AIBalanceBenchmarkTests|SoakTests"
```

## Voices

The umpire and the computer are recordings made with the open Kokoro model. To change a voice or a line, edit `Umpire.swift` or `OpponentLine.swift`, then re-render:

```bash
swift run --package-path SmartyCore smarty-voice-lines > lines.json
```

```bash
python Tools/render_voice.py lines.json Assets/Voice
```

## Recording the motion dataset

1. Run SmartyRecorder on an iPhone. Pick the participant and the activity, then tap Start recording.
2. For swings, keep your thumb anywhere on the screen during each swing and lift it after. Every press is one labelled swing. For everything else, just do the activity until the timer passes the target.
3. Export with the share button (AirDrop to the Mac), or copy the files from the iPhone in Finder. Put them in `Fixtures/recordings/`.
4. Check progress against the targets: 17 swings per participant, stroke and strength (306 in total), 3 minutes of each non-swing activity, and 3 minutes holding still.

```bash
swift run --package-path SmartyCore smarty-fixtures summary Fixtures/recordings
```

5. When the summary says complete, split once. Every recording is cut at 70% of its length, moved to the nearest gap between swings. After the split, `swift test` also runs the sensing benchmarks on `Fixtures/holdout`; until then they show as skipped.

```bash
swift run --package-path SmartyCore smarty-fixtures split Fixtures/recordings Fixtures
```
