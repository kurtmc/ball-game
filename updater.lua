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
updater.checking = false
updater.check_failed = false
updater.status_message = nil
updater.status_timer = 0

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
    if updater.checking then return end

    updater.check_done = false
    updater.check_failed = false
    updater.checking = true
    updater.dismissed = false

    channel = love.thread.getChannel("updater")
    -- Drain any stale messages
    while channel:pop() do end
    thread = love.thread.newThread(thread_code)
    thread:start(CHECK_URL)
end

local function compareVersions(current, latest)
    -- Strip leading 'v' if present
    current = current:gsub("^v", "")
    latest = latest:gsub("^v", "")
    return current ~= latest
end

function updater.update(dt)
    -- Fade status messages
    if updater.status_timer > 0 then
        updater.status_timer = updater.status_timer - dt
        if updater.status_timer <= 0 then
            updater.status_message = nil
        end
    end

    if updater.check_done or not channel then return end

    local result = channel:pop()
    if result then
        updater.check_done = true
        updater.checking = false
        if result ~= "error" then
            updater.latest_version = result
            updater.update_available = compareVersions(updater.current_version, result)
            if not updater.update_available then
                updater.status_message = "You're up to date! (" .. updater.current_version .. ")"
                updater.status_timer = 4
            end
        else
            updater.check_failed = true
            updater.status_message = "Update check failed"
            updater.status_timer = 4
        end
    end

    -- Check for thread errors
    if thread and thread:getError() then
        updater.check_done = true
        updater.checking = false
        updater.check_failed = true
        updater.status_message = "Update check failed"
        updater.status_timer = 4
    end
end

-- Refresh icon hit area
local ICON_R = 10
local ICON_CX, ICON_CY = 800 - ICON_R - 8, 800 - ICON_R - 6
local spin_angle = 0

local function drawRefreshIcon(cx, cy, r, color_r, color_g, color_b, alpha)
    love.graphics.setColor(color_r, color_g, color_b, alpha)
    love.graphics.setLineWidth(2)

    -- Draw a circular arc (~270 degrees)
    local segments = 20
    local start_a = spin_angle
    local arc_len = math.pi * 1.5
    local points = {}
    for i = 0, segments do
        local a = start_a + (i / segments) * arc_len
        table.insert(points, cx + math.cos(a) * r)
        table.insert(points, cy + math.sin(a) * r)
    end
    love.graphics.line(points)

    -- Arrowhead at the end of the arc
    local end_a = start_a + arc_len
    local ex = cx + math.cos(end_a) * r
    local ey = cy + math.sin(end_a) * r
    local arrow_size = 5
    local a1 = end_a + 0.6
    local a2 = end_a + 2.2
    love.graphics.polygon("fill",
        ex, ey,
        ex + math.cos(a1) * arrow_size, ey + math.sin(a1) * arrow_size,
        ex + math.cos(a2) * arrow_size, ey + math.sin(a2) * arrow_size
    )

    love.graphics.setLineWidth(1)
end

function updater.draw()
    -- Version in bottom-left
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.printf(updater.current_version, 10, 800 - 18, 200, "left")

    -- Refresh icon
    if updater.checking then
        spin_angle = spin_angle + 0.1
        drawRefreshIcon(ICON_CX, ICON_CY, ICON_R, 0.4, 0.4, 0.5, 0.7)
    else
        drawRefreshIcon(ICON_CX, ICON_CY, ICON_R, 0.3, 0.3, 0.4, 0.5)
    end

    -- Status message (fades out)
    if updater.status_message and updater.status_timer > 0 then
        local alpha = math.min(1, updater.status_timer) * 0.5
        love.graphics.setColor(0.5, 0.5, 0.5, alpha)
        love.graphics.printf(updater.status_message, ICON_CX - 210, ICON_CY - 6, 200, "right")
    end

    -- Update available banner
    if updater.update_available and not updater.dismissed then
        local w = 800
        local banner_h = 30

        love.graphics.setColor(0.15, 0.5, 0.15, 0.9)
        love.graphics.rectangle("fill", 0, 0, w, banner_h)

        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(
            "Update available: " .. (updater.latest_version or "") .. "  |  Press [U] to open download  |  [X] to dismiss",
            10, 7, w - 20, "center"
        )
    end
end

function updater.mousepressed(x, y)
    -- Check if refresh icon was clicked
    local dx = x - ICON_CX
    local dy = y - ICON_CY
    if dx * dx + dy * dy <= (ICON_R + 4) * (ICON_R + 4) then
        updater.checkForUpdates()
        return true
    end
    return false
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
