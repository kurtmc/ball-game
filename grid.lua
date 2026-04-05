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

    -- More blocks per row at higher tiers: 3-4 → 3-5 → 4-6 → 5-7
    local min_blocks = util.clamp(3 + tier, 3, 5)
    local max_blocks = util.clamp(4 + tier, 4, grid.COLS)
    local num_blocks = math.random(min_blocks, max_blocks)

    -- HP multiplier ramps with tier: 1.0x, 1.3x, 1.6x, 2.0x, ...
    local hp_mult = 1.0 + tier * 0.3

    local blocks = {}
    for i = 1, num_blocks do
        local lo = math.max(1, math.floor(level * 0.5 * hp_mult))
        local hi = math.max(1, math.floor(level * 1.5 * hp_mult))
        local hp = math.random(lo, hi)
        table.insert(blocks, { col = cols[i], hp = hp, max_hp = hp })
    end

    -- Fewer pickups at higher tiers: always 1-2 early, sometimes 0-1 later
    local pickup_min = tier >= 3 and 0 or 1
    local pickup_max = tier >= 2 and 1 or 2
    local num_pickups = math.random(pickup_min, pickup_max)
    local pickups = {}
    for i = num_blocks + 1, math.min(num_blocks + num_pickups, grid.COLS) do
        table.insert(pickups, { col = cols[i] })
    end

    return blocks, pickups
end

return grid
