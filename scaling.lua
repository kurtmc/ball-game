local scaling = {}

-- The game is designed for 800x800 (square). On taller-than-square screens
-- (portrait phones), scaling.GAME_HEIGHT stretches to match the screen's
-- aspect ratio so the game fills the full width without letterbox bars.
-- The grid stays at y=40..755 (top of canvas); the extra vertical slack
-- becomes the aim-drag zone and hosts the bottom UI.
scaling.GAME_WIDTH = 800
scaling.GAME_HEIGHT = 800

scaling.scale = 1
scaling.offset_x = 0
scaling.offset_y = 0

function scaling.update()
    local w, h = love.graphics.getDimensions()
    local aspect = h / w
    if aspect > 1 then
        scaling.GAME_HEIGHT = scaling.GAME_WIDTH * aspect
    else
        scaling.GAME_HEIGHT = scaling.GAME_WIDTH
    end
    scaling.scale = math.min(w / scaling.GAME_WIDTH, h / scaling.GAME_HEIGHT)
    scaling.offset_x = (w - scaling.GAME_WIDTH * scaling.scale) / 2
    scaling.offset_y = (h - scaling.GAME_HEIGHT * scaling.scale) / 2
end

-- Apply the transform for drawing
function scaling.push()
    love.graphics.push()
    love.graphics.translate(scaling.offset_x, scaling.offset_y)
    love.graphics.scale(scaling.scale)
end

function scaling.pop()
    love.graphics.pop()
end

-- Convert screen coordinates to game coordinates
function scaling.toGame(sx, sy)
    local gx = (sx - scaling.offset_x) / scaling.scale
    local gy = (sy - scaling.offset_y) / scaling.scale
    return gx, gy
end

return scaling
