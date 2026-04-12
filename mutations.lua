local G = require("grid")
local particles = require("particles")
local audio = require("audio")

local mutations = {}

-- Mutation type definitions
mutations.TYPES = {
    heavy   = { name = "HEAVY",    color = {1.0, 0.3, 0.3}, symbol = "H", weight = 3, desc = "+1 damage per ball" },
    splitter= { name = "SPLITTER", color = {0.3, 1.0, 0.3}, symbol = "S", weight = 1, desc = "Balls split on first block hit" },
    ghost   = { name = "GHOST",    color = {0.7, 0.3, 1.0}, symbol = "G", weight = 2, desc = "Phase through 1 extra block" },
    kaboom  = { name = "KABOOM",   color = {1.0, 0.6, 0.2}, symbol = "K", weight = 1, desc = "Destroyed blocks chain-explode" },
    drunk   = { name = "DRUNK",    color = {1.0, 0.5, 0.8}, symbol = "D", weight = 3, desc = "Random +-15 deg angle on bounce" },
    magnet  = { name = "MAGNET",   color = {0.3, 0.6, 1.0}, symbol = "M", weight = 2, desc = "Balls curve toward blocks" },
}

-- Ordered list for consistent iteration
mutations.ORDER = { "heavy", "splitter", "ghost", "kaboom", "drunk", "magnet" }

-- Weighted random selection of a mutation type key
function mutations.rollMutagen()
    local total = 0
    for _, key in ipairs(mutations.ORDER) do
        total = total + mutations.TYPES[key].weight
    end
    local roll = math.random() * total
    local acc = 0
    for _, key in ipairs(mutations.ORDER) do
        acc = acc + mutations.TYPES[key].weight
        if roll <= acc then return key end
    end
    return mutations.ORDER[#mutations.ORDER]
end

-- Getters for mutation effects
function mutations.getDamage(game)
    return 1 + (game.mutations.heavy or 0)
end

function mutations.getSplitCount(game)
    return 1 + (game.mutations.splitter or 0)
end

function mutations.getPhaseCount(game)
    return game.mutations.ghost or 0
end

function mutations.getAOEDamage(game)
    return 2 * (game.mutations.kaboom or 0)
end

function mutations.getDrunkAngle(game)
    local stacks = game.mutations.drunk or 0
    return math.rad(15) * stacks
end

function mutations.getMagnetStrength(game)
    local stacks = game.mutations.magnet or 0
    return 0.05 * stacks
end

-- Check if any mutations are active
function mutations.hasAny(game)
    for _, key in ipairs(mutations.ORDER) do
        if (game.mutations[key] or 0) > 0 then return true end
    end
    return false
end

-- KABOOM chain explosion: recursive AOE from a destroyed block
-- Returns total number of blocks destroyed in the chain
local MAX_CHAIN = 50
function mutations.chainExplosion(game, row, col, visited)
    if not visited then visited = {} end
    local aoeDamage = mutations.getAOEDamage(game)
    if aoeDamage <= 0 then return 0 end

    local destroyed = 0
    local directions = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }

    for _, dir in ipairs(directions) do
        local r = row + dir[1]
        local c = col + dir[2]
        local key = r .. "," .. c

        if r >= 1 and r <= G.ROWS + 1 and c >= 1 and c <= G.COLS
           and not visited[key]
           and game.grid[r] and game.grid[r][c]
           and not game.grid[r][c].void then

            local block = game.grid[r][c]
            block.hp = block.hp - aoeDamage

            if block.hp <= 0 then
                visited[key] = true
                destroyed = destroyed + 1
                game.score = game.score + 1

                -- Spawn orange explosion particles
                local cx, cy = G.gridToPixelCenter(c, r)
                particles.spawn(cx, cy, 1.0, 0.5, 0.1, 20)

                audio.playDestroy()
                game.grid[r][c] = nil

                -- Recurse if under chain cap
                local totalVisited = 0
                for _ in pairs(visited) do totalVisited = totalVisited + 1 end
                if totalVisited < MAX_CHAIN then
                    destroyed = destroyed + mutations.chainExplosion(game, r, c, visited)
                end
            end
        end
    end

    return destroyed
end

return mutations
