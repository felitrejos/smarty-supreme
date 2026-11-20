# Physics and paddle design

How the ball flies, how a shot is made and how the phone becomes the bat. Flight and bounce numbers come from the papers in `research/papers` (not committed): Nakashima et al. for the table bounce, TT3D and the serve-control paper for flight constants. Where they disagree, the most common value is used.

## World

Metres, on a regulation table. `x` runs across the table (0 to 1.525), `y` runs along it (Player A's end line at 0, Player B's at 2.74), `z` is height above the table top. The net is 0.1525 high at `y = 1.37`, overhanging the sides by 0.1525. The floor is 0.76 below the top.

The engine steps at 240 Hz. Physics runs at real scale but is played at `timeScale` 0.7 of real time, so a 6 m/s drive crosses the table in about 0.65 s on screen instead of 0.45 s. Speed never compounds: a return's speed comes from the stroke, plus, for keyboard and computer strokes, a small carry of the incoming ball (`incomingCarry`).

## Ball flight

`a = g − k_d·|v|·v + k_m·(ω × v)`, with `g` = 9.81, `k_d` = 0.14 1/m, `k_m` = 1.5e-3 (both per unit mass, from k_d ≈ 3.8e-4 kg/m and k_m ≈ 4e-6 kg). Spin `ω` is in rad/s and stays constant in flight, as in every paper. Semi-implicit Euler at the physics step.

## Bounces

Table (Nakashima): slip at the contact point `u = (vx − r·ωy, vy + r·ωx)`, `α = min(0.4, μ(1+e)|vz| / |u|)`, then `v_t −= α·u`, `ω += (1.5/r)·(Δv_y, −Δv_x, 0)` and `vz = −e·vz`. `e` = 0.92, `μ` = 0.25. α = 0.4 is the rolling case.

Net: below the tape the ball is stopped (`vy` reversed ×0.1, the rest ×0.4) and drops. Touching the tape slows it (`vy` ×0.6) and it carries on.

Floor: `e` = 0.6, for the look only. Touching the floor decides the point.

The ball keeps flying after a point is decided, so a net ball drops off the net and rolls rather than freezing. The net shakes and plays a soft sound when hit.

## Rules

A rally remembers who hit last and the table halves the ball has touched since.

| After a hit by H | Result |
| --- | --- |
| Serve: first bounce on H's half, second on R's | Ready for R |
| Rally: first bounce on R's half | Ready for R |
| First bounce on the wrong half | Point to R |
| Floor before the ball is ready | Point to R (out) |
| Second bounce, or floor, once ready | Point to H (not returned) |

A point is awarded `lagCompensation` (60 ms) after it is decided, and never while a late stroke could still save it.

## Contact chance

When a ball that is ready for R reaches R's contact plane (0.3 m behind R's end line), or drops through 8 cm above the table on R's half (a short ball R leans in for), R gets one contact chance at that step `c`, with the ball's state at `c`. The ball must be between 0.3 m below and 1.3 m above the table top. A hit decided after `c` replays the return flight from `c`; the replayed path is kept (`GameState.lastReplay`) so the display can follow it.

## Two kinds of stroke

**Phone stroke.** The phone streams its orientation, rotation rate and a short-memory linear velocity at 100 Hz. `ArmModel` turns rotation into blade speed with a forearm lever, so a forehand turn about the vertical is a real forward swing. The stance is whichever face points at the table, with a margin so it doesn't flicker.

*Timing.* For a chance at `c` the engine looks at samples from 100 ms before to 120 ms after `c + perceivedLag` and takes the fastest, at least 0.8 m/s, once it has clearly peaked (two samples below 85%) or the window is over. Forward speed counts in either direction, so a heading that is turned round still swings. The higher the ball (0.3 to 0.6 m), the more a downward swing counts alongside a forward one. `perceivedLag` (40 ms) covers display and reaction lag. Each player's median timing per stance over their last 8 swings (clamped to ±50 ms) shifts the window and is subtracted from judged timing, so a consistent habit isn't punished. Within 70 ms is labelled clean; that label only drives feedback.

*The shot* (`Shot.stroke`). One continuous model, from what the phone measures well:

- power: swing speed over 5 m/s sets pace (3 to 12 m/s) and depth (45% to 90% of the half)
- aim: the face's angle across the table, fading out as the face turns side-on
- lift: vertical blade speed, chop to brush, sets spin from 15 rev/s of backspin to 45 of topspin
- timing error, early or late, as a share of the window: up to 35% less pace, a shorter target, more loft (mistimes pop up), and a drift across the table, cross-court when early and down the line when late
- overhead: high balls allow a launch down to −25°, otherwise every stroke leaves at least 3° upward

A hard swing timed right (power × (1 − error)²) adds up to 3 m/s of pace and 12 rev/s of topspin, so a nailed drive comes off visibly faster and dips in. The launch is then solved on the real flight to land on the target and clear the net. If the asked-for pace can't make it, the nearest workable speed is used. Any swing in the window crosses the net; the way to miss is to aim near a sideline and mistime toward it, which can take the ball out wide.

**Planned stroke (keyboard and computer).** A swing has a strength and an aim. The engine picks a landing point (depth from strength, side 60% from aim and 40% from where the ball meets the bat), moves it by the timing error (early goes long, late goes short and wide, nothing inside the sweet spot), then solves the launch angle by bisection on the real flight so the ball lands there, raising it if needed to clear the net.

## Serve

Tap the phone's screen to toss: the ball sits in the free hand on the side you're holding the phone for and goes up 0.45 m. The ring marks the strike point, where the ball comes back down through 0.25 m. A swing timed to it serves from that point; timing error costs pace and drifts the serve like a rally stroke. Forehand and backhand put opposite sidespin on it, and chopping down gives backspin. Miss the toss and it drops back into your hand to try again. Phone players are never served for; keyboard and computer servers toss and strike on the way down.

## Movement

Phone players move automatically, as in Wii Sports Resort, but never onto the ball: 0.08 s after the opponent hits, the body walks to where the ball will reach your hand for your grip (the forehand puts the ball 0.32 m to your side, the backhand 0.2 m across). The grip has to settle for 0.15 s before the body walks to the other side, and it locks 0.2 s before contact. Between points and while serving, phone players walk back to the middle. Everyone moves at most 1.5 table widths a second (about 2.3 m/s), so a wide, fast ball can still beat you. Keyboard players walk to the ball too; W readies a swing that fires on arrival, A/D aim.

## Phone as the bat

- **Hold:** like a bat handle, bottom of the phone in the palm, screen facing you. The back of the phone is the forehand face. Pick left or right hand on the calibration screen.
- **Calibrate:** face the Mac, hold still in that pose and tap Calibrate. That heading becomes "toward the table". Distance from the screen doesn't matter.
- **Sensing:** `CMDeviceMotion` at 100 Hz (`xArbitraryZVertical`). The phone sends its orientation relative to calibration, its rotation rate, and a linear velocity integrated from acceleration with a 0.3 s memory that resets whenever the phone is still.
- **Calibrate settles first:** the first 0.35 s after the tap isn't measured, because tapping a phone held like a bat jolts it. A failure says TRY AGAIN with the reason.
- **Connecting:** a relaunched phone comes back under a new network identity before the Mac has noticed its old connection is gone, so a phone with the same device name takes over that connection and keeps its side. In a one-phone game the held side always goes to the arriving phone; with two phones a stranger waits for the Mac to confirm.
- **Haptics:** when a ball heads your way, the Mac tells the phone the contact time in the phone's own clock, including your learned timing habit. The phone buzzes itself at the peak of your swing if it lands in the window, scaled by how hard you swung, so the buzz isn't a network hop late: a crisp, sharp tap when the peak is within 70 ms of the ball, a duller knock with a short rattle when it isn't. The Mac sends the serve and miss buzzes.

## Screen

A phone hit is only decided once the swing has peaked, just after the ball reaches the bat. So while the player is swinging at it (at least half the swing threshold) the ball is drawn in slow motion (hit-stop, a quarter speed) until the swing is decided; with no swing it flies on at full speed. After the decision the return plays a little fast (1.6×) until the drawing has caught up, never more than 0.25 s behind. Poses not yet drawn take the replayed path, and any remaining correction eases over 0.12 s. The phone player's bat is live: it sits at the hand for the settled grip, turns with the phone and moves with the swing. A ring at the predicted contact point (or the serve strike point) shrinks over the last 0.45 s. The hit glow turns white when you're on time, blue when early and orange when late, with an "EARLY · 40 MS" card. A clean hit's paddle sound plays a little higher and brighter the harder it's struck; an edge plays lower, duller and quieter. Between points the ball fades in at the server's hand. The computer's and keyboard players' bats keep the animated stroke.

## Computer opponent

The computer reads the same prediction the engine uses, then plays like a person: it reacts after a delay, stands a little off where it should, and swings with a timing error. Against a scripted average player over 1,000 games each (`AIBalanceBenchmarkTests`, release build):

| Level | Timing error | Position error | Power | Aims away | Wins |
| --- | --- | --- | --- | --- | --- |
| Easy | 45 ms | 12 cm | 0.1–0.4 | never | 12% |
| Medium | 35 ms | 8 cm | 0.2–0.6 | 70% of shots | 52% |
| Hard | 29 ms | 7 cm | 0.3–0.7 | every shot | 91% |

Aiming away from the player adds about 11 points of win share for Medium.
