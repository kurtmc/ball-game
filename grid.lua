local util = require("util")

local grid = {}

grid.COLS = 7
grid.ROWS = 11
grid.LAUNCH_DELAY = 0.065

-- Layout constants recomputed by grid.updateLayout(canvas_w, canvas_h).
-- Defaults match the 800x800 square design. On portrait canvases the cells
-- expand so the grid fills ~88% of the width, and the floor drops to ~62%
-- of the canvas height so there's a natural aim-drag zone below for thumbs.
grid.CELL_SIZE    = 65
grid.GRID_WIDTH   = grid.COLS * grid.CELL_SIZE
grid.GRID_LEFT    = math.floor((800 - grid.GRID_WIDTH) / 2)
grid.GRID_RIGHT   = grid.GRID_LEFT + grid.GRID_WIDTH
grid.GRID_TOP     = 40
grid.FLOOR_Y      = grid.GRID_TOP + grid.ROWS * grid.CELL_SIZE
grid.BLOCK_PAD    = 3
grid.BLOCK_SIZE   = grid.CELL_SIZE - 2 * grid.BLOCK_PAD
grid.BALL_RADIUS  = 5
grid.BALL_SPEED   = 600
grid.PICKUP_RADIUS = 12

function grid.updateLayout(canvas_w, canvas_h)
    local is_portrait = canvas_h > canvas_w
    local target_w, target_floor_frac, aim_zone, top_pad

    if is_portrait then
        target_w          = canvas_w * 0.88
        target_floor_frac = 0.62
        aim_zone          = 180   -- reserved space below floor for thumb
        top_pad           = 60    -- reserved space above grid for HUD
    else
        target_w          = 455   -- original 7 x 65
        target_floor_frac = 755 / 800
        aim_zone          = 40
        top_pad           = 40
    end

    local new_cell = math.floor(target_w / grid.COLS)
    local max_h_cell = math.floor((canvas_h - top_pad - aim_zone) / grid.ROWS)
    if max_h_cell > 0 then new_cell = math.min(new_cell, max_h_cell) end
    new_cell = math.max(55, new_cell)

    grid.CELL_SIZE  = new_cell
    grid.GRID_WIDTH = grid.COLS * grid.CELL_SIZE
    grid.GRID_LEFT  = math.floor((canvas_w - grid.GRID_WIDTH) / 2)
    grid.GRID_RIGHT = grid.GRID_LEFT + grid.GRID_WIDTH
    grid.BLOCK_PAD  = math.max(3, math.floor(grid.CELL_SIZE * 3 / 65))
    grid.BLOCK_SIZE = grid.CELL_SIZE - 2 * grid.BLOCK_PAD

    local grid_h = grid.ROWS * grid.CELL_SIZE
    local target_top = math.floor(canvas_h * target_floor_frac) - grid_h
    target_top = math.max(top_pad, target_top)
    target_top = math.min(target_top, canvas_h - grid_h - aim_zone)
    grid.GRID_TOP = target_top
    grid.FLOOR_Y  = grid.GRID_TOP + grid_h

    -- Scale ball/pickup/speed with cell size so gameplay feel stays consistent
    local s = grid.CELL_SIZE / 65
    grid.BALL_RADIUS   = math.max(5, math.floor(5 * s))
    grid.PICKUP_RADIUS = math.max(12, math.floor(12 * s))
    grid.BALL_SPEED    = 600 * s
end

-- Convert grid coords (1-based) to pixel center
function grid.gridToPixelCenter(col, row)
    local x = grid.GRID_LEFT + (col - 0.5) * grid.CELL_SIZE
    local y = grid.GRID_TOP + (row - 0.5) * grid.CELL_SIZE
    return x, y
end

-- Get block rectangle (top-left corner + size) for collision
function grid.blockRect(col, row)
    local x = grid.GRID_LEFT + (col - 1) * grid.CELL_SIZE + grid.BLOCK_PAD
    local y = grid.GRID_TOP + (row - 1) * grid.CELL_SIZE + grid.BLOCK_PAD
    return x, y, grid.BLOCK_SIZE, grid.BLOCK_SIZE
end

-- Get color for a block based on HP relative to level
function grid.blockColor(hp, level)
    local ratio = util.clamp(hp / math.max(1, level * 1.5), 0, 1)
    local hue = (1 - ratio) * (240 / 360)  -- blue (low) to red (high)
    local r, g, b = util.hslToRgb(hue, 0.75, 0.55)
    return r, g, b
end

-- Generate a new row of blocks and pickups for the given level
-- Returns blocks = {{col=, hp=, max_hp=}}, pickups = {{col=}}
function grid.generateRow(level)
    local tier = math.floor((level - 1) / 10)  -- 0 at level 1-10, 1 at 11-20, etc.

    local cols = {}
    for i = 1, grid.COLS do cols[i] = i end
    util.shuffle(cols)

    -- Blocks per row: keep sparse so gaps are plentiful: 2-3 → 2-4 → 3-4
    local min_blocks = util.clamp(2 + math.floor(tier / 2), 2, 3)
    local max_blocks = util.clamp(3 + math.floor(tier / 2), 3, 4)
    local num_blocks = math.random(min_blocks, max_blocks)

    -- HP multiplier ramps with tier: 1.0x, 1.3x, 1.6x, 1.9x, 2.2x ...
    -- Post tier 4 (level 50+): steeper ramp to match mutation power
    local hp_mult
    if tier <= 4 then
        hp_mult = 1.0 + tier * 0.3
    else
        hp_mult = 1.0 + 4 * 0.3 + (tier - 4) * 0.5
    end

    local blocks = {}
    for i = 1, num_blocks do
        local lo = math.max(1, math.floor(level * 0.5 * hp_mult))
        local hi = math.max(1, math.floor(level * 1.5 * hp_mult))
        local hp = math.random(lo, hi)
        table.insert(blocks, { col = cols[i], hp = hp, max_hp = hp })
    end

    -- Fewer pickups at higher tiers: always 1-2 early, sometimes 0-1 later
    -- Post-50: even fewer ball pickups (mutations compensate)
    local pickup_min, pickup_max
    if level > 50 then
        pickup_min = 0
        pickup_max = 1
    elseif tier >= 3 then
        pickup_min = 0
        pickup_max = 1
    elseif tier >= 2 then
        pickup_min = 1
        pickup_max = 1
    else
        pickup_min = 1
        pickup_max = 2
    end
    local num_pickups = math.random(pickup_min, pickup_max)
    local pickups = {}
    local next_col = num_blocks + 1
    for i = next_col, math.min(next_col + num_pickups - 1, grid.COLS) do
        table.insert(pickups, { col = cols[i] })
    end
    next_col = next_col + num_pickups

    -- Mutagen orbs: only in Chaos Zone (level > 50), ~35% chance per row
    -- Type is filled in by caller (states.lua) to avoid circular dependency
    local mutagens = {}
    if level > 50 and next_col <= grid.COLS and math.random() < 0.35 then
        table.insert(mutagens, { col = cols[next_col] })
        next_col = next_col + 1
    end

    -- Draft orb: ~30% chance per row in Chaos Zone. Player chooses 1 of 3 mutations.
    if level > 50 and next_col <= grid.COLS and math.random() < 0.30 then
        table.insert(mutagens, { col = cols[next_col], draft = true })
        next_col = next_col + 1
    end

    -- Void blocks: only in Chaos Zone, ~30% chance per row, max 1
    local void_block = nil
    if level > 50 and next_col <= grid.COLS and math.random() < 0.30 then
        void_block = { col = cols[next_col] }
        next_col = next_col + 1
    end

    return blocks, pickups, mutagens, void_block
end

return grid
