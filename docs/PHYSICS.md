# Physics and paddle design

How the ball flies, how a shot is made and how the phone becomes the bat. Numbers come from the papers in `research/papers` (not committed): Nakashima et al. for the table bounce, the Sony AI sim-to-real paper for the racket contact, TT3D and the serve-control paper for flight constants. Where they disagree, the most common value is used.

## World

Metres, on a regulation table. `x` runs across the table (0 to 1.525), `y` runs along it (Player A's end line at 0, Player B's at 2.74), `z` is height above the table top. The net is 0.1525 high at `y = 1.37`, overhanging the sides by 0.1525. The floor is 0.76 below the top.

The engine steps at 240 Hz. Physics runs at real scale but is played at `timeScale` 0.7 of real time, so a 6 m/s drive crosses the table in about 0.65 s on screen instead of 0.45 s. Speed never compounds: a return's speed comes from the stroke, plus a small carry of the incoming ball (`incomingCarry`).

## Ball flight

`a = g − k_d·|v|·v + k_m·(ω × v)`, with `g` = 9.81, `k_d` = 0.14 1/m, `k_m` = 1.5e-3 (both per unit mass, from k_d ≈ 3.8e-4 kg/m and k_m ≈ 4e-6 kg). Spin `ω` is in rad/s and stays constant in flight, as in every paper. Semi-implicit Euler at the physics step.

## Bounces

Table (Nakashima): slip at the contact point `u = (vx − r·ωy, vy + r·ωx)`, `α = min(0.4, μ(1+e)|vz| / |u|)`, then `v_t −= α·u`, `ω += (1.5/r)·(Δv_y, −Δv_x, 0)` and `vz = −e·vz`. `e` = 0.92, `μ` = 0.25. α = 0.4 is the rolling case.

Net: below the tape the ball is stopped (`vy` reversed ×0.1, the rest ×0.4) and drops. Touching the tape slows it (`vy` ×0.6) and it carries on.

Floor: `e` = 0.6, for the look only. Touching the floor decides the point.

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

When a ball that is ready for R reaches R's contact plane (0.3 m behind R's end line), or drops through 8 cm above the table on R's half (a short ball R leans in for), R gets one contact chance at that step `c`, with the ball's state at `c`. The chance is resolved once R's stroke data for `c` has arrived: right away for keyboard and computer strokes, up to 60 ms later for phones. A hit then rewinds to `c` and replays the flight to now, so phone lag never costs a ball.

The ball must be within reach of R's body (`reach`, 0.3 m across) and between 0.3 m below and 0.9 m above the table top.

## Two kinds of stroke

**Racket stroke (phones).** The phone streams the bat's orientation and the velocity of the blade centre at 100 Hz. At the contact step the engine takes the sample nearest `c` within `swingWindow` (±0.1 s) whose bat speed is at least `swingThreshold` (0.8 m/s). A still bat never returns the ball. Then real racket physics (Sony AI, inverted rubber) in the bat's frame:

- relative velocity `v_rel = v_ball − v_bat`, face normal `n` (whichever face meets the ball)
- normal: `v_n' = −e_n·v_n`, `e_n = 0.878 − 0.020·|v_n|`
- tangential: same slip map as the table with `α = (1 + e_t)/2.5`, `e_t = 0.8`, which turns brushing into spin
- outgoing `v = v_bat + v_n'·n + v_t'`

So the bat's angle and path decide everything. An open face lifts the ball, a closed face drives it down, an upward brush puts topspin on it, a downward chop gives backspin, a long hard swing is a power shot and a short light swing is a tap. `aimAssist` (0.35) nudges the launch angle a fraction of the way toward the nearest landing on the table, so a decent swing lands and a bad one still misses.

**Planned stroke (keyboard and computer).** A swing has a strength and an aim. The engine picks a landing point (depth from strength, side 60% from aim and 40% from where the ball meets the bat), moves it by the timing error (early goes long, late goes short and wide, nothing inside the sweet spot), then solves the launch angle by bisection on the real flight so the ball lands there, raising it if needed to clear the net.

## Movement

Phone players move automatically, as in Wii Sports Resort: the body heads for where the ball will reach the contact plane. Everyone moves at most 1.2 table widths a second (about 1.8 m/s, real footwork), so a wide, fast ball can still beat you and placement pays. Keyboard players move with A/D or ← →.

## Phone as the bat

- **Hold:** like a bat handle, bottom of the phone in the palm, screen facing the Mac as the forehand face.
- **Calibrate:** hold still in that pose and tap Calibrate. That attitude becomes upright, facing the table.
- **Sensing:** `CMDeviceMotion` at 100 Hz (`xArbitraryZVertical`). Bat orientation is the attitude relative to calibration. Blade velocity is `ω × (R·r_blade)` plus the leaky integral of user acceleration (τ 0.15 s), with `r_blade` 0.25 m up the handle.
- **Link:** each sample (timestamp, orientation quaternion, blade velocity) goes to the Mac over the unreliable channel, timed with the existing clock sync. Haptics stay: a contact buzz scaled by bat speed.

## Screen

The Mac draws the ball at its real height, plays the table sound on each bounce, and draws a phone player's bat at the phone's real orientation, so the bat on screen moves with your hand. The computer's and keyboard players' bats keep the animated stroke.

## Computer opponent

The computer reads the same prediction the engine uses, then plays like a person: it reacts after a delay, stands a little off where it should, and swings with a timing error. Against a scripted average player over 1,000 games each (`AIBalanceBenchmarkTests`, release build):

| Level | Timing error | Position error | Power | Aims away | Wins |
| --- | --- | --- | --- | --- | --- |
| Easy | 45 ms | 12 cm | 0.1–0.4 | never | 12% |
| Medium | 35 ms | 8 cm | 0.2–0.6 | 70% of shots | 52% |
| Hard | 29 ms | 7 cm | 0.3–0.7 | every shot | 91% |

Aiming away from the player adds about 11 points of win share for Medium.
