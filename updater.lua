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

local thread_code = [==[
local url = ...
require("love.system")
local channel = love.thread.getChannel("updater")

local os_name = love.system.getOS()

local body = nil

if os_name == "Windows" then
    -- Use PowerShell hidden window to make HTTPS request, write to %TEMP%
    local temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    local out_path = temp .. "\\ballz_update_check.txt"
    -- Clean up any stale file
    os.remove(out_path)
    local cmd = 'powershell -NoProfile -NoLogo -WindowStyle Hidden -Command "'
        .. "try { "
        .. "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
        .. "$r = Invoke-WebRequest -Uri '" .. url .. "' -UseBasicParsing; "
        .. "Set-Content -Path '" .. out_path .. "' -Value $r.Content -Encoding UTF8"
        .. " } catch { }"
        .. '"'
    os.execute(cmd)

    local rf = io.open(out_path, "r")
    if rf then
        body = rf:read("*a")
        rf:close()
        os.remove(out_path)
    end
else
    -- Unix: use curl directly (no window flash issue)
    local handle = io.popen('curl -s -L -H "Accept: application/vnd.github.v3+json" "' .. url .. '" 2>/dev/null')
    if handle then
        body = handle:read("*a")
        handle:close()
    end
end

if body and #body > 0 then
    local tag = body:match('"tag_name"%s*:%s*"([^"]+)"')
    if tag then
        channel:push(tag)
        return
    end
end

channel:push("error")
]==]

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
