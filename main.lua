local G = require("grid")
local states = require("states")
local ui = require("ui")
local particles = require("particles")
local updater = require("updater")
local scaling = require("scaling")

local game = {}
local dev_mode = false

local normal_bg = {0.08, 0.08, 0.12}
local chaos_bg  = {0.12, 0.05, 0.15}

local function resetGame()
    game.state          = "aiming"
    game.level          = 1
    game.score          = 0
    game.grid           = {}  -- grid[row][col] = {hp, max_hp}
    game.pickups        = {}  -- {col, row, collected}
    game.ball_count     = 1
    game.pending_balls  = 0
    game.launch_x       = 400
    game.balls          = {}
    game.landed_balls   = {}
    game.first_landed_x = nil
    game.aim_active     = false
    game.aim_angle      = nil
    game.aim_vx         = 0
    game.aim_vy         = 0
    game.descend_offset = 0
    game.shake_timer    = 0
    game.shake_intensity= 0
    game.launch_timer   = 0
    game.balls_launched = 0
    game.combo          = 0
    game.collect_timer  = 0
    game.speed_mult     = 1

    -- Chaos Zone state (post-level 50)
    game.chaos_active       = false
    game.mutations          = {}   -- {heavy=0, splitter=0, ghost=0, kaboom=0, drunk=0, magnet=0}
    game.chaos_modifier     = nil  -- current turn's chaos modifier table or nil
    game.mutagens           = {}   -- {col, row, type, collected} grid pickups
    game.pending_mutations  = {}   -- collected this turn, applied at turn end
    game.splitter_queue     = {}   -- deferred ball splits
    game.chaos_banner_timer = 0    -- countdown for modifier announcement
    game.chaos_zone_flash   = 0    -- entrance animation timer
    game.sniper_damage_mult = 1    -- damage multiplier for SNIPER modifier
    game.jackpot_mutagens   = 0    -- count of mutagens spawned this turn by JACKPOT

    -- Initialize grid rows
    for r = 1, G.ROWS do
        game.grid[r] = {}
    end

    -- Spawn initial rows in the top 4 rows
    for start_row = 1, 4 do
        local blocks, pickups = G.generateRow(game.level)
        for _, b in ipairs(blocks) do
            game.grid[start_row][b.col] = { hp = b.hp, max_hp = b.max_hp }
        end
        for _, p in ipairs(pickups) do
            table.insert(game.pickups, { col = p.col, row = start_row, collected = false })
        end
    end

    particles.clear()
end

function love.load()
    love.graphics.setBackgroundColor(0, 0, 0)
    math.randomseed(os.time())
    dev_mode = not love.filesystem.isFused()
    ui.load()
    local audio = require("audio")
    audio.load()
    resetGame()
    game.resetGame = resetGame
    game.dev_mode = dev_mode
    updater.checkForUpdates()
    scaling.update()
end

function love.update(dt)
    updater.update(dt)
    states.update(game, dt)
    particles.update(dt)

    -- Decay screen shake
    if game.shake_timer > 0 then
        game.shake_timer = game.shake_timer - dt
    end

    -- Decay chaos zone timers
    if game.chaos_banner_timer > 0 then
        game.chaos_banner_timer = game.chaos_banner_timer - dt
    end
    if game.chaos_zone_flash > 0 then
        game.chaos_zone_flash = game.chaos_zone_flash - dt
    end

    -- (background color handled in love.draw for scaling support)
end

function love.draw()
    -- Letterbox: fill bars with black
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    scaling.push()

    -- Apply screen shake
    if game.shake_timer > 0 then
        local sx = (math.random() - 0.5) * 2 * game.shake_intensity
        local sy = (math.random() - 0.5) * 2 * game.shake_intensity
        love.graphics.translate(sx, sy)
    end

    -- Draw background for game area
    local bg = game.chaos_active and chaos_bg or normal_bg
    love.graphics.setColor(bg[1], bg[2], bg[3])
    love.graphics.rectangle("fill", 0, 0, 800, 800)

    ui.drawGrid(game)
    states.draw(game)
    particles.draw()
    ui.drawHUD(game)

    scaling.pop()

    -- Draw update banner on top of everything (inside scaling but outside shake)
    scaling.push()
    updater.draw()
    scaling.pop()
end

function love.mousepressed(x, y, button)
    if button == 1 then
        local gx, gy = scaling.toGame(x, y)
        if updater.mousepressed(gx, gy) then return end
        states.mousepressed(game, gx, gy)
    end
end

function love.mousemoved(x, y)
    local gx, gy = scaling.toGame(x, y)
    states.mousemoved(game, gx, gy)
end

function love.mousereleased(x, y, button)
    if button == 1 then
        local gx, gy = scaling.toGame(x, y)
        states.mousereleased(game, gx, gy)
    end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    if game.state == "launching" or game.state == "resolving" then
        local gx, gy = scaling.toGame(x, y)
        if gy > 30 then  -- avoid update banner area
            if game.speed_mult == 1 then game.speed_mult = 3
            elseif game.speed_mult == 3 then game.speed_mult = 6
            elseif game.speed_mult == 6 then game.speed_mult = 9
            else game.speed_mult = 1 end
        end
    end
end

function love.resize(w, h)
    scaling.update()
end

local RESIZE_STEP = 100

function love.keypressed(key)
    if updater.keypressed(key) then return end
    if key == "=" or key == "kp+" then
        local w, h = love.graphics.getDimensions()
        love.window.setMode(w + RESIZE_STEP, h + RESIZE_STEP, {resizable = true, minwidth = 400, minheight = 400})
        scaling.update()
        return
    elseif key == "-" or key == "kp-" then
        local w, h = love.graphics.getDimensions()
        local nw = math.max(400, w - RESIZE_STEP)
        local nh = math.max(400, h - RESIZE_STEP)
        love.window.setMode(nw, nh, {resizable = true, minwidth = 400, minheight = 400})
        scaling.update()
        return
    end
    states.keypressed(game, key)
end
