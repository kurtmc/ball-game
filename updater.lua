local version = require("version")

local updater = {}

local REPO = "kurtmc/ball-game"
local CHECK_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local RELEASES_URL = "https://github.com/" .. REPO .. "/releases/latest"

updater.current_version = version
updater.latest_version = nil
updater.update_available = false
updater.download_url = RELEASES_URL
updater.check_done = false
updater.dismissed = false

local channel = nil
local thread = nil

local thread_code = [[
local url = ...
local http = require("socket.http")
local ltn12 = require("ltn12")

-- GitHub API redirects HTTP to HTTPS, so use curl which handles HTTPS
local handle = io.popen('curl -s -L -H "Accept: application/vnd.github.v3+json" "' .. url .. '" 2>/dev/null')
if not handle then
    love.thread.getChannel("updater"):push("error")
    return
end

local body = handle:read("*a")
handle:close()

if body and #body > 0 then
    -- Extract tag_name from JSON (simple pattern match, no JSON lib needed)
    local tag = body:match('"tag_name"%s*:%s*"([^"]+)"')
    if tag then
        love.thread.getChannel("updater"):push(tag)
        return
    end
end

love.thread.getChannel("updater"):push("error")
]]

function updater.checkForUpdates()
    if version == "0.0.0-dev" then return end  -- skip in dev mode

    channel = love.thread.getChannel("updater")
    thread = love.thread.newThread(thread_code)
    thread:start(CHECK_URL)
end

local function compareVersions(current, latest)
    -- Strip leading 'v' if present
    current = current:gsub("^v", "")
    latest = latest:gsub("^v", "")
    return current ~= latest
end

function updater.update()
    if updater.check_done or not channel then return end

    local result = channel:pop()
    if result then
        updater.check_done = true
        if result ~= "error" then
            updater.latest_version = result
            updater.update_available = compareVersions(updater.current_version, result)
        end
        -- Check for thread errors
        if thread and thread:getError() then
            -- Silently ignore update check failures
        end
    end
end

function updater.draw()
    if not updater.update_available or updater.dismissed then return end

    local w = 800
    local banner_h = 30
    local y = 0

    -- Banner background
    love.graphics.setColor(0.15, 0.5, 0.15, 0.9)
    love.graphics.rectangle("fill", 0, y, w, banner_h)

    -- Text
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(
        "Update available: " .. (updater.latest_version or "") .. "  |  Press [U] to open download  |  [X] to dismiss",
        10, y + 7, w - 20, "center"
    )
end

function updater.keypressed(key)
    if not updater.update_available or updater.dismissed then return false end

    if key == "u" then
        love.system.openURL(updater.download_url)
        return true
    elseif key == "x" then
        updater.dismissed = true
        return true
    end
    return false
end

return updater
