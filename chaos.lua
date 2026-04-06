local chaos = {}

-- Chaos modifier definitions
chaos.MODIFIERS = {
    { name = "GRAVITY",       desc = "Balls curve downward!",        color = {0.8, 0.4, 1.0} },
    { name = "PORTAL_WALLS",  desc = "Walls wrap around!",           color = {0.2, 1.0, 0.8} },
    { name = "BIG_BALLS",     desc = "Ball size x3!",                color = {1.0, 1.0, 0.3} },
    { name = "SNIPER",        desc = "One ball, massive damage!",    color = {1.0, 0.2, 0.2} },
    { name = "EARTHQUAKE",    desc = "Blocks shift around!",         color = {0.7, 0.5, 0.3} },
    { name = "JACKPOT",       desc = "Destroyed blocks drop mutagens!", color = {1.0, 0.85, 0.0} },
    { name = "TRIPLE_THREAT", desc = "Triple the balls!",            color = {0.3, 1.0, 0.3} },
}

-- Roll a random chaos modifier. ~25% chance of nil (no modifier)
function chaos.rollModifier()
    if math.random() < 0.25 then return nil end
    return chaos.MODIFIERS[math.random(#chaos.MODIFIERS)]
end

-- Check if a specific modifier is active
function chaos.isActive(game, name)
    return game.chaos_modifier ~= nil and game.chaos_modifier.name == name
end

-- Get effective ball count for this turn (handles SNIPER and TRIPLE overrides)
function chaos.getEffectiveBallCount(game)
    if chaos.isActive(game, "SNIPER") then
        return 1
    elseif chaos.isActive(game, "TRIPLE_THREAT") then
        return game.ball_count * 3
    end
    return game.ball_count
end

-- Get effective damage multiplier from chaos modifiers
function chaos.getDamageMult(game)
    if chaos.isActive(game, "SNIPER") then
        return game.ball_count  -- 1 ball does damage equal to total ball count
    end
    return 1
end

-- Get effective ball radius multiplier
function chaos.getBallRadiusMult(game)
    if chaos.isActive(game, "BIG_BALLS") then
        return 3
    end
    return 1
end

return chaos
