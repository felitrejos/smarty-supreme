# Development

How Smarty Supreme is put together, built and tested. Design decisions and their references are in [DESIGN.md](DESIGN.md); ball physics, rules and the phone-as-bat model are in [PHYSICS.md](PHYSICS.md). The spec lives in Claude Docs.

## Layout

| Path | What it is |
| --- | --- |
| `SmartyCore/` | Swift package with all hardware-free logic: the 240 Hz ball physics and rules, racket tracking and swing detection, the binary protocol and links, the computer opponent, the match session (lobby, pauses, reconnects), the second-Mac viewer, and the referee's commentary. `SmartyTestSupport` holds the fakes (`ManualClock`, `LoopbackNetwork`). |
| `Apps/SmartyHost/` | Mac app (macOS 26+), shipped as Smarty Supreme: the 3D arena, keyboard input, sound, the voices, the in-window settings and How to Play card, and the iPhone Paddles window. It can also act as Player B's screen for another Mac. |
| `Apps/SmartyPaddle/` | iPhone paddle (iOS 18+), shipped as Smarty Paddle: pairs with the Mac, calibrates, streams the bat's orientation, rotation rate and velocity at 100 Hz, sends the serve toss, and plays haptics |
| `Apps/Shared/` | Core Motion wrapper shared by the iPhone apps |
| `Apps/Link/` | MultipeerConnectivity transport shared by the paddle and the Mac |
| `Apps/Style/` | Player names and colours shared by the paddle and the Mac |
| `Apps/Icon/` | The Icon Composer app icon used by both apps |
| `Assets/Lighting/`, `Assets/Models/`, `Assets/Textures/` | The arena photo, chair model and wood textures from Poly Haven (CC0); credits in [CREDITS.md](../Assets/Lighting/CREDITS.md) |
| `Assets/Crowd/` | Spectator cards rendered from CC0 MakeHuman people |
| `Assets/Voice/` | Every umpire call and computer line, rendered with Kokoro |
| `Assets/Sounds/` | Paddle, table and crowd sounds cut from CC0 Freesound recordings; sources in [CREDITS.md](../Assets/Sounds/CREDITS.md) |
| `Tools/` | `render_voice.py` (re-render the voices), `glb_to_usdz.py` and `render_crowd_sprites.swift` (turn a GLB model into crowd cards) |
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

## Playing

Against the computer the match starts at once. Player A plays on the keyboard until an iPhone joins and calibrates. With two players the match starts 3 seconds after both phones are calibrated and ready, or on Start Now, where a side without a phone gets the keyboard.

| Input | Controls |
| --- | --- |
| iPhone | Swing it like a bat. Tap the screen to toss a serve, double-tap to recalibrate, Pause on its screen to pause. |
| Keyboard, Player A | W swings and serves, A/D aim |
| Keyboard, Player B | ↑ swings and serves, ← → aim |

The gear button in the game window opens the settings: New Game (⌘N), Pause (Esc), the camera for two players (A's end ⌘1, B's end ⌘2, split screen ⌘3), commentary, How to Play, the keyboard controls hint, Player B's Screen and frame times (⌥⌘F). The same items are in the menu bar. ⌘0 opens the iPhone Paddles window.

## Tests

```bash
swift test --package-path SmartyCore
```

Two benchmarks only run in an optimized build: the AI balance benchmark (1,000 games per difficulty against a scripted player) and a soak test of 30 simulated minutes with two phones and Player B's screen over a lossy link.

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
