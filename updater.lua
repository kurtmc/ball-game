local version = require("version")

local updater = {}

local REPO = "kurtmc/ball-game"
local CHECK_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local RELEASES_URL = "https://github.com/" .. REPO .. "/releases/latest"

updater.current_version = version
updater.latest_version = nil
updater.update_available = false
updater.installer_url = nil
updater.installer_size = nil
updater.check_done = false
updater.dismissed = false
updater.checking = false
updater.check_failed = false
updater.downloading = false
updater.download_path = nil
updater.download_progress = 0
updater.download_total = 0
updater.download_poll_timer = 0
updater.status_message = nil
updater.status_timer = 0

local channel = nil
local thread = nil

local thread_code = [==[
local url = ...
local channel = love.thread.getChannel("updater")

-- Detect OS for choosing the right asset type
require("love.system")
local os_name = love.system.getOS()

local function findAssetInBody(body)
    local tag = body:match('"tag_name"%s*:%s*"([^"]+)"')
    if not tag then return nil end

    local installer_url = nil
    local installer_size = "0"

    -- Search for the appropriate asset based on OS
    if os_name == "Linux" then
        for u in body:gmatch('"browser_download_url"%s*:%s*"([^"]*%.AppImage)"') do
            installer_url = u
            break
        end
    else
        for u in body:gmatch('"browser_download_url"%s*:%s*"([^"]*setup[^"]*%.exe)"') do
            installer_url = u
            break
        end
    end

    if installer_url then
        local escaped = installer_url:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
        local pattern = '"size"%s*:%s*(%d+).-"browser_download_url"%s*:%s*"' .. escaped .. '"'
        local size_match = body:match(pattern)
        if not size_match then
            pattern = '"browser_download_url"%s*:%s*"' .. escaped .. '".-"size"%s*:%s*(%d+)'
            size_match = body:match(pattern)
        end
        installer_size = size_match or "0"
    end

    return tag .. "|" .. (installer_url or "") .. "|" .. installer_size
end

-- Try native Lua HTTPS first (LuaSec bundled with many LÖVE builds)
local ok, https = pcall(require, "ssl.https")
local ltn12_ok, ltn12 = pcall(require, "ltn12")

if ok and ltn12_ok then
    local chunks = {}
    local _, status = https.request({
        url = url,
        headers = { ["Accept"] = "application/vnd.github.v3+json" },
        sink = ltn12.sink.table(chunks),
        protocol = "tlsv1_2",
    })
    if status == 200 and #chunks > 0 then
        local body = table.concat(chunks)
        local result = findAssetInBody(body)
        if result then
            channel:push(result)
            return
        end
    end
    channel:push("error")
    return
end

-- Fallback: shell out to curl or PowerShell
local body = nil

if os_name == "Windows" then
    local temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    local out_path = temp .. "\\ballz_update_check.txt"
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
    local handle = io.popen('curl -s -L -H "Accept: application/vnd.github.v3+json" "' .. url .. '" 2>/dev/null')
    if handle then
        body = handle:read("*a")
        handle:close()
    end
end

if body and #body > 0 then
    local result = findAssetInBody(body)
    if result then
        channel:push(result)
        return
    end
end

channel:push("error")
]==]

local download_channel = nil
local download_thread = nil

local download_thread_code = [==[
local installer_url, total_size_str = ...
local channel = love.thread.getChannel("updater_download")
local total_size = tonumber(total_size_str) or 0

require("love.system")
local os_name = love.system.getOS()

local temp
if os_name == "Windows" then
    temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
else
    temp = "/tmp"
end

local installer_path
if os_name == "Windows" then
    installer_path = temp .. "\\ballz-setup.exe"
elseif os_name == "Linux" then
    installer_path = temp .. "/ballz-update.AppImage"
else
    installer_path = temp .. "/ballz-update"
end
os.remove(installer_path)

local function finishLinuxInstall(path)
    os.execute('chmod +x "' .. path .. '"')
    local appimage_path = os.getenv("APPIMAGE")
    if appimage_path and #appimage_path > 0 then
        -- Unlink old file first (still held open by running FUSE mount),
        -- then copy new file to create a fresh inode at the same path
        local status = os.execute('rm -f "' .. appimage_path .. '" && cp "' .. path .. '" "' .. appimage_path .. '" && chmod +x "' .. appimage_path .. '"')
        if status == 0 or status == true then
            os.remove(path)
            return appimage_path
        end
    end
    return path
end

-- Try native Lua HTTPS with chunked progress reporting
local ok, https = pcall(require, "ssl.https")
local ltn12_ok, ltn12 = pcall(require, "ltn12")
local http_ok, http = pcall(require, "socket.http")

if ok and ltn12_ok and http_ok then
    local file = io.open(installer_path, "wb")
    if not file then
        channel:push("error")
        return
    end

    local bytes_written = 0
    -- Custom ltn12 sink: writes chunks to file and pushes progress to channel
    local progress_sink = function(chunk, err)
        if chunk then
            file:write(chunk)
            bytes_written = bytes_written + #chunk
            channel:push("progress|" .. bytes_written)
            return 1
        else
            file:close()
            return nil, err
        end
    end

    -- Allow redirects (GitHub CDN)
    http.TIMEOUT = 60
    local _, status = https.request({
        url = installer_url,
        sink = progress_sink,
        protocol = "tlsv1_2",
        redirect = true,
    })

    if status == 200 and bytes_written > 10000 then
        if os_name == "Windows" then
            channel:push("ok|" .. installer_path)
        elseif os_name == "Linux" then
            local final_path = finishLinuxInstall(installer_path)
            channel:push("ok|" .. final_path)
        else
            channel:push("noinstaller")
        end
    else
        os.remove(installer_path)
        channel:push("error")
    end
    return
end

-- Fallback: shell out to PowerShell (Windows), curl (Linux), or open URL (other)
if os_name == "Windows" then
    channel:push("path|" .. installer_path)

    local ps_cmd = 'powershell -NoProfile -NoLogo -WindowStyle Hidden -Command "'
        .. "try { "
        .. "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
        .. "Invoke-WebRequest -Uri '" .. installer_url .. "' -OutFile '" .. installer_path .. "' -UseBasicParsing"
        .. " } catch { }"
        .. '"'
    os.execute(ps_cmd)

    local f = io.open(installer_path, "r")
    if f then
        local size = f:seek("end")
        f:close()
        if size and size > 10000 then
            channel:push("ok|" .. installer_path)
            return
        end
    end
    channel:push("error")
elseif os_name == "Linux" then
    channel:push("path|" .. installer_path)
    os.execute('curl -s -L -o "' .. installer_path .. '" "' .. installer_url .. '"')

    local f = io.open(installer_path, "r")
    if f then
        local size = f:seek("end")
        f:close()
        if size and size > 10000 then
            local final_path = finishLinuxInstall(installer_path)
            channel:push("ok|" .. final_path)
            return
        end
    end
    channel:push("error")
else
    channel:push("noinstaller")
end
]==]

function updater.startDownload()
    if updater.downloading or not updater.installer_url then return end
    updater.downloading = true
    updater.download_progress = 0
    updater.download_total = updater.installer_size or 0
    updater.download_path = nil
    updater.download_poll_timer = 0
    updater.status_message = "Downloading update..."
    updater.status_timer = 999

    download_channel = love.thread.getChannel("updater_download")
    while download_channel:pop() do end
    download_thread = love.thread.newThread(download_thread_code)
    download_thread:start(updater.installer_url, tostring(updater.installer_size or 0))
end

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
            local tag, installer, size_str = result:match("^([^|]+)|([^|]*)|?(.*)$")
            updater.latest_version = tag or result
            updater.installer_url = (installer and #installer > 0) and installer or nil
            updater.installer_size = tonumber(size_str) or 0
            updater.update_available = compareVersions(updater.current_version, updater.latest_version)
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

    -- Poll download thread
    if updater.downloading and download_channel then
        -- Drain all pending messages from the download thread
        local dl_result = download_channel:pop()
        while dl_result do
            if dl_result:sub(1, 9) == "progress|" then
                -- Native download: real-time byte count from chunked sink
                updater.download_progress = tonumber(dl_result:sub(10)) or 0
            elseif dl_result:sub(1, 5) == "path|" then
                -- Fallback download: file path for polling
                updater.download_path = dl_result:match("^path|(.+)$")
            elseif dl_result:sub(1, 2) == "ok" then
                updater.downloading = false
                updater.download_progress = updater.download_total
                local installer_path = dl_result:match("^ok|(.+)$")
                if love.system.getOS() == "Windows" then
                    os.execute('start "" "' .. installer_path .. '"')
                else
                    os.execute('"' .. installer_path .. '" &')
                end
                love.event.quit()
                return
            elseif dl_result == "noinstaller" then
                updater.downloading = false
                love.system.openURL(RELEASES_URL)
                return
            else
                updater.downloading = false
                updater.status_message = "Download failed"
                updater.status_timer = 4
                return
            end
            dl_result = download_channel:pop()
        end

        -- Fallback: poll file size when using curl/PowerShell
        if updater.download_path and updater.download_total > 0 then
            updater.download_poll_timer = updater.download_poll_timer + dt
            if updater.download_poll_timer >= 0.25 then
                updater.download_poll_timer = 0
                local f = io.open(updater.download_path, "rb")
                if f then
                    updater.download_progress = f:seek("end") or 0
                    f:close()
                end
            end
        end

        if download_thread and download_thread:getError() then
            updater.downloading = false
            updater.status_message = "Download failed"
            updater.status_timer = 4
        end
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

        if updater.downloading and updater.download_total > 0 then
            -- Progress bar
            local bar_x, bar_y = 100, 20
            local bar_w, bar_h = w - 200, 6
            local fraction = math.min(updater.download_progress / updater.download_total, 1)
            local mb_done = updater.download_progress / (1024 * 1024)
            local mb_total = updater.download_total / (1024 * 1024)
            local pct = math.floor(fraction * 100)

            -- Text
            love.graphics.setColor(1, 1, 1)
            local msg = string.format("Downloading %s... %.1f / %.1f MB (%d%%)",
                updater.latest_version or "", mb_done, mb_total, pct)
            love.graphics.printf(msg, 10, 3, w - 20, "center")

            -- Bar background
            love.graphics.setColor(0.1, 0.3, 0.1, 0.8)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 3, 3)
            -- Bar fill
            love.graphics.setColor(0.3, 1.0, 0.3, 0.9)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_w * fraction, bar_h, 3, 3)
        elseif updater.downloading then
            -- Downloading but no size info — show indeterminate message
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("Downloading " .. (updater.latest_version or "") .. "...",
                10, 7, w - 20, "center")
        else
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("Update available: " .. (updater.latest_version or "")
                .. "  |  Press [U] to install  |  [X] to dismiss",
                10, 7, w - 20, "center")
        end
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
        updater.startDownload()
        return true
    elseif key == "x" then
        updater.dismissed = true
        return true
    end
    return false
end

return updater
