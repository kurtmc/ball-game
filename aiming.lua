local G = require("grid")
local physics = require("physics")
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

    local ox = game.launch_x
    local oy = G.FLOOR_Y
    local vx = game.aim_vx
    local vy = game.aim_vy

    -- Cast ray for first segment
    local t1, type1, data1 = physics.castRay(ox, oy, vx, vy, game.grid, 2.0)
    local hx1 = ox + vx * t1
    local hy1 = oy + vy * t1

    -- Draw first segment as dotted line
    drawDottedLine(ox, oy, hx1, hy1, 1, 1, 1, 0.6)

    -- Draw bounce point
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", hx1, hy1, 3)

    -- Cast second segment (after reflection)
    if type1 and type1 ~= "floor" then
        local nvx, nvy = physics.reflect(vx, vy, type1, data1)
        local seg2_ox = hx1 + nvx * 0.001
        local seg2_oy = hy1 + nvy * 0.001
        local t2 = physics.castRay(seg2_ox, seg2_oy, nvx, nvy, game.grid, 0.5)
        local hx2 = seg2_ox + nvx * t2
        local hy2 = seg2_oy + nvy * t2
        drawDottedLine(seg2_ox, seg2_oy, hx2, hy2, 1, 1, 1, 0.3)
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
