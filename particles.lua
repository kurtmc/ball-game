local particles = {}

local active = {}

function particles.spawn(x, y, r, g, b, count)
    count = count or 15
    for _ = 1, count do
        table.insert(active, {
            x = x,
            y = y,
            vx = (math.random() - 0.5) * 300,
            vy = (math.random() - 0.5) * 300 - 100,
            size = math.random(2, 6),
            r = r, g = g, b = b,
            life = math.random() * 0.6 + 0.2,
            maxLife = 0.8,
        })
    end
end

function particles.update(dt)
    for i = #active, 1, -1 do
        local p = active[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 400 * dt  -- gravity
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(active, i)
        end
    end
end

function particles.draw()
    for _, p in ipairs(active) do
        local alpha = math.max(0, p.life / p.maxLife)
        love.graphics.setColor(p.r, p.g, p.b, alpha)
        love.graphics.circle("fill", p.x, p.y, p.size * alpha)
    end
end

-- Void absorb: dark implosion (particles move INWARD)
function particles.spawnVoidAbsorb(x, y)
    for _ = 1, 12 do
        local angle = math.random() * math.pi * 2
        local dist = math.random(20, 40)
        table.insert(active, {
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist,
            vx = -math.cos(angle) * 150,
            vy = -math.sin(angle) * 150,
            size = math.random(2, 5),
            r = 0.4, g = 0.1, b = 0.6,
            life = 0.4,
            maxLife = 0.5,
        })
    end
end

function particles.clear()
    active = {}
end

return particles
