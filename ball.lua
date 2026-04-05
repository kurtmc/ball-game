local G = require("grid")
local physics = require("physics")

local ball = {}

local MAX_BOUNCES = 10000
local MAX_TIME = 300
local TRAIL_LEN = 8

function ball.create(x, y, vx, vy)
    return {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        active = true,
        bounces = 0,
        alive_time = 0,
        trail = {},
        trail_timer = 0,
    }
end

function ball.updateOne(b, game, dt)
    if not b.active then return end

    b.alive_time = b.alive_time + dt

    -- Trail update
    b.trail_timer = b.trail_timer + dt
    if b.trail_timer >= 0.016 then  -- ~60fps trail sampling
        b.trail_timer = 0
        table.insert(b.trail, { x = b.x, y = b.y })
        if #b.trail > TRAIL_LEN then
            table.remove(b.trail, 1)
        end
    end

    -- Stuck detection
    if b.bounces >= MAX_BOUNCES or b.alive_time >= MAX_TIME then
        b.active = false
        b.x = math.max(G.GRID_LEFT + G.BALL_RADIUS, math.min(G.GRID_RIGHT - G.BALL_RADIUS, b.x))
        return b.x  -- return landing x
    end

    local remaining = dt
    local safety = 0

    while remaining > 1e-7 and safety < 30 do
        safety = safety + 1

        local t, hit_type, hit_data = physics.castRay(b.x, b.y, b.vx, b.vy, game.grid, remaining)

        if hit_type and t < remaining then
            -- Advance to collision point
            b.x = b.x + b.vx * t
            b.y = b.y + b.vy * t
            remaining = remaining - t

            if hit_type == "floor" then
                b.y = G.FLOOR_Y
                b.active = false
                return b.x  -- return landing x
            end

            -- Reflect
            b.vx, b.vy = physics.reflect(b.vx, b.vy, hit_type, hit_data)
            b.bounces = b.bounces + 1

            -- Handle block damage
            if hit_type == "block" then
                local block = game.grid[hit_data.row][hit_data.col]
                if block then
                    block.hp = block.hp - 1
                    game.combo = game.combo + 1

                    if block.hp <= 0 then
                        -- Destroy block
                        local audio = require("audio")
                        audio.playDestroy()
                        game.grid[hit_data.row][hit_data.col] = nil
                        game.score = game.score + 1

                        -- Spawn particles
                        local particles = require("particles")
                        local cx, cy = G.gridToPixelCenter(hit_data.col, hit_data.row)
                        local cr, cg, cb = G.blockColor(block.max_hp, game.level)
                        particles.spawn(cx, cy, cr, cg, cb, 15)

                        -- Screen shake
                        game.shake_timer = 0.1
                        game.shake_intensity = 3
                    else
                        local audio = require("audio")
                        audio.playBlockHit(game.combo)
                    end
                end
            else
                -- Wall hit sound
                local audio = require("audio")
                audio.playWallBounce()
            end

            -- Nudge away from collision surface to prevent re-hit
            b.x = b.x + b.vx * 0.0001
            b.y = b.y + b.vy * 0.0001
        else
            -- No collision in remaining time, advance freely
            b.x = b.x + b.vx * remaining
            b.y = b.y + b.vy * remaining
            remaining = 0
        end
    end

    -- Check pickup collisions (balls pass through pickups)
    for _, p in ipairs(game.pickups) do
        if not p.collected then
            local px, py = G.gridToPixelCenter(p.col, p.row)
            local dx = b.x - px
            local dy = b.y - py
            if dx * dx + dy * dy < (G.BALL_RADIUS + G.PICKUP_RADIUS) * (G.BALL_RADIUS + G.PICKUP_RADIUS) then
                p.collected = true
                game.pending_balls = game.pending_balls + 1
                local audio = require("audio")
                audio.playPickup()
            end
        end
    end

    return nil  -- still active
end

function ball.updateAll(game, dt)
    local effective_dt = dt * game.speed_mult
    for _, b in ipairs(game.balls) do
        if b.active then
            local landed_x = ball.updateOne(b, game, effective_dt)
            if landed_x then
                table.insert(game.landed_balls, landed_x)
                if not game.first_landed_x then
                    game.first_landed_x = landed_x
                end
            end
        end
    end

    -- Remove collected pickups
    for i = #game.pickups, 1, -1 do
        if game.pickups[i].collected then
            table.remove(game.pickups, i)
        end
    end
end

function ball.drawAll(game)
    for _, b in ipairs(game.balls) do
        -- Draw trail
        for i, t in ipairs(b.trail) do
            local alpha = i / #b.trail * 0.4
            local size = G.BALL_RADIUS * (i / #b.trail) * 0.7
            love.graphics.setColor(0.8, 0.8, 1, alpha)
            love.graphics.circle("fill", t.x, t.y, size)
        end

        -- Draw ball (even if inactive, briefly show at final position)
        if b.active then
            love.graphics.setColor(1, 1, 1)
            love.graphics.circle("fill", b.x, b.y, G.BALL_RADIUS)
            -- Small highlight
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("fill", b.x - 2, b.y - 2, G.BALL_RADIUS * 0.4)
        end
    end
end

return ball
