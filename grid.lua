local util = require("util")

local grid = {}

-- Layout constants
grid.COLS         = 7
grid.ROWS         = 11
grid.CELL_SIZE    = 65
grid.GRID_WIDTH   = grid.COLS * grid.CELL_SIZE   -- 455
grid.GRID_LEFT    = math.floor((800 - grid.GRID_WIDTH) / 2)  -- 172
grid.GRID_RIGHT   = grid.GRID_LEFT + grid.GRID_WIDTH         -- 627
grid.GRID_TOP     = 40
grid.FLOOR_Y      = grid.GRID_TOP + grid.ROWS * grid.CELL_SIZE  -- 560
grid.BLOCK_PAD    = 3
grid.BLOCK_SIZE   = grid.CELL_SIZE - 2 * grid.BLOCK_PAD  -- 59
grid.BALL_RADIUS  = 5
grid.BALL_SPEED   = 600
grid.LAUNCH_DELAY = 0.065
grid.PICKUP_RADIUS = 12

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

    -- Void blocks: only in Chaos Zone, ~30% chance per row, max 1
    local void_block = nil
    if level > 50 and next_col <= grid.COLS and math.random() < 0.30 then
        void_block = { col = cols[next_col] }
        next_col = next_col + 1
    end

    return blocks, pickups, mutagens, void_block
end

return grid
