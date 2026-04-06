local G = require("grid")
local states = require("states")
local ui = require("ui")
local particles = require("particles")
local updater = require("updater")

local game = {}
local dev_mode = false

local normal_bg = {0.08, 0.08, 0.12}
local chaos_bg  = {0.12, 0.05, 0.15}

local function resetGame()
    love.graphics.setBackgroundColor(unpack(normal_bg))
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
    love.graphics.setBackgroundColor(unpack(normal_bg))
    math.randomseed(os.time())
    dev_mode = not love.filesystem.isFused()
    ui.load()
    local audio = require("audio")
    audio.load()
    resetGame()
    game.resetGame = resetGame
    game.dev_mode = dev_mode
    updater.checkForUpdates()
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

    -- Background color shift in chaos zone
    if game.chaos_active then
        love.graphics.setBackgroundColor(unpack(chaos_bg))
    end
end

function love.draw()
    love.graphics.push()

    -- Apply screen shake
    if game.shake_timer > 0 then
        local sx = (math.random() - 0.5) * 2 * game.shake_intensity
        local sy = (math.random() - 0.5) * 2 * game.shake_intensity
        love.graphics.translate(sx, sy)
    end

    ui.drawGrid(game)
    states.draw(game)
    particles.draw()
    ui.drawHUD(game)

    love.graphics.pop()

    -- Draw update banner on top of everything (outside shake transform)
    updater.draw()
end

function love.mousepressed(x, y, button)
    if button == 1 then
        if updater.mousepressed(x, y) then return end
        states.mousepressed(game, x, y)
    end
end

function love.mousemoved(x, y)
    states.mousemoved(game, x, y)
end

function love.mousereleased(x, y, button)
    if button == 1 then
        states.mousereleased(game, x, y)
    end
end

function love.keypressed(key)
    if updater.keypressed(key) then return end
    states.keypressed(game, key)
end
