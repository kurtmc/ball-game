local G = require("grid")
local util = require("util")
local mut = require("mutations")
local chaos = require("chaos")

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

    -- Mutation icons (below ball count)
    if game.chaos_active then
        local mx = 310
        local my = 28
        love.graphics.setFont(fontSmall)
        for _, key in ipairs(mut.ORDER) do
            local stacks = game.mutations[key] or 0
            if stacks > 0 then
                local t = mut.TYPES[key]
                love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.9)
                love.graphics.circle("fill", mx, my + 4, 6)
                love.graphics.setColor(1, 1, 1)
                love.graphics.print(t.symbol .. stacks, mx + 8, my - 2)
                mx = mx + 32
            end
        end
        love.graphics.setFont(fontMedium)
    end

    -- Chaos modifier banner
    if game.chaos_active and game.chaos_modifier and game.chaos_banner_timer > 0 then
        local mod = game.chaos_modifier
        local alpha = math.min(1, game.chaos_banner_timer / 1.0)
        -- Dark background pill
        local bw, bh = 340, 48
        local bx, by = (800 - bw) / 2, 54
        love.graphics.setColor(0, 0, 0, alpha * 0.7)
        love.graphics.rectangle("fill", bx, by, bw, bh, 10, 10)
        -- Colored border
        love.graphics.setColor(mod.color[1], mod.color[2], mod.color[3], alpha * 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", bx, by, bw, bh, 10, 10)
        love.graphics.setLineWidth(1)
        -- Title text
        love.graphics.setFont(fontLarge)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(mod.name, 0, 58, 800, "center")
        -- Description text
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(1, 1, 1, alpha * 0.8)
        love.graphics.printf(mod.desc, 0, 83, 800, "center")
        love.graphics.setFont(fontMedium)
    elseif game.chaos_active and game.chaos_modifier then
        -- Persistent small indicator with background
        love.graphics.setFont(fontSmall)
        local mod = game.chaos_modifier
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", 596, 25, 198, 18, 4, 4)
        love.graphics.setColor(mod.color[1], mod.color[2], mod.color[3], 0.7)
        love.graphics.printf(mod.name, 600, 28, 190, "right")
        love.graphics.setFont(fontMedium)
    end

    -- Chaos Zone entrance flash
    if game.chaos_zone_flash > 0 then
        local alpha = math.min(1, game.chaos_zone_flash / 1.0)
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 8)
        love.graphics.setFont(fontLarge)
        love.graphics.setColor(0.8, 0.2, 1.0, alpha * pulse)
        love.graphics.printf("T H E   C H A O S   Z O N E", 0, 370, 800, "center")
        love.graphics.setFont(fontMedium)
    end

    -- Speed indicator during resolve
    if game.state == "launching" or game.state == "resolving" then
        if game.speed_mult > 1 then
            love.graphics.setColor(1, 1, 0.3)
            love.graphics.printf(">> " .. game.speed_mult .. "x", 0, 775, 800, "center")
        else
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.printf("[Space] to speed up", 0, 775, 800, "center")
        end
        -- Combo multiplier display
        local mult = math.max(1, math.ceil((game.combo or 0) / 10))
        if mult > 1 then
            love.graphics.setFont(fontLarge)
            love.graphics.setColor(1, 1, 0.2, 0.9)
            love.graphics.printf("x" .. mult .. " COMBO!", 0, 740, 800, "center")
            love.graphics.setFont(fontMedium)
        end
    end

    -- Draft selection screen
    if game.state == "drafting" then
        ui.drawDraft(game)
    end

    -- Dev mode panel
    if game.dev_mode and game.state == "aiming" then
        love.graphics.setFont(fontSmall)
        local dy = 620
        local dx = 10
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", dx - 4, dy - 4, 180, 170, 4, 4)
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.print("DEV MODE", dx, dy)
        love.graphics.setColor(1, 1, 1, 0.5)
        dy = dy + 14
        love.graphics.print("[N] +1 level  [M] +10", dx, dy); dy = dy + 12
        love.graphics.print("[C] clear bottom 5 rows", dx, dy); dy = dy + 12
        love.graphics.print("[B] +10 balls [V] +100", dx, dy); dy = dy + 12
        love.graphics.print("[T] toggle chaos zone", dx, dy); dy = dy + 14
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.print("Mutations:", dx, dy); dy = dy + 12
        for i, key in ipairs(mut.ORDER) do
            local t = mut.TYPES[key]
            local stacks = game.mutations[key] or 0
            love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.6)
            local label = string.format("[%d] %s", i, t.name)
            if stacks > 0 then label = label .. " x" .. stacks end
            love.graphics.print(label, dx, dy); dy = dy + 12
        end
        love.graphics.setFont(fontMedium)
    elseif game.dev_mode then
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(1, 1, 0, 0.3)
        love.graphics.print("DEV", 10, 780)
        love.graphics.setFont(fontMedium)
    end
end

function ui.drawDraft(game)
    if not game.draft_choices then return end

    local PANEL_W = 190
    local PANEL_H = 210
    local PANEL_GAP = 15
    local PANEL_Y = 290
    local total_w = 3 * PANEL_W + 2 * PANEL_GAP
    local start_x = (800 - total_w) / 2

    -- Dimmed background overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, 800, 800)

    -- Title
    love.graphics.setFont(fontLarge)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("MUTATION DRAFT", 0, 230, 800, "center")
    love.graphics.setFont(fontSmall)
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("Choose one  [1] [2] [3]", 0, 260, 800, "center")

    for i, mtype in ipairs(game.draft_choices) do
        local t = mut.TYPES[mtype]
        local px = start_x + (i - 1) * (PANEL_W + PANEL_GAP)

        -- Panel background
        love.graphics.setColor(t.color[1] * 0.2, t.color[2] * 0.2, t.color[3] * 0.2, 0.95)
        love.graphics.rectangle("fill", px, PANEL_Y, PANEL_W, PANEL_H, 10, 10)

        -- Colored border
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.8)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px, PANEL_Y, PANEL_W, PANEL_H, 10, 10)
        love.graphics.setLineWidth(1)

        -- Key hint
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.6)
        love.graphics.printf("[" .. i .. "]", px, PANEL_Y + 10, PANEL_W, "center")

        -- Mutation symbol circle
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.9)
        love.graphics.circle("fill", px + PANEL_W / 2, PANEL_Y + 65, 22)
        love.graphics.setFont(fontLarge)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(t.symbol, px, PANEL_Y + 54, PANEL_W, "center")

        -- Mutation name
        love.graphics.setFont(fontMedium)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(t.name, px, PANEL_Y + 100, PANEL_W, "center")

        -- Description
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
        love.graphics.printf(t.desc, px + 8, PANEL_Y + 125, PANEL_W - 16, "center")

        -- Current stacks indicator
        local stacks = game.mutations[mtype] or 0
        if stacks > 0 then
            love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.7)
            love.graphics.printf("Current: x" .. stacks, px, PANEL_Y + 175, PANEL_W, "center")
        else
            love.graphics.setColor(0.4, 0.4, 0.4, 0.7)
            love.graphics.printf("New!", px, PANEL_Y + 175, PANEL_W, "center")
        end
    end

    love.graphics.setFont(fontMedium)
end

function ui.drawGrid(game)
    local offset_y = game.descend_offset or 0
    local time = love.timer.getTime()

    -- Draw boundary lines (left, right, floor)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.setLineWidth(2)
    love.graphics.line(G.GRID_LEFT, G.GRID_TOP, G.GRID_LEFT, G.FLOOR_Y)    -- left wall
    love.graphics.line(G.GRID_RIGHT, G.GRID_TOP, G.GRID_RIGHT, G.FLOOR_Y)  -- right wall
    love.graphics.line(G.GRID_LEFT, G.FLOOR_Y, G.GRID_RIGHT, G.FLOOR_Y)    -- floor
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
                        if block.void then
                            -- Void block: black with pulsing purple border
                            love.graphics.setColor(0.05, 0.02, 0.08)
                            love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
                            local pulse = 0.4 + 0.3 * math.sin(time * 3 + bx * 0.1)
                            love.graphics.setColor(0.5, 0.1, 0.7, pulse)
                            love.graphics.setLineWidth(2)
                            love.graphics.rectangle("line", bx, by, bw, bh, 6, 6)
                            love.graphics.setLineWidth(1)
                            -- Swirl dots
                            for s = 1, 3 do
                                local angle = time * 2 + s * 2.09
                                local sr = bw * 0.25
                                local sx = bx + bw/2 + math.cos(angle) * sr
                                local sy = by + bh/2 + math.sin(angle) * sr
                                love.graphics.setColor(0.6, 0.2, 0.9, 0.5)
                                love.graphics.circle("fill", sx, sy, 3)
                            end
                        else
                            -- Normal block
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
    end

    -- Draw pickups
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

    -- Draw mutagen orbs
    for _, m in ipairs(game.mutagens) do
        if not m.collected then
            local mx, my = G.gridToPixelCenter(m.col, m.row)
            my = my + offset_y
            if my > G.GRID_TOP and my < G.FLOOR_Y then
                local pulse = 0.6 + 0.4 * math.sin(time * 5 + mx * 0.05)
                if m.draft then
                    -- Draft orb: gold with rotating star ring and "?" symbol
                    love.graphics.setColor(1.0, 0.85, 0.0, pulse * 0.3)
                    love.graphics.circle("fill", mx, my, G.PICKUP_RADIUS + 6)
                    love.graphics.setColor(1.0, 0.85, 0.0, pulse)
                    love.graphics.circle("fill", mx, my, G.PICKUP_RADIUS)
                    -- Rotating sparkle dots
                    for s = 1, 4 do
                        local angle = time * 3 + s * 1.5708
                        local sr = G.PICKUP_RADIUS + 3
                        local sx = mx + math.cos(angle) * sr
                        local sy = my + math.sin(angle) * sr
                        love.graphics.setColor(1.0, 1.0, 0.5, pulse * 0.8)
                        love.graphics.circle("fill", sx, sy, 2)
                    end
                    love.graphics.setColor(0.1, 0.05, 0, pulse)
                    love.graphics.setFont(fontSmall)
                    love.graphics.printf("?", mx - 10, my - 7, 20, "center")
                else
                    local t = mut.TYPES[m.type]
                    -- Outer glow
                    love.graphics.setColor(t.color[1], t.color[2], t.color[3], pulse * 0.3)
                    love.graphics.circle("fill", mx, my, G.PICKUP_RADIUS + 4)
                    -- Inner orb
                    love.graphics.setColor(t.color[1], t.color[2], t.color[3], pulse)
                    love.graphics.circle("fill", mx, my, G.PICKUP_RADIUS)
                    -- Symbol
                    love.graphics.setColor(1, 1, 1, pulse)
                    love.graphics.setFont(fontSmall)
                    love.graphics.printf(t.symbol, mx - 10, my - 7, 20, "center")
                end
            end
        end
    end

    love.graphics.setFont(fontMedium)
end

return ui
