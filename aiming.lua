local G = require("grid")
local physics = require("physics")
local chaos = require("chaos")
local util = require("util")

local aiming = {}

local MIN_ANGLE = 0.035  -- ~2 degrees from horizontal

function aiming.mousepressed(game, x, y)
    if y < G.FLOOR_Y then
        game.aim_active = true
        aiming.updateAngle(game, x, y)
    end
end

function aiming.mousemoved(game, x, y)
    if game.aim_active then
        aiming.updateAngle(game, x, y)
    end
end

function aiming.updateAngle(game, mx, my)
    if my >= G.FLOOR_Y - 5 then
        game.aim_angle = nil  -- cancel zone
        return
    end

    local dx = mx - game.launch_x
    local dy = -(my - G.FLOOR_Y)  -- flip y so up is positive

    local angle = math.atan2(dy, dx)
    -- Clamp to avoid horizontal shots
    angle = util.clamp(angle, MIN_ANGLE, math.pi - MIN_ANGLE)

    game.aim_angle = angle
    game.aim_vx = G.BALL_SPEED * math.cos(angle)
    game.aim_vy = -G.BALL_SPEED * math.sin(angle)  -- negative because screen y is down
end

function aiming.mousereleased(game, x, y)
    if not game.aim_active then return false end
    game.aim_active = false

    if game.aim_angle then
        return true  -- launch
    end
    return false  -- cancelled
end

function aiming.draw(game)
    if not game.aim_active or not game.aim_angle then return end

    local ball_radius = G.BALL_RADIUS * chaos.getBallRadiusMult(game)
    local is_gravity = chaos.isActive(game, "GRAVITY")
    local is_portal  = chaos.isActive(game, "PORTAL_WALLS")

    local ox, oy = game.launch_x, G.FLOOR_Y
    local vx, vy = game.aim_vx, game.aim_vy

    if is_gravity then
        drawSimulatedPreview(ox, oy, vx, vy, game, ball_radius, is_portal)
    else
        drawRaycastPreview(ox, oy, vx, vy, game, ball_radius, is_portal)
    end
end

-- Ray-cast based preview: accurate for straight-line flight (no gravity).
-- Handles PORTAL_WALLS wrap and correct ball radius for BIG_BALLS.
function drawRaycastPreview(ox, oy, vx, vy, game, ball_radius, is_portal)
    local t1, type1, data1 = physics.castRay(ox, oy, vx, vy, game.grid, 2.0, ball_radius)
    local hx1 = ox + vx * t1
    local hy1 = oy + vy * t1
    drawDottedLine(ox, oy, hx1, hy1, 1, 1, 1, 0.6)

    if not type1 or type1 == "floor" then return end

    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", hx1, hy1, 3)

    -- Compute second segment start and direction, accounting for portal wrap
    local nvx, nvy, nx, ny
    if is_portal and (type1 == "wall_left" or type1 == "wall_right") then
        nvx, nvy = vx, vy
        if type1 == "wall_left" then
            nx = G.GRID_RIGHT - ball_radius - 0.1
        else
            nx = G.GRID_LEFT + ball_radius + 0.1
        end
        ny = hy1
    else
        nvx, nvy = physics.reflect(vx, vy, type1, data1)
        nx, ny = hx1 + nvx * 0.001, hy1 + nvy * 0.001
    end

    local t2 = physics.castRay(nx, ny, nvx, nvy, game.grid, 0.5, ball_radius)
    local hx2 = nx + nvx * t2
    local hy2 = ny + nvy * t2
    drawDottedLine(nx, ny, hx2, hy2, 1, 1, 1, 0.3)
end

-- Step-simulation preview for GRAVITY: curves the trajectory visually.
-- Also handles PORTAL_WALLS. Simulates up to 3 wall/ceiling bounces.
function drawSimulatedPreview(ox, oy, vx, vy, game, ball_radius, is_portal)
    local x, y = ox, oy
    local cvx, cvy = vx, vy
    local bounces = 0
    local prev_x, prev_y = x, y
    local DT = 0.01
    local STEPS = 150

    for step = 1, STEPS do
        -- Apply gravity exactly as ball.lua does each sub-step
        cvy = cvy + 400 * DT
        local spd = math.sqrt(cvx * cvx + cvy * cvy)
        if spd > 0 then
            cvx = cvx / spd * G.BALL_SPEED
            cvy = cvy / spd * G.BALL_SPEED
        end

        local t, hit_type, hit_data = physics.castRay(x, y, cvx, cvy, game.grid, DT, ball_radius)
        local alpha = math.max(0.1, 0.6 - step / STEPS * 0.4)

        if hit_type and t < DT then
            local hx = x + cvx * t
            local hy = y + cvy * t
            drawDottedLine(prev_x, prev_y, hx, hy, 1, 1, 1, alpha)
            x, y = hx, hy

            if hit_type == "floor" or hit_type == "block" then break end

            love.graphics.setColor(1, 1, 1, alpha * 0.8)
            love.graphics.circle("fill", x, y, 3)

            if is_portal and (hit_type == "wall_left" or hit_type == "wall_right") then
                if hit_type == "wall_left" then
                    x = G.GRID_RIGHT - ball_radius - 0.1
                else
                    x = G.GRID_LEFT + ball_radius + 0.1
                end
            else
                cvx, cvy = physics.reflect(cvx, cvy, hit_type, hit_data)
            end

            bounces = bounces + 1
            if bounces >= 3 then break end
            prev_x, prev_y = x, y
        else
            x = x + cvx * DT
            y = y + cvy * DT
            drawDottedLine(prev_x, prev_y, x, y, 1, 1, 1, alpha)
            prev_x, prev_y = x, y
        end
    end
end

function drawDottedLine(x1, y1, x2, y2, r, g, b, a)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.floor(dist / 10)
    if steps < 1 then steps = 1 end

    love.graphics.setColor(r, g, b, a)
    for i = 0, steps do
        local t = i / steps
        local px = x1 + dx * t
        local py = y1 + dy * t
        love.graphics.circle("fill", px, py, 2)
    end
end

return aiming
