local G = require("grid")
local physics = require("physics")
local mutations = require("mutations")
local chaos = require("chaos")

local ball = {}

local MAX_BOUNCES = 10000
local MAX_TIME = 300
local TRAIL_LEN = 8
local MAX_ACTIVE_BALLS = 500

function ball.create(x, y, vx, vy, game)
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
        -- Mutation state per ball
        ghost_remaining = game and mutations.getPhaseCount(game) or 0,
        has_split = false,
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
    local ball_radius = G.BALL_RADIUS * chaos.getBallRadiusMult(game)
    local is_gravity = chaos.isActive(game, "GRAVITY")
    local is_portal = chaos.isActive(game, "PORTAL_WALLS")
    local damage = mutations.getDamage(game) * chaos.getDamageMult(game)
    local drunk_angle = mutations.getDrunkAngle(game)
    local magnet_str = mutations.getMagnetStrength(game)

    while remaining > 1e-7 and safety < 30 do
        safety = safety + 1

        -- GRAVITY: bend velocity downward each sub-step
        if is_gravity then
            b.vy = b.vy + 400 * math.min(remaining, 0.016)
            -- Renormalize to keep speed consistent
            local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
            if spd > 0 then
                local target = G.BALL_SPEED
                b.vx = b.vx / spd * target
                b.vy = b.vy / spd * target
            end
        end

        local t, hit_type, hit_data = physics.castRay(b.x, b.y, b.vx, b.vy, game.grid, remaining, ball_radius)

        if hit_type and t < remaining then
            -- Advance to collision point
            b.x = b.x + b.vx * t
            b.y = b.y + b.vy * t
            remaining = remaining - t

            if hit_type == "floor" then
                b.y = G.FLOOR_Y
                b.active = false
                return b.x
            end

            -- Determine if we should reflect
            local should_reflect = true
            local is_block = (hit_type == "block")
            local block = nil

            if is_block then
                block = game.grid[hit_data.row][hit_data.col]
            end

            -- VOID BLOCK: absorb ball or ghost through
            local phase_through = false
            if is_block and block and block.void then
                if b.ghost_remaining > 0 then
                    b.ghost_remaining = b.ghost_remaining - 1
                    should_reflect = false
                    phase_through = true
                else
                    -- Ball absorbed
                    b.active = false
                    local audio = require("audio")
                    audio.playVoidAbsorb()
                    local particles = require("particles")
                    local cx, cy = G.gridToPixelCenter(hit_data.col, hit_data.row)
                    particles.spawn(cx, cy, 0.4, 0.1, 0.6, 10)
                    return b.x
                end
            -- GHOST: phase through normal blocks
            elseif is_block and block and b.ghost_remaining > 0 then
                b.ghost_remaining = b.ghost_remaining - 1
                should_reflect = false
                phase_through = true
            end

            -- PORTAL WALLS: wrap instead of reflect
            if is_portal and (hit_type == "wall_left" or hit_type == "wall_right") then
                should_reflect = false
                if hit_type == "wall_left" then
                    b.x = G.GRID_RIGHT - ball_radius - 0.1
                else
                    b.x = G.GRID_LEFT + ball_radius + 0.1
                end
                -- Keep same velocity (no reflect)
            end

            -- Apply reflection if needed
            if should_reflect then
                b.vx, b.vy = physics.reflect(b.vx, b.vy, hit_type, hit_data)
            end
            b.bounces = b.bounces + 1

            -- Handle block damage (skip void blocks)
            if is_block and block and not block.void then
                block.hp = block.hp - damage
                game.combo = game.combo + 1

                -- SPLITTER: split on first block hit
                if not b.has_split and mutations.getSplitCount(game) > 1 then
                    b.has_split = true
                    local split_n = mutations.getSplitCount(game) - 1
                    for s = 1, split_n do
                        local angle_offset = (s / (split_n + 1)) * math.pi - math.pi / 2
                        local base_angle = math.atan2(b.vy, b.vx)
                        local new_angle = base_angle + angle_offset * 0.5
                        table.insert(game.splitter_queue, {
                            x = b.x, y = b.y,
                            vx = G.BALL_SPEED * math.cos(new_angle),
                            vy = G.BALL_SPEED * math.sin(new_angle),
                        })
                    end
                end

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

                    -- KABOOM: chain explosion
                    if (game.mutations.kaboom or 0) > 0 then
                        mutations.chainExplosion(game, hit_data.row, hit_data.col)
                        game.shake_intensity = 5
                    end

                    -- JACKPOT: destroyed blocks drop mutagens
                    if chaos.isActive(game, "JACKPOT") and game.jackpot_mutagens < 20 then
                        game.jackpot_mutagens = game.jackpot_mutagens + 1
                        table.insert(game.mutagens, {
                            col = hit_data.col, row = hit_data.row,
                            type = mutations.rollMutagen(),
                            collected = false,
                        })
                    end
                else
                    local audio = require("audio")
                    audio.playBlockHit(game.combo)
                end
            elseif not is_block then
                -- Wall/ceiling hit sound (skip for portal wrap)
                if should_reflect then
                    local audio = require("audio")
                    audio.playWallBounce()
                end
            end

            -- DRUNK: random angle deviation after reflect
            if should_reflect and drunk_angle > 0 then
                local angle = math.atan2(b.vy, b.vx)
                local deviation = (math.random() * 2 - 1) * drunk_angle
                angle = angle + deviation
                local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                b.vx = spd * math.cos(angle)
                b.vy = spd * math.sin(angle)
            end

            -- MAGNET: curve toward nearest block after reflect
            if should_reflect and magnet_str > 0 then
                local best_dist2 = math.huge
                local best_bx, best_by
                for r = 1, G.ROWS + 1 do
                    if game.grid[r] then
                        for c = 1, G.COLS do
                            if game.grid[r][c] and not game.grid[r][c].void then
                                local bx, by = G.gridToPixelCenter(c, r)
                                local ddx = bx - b.x
                                local ddy = by - b.y
                                local d2 = ddx * ddx + ddy * ddy
                                if d2 < best_dist2 then
                                    best_dist2 = d2
                                    best_bx = bx
                                    best_by = by
                                end
                            end
                        end
                    end
                end
                if best_bx then
                    local to_x = best_bx - b.x
                    local to_y = best_by - b.y
                    local to_len = math.sqrt(to_x * to_x + to_y * to_y)
                    if to_len > 0 then
                        to_x = to_x / to_len
                        to_y = to_y / to_len
                        local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        b.vx = b.vx + to_x * spd * magnet_str
                        b.vy = b.vy + to_y * spd * magnet_str
                        -- Renormalize speed
                        local new_spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        if new_spd > 0 then
                            b.vx = b.vx / new_spd * spd
                            b.vy = b.vy / new_spd * spd
                        end
                    end
                end
            end

            -- Nudge away from collision surface to prevent re-hit
            if phase_through and is_block then
                -- Push fully through the block (cell_size + ball radius to clear it)
                local push_dist = (G.CELL_SIZE + ball_radius * 2) + 1
                local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                if spd > 0 then
                    local push_t = push_dist / spd
                    b.x = b.x + b.vx * push_t
                    b.y = b.y + b.vy * push_t
                    remaining = remaining - push_t
                end
            else
                b.x = b.x + b.vx * 0.0001
                b.y = b.y + b.vy * 0.0001
            end
        else
            -- No collision in remaining time, advance freely
            b.x = b.x + b.vx * remaining
            b.y = b.y + b.vy * remaining
            remaining = 0
        end
    end

    -- Check pickup collisions (balls pass through pickups)
    local pickup_r = G.BALL_RADIUS + G.PICKUP_RADIUS
    local pickup_r2 = pickup_r * pickup_r
    for _, p in ipairs(game.pickups) do
        if not p.collected then
            local px, py = G.gridToPixelCenter(p.col, p.row)
            local ddx = b.x - px
            local ddy = b.y - py
            if ddx * ddx + ddy * ddy < pickup_r2 then
                p.collected = true
                game.pending_balls = game.pending_balls + 1
                local audio = require("audio")
                audio.playPickup()
            end
        end
    end

    -- Check mutagen collisions
    for _, m in ipairs(game.mutagens) do
        if not m.collected then
            local mx, my = G.gridToPixelCenter(m.col, m.row)
            local ddx = b.x - mx
            local ddy = b.y - my
            if ddx * ddx + ddy * ddy < pickup_r2 then
                m.collected = true
                table.insert(game.pending_mutations, m.type)
                local audio = require("audio")
                audio.playMutagenPickup()
            end
        end
    end

    -- Out-of-bounds safety: if ball escaped playable area, force collect
    if b.active then
        local margin = 200
        if b.y >= G.FLOOR_Y or b.y < G.GRID_TOP - margin
           or b.x < G.GRID_LEFT - margin or b.x > G.GRID_RIGHT + margin
           or b.x ~= b.x or b.y ~= b.y then  -- NaN check
            b.active = false
            b.x = math.max(G.GRID_LEFT + G.BALL_RADIUS, math.min(G.GRID_RIGHT - G.BALL_RADIUS, b.x))
            if b.x ~= b.x then b.x = 400 end  -- NaN fallback
            return b.x
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

    -- Drain splitter queue (deferred to avoid iterator invalidation)
    if game.splitter_queue then
        for _, sq in ipairs(game.splitter_queue) do
            if #game.balls < MAX_ACTIVE_BALLS then
                local child = ball.create(sq.x, sq.y, sq.vx, sq.vy, game)
                child.has_split = true  -- prevent re-splitting
                table.insert(game.balls, child)
            end
        end
        game.splitter_queue = {}
    end

    -- Remove collected pickups
    for i = #game.pickups, 1, -1 do
        if game.pickups[i].collected then
            table.remove(game.pickups, i)
        end
    end
    -- Remove collected mutagens
    for i = #game.mutagens, 1, -1 do
        if game.mutagens[i].collected then
            table.remove(game.mutagens, i)
        end
    end
end

function ball.drawAll(game)
    local draw_radius = G.BALL_RADIUS * chaos.getBallRadiusMult(game)

    -- Determine trail color from strongest mutation
    local trail_r, trail_g, trail_b = 0.8, 0.8, 1.0
    if game.chaos_active then
        local best_key, best_count = nil, 0
        for _, key in ipairs(mutations.ORDER) do
            local count = game.mutations[key] or 0
            if count > best_count then
                best_count = count
                best_key = key
            end
        end
        if best_key then
            local t = mutations.TYPES[best_key]
            trail_r, trail_g, trail_b = t.color[1], t.color[2], t.color[3]
        end
    end

    for _, b in ipairs(game.balls) do
        -- Draw trail
        for i, t in ipairs(b.trail) do
            local alpha = i / #b.trail * 0.4
            local size = draw_radius * (i / #b.trail) * 0.7
            love.graphics.setColor(trail_r, trail_g, trail_b, alpha)
            love.graphics.circle("fill", t.x, t.y, size)
        end

        -- Draw ball
        if b.active then
            love.graphics.setColor(1, 1, 1)
            love.graphics.circle("fill", b.x, b.y, draw_radius)
            -- Small highlight
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("fill", b.x - 2, b.y - 2, draw_radius * 0.4)
        end
    end
end

return ball
