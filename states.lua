local G = require("grid")
local aiming = require("aiming")
local ball = require("ball")
local audio = require("audio")
local particles = require("particles")
local chaos = require("chaos")
local mutations = require("mutations")

local states = {}

-- State handlers table
local handlers = {}

----------------------------------------------------------------
-- AIMING
----------------------------------------------------------------
handlers.aiming = {}

function handlers.aiming.update(game, dt)
    -- nothing to tick
end

function handlers.aiming.draw(game)
    aiming.draw(game)
    -- Draw launch point indicator
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", game.launch_x, G.FLOOR_Y, G.BALL_RADIUS)
    -- Draw ball count near launch point
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("x" .. game.ball_count, game.launch_x - 30, G.FLOOR_Y + 8, 60, "center")
end

function handlers.aiming.mousepressed(game, x, y)
    aiming.mousepressed(game, x, y)
end

function handlers.aiming.mousemoved(game, x, y)
    aiming.mousemoved(game, x, y)
end

function handlers.aiming.mousereleased(game, x, y)
    local launched = aiming.mousereleased(game, x, y)
    if launched then
        game.state = "launching"
        game.balls = {}
        game.landed_balls = {}
        game.first_landed_x = nil
        game.launch_timer = 0
        game.balls_launched = 0
        game.combo = 0
        game.splitter_queue = {}
        -- Apply chaos modifier overrides for ball count
        game.effective_ball_count = chaos.getEffectiveBallCount(game)
        if chaos.isActive(game, "SNIPER") then
            game.sniper_damage_mult = game.ball_count
        end
    end
end

-- Dev: advance N levels (shared by skip keys)
local function devSkipLevels(game, count)
    for _ = 1, count do
        for r = G.ROWS, 1, -1 do
            game.grid[r + 1] = game.grid[r]
        end
        game.grid[1] = {}
        for _, p in ipairs(game.pickups) do p.row = p.row + 1 end
        for _, mu in ipairs(game.mutagens) do mu.row = mu.row + 1 end
        game.level = game.level + 1
        local blocks, pickups, muts, void_block = G.generateRow(game.level)
        for _, b in ipairs(blocks) do
            game.grid[1][b.col] = { hp = b.hp, max_hp = b.max_hp }
        end
        for _, p in ipairs(pickups) do
            table.insert(game.pickups, { col = p.col, row = 1, collected = false })
        end
        for _, mg in ipairs(muts) do
            table.insert(game.mutagens, { col = mg.col, row = 1, type = mutations.rollMutagen(), collected = false })
        end
        if void_block then
            game.grid[1][void_block.col] = { hp = math.huge, max_hp = 1, void = true }
        end
        game.grid[G.ROWS + 1] = nil
        for i = #game.pickups, 1, -1 do
            if game.pickups[i].row > G.ROWS then table.remove(game.pickups, i) end
        end
        for i = #game.mutagens, 1, -1 do
            if game.mutagens[i].row > G.ROWS then table.remove(game.mutagens, i) end
        end
    end
    if game.level > 50 and not game.chaos_active then
        game.chaos_active = true
        game.chaos_zone_flash = 3.0
    end
    if game.chaos_active then
        game.chaos_modifier = chaos.rollModifier()
        game.chaos_banner_timer = 3.5
    end
end

-- Dev: clear bottom N rows of blocks
local function devClearRows(game, count)
    for r = G.ROWS, math.max(1, G.ROWS - count + 1), -1 do
        if game.grid[r] then
            for c = 1, G.COLS do
                game.grid[r][c] = nil
            end
        end
    end
    -- Remove pickups/mutagens in cleared rows
    for i = #game.pickups, 1, -1 do
        if game.pickups[i].row > G.ROWS - count then table.remove(game.pickups, i) end
    end
    for i = #game.mutagens, 1, -1 do
        if game.mutagens[i].row > G.ROWS - count then table.remove(game.mutagens, i) end
    end
end

-- Mutation key map: number keys 1-6 map to mutation types
local DEV_MUTATION_KEYS = { "1", "2", "3", "4", "5", "6" }

function handlers.aiming.keypressed(game, key)
    if not game.dev_mode then return end

    if key == "n" then devSkipLevels(game, 1)
    elseif key == "m" then devSkipLevels(game, 10)
    elseif key == "c" then devClearRows(game, 5)
    elseif key == "b" then game.ball_count = game.ball_count + 10
    elseif key == "v" then game.ball_count = game.ball_count + 100
    elseif key == "t" then
        -- Toggle chaos zone on/off
        game.chaos_active = not game.chaos_active
        if game.chaos_active then
            game.chaos_zone_flash = 3.0
            game.chaos_modifier = chaos.rollModifier()
            game.chaos_banner_timer = 3.5
        else
            game.chaos_modifier = nil
        end
    else
        -- 1-6: add a stack of the corresponding mutation
        for i, k in ipairs(DEV_MUTATION_KEYS) do
            if key == k then
                local mkey = mutations.ORDER[i]
                game.mutations[mkey] = (game.mutations[mkey] or 0) + 1
                if not game.chaos_active then
                    game.chaos_active = true
                    game.chaos_zone_flash = 3.0
                end
                break
            end
        end
    end
end

----------------------------------------------------------------
-- LAUNCHING
----------------------------------------------------------------
handlers.launching = {}

function handlers.launching.update(game, dt)
    local count = game.effective_ball_count or game.ball_count
    game.launch_timer = game.launch_timer + dt
    while game.balls_launched < count and game.launch_timer >= G.LAUNCH_DELAY do
        game.launch_timer = game.launch_timer - G.LAUNCH_DELAY
        game.balls_launched = game.balls_launched + 1
        local b = ball.create(game.launch_x, G.FLOOR_Y, game.aim_vx, game.aim_vy, game)
        table.insert(game.balls, b)
    end

    -- Update existing balls
    ball.updateAll(game, dt)

    if game.balls_launched >= count then
        game.state = "resolving"
    end
end

function handlers.launching.draw(game)
    ball.drawAll(game)
    -- Show launch point and remaining count
    local remaining = (game.effective_ball_count or game.ball_count) - game.balls_launched
    if remaining > 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", game.launch_x, G.FLOOR_Y, G.BALL_RADIUS)
        love.graphics.printf("x" .. remaining, game.launch_x - 30, G.FLOOR_Y + 8, 60, "center")
    end
end

function handlers.launching.mousepressed() end
function handlers.launching.mousemoved() end
function handlers.launching.mousereleased() end
function handlers.launching.keypressed(game, key)
    if key == "space" then
        if game.speed_mult == 1 then game.speed_mult = 3
        elseif game.speed_mult == 3 then game.speed_mult = 6
        elseif game.speed_mult == 6 then game.speed_mult = 9
        else game.speed_mult = 1 end
    end
end

----------------------------------------------------------------
-- RESOLVING
----------------------------------------------------------------
handlers.resolving = {}

function handlers.resolving.update(game, dt)
    ball.updateAll(game, dt)

    -- Check if all balls collected
    local all_done = true
    for _, b in ipairs(game.balls) do
        if b.active then
            all_done = false
            break
        end
    end

    if all_done then
        game.state = "collecting"
        game.collect_timer = 0
        game.speed_mult = 1
    end
end

function handlers.resolving.draw(game)
    ball.drawAll(game)
end

function handlers.resolving.mousepressed() end
function handlers.resolving.mousemoved() end
function handlers.resolving.mousereleased() end
function handlers.resolving.keypressed(game, key)
    if key == "space" then
        if game.speed_mult == 1 then game.speed_mult = 3
        elseif game.speed_mult == 3 then game.speed_mult = 6
        elseif game.speed_mult == 6 then game.speed_mult = 9
        else game.speed_mult = 1 end
    end
end

----------------------------------------------------------------
-- COLLECTING
----------------------------------------------------------------
handlers.collecting = {}

function handlers.collecting.update(game, dt)
    game.collect_timer = game.collect_timer + dt
    if game.collect_timer >= 0.3 then
        -- Set new launch position
        if game.first_landed_x then
            game.launch_x = game.first_landed_x
        end
        -- Clamp launch_x to grid bounds
        game.launch_x = math.max(G.GRID_LEFT + G.BALL_RADIUS, math.min(G.GRID_RIGHT - G.BALL_RADIUS, game.launch_x))

        -- Transition to advancing
        game.state = "advancing"
        game.descend_offset = -G.CELL_SIZE

        -- Advance grid: shift all blocks and pickups down by 1 row
        -- Process from bottom to top to avoid overwriting
        for r = G.ROWS, 1, -1 do
            game.grid[r + 1] = game.grid[r]
        end
        game.grid[1] = {}

        for _, p in ipairs(game.pickups) do
            p.row = p.row + 1
        end
        for _, m in ipairs(game.mutagens) do
            m.row = m.row + 1
        end

        -- Generate new row at top
        game.level = game.level + 1
        local blocks, pickups, mutagens, void_block = G.generateRow(game.level)
        for _, b in ipairs(blocks) do
            game.grid[1][b.col] = { hp = b.hp, max_hp = b.max_hp }
        end
        for _, p in ipairs(pickups) do
            table.insert(game.pickups, { col = p.col, row = 1, collected = false })
        end
        for _, m in ipairs(mutagens) do
            table.insert(game.mutagens, {
                col = m.col, row = 1,
                type = mutations.rollMutagen(),
                collected = false,
            })
        end
        if void_block then
            game.grid[1][void_block.col] = { hp = math.huge, max_hp = 1, void = true }
        end

        -- Apply pending ball pickups
        game.ball_count = game.ball_count + game.pending_balls
        game.pending_balls = 0

        -- Apply pending mutations
        for _, mtype in ipairs(game.pending_mutations) do
            game.mutations[mtype] = (game.mutations[mtype] or 0) + 1
        end
        game.pending_mutations = {}

        -- Activate Chaos Zone at level 51
        if game.level > 50 and not game.chaos_active then
            game.chaos_active = true
            game.chaos_zone_flash = 3.0
        end

        -- Roll chaos modifier for next turn
        if game.chaos_active then
            game.chaos_modifier = chaos.rollModifier()
            game.chaos_banner_timer = 3.5
            -- Play announcement sound
            if game.chaos_modifier then
                audio.playChaosAnnounce()
            end
        end
        game.jackpot_mutagens = 0
        game.sniper_damage_mult = 1

        -- EARTHQUAKE: shift blocks randomly before next turn
        if chaos.isActive(game, "EARTHQUAKE") then
            local dir = math.random() < 0.5 and -1 or 1
            for r = 1, G.ROWS do
                if game.grid[r] then
                    local new_row = {}
                    for c = 1, G.COLS do
                        if game.grid[r][c] then
                            local nc = c + dir
                            if nc >= 1 and nc <= G.COLS and not new_row[nc] then
                                new_row[nc] = game.grid[r][c]
                            else
                                new_row[c] = game.grid[r][c]
                            end
                        end
                    end
                    game.grid[r] = new_row
                end
            end
            game.shake_timer = 0.3
            game.shake_intensity = 5
        end

        -- Remove void blocks within 3 rows of the bottom
        for r = G.ROWS - 2, G.ROWS + 1 do
            if game.grid[r] then
                for c = 1, G.COLS do
                    if game.grid[r][c] and game.grid[r][c].void then
                        game.grid[r][c] = nil
                    end
                end
            end
        end

        -- Remove mutagens that went off grid
        for i = #game.mutagens, 1, -1 do
            if game.mutagens[i].row > G.ROWS then
                table.remove(game.mutagens, i)
            end
        end
    end
end

function handlers.collecting.draw(game)
    -- Show launch point moving to new position
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", game.launch_x, G.FLOOR_Y, G.BALL_RADIUS)
end

function handlers.collecting.mousepressed() end
function handlers.collecting.mousemoved() end
function handlers.collecting.mousereleased() end
function handlers.collecting.keypressed() end

----------------------------------------------------------------
-- ADVANCING
----------------------------------------------------------------
handlers.advancing = {}

function handlers.advancing.update(game, dt)
    game.descend_offset = game.descend_offset + G.CELL_SIZE * dt / 0.3
    if game.descend_offset >= 0 then
        game.descend_offset = 0

        -- Check game over: any block below visible grid
        local game_over = false
        for r = G.ROWS + 1, G.ROWS + 1 do
            if game.grid[r] then
                for c = 1, G.COLS do
                    if game.grid[r][c] then
                        game_over = true
                        break
                    end
                end
            end
        end

        -- Also check row ROWS (bottom visible row) — blocks there are fine,
        -- but if they were pushed past it, game over
        if game_over then
            game.state = "game_over"
        else
            -- Clean up any row beyond ROWS (shouldn't have blocks if no game over)
            game.grid[G.ROWS + 1] = nil
            -- Remove pickups that went off grid
            for i = #game.pickups, 1, -1 do
                if game.pickups[i].row > G.ROWS then
                    table.remove(game.pickups, i)
                end
            end
            game.state = "aiming"
        end
    end
end

function handlers.advancing.draw(game)
    -- Launch point
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", game.launch_x, G.FLOOR_Y, G.BALL_RADIUS)
end

function handlers.advancing.mousepressed() end
function handlers.advancing.mousemoved() end
function handlers.advancing.mousereleased() end
function handlers.advancing.keypressed() end

----------------------------------------------------------------
-- GAME OVER
----------------------------------------------------------------
handlers.game_over = {}

function handlers.game_over.update(game, dt)
end

function handlers.game_over.draw(game)
    -- Darken overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 800, 800)

    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.printf("GAME OVER", 0, 300, 800, "center")

    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Level: " .. game.level .. "  Score: " .. game.score, 0, 360, 800, "center")

    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("Click or press any key to restart", 0, 420, 800, "center")
end

function handlers.game_over.mousepressed(game, x, y)
    game.resetGame()
end

function handlers.game_over.mousemoved() end
function handlers.game_over.mousereleased() end

function handlers.game_over.keypressed(game, key)
    if key ~= "escape" then
        game.resetGame()
    else
        love.event.quit()
    end
end

----------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------
function states.update(game, dt)
    local h = handlers[game.state]
    if h and h.update then h.update(game, dt) end
end

function states.draw(game)
    local h = handlers[game.state]
    if h and h.draw then h.draw(game, dt) end
end

function states.mousepressed(game, x, y)
    local h = handlers[game.state]
    if h and h.mousepressed then h.mousepressed(game, x, y) end
end

function states.mousemoved(game, x, y)
    local h = handlers[game.state]
    if h and h.mousemoved then h.mousemoved(game, x, y) end
end

function states.mousereleased(game, x, y)
    local h = handlers[game.state]
    if h and h.mousereleased then h.mousereleased(game, x, y) end
end

function states.keypressed(game, key)
    if key == "escape" and game.state ~= "game_over" then
        love.event.quit()
        return
    end
    local h = handlers[game.state]
    if h and h.keypressed then h.keypressed(game, key) end
end

return states
