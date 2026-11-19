# Smarty Supreme design

The Mac shows one match in a 1950s arena: the London tournament in *Marty Supreme* (A24, 2025), checked against real 1950s English Open and World Championship photos at the Empire Pool, Wembley. The iPhone is a hardbat paddle.

## Decisions and where they come from

| Decision | Reference | What was taken |
| --- | --- | --- |
| A single teal table on a lit wooden court, boxed in by low dark surround barriers, inside a dark arena | *Marty Supreme* London match frames; 1950s Pathé and Getty photos at Wembley | Court layout, surround height, the table as the only bright object |
| Even light from an overhead rig, not lamp pools; deep blacks outside the court | ASC on Darius Khondji's overhead rig; Reverse Shot on "deep blacks beyond the reach of warm tungsten light" | Five wide warm spots 7 m up, one casting shadows; dim fill from a photographed arena (Poly Haven `circus_arena`, CC0) |
| A crowd in tiered stands, out of focus, lit only by spill from the court | Sports games' impostor crowds (rendered 3D people shown as camera-facing cards); the film's dim audience | Real MakeHuman people (Innerscene, CC0) rendered once into blurred cards; brightness falls off as 1/(1+d²) from the court; idle sway and a staggered cheer on points |
| Umpire's table beside the court with flip score cards that follow the score | The film's officials' table and number stands | Cards set in Futura Condensed ExtraBold, cream on black |
| 1950s trestle-legged table and hardbat paddles: wooden blade, pimpled rubber, no sponge | Pathé footage; the Hardbat entry on Wikipedia | Folding legs with stretchers; red (Player A) and black (Player B) pips |
| Real materials | Poly Haven (CC0): Old Wooden Floor 02, Coated Pine, Plywood, Black Painted Planks; a Painted Wooden Chair 01 model | Floor, table frame, blades, barriers, umpire and court chairs |
| 35mm look over the 3D view | Kodak on the film's 35mm stock | Fine animated grain, a vignette and a warm grade (`FilmLook.swift`) |
| Umpire calls and the computer's voice from fixed, pre-recorded lines | Real table tennis umpiring ("seven, five", "deuce", "game, Player A") | Kokoro voices (`bm_george` umpire, `am_puck` computer) rendered by `Tools/render_voice.py`, played through a large-hall reverb |
| Sound from real recordings | The film's halls (mood only); CC0 recordings in `Assets/Sounds` | Ball-on-wood hits, hall reverb, crowd murmur, applause on points |

## Rules for new work

- Look for the best real reference or asset first (film frames, period photos, shipped games, CC0 libraries), study it, then build from it. No hand-made primitives standing in for people, lights or props.
- Colour carries meaning: the table and the two rubbers. Everything else is warm, dark and desaturated.
- One small performance line (fps and CPU) when View › Show Frame Times is on; nothing else on screen that a menu can hold.
