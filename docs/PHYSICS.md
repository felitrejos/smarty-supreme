# Physics and paddle design

How the ball flies, how a shot is made and how the phone becomes the bat. Flight and bounce numbers come from the papers in `research/papers` (not committed): Nakashima et al. for the table bounce, TT3D and the serve-control paper for flight constants. Where they disagree, the most common value is used.

## World

Metres, on a regulation table. `x` runs across the table (0 to 1.525), `y` runs along it (Player A's end line at 0, Player B's at 2.74), `z` is height above the table top. The net is 0.1525 high at `y = 1.37`, overhanging the sides by 0.1525. The floor is 0.76 below the top. The ball's radius is 0.02.

The engine steps at 240 Hz. Physics runs at real scale but is played at `timeScale` 0.7 of real time, so a 6 m/s drive crosses the table in about 0.65 s on screen instead of 0.45 s. Speed never compounds: a return's speed comes from the stroke, plus, for keyboard and computer strokes, 8% of the incoming ball's speed (`incomingCarry`).

## Ball flight

`a = g − k_d·|v|·v + k_m·(ω × v)`, with `g` = 9.81, `k_d` = 0.14 1/m, `k_m` = 1.5e-3 (both per unit mass, from k_d ≈ 3.8e-4 kg/m and k_m ≈ 4e-6 kg). Spin `ω` is in rad/s and stays constant in flight, as in every paper. Semi-implicit Euler at the physics step.

## Bounces

Table (Nakashima): slip at the contact point `u = (vx − r·ωy, vy + r·ωx)`, `α = min(0.4, μ(1+e)|vz| / |u|)`, then `v_t −= α·u`, `ω += (1.5/r)·(Δv_y, −Δv_x, 0)` and `vz = −e·vz`. `e` = 0.92, `μ` = 0.25. α = 0.4 is the rolling case.

Net: below the tape the ball is stopped (`vy` reversed ×0.1, the rest ×0.4) and drops. Touching the tape slows it (`vy` ×0.6), pops it up at 0.4 of its vertical speed, and it carries on. Either way the spin is cut to 0.4 of what it was.

Floor: `e` = 0.6, for the look only. Touching the floor decides the point.

The ball keeps flying for the 1.5 s between points, so a net ball drops off the net and rolls rather than freezing.

## Rules

A rally remembers who hit last and the table halves the ball has touched since.

| After a hit by H | Result |
| --- | --- |
| Serve: first bounce on H's half, second on R's | Ready for R |
| Rally: first bounce on R's half | Ready for R |
| First bounce on the wrong half | Point to R |
| Floor before the ball is ready | Point to R (out) |
| Second bounce, or floor, once ready | Point to H (not returned) |

A point is awarded `lagCompensation` (60 ms) after it is decided, and never while the loser still has a contact chance open or a return still being refined. A return that comes in time cancels the pending point.

Games go to 11, two clear, two serves each and one each from 10–10.

## Contact chance

When a ball that is ready for R reaches R's contact plane (0.3 m behind R's end line), or drops through 8 cm above the table on R's half (a short ball R leans in for), R gets one contact chance at that step `c`, with the ball's state at `c`. The ball must be between 0.3 m below and 1.3 m above the table top, or the swing is a whiff. A hit decided after `c` starts the return from the ball's state at `c` and replays it forward to the current step, so the return always leaves the bat on time.

## Two kinds of stroke

**Phone stroke.** The phone streams its orientation, rotation rate and a short-memory linear velocity at 100 Hz. `ArmModel` turns rotation into blade speed with a forearm lever, so a forehand turn about the vertical is a real forward swing. The stance is whichever face points at the table, with a margin so it doesn't flicker.

*Timing.* For a chance at `c` the engine looks at samples from 100 ms before to 120 ms after `c + perceivedLag` and takes the fastest, at least 0.8 m/s, that the swing actually climbed to: within the last 0.25 s before the window opens or since, the speed must have been below half that peak (`swingRiseFrom`, `swingRiseLookback`) with nothing faster in between, so a bat already drifting along is never the stroke. Only speed toward the table counts (`SwingDirection`), so a backswing, even one peaking inside the window, is never the stroke. Calibration gives a first guess at which way that is, and every serve settles it: a serve swing always goes toward the table, so whichever way it reads becomes forward. Half a second after each ball the engine looks at the whole swing, a second around it: if the hardest swing went clearly the other way (at least 2.5 m/s and at least 1.5 times the hardest swing toward the table), that counts against the direction, and two such balls in a row turn it round. A late player's backswing never counts, because their stroke follows it, and the same rule turns a wrong turn back. Recalibrating starts the direction over. Samples are kept for 1.1 s for this. A serve counts a swing in either direction. Samples are kept in the order they were taken, stamped at the step they were taken (extrapolated past the last frame, never beyond the last step the engine actually runs that frame, which on a frame over 100 ms is 100 ms on), and are kept through a long frame rather than dropped. The higher the ball (0.3 to 0.6 m), the more a downward swing counts alongside a forward one. `perceivedLag` (40 ms) covers display and reaction lag. Each player's median timing per stance over their last 8 swings (from the third swing on, clamped to ±50 ms) shifts the window and is subtracted from judged timing, so a consistent habit isn't punished. The stance is the grip as the ball arrives. Within 70 ms is clean, otherwise an edge; that label only drives feedback.

*Committing the hit.* Any swing over the threshold in the window is a hit, so the engine doesn't wait for the swing to peak and start falling. It commits when the swing is near its peak, the moment a real bat meets the ball: once its speed is growing by less than 30% every 10 ms (`nearTopGrowth`, 30 per second; about 15 ms before the top of a typical swing), or it has started to slow. At the first step at or after `c` where that holds, the return leaves from the contact state at `c` with the fastest sample so far, the rally count goes up and the hit sound plays. The ball therefore turns as the bat comes through, at close to the swing's real power, not at its first fast sample. While the swing is still rising, its peak can only come later, so the provisional timing is never counted as early.

After that, whenever the fastest sample changes, the return is solved again and, if it changed, replaces the old one and is replayed from `c`; when nothing changed, nothing is solved. A swing that speeds up again after the commit keeps being refined. The stroke settles when the peak is confirmed (two samples below 85% of it, or the window is over), when `swingRefinement` (0.12 s) has passed since the commit, or when the return touches anything (table, net, floor or the other bat's contact plane). A swing whose peak is already confirmed when it is first seen commits and settles in the same step.

Settling fixes the timing: the swing is reported and logged (with how long after `c` it was committed and at what power), the timing feedback is sent, and the timing is learned for the habit unless it was at the very edge of the window (95% or more) or the stroke settled before its peak was confirmed. Clean or edge is judged on the same timing the shot uses. Later samples never undo a hit, they only change its pace, depth, aim and spin.

With no swing, the chance closes 0.27 s after `c`.

*The shot* (`Shot.stroke`). One continuous model, from what the phone measures well:

- power: swing speed over 5 m/s sets pace (3 to 12 m/s) and depth (45% to 90% of the half)
- aim: the face's angle across the table, fading out as the face turns side-on
- lift: vertical blade speed over 1.5 m/s, chop to brush, sets spin from 15 rev/s of backspin to 45 of topspin
- timing error, early or late, as a share of the window: up to 35% less pace, a target up to 25% of the half shorter, up to 12° more loft (mistimes pop up), and a drift across the table, cross-court when early and down the line when late
- overhead: high balls allow a launch down to −25°, otherwise every stroke leaves at least 3° upward

A hard swing timed right (power × (1 − error)²) adds up to 3 m/s of pace and 12 rev/s of topspin, so a nailed drive comes off visibly faster and dips in. The launch is then solved on the real flight to land within 5 cm of the target and clear the net by 4 cm. If the asked-for pace can't make it, the nearest workable speed between 3 and 20 m/s is used. A phone stroke has no reach across the table: the body walks to the ball, and any swing in the window is solved to cross the net. The way to miss is to aim near a sideline and mistime toward it, which can take the ball out wide.

**Planned stroke (keyboard and computer).** A swing has a strength and an aim, and counts if it comes within 100 ms of `c` with the ball within 0.3 m of the bat across the table. The engine picks a landing point (depth 70% to 85% of the half by strength, side 60% from aim and 40% from where the ball meets the bat), moves it by the timing error (early goes up to 0.75 m long, late up to 0.9 m short, both drift up to 0.55 m to either side, nothing inside the middle quarter of the window), then solves the launch angle by bisection on the real flight so the ball lands there, raising it if needed to clear the net. Pace is 4.5 to 12 m/s and topspin 20 to 60 rev/s by strength. A ball met in the outer 15% of the reach is an edge.

## Serve

Tap the phone's screen to toss: the ball sits in the free hand on the side you're holding the phone for, 0.12 m above the table just behind the end line, and goes up 0.45 m. The ring marks the strike point, where the ball comes back down through 0.25 m. A swing timed to it serves from that point. Unlike a rally hit, a serve waits for the swing's peak to be confirmed. Timing error costs up to 35% of the pace and drifts the serve like a rally stroke. Forehand and backhand put opposite sidespin on it (25 rev/s), brushing up adds topspin and chopping down hard gives backspin. Miss the toss and it drops back into your hand to try again.

A serve leaves 14° downward. Its speed (1.5 to 9 m/s) is solved so the second bounce lands 75% to 90% of the way into the receiver's half, by strength.

Phone players are never served for. Keyboard and computer servers toss and strike on the way down: the keyboard on W (or by itself after 5 s), the computer 0.8 s into its turn.

## Movement

Phone players move automatically, as in Wii Sports Resort, but never onto the ball: 0.08 s after the opponent hits, the body walks to where the ball will reach your hand for your grip (the forehand puts the ball 0.32 m to your side, the backhand 0.2 m across). The grip has to settle for 0.15 s before the body walks to the other side, and it locks 0.2 s before contact. If the opponent's return is refined, the walk re-aims at the new path. Between points and while serving, phone players walk back to the middle. Everyone moves at most 1.5 table widths a second (about 2.3 m/s). For keyboard and computer players a wide, fast ball can still beat them; a phone stroke has no reach check, so a phone player is never beaten across the table, only by timing.

Keyboard players walk to the ball too. W readies a swing that fires as the ball arrives: pressed 0.25 s before contact it is on time, earlier or later shifts it by up to 45 ms. A/D aim.

## Phone as the bat

- **Hold:** like a bat handle, bottom of the phone in the palm, screen facing you. The back of the phone is the forehand face. Pick left or right hand on the calibration screen.
- **Calibrate:** face the Mac, hold still in that pose and tap Calibrate. That heading becomes "toward the table". Distance from the screen doesn't matter. Double-tap the phone to do it again.
- **Calibrate settles first:** the first 0.35 s after the tap isn't measured, because tapping a phone held like a bat jolts it. The next 0.5 s must be upright and steady to within 3°. A failure says TRY AGAIN with the reason.
- **Sensing:** `CMDeviceMotion` at 100 Hz (`xArbitraryZVertical`, the default frame). The phone sends its orientation relative to calibration, its rotation rate, and a linear velocity integrated from acceleration with a 0.3 s memory that resets whenever the phone has been still for 60 ms.
- **Connecting:** a relaunched phone comes back under a new network identity before the Mac has noticed its old connection is gone, so a phone with the same device name takes over that connection and keeps its side. In a one-phone game the held side always goes to the arriving phone; with two phones a stranger waits for the Mac to confirm.
- **Haptics:** when a ball heads your way, the Mac tells the phone the contact time in the phone's own clock, including `perceivedLag` and your learned timing habit. The phone buzzes itself as your swing passes its peak if that lands in the window, judged with the engine's own `GameConfig` threshold, window, falloff and rise rule (watching for the rise from 0.25 s before the window, like the Mac), counting only speed toward the table (it doesn't know the ball's height, so not the downward blend, nor a direction the Mac has turned round), scaled by how hard you swung, so the buzz isn't a network hop late: a crisp, sharp tap when the peak is within 70 ms of the ball, a duller knock with a 50 ms rattle when it isn't. The Mac doesn't send a hit buzz for rally strokes to a phone that is streaming as a bat. It sends the serve, miss, point and win buzzes.

## Screen

The ball is drawn where the engine has it; there is no hit-stop and no delayed display. A phone hit is committed as soon as the swing shows, so the return normally leaves the bat at contact. When a hit is committed a few steps after contact, or a committed return is refined, the ball's path changes under the drawing. The scene notices the new flight and eases the drawn ball onto it (the offset decays with a 0.12 s time constant) instead of jumping.

The phone player's bat is live: it sits at the hand for the settled grip, turns with the phone and moves with the swing. A ring at the predicted contact point (or the serve strike point) appears 0.45 s ahead and shrinks onto it.

The hit glow lasts 0.18 s. It starts at the commit in the ball's colour and takes the timing colour when the stroke settles: white within 25 ms, blue when early, orange when late. A card shows the same, "ON TIME" or "EARLY · 40 MS", for 1.1 s.

A clean hit's paddle sound plays a little higher and brighter the harder it's struck; an edge plays lower, duller and quieter. The sound plays at the commit. For a phone stroke it is the edge sound only when the stroke has already settled as an edge in that frame; a swing committed while still rising sounds clean. The net plays a soft sound when hit and shakes, more for a faster ball.

Between points the ball fades in at the server's hand. The computer's and keyboard players' bats keep the animated stroke.

## Computer opponent

The computer reads the same prediction the engine uses, then plays like a person: it reacts after a delay (0.2, 0.18 and 0.15 s for Easy, Medium and Hard), stands a little off where it should, and swings with a timing error. Its reaction is always longer than `swingRefinement`, so it plans against a phone return that has stopped changing.

Against a scripted average player over 1,000 games each (`AIBalanceBenchmarkTests`, release build). These win shares were measured before phone hits were committed early and have not been re-measured; both players in the benchmark use planned strokes, which that change did not touch.

| Level | Timing error | Position error | Power | Aims away | Wins |
| --- | --- | --- | --- | --- | --- |
| Easy | 45 ms | 12 cm | 0.1–0.4 | never | 12% |
| Medium | 35 ms | 8 cm | 0.2–0.6 | 70% of shots | 52% |
| Hard | 29 ms | 7 cm | 0.3–0.7 | every shot | 91% |

Aiming away from the player adds about 11 points of win share for Medium.
