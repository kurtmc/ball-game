local G = require("grid")
local aiming = require("aiming")
local ball = require("ball")
local audio = require("audio")
local particles = require("particles")

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
    end
end

function handlers.aiming.keypressed(game, key)
end

----------------------------------------------------------------
-- LAUNCHING
----------------------------------------------------------------
handlers.launching = {}

function handlers.launching.update(game, dt)
    game.launch_timer = game.launch_timer + dt
    while game.balls_launched < game.ball_count and game.launch_timer >= G.LAUNCH_DELAY do
        game.launch_timer = game.launch_timer - G.LAUNCH_DELAY
        game.balls_launched = game.balls_launched + 1
        local b = ball.create(game.launch_x, G.FLOOR_Y, game.aim_vx, game.aim_vy)
        table.insert(game.balls, b)
    end

    -- Update existing balls
    ball.updateAll(game, dt)

    if game.balls_launched >= game.ball_count then
        game.state = "resolving"
    end
end

function handlers.launching.draw(game)
    ball.drawAll(game)
    -- Show launch point and remaining count
    local remaining = game.ball_count - game.balls_launched
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
        game.speed_mult = game.speed_mult == 1 and 3 or 1
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
        game.speed_mult = game.speed_mult == 1 and 3 or 1
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

        -- Generate new row at top
        game.level = game.level + 1
        local blocks, pickups = G.generateRow(game.level)
        for _, b in ipairs(blocks) do
            game.grid[1][b.col] = { hp = b.hp, max_hp = b.max_hp }
        end
        for _, p in ipairs(pickups) do
            table.insert(game.pickups, { col = p.col, row = 1, collected = false })
        end

        -- Apply pending ball pickups
        game.ball_count = game.ball_count + game.pending_balls
        game.pending_balls = 0
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
