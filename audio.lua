local audio = {}

local wallBounce
local blockHits = {}  -- indexed by combo level
local destroySound
local pickupSound
local mutagenSound
local chainExplosionSound
local voidAbsorbSound
local chaosAnnounceSound

local NUM_HIT_TONES = 20

local function generateTone(freq, duration, amplitude, decay_power)
    decay_power = decay_power or 2
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local envelope = math.max(0, 1 - t / duration) ^ decay_power
        local sample = math.sin(2 * math.pi * freq * t) * amplitude
        sample = sample + math.sin(2 * math.pi * freq * 2 * t) * amplitude * 0.2
        sample = sample * envelope
        soundData:setSample(i, sample)
    end
    return love.audio.newSource(soundData)
end

local function generateNoise(duration, amplitude)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local envelope = math.max(0, 1 - t / duration) ^ 3
        local sample = (math.random() * 2 - 1) * amplitude * envelope
        -- Mix in low tone for body
        sample = sample + math.sin(2 * math.pi * 200 * t) * amplitude * 0.3 * envelope
        soundData:setSample(i, sample)
    end
    return love.audio.newSource(soundData)
end

function audio.load()
    -- Wall bounce: soft tick
    wallBounce = generateTone(440, 0.04, 0.15, 3)

    -- Block hits: rising pitch with combo
    for i = 1, NUM_HIT_TONES do
        local freq = 300 + (i - 1) * 40  -- 300Hz to 1060Hz
        blockHits[i] = generateTone(freq, 0.06, 0.2, 2)
    end

    -- Block destroy: crunchy pop
    destroySound = generateNoise(0.15, 0.35)

    -- Pickup collect: pleasant chime
    pickupSound = generateTone(880, 0.15, 0.25, 2)

    -- Mutagen collect: deep warbling tone
    mutagenSound = generateTone(300, 0.25, 0.3, 2)

    -- Chain explosion: rumbling boom
    chainExplosionSound = generateNoise(0.3, 0.3)

    -- Void absorb: low dark whoosh
    voidAbsorbSound = generateTone(150, 0.2, 0.25, 3)

    -- Chaos announce: dramatic ascending tone
    chaosAnnounceSound = generateTone(600, 0.3, 0.25, 2)
end

local function playSound(source)
    local clone = source:clone()
    clone:play()
end

function audio.playWallBounce()
    playSound(wallBounce)
end

function audio.playBlockHit(combo)
    local idx = math.min(combo, NUM_HIT_TONES)
    if idx < 1 then idx = 1 end
    playSound(blockHits[idx])
end

function audio.playDestroy()
    playSound(destroySound)
end

function audio.playPickup()
    playSound(pickupSound)
end

function audio.playMutagenPickup()
    playSound(mutagenSound)
end

function audio.playChainExplosion()
    playSound(chainExplosionSound)
end

function audio.playVoidAbsorb()
    playSound(voidAbsorbSound)
end

function audio.playChaosAnnounce()
    playSound(chaosAnnounceSound)
end

return audio
