# Flick Pong design

The Mac is a window onto one object: the table. Everything else stays out of the way, the way Apple's Chess app treats its board.

## Decisions and where they come from

| Decision | Reference | What was taken |
| --- | --- | --- |
| The table alone in the window, floating in a charcoal space lighter behind it and darker at the edges | Apple Chess (macOS), studied on this Mac | No floor or horizon; a soft vertical gradient backdrop; the object fills the frame from an elevated three-quarter view |
| Game state in the window title ("Flick Pong – Player A to serve") | Apple Chess window title ("White to Move") | Status lives in the title bar, not in an on-screen banner |
| Actions in the menu bar: New Game ⌘N, Pause Esc, cameras ⌘1–3, iPhone Paddles ⌘0, Show Frame Times ⌥⌘F | Apple Chess Game / View / Moves menus | Nothing on screen that a menu can hold |
| One Liquid Glass scoreboard; controls hint only at the start of a game and while paused | Apple's Liquid Glass material (macOS 26), with a regular material on macOS 15–25 | One floating control surface, system material, system font with rounded tabular figures |
| Player colour shown only as the paddle's rubber colour (blue for A, red for B) | Real table tennis rubbers | Colour carries meaning once: which paddle is whose |
| Studio lighting from an HDRI with one soft key light for shadows | Poly Haven `studio_small_09` (CC0), in `Assets/Lighting` | Soft softbox reflections on aluminium, rubber and the table's clear coat |
| Sculptural curved base under the table | "ping pong" by alixor22 on Sketchfab (CC BY 4.0), shape reference only | The silhouette idea of two swept supports; the geometry is our own, built in `Geometry.swift` |
| Sound from real recordings: hard ball-on-wood hits, a large-hall reverb and a low crowd murmur, applause on points | The 1950s table-tennis halls in *Marty Supreme* (mood only, none of its audio); CC0 recordings in `Assets/Sounds` | Each hit sounds physical and placed in a room; the crowd reacts only to points and the win |
| Hit feedback as a short glow, a fading trail on fast balls and a follow-through scaled by swing strength | Broadcast table tennis replays | The moment of contact reads instantly without on-screen text |
| iPhone Paddles as its own window, a grouped form | macOS System Settings | Sections per player, label–value rows, one plain-language footer, a target check shown once per measurement |

## Models

Table, net, paddles and ball are built in code at real dimensions (`Apps/FlickHost/Game/Equipment.swift`): a 2.74 × 1.525 m top with 2 cm lines, a 15.25 cm net, 150 × 158 mm blades with 5.8 mm wood cores and 2.1 mm rubber sheets with a grain normal map, and flared wooden handles. Textures are generated in `Textures.swift`.

## Rules for new UI

- No on-screen controls for anything a menu can do.
- One glass surface at a time; never a card inside a card.
- System font only, rounded design for score figures, tabular digits for anything that changes.
- Colour only for the two players' rubbers and for target checks (green met, orange missed).
