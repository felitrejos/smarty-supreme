# Flick Pong

An iPhone is the paddle, a Mac is the table. The spec lives in Claude Docs: Flick Pong MVP Spec.

## Layout

| Path | What it is |
| --- | --- |
| `FlickCore/` | Swift package with all hardware-free logic. `FlickTestSupport` holds the fakes (`ManualClock`, `LoopbackNetwork`). |
| `Apps/FlickPaddle/` | iPhone app (iOS 18+) |
| `Apps/FlickHost/` | Mac app (macOS 15+) |
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

To run on a real iPhone, pick your team under Signing & Capabilities for FlickPaddle.
