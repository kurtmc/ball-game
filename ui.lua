local G = require("grid")
local util = require("util")

local ui = {}

local fontSmall, fontMedium, fontLarge

function ui.load()
    fontSmall  = love.graphics.newFont(12)
    fontMedium = love.graphics.newFont(16)
    fontLarge  = love.graphics.newFont(22)
end

function ui.drawHUD(game)
    love.graphics.setFont(fontMedium)
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.printf("Level " .. game.level, 10, 10, 200, "left")
    love.graphics.printf("Score: " .. game.score, 590, 10, 200, "right")

    -- Ball count
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Balls: " .. game.ball_count, 300, 10, 200, "center")

    -- Speed indicator during resolve
    if game.state == "launching" or game.state == "resolving" then
        if game.speed_mult > 1 then
            love.graphics.setColor(1, 1, 0.3)
            love.graphics.printf(">> " .. game.speed_mult .. "x", 0, 775, 800, "center")
        else
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.printf("[Space] to speed up", 0, 775, 800, "center")
        end
    end
end

function ui.drawGrid(game)
    local offset_y = game.descend_offset or 0

    -- Draw floor line
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.setLineWidth(2)
    love.graphics.line(G.GRID_LEFT, G.FLOOR_Y, G.GRID_RIGHT, G.FLOOR_Y)
    love.graphics.setLineWidth(1)

    -- Draw blocks
    for r = 1, G.ROWS + 1 do
        if game.grid[r] then
            for c = 1, G.COLS do
                local block = game.grid[r][c]
                if block then
                    local bx, by, bw, bh = G.blockRect(c, r)
                    by = by + offset_y

                    -- Only draw if visible
                    if by + bh > G.GRID_TOP and by < G.FLOOR_Y then
                        -- Block body
                        local cr, cg, cb = G.blockColor(block.hp, game.level)
                        love.graphics.setColor(cr, cg, cb)
                        love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)

                        -- Slight border
                        love.graphics.setColor(cr * 0.7, cg * 0.7, cb * 0.7)
                        love.graphics.rectangle("line", bx, by, bw, bh, 6, 6)

                        -- HP text
                        local hp_str = tostring(block.hp)
                        if #hp_str >= 3 then
                            love.graphics.setFont(fontSmall)
                        else
                            love.graphics.setFont(fontMedium)
                        end
                        love.graphics.setColor(1, 1, 1)
                        love.graphics.printf(hp_str, bx, by + bh/2 - 8, bw, "center")
                    end
                end
            end
        end
    end

    -- Draw pickups
    local time = love.timer.getTime()
    for _, p in ipairs(game.pickups) do
        if not p.collected then
            local px, py = G.gridToPixelCenter(p.col, p.row)
            py = py + offset_y
            if py > G.GRID_TOP and py < G.FLOOR_Y then
                local pulse = 0.7 + 0.3 * math.sin(time * 4)
                love.graphics.setColor(1, 1, 1, pulse)
                love.graphics.circle("fill", px, py, G.PICKUP_RADIUS)
                love.graphics.setColor(0.3, 0.8, 0.3, pulse)
                love.graphics.setFont(fontMedium)
                love.graphics.printf("+", px - 10, py - 9, 20, "center")
            end
        end
    end

    love.graphics.setFont(fontMedium)
end

return ui
