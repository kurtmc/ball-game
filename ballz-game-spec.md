# Ballz — Game Specification

## Overview

Ballz is a turn-based brick-breaker puzzle game. The player launches a volley of balls from the bottom of the screen upward into a grid of numbered blocks. Each ball bounce reduces a block's number by 1. When a block reaches 0, it is destroyed. After each turn, a new row of blocks descends from the top. The game ends when any block reaches the bottom row.

---

## Core Loop

1. **Aim** — The player drags/swipes from the launch point to set an angle. A dotted trajectory line previews the first bounce.
2. **Launch** — On release, balls fire one-by-one in rapid succession (short delay between each) at the chosen angle.
3. **Resolve** — Balls ricochet off walls, ceiling, and blocks. Each collision with a block reduces its HP by 1. Balls that hit the floor are collected at their landing position.
4. **Collect** — Once all balls have returned to the floor, the new launch point is set to where the *first* ball landed.
5. **Advance** — All existing blocks shift down by one row. A new row of blocks (and bonus items) spawns at the top.
6. **Check game over** — If any block occupies the bottom row after advancing, the game ends.
7. **Repeat** from step 1.

---

## Playing Field

| Property | Value |
|---|---|
| Grid columns | 7 |
| Grid rows (visible) | ~9–10 (varies by screen) |
| Coordinate system | Column-aligned grid for blocks; continuous 2D space for ball physics |
| Walls | Left, right, and top edges are solid and reflective |
| Floor | Bottom edge — balls that reach it are "collected" and stop |

---

## Blocks

### Appearance
- Square tiles that fill one grid cell with small padding/margin between them.
- Each block displays its current HP as a number in its centre.
- Colour shifts based on HP relative to the current level number (low HP → cool colours, high HP → warm/hot colours). This gives an instant visual read on difficulty.

### HP Assignment
- New blocks spawn with HP values roughly proportional to the current level (turn number).
- Exact HP is randomised within a range. A simple formula:
  - `HP = randInt(level * 0.5, level * 1.5)` (tunable).
- As levels increase, blocks become progressively harder to destroy.

### Spawning Rules
- Each new row is generated with a random subset of the 7 columns filled (not all columns every turn).
- Typical fill rate: 3–5 blocks per row (randomised).
- Empty cells may contain bonus items (see below).

---

## Balls

| Property | Description |
|---|---|
| Size | Small circle, roughly 1/7th of a column width in diameter |
| Speed | Constant; all balls travel at the same speed |
| Launch rate | Balls fire sequentially with a short fixed delay (~50–80 ms) between each |
| Physics | Perfect elastic reflection off walls, ceiling, and block surfaces |
| Damage | Each collision with a block deals exactly 1 HP of damage |
| Collection | A ball is removed from play when it crosses the floor line; its x-position is recorded |

### Launch Point
- The launch point is a single x-position along the bottom of the screen.
- At the start of the game it is centred.
- After each turn it moves to the x-position where the **first** ball landed.

### Ball Count
- The player starts with **1 ball**.
- Ball count increases by collecting **ball pickups** (see Bonus Items).
- Ball count never decreases — it only grows over the course of a game.

---

## Bonus Items

Bonus items appear in empty grid cells within each new row.

### Ball Pickup (+1 Ball)
- Appearance: small white/glowing circle, slightly smaller than a block, often with a "+" or ring animation.
- When any ball passes through it, it is collected and the player's ball count increases by 1 on the **next** turn.
- Multiple pickups can appear per row (typically 1–2).
- Pickups do not block ball movement — balls pass straight through them.

### Ring / Coin (Currency — optional)
- Appearance: small gold/yellow circle.
- Collected on contact, awards currency for cosmetic unlocks.
- Does not affect core gameplay.

---

## Aiming & Controls

- **Input**: touch drag (mobile) or mouse drag (desktop).
- **Drag direction**: pulling down and away from the desired launch direction (slingshot style), **or** swiping in the direction of the shot (direct aim). The original Ballz uses **direct aim** — drag upward in the direction you want balls to go.
- **Trajectory preview**: a dotted line from the launch point showing the path and first bounce point. The preview updates in real-time as the player adjusts aim.
- **Angle constraints**: the launch angle is clamped to prevent purely horizontal shots. Minimum angle from horizontal ≈ 5–10°.
- **Cancel**: dragging back below the launch point cancels the shot.

---

## Collision & Physics

### Ball-Wall Collisions
- Perfect reflection: angle of incidence = angle of reflection.
- Walls are the left edge, right edge, and top edge (ceiling).

### Ball-Block Collisions
- Detect which face of the block the ball hits (top, bottom, left, right).
- Reflect the ball's velocity component perpendicular to that face.
- Subtract 1 from the block's HP.
- If HP reaches 0, destroy the block immediately (remove it from the grid so the ball continues unobstructed).

### Ball-Ball Collisions
- **Ignored.** Balls pass through each other.

### Edge Cases
- **Corner hits**: when a ball hits the exact corner of a block, reflect both velocity components (treat as hitting two perpendicular faces simultaneously).
- **Tunnelling**: at high speeds, use swept/continuous collision detection or a small enough time step to prevent balls passing through thin blocks.
- **Stuck balls**: if a ball has been bouncing for an unusually long time (e.g., >10 seconds or >200 bounces), auto-return it to the floor to avoid infinite loops from near-horizontal trajectories.

---

## Scoring & Progression

| Metric | Description |
|---|---|
| Level | Increments by 1 each turn (turn 1 = level 1) |
| Score | Can be the level number itself, or cumulative blocks destroyed — either works |
| Difficulty curve | Block HP scales with level; row fill density can also increase gradually |
| High score | Persist locally; track highest level reached |

---

## Game Over

- **Trigger**: after blocks advance downward, if any block's position is at or below the bottom row (the row just above the launch line).
- **Screen**: display "Game Over" with the final level/score and the option to restart.
- No lives system — one game over ends the run.

---

## Visual & Audio Guidelines

### Visual Style
- Dark background (black or very dark grey).
- Blocks are solid bright colours with rounded corners.
- Ball colour is white by default (cosmetic unlocks can change this).
- Smooth animations: block destruction (pop/shatter), ball launch, row descent.
- Number text on blocks should be bold, centred, and clearly legible even at high values (scale font size down for 3–4 digit numbers).

### Juice & Polish
- **Screen shake** on block destruction (subtle).
- **Particle burst** when a block is destroyed.
- **Satisfying sound** on each ball-block hit (pitch can increase with combo/chain).
- **Row descent animation** should be a smooth slide, not a snap.
- **Ball trail** — short fading trail behind each ball for visual clarity when many balls are in play.

### Audio
- Soft ball-bounce sound on wall/ceiling hits.
- Slightly different pitch/tone on block hits.
- Crunch/pop on block destruction.
- Ambient background music (optional, low-key).

---

## Technical Considerations

### Performance
- At high levels the player may have 100+ balls in flight simultaneously. The physics and rendering loop must handle this efficiently.
- Consider spatial partitioning (e.g., grid-based) for collision checks rather than brute-force ball-vs-all-blocks.
- Use `requestAnimationFrame` (web) or equivalent fixed-timestep loop for consistent physics.

### State Management
- **Minimal state per turn**: ball count, launch x-position, grid of blocks (column, row, HP), list of bonus items.
- Serialise state for save/resume functionality.

### Suggested Tech Stack (flexible)
- **Web**: HTML5 Canvas or WebGL, vanilla JS or a lightweight framework.
- **Mobile**: Unity, Godot, or native (SpriteKit / Android Canvas).
- **Physics**: custom 2D — the physics are simple enough that a full engine is unnecessary.

---

## MVP Feature Checklist

- [ ] Render 7-column grid with numbered blocks
- [ ] Aim with trajectory preview (dotted line + first bounce)
- [ ] Launch balls sequentially at chosen angle
- [ ] Ball physics: wall reflection, block collision, floor collection
- [ ] Block HP reduction and destruction
- [ ] Ball pickup items that increase ball count
- [ ] New row generation and grid descent each turn
- [ ] Launch point follows first ball's landing position
- [ ] Game over detection
- [ ] Level/score display
- [ ] Restart functionality

## Stretch Features

- [ ] High score persistence (local storage)
- [ ] Cosmetic ball colour unlocks
- [ ] Sound effects and background music
- [ ] Particle effects on block destruction
- [ ] Speed-up button (fast-forward ball resolution)
- [ ] Pause menu
- [ ] Responsive layout for different screen sizes
