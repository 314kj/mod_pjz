-- Cookie Slicer (client): settings, frame-rate sampler, helper data, advice.
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
--
-- Files in Zomboid/Lua (the only folder Lua may use):
--   CookieSlicer_client.txt   this player's choices (look, brightness, button place)
--   CookieSlicer_pc.txt       written by the Cookie Slicer Helper (optional) every 2 s:
--                             CPU / RAM numbers the game's Lua cannot see
--   CookieSlicer_request.txt  what the player asked the helper to do (more RAM next start,
--                             RAM savers on / off, list what uses the game's RAM)
--   CookieSlicer_diag.txt     written by the helper (1.2.0+): problems in the game's log
--                             that stop a join (_prev: the game start before this one)
--   CookieSlicer_heap.txt     written by the helper on request: what fills the game's RAM
if isServer() then return end

CookieSlicer = CookieSlicer or {}
local CS = CookieSlicer
CS.VERSION = "1.2.0"
CS.HELPER_LATEST = "1.2.0" -- the helper shipped in this mod's helper/ folder
CS.SHADER_HELPER_MIN = "1.1.0" -- first helper that draws the shader
CS.JOIN_HELPER_MIN = "1.2.0" -- first helper that reads the game's log and has the RAM savers

local SETTINGS_FILE = "CookieSlicer_client.txt"
local HELPER_FILE = "CookieSlicer_pc.txt"
local REQUEST_FILE = "CookieSlicer_request.txt"

-- ---------------------------------------------------------------- settings

CS.settings = { look = "natural", bright = 0, bx = -1, by = -1, seen = 0, keyhint = 0, page = "perf", glass = 1, jopen = 0 }
local NUMBERS = { bright = true, bx = true, by = true, seen = true, keyhint = true, glass = true, jopen = true }

local function parseLine(line)
    local k, v = string.match(line or "", "^%s*([%w_]+)%s*=%s*(.-)%s*$")
    return k, v
end

function CS.loadSettings()
    local ok = pcall(function()
        local r = getFileReader(SETTINGS_FILE, false)
        if not r then return end
        local line = r:readLine()
        while line do
            local k, v = parseLine(line)
            if k and (string.sub(k, 1, 5) == "prev_" or string.sub(k, 1, 3) == "sh_") then
                CS.settings[k] = v -- a game option before "Lighter game" changed it / shader choices
            elseif k and CS.settings[k] ~= nil then
                if NUMBERS[k] then
                    CS.settings[k] = tonumber(v) or CS.settings[k]
                else
                    CS.settings[k] = v
                end
            end
            line = r:readLine()
        end
        r:close()
    end)
    return ok
end

function CS.saveSettings()
    pcall(function()
        local w = getFileWriter(SETTINGS_FILE, true, false)
        if not w then return end
        for _, k in ipairs({ "look", "bright", "bx", "by", "seen", "keyhint", "page", "glass", "jopen" }) do
            w:write(k .. "=" .. tostring(CS.settings[k]) .. "\n")
        end
        for k, v in pairs(CS.settings) do
            if (string.sub(k, 1, 5) == "prev_" or string.sub(k, 1, 3) == "sh_") and v ~= nil then
                w:write(k .. "=" .. tostring(v) .. "\n")
            end
        end
        w:close()
    end)
end

-- ---------------------------------------------------------------- frame rate

CS.fps = { now = 0, avg = 0, min = 0, n = 0 }
local samples = {}
local frames, windowStart = 0, nil
local SAMPLES = 60 -- one per second: the last minute

local function addSample(f)
    samples[#samples + 1] = f
    if #samples > SAMPLES then table.remove(samples, 1) end
    local sum, lo = 0, nil
    for i = 1, #samples do
        sum = sum + samples[i]
        if lo == nil or samples[i] < lo then lo = samples[i] end
    end
    CS.fps.now = f
    CS.fps.avg = sum / #samples
    CS.fps.min = lo or f
    CS.fps.n = #samples
    local m = CS.measure
    if m and m.n < 60 then
        m.sum, m.n = m.sum + f, m.n + 1
        if m.n >= 60 then m.after = m.sum / m.n end
    end
end

-- FPS before / after a settings change (this session only). A change made
-- while playing keeps the FPS of the last minute as "before"; more clicks
-- within the next minute keep that first "before" and start "after" again.
CS.measure = nil
function CS.markChange()
    local old = CS.measure
    local inGame = getPlayer() ~= nil
    local before, mainBefore = nil, nil
    if old and old.inGame and old.before and old.after == nil then
        before, mainBefore = old.before, old.mainBefore
    elseif inGame and CS.fps.n >= 20 then
        before = CS.fps.avg
        if CS.pc.fresh then mainBefore = tonumber(CS.pc.main_thread) end
    end
    CS.measure = { before = before, mainBefore = mainBefore, sum = 0, n = 0, inGame = inGame }
end

-- ---------------------------------------------------------------- helper data

CS.pc = { fresh = false }
local lastHelperRead = 0

local function readHelper(now)
    local data = {}
    local ok = pcall(function()
        local r = getFileReader(HELPER_FILE, false)
        if not r then return end
        local line = r:readLine()
        while line do
            local k, v = parseLine(line)
            if k then data[k] = tonumber(v) or v end
            line = r:readLine()
        end
        r:close()
    end)
    if not ok then return end
    local t = tonumber(data.t)
    data.fresh = t ~= nil and math.abs(now - t) < 10000
    data.present = t ~= nil
    CS.pc = data
end

-- ---------------------------------------------------------------- advice

-- "good" / "ok" / "heavy", and one tip key (UI_CookieSlicer_Tip_<key>)
function CS.verdict()
    local pc, f = CS.pc, CS.fps
    local tip, level = "fine", "good"
    local function worse(l) if l == "heavy" or (l == "ok" and level == "good") then level = l end end
    if f.n >= 5 then
        if f.avg < 25 then worse("heavy") elseif f.avg < 45 then worse("ok") end
    end
    if pc.fresh then
        -- after the last clean-up when known (what the game really keeps); the
        -- number right now also counts garbage waiting to be cleaned
        local heapUsed = tonumber(pc.heap_live_mb) or tonumber(pc.heap_used_mb)
        local heapMax = tonumber(pc.heap_max_mb)
        if tonumber(pc.heap_live_mb) == 0 then heapUsed = tonumber(pc.heap_used_mb) end
        local ramFree = tonumber(pc.ram_free_mb)
        local main, cpuAll = tonumber(pc.main_thread), tonumber(pc.cpu_total)
        if heapUsed and heapMax and heapMax > 0 and heapUsed / heapMax > 0.85 then
            worse("heavy"); return level, "ram_heap"
        end
        if ramFree and ramFree < 1500 then worse("ok"); return level, "ram_pc" end
        if cpuAll and cpuAll > 90 then worse("ok"); return level, "cpu" end
        if main and main > 90 then worse("ok"); tip = "main" end
    end
    if tip == "fine" and CS.uiFpsTooHigh() then tip = "uifps" end
    if tip == "fine" and CS.tuneRemaining and CS.tuneRemaining(false) > 0 then tip = "tune" end
    if tip == "fine" and level ~= "good" then tip = "low_fps" end
    return level, tip
end

-- UI drawn more often than needed: with UI offscreen rendering on, every UI
-- window's Lua runs at this rate; 30 looks the same and frees the game's thread.
function CS.uiFpsTooHigh()
    local ok, yes = pcall(function()
        local c = getCore()
        return c:getOptionUIFBO() and c:getOptionUIRenderFPS() > 30
    end)
    return ok and yes == true
end

function CS.setUiFps30()
    pcall(function()
        local c = getCore()
        c:setOptionUIRenderFPS(30)
        c:saveOptions()
    end)
end

-- requests to the helper (read every 2 s): asks made within a few seconds of each other
-- go in one file, so a second click does not overwrite the first before it is read
local pending, pendingT = {}, 0
function CS.request(kv)
    local now = getTimestampMs()
    if now - pendingT > 6000 then pending = {} end
    for k, v in pairs(kv) do pending[k] = v end
    pendingT = now
    pcall(function()
        local w = getFileWriter(REQUEST_FILE, true, false)
        if not w then return end
        for k, v in pairs(pending) do w:write(k .. "=" .. tostring(v) .. "\n") end
        w:write("t=" .. tostring(now) .. "\n")
        w:close()
    end)
end

-- more RAM from the next game start (the helper writes heap.txt for the start script)
function CS.requestHeap(mb)
    CS.request({ heap_mb = math.floor(mb) })
end

-- Java's RAM savers on / off from the next game start (ramsave.txt for the start script)
function CS.requestRamSave(on)
    CS.request({ ramsave = on and 1 or 0 })
    CS.ramsaveAsked = on and 1 or 0
end

-- list what fills the game's RAM now (the game stops for a moment)
function CS.requestHeapReport()
    CS.request({ heap_report = 1 })
    CS.heapAskedT = getTimestampMs()
end

-- a key=value file in Zomboid/Lua, or nil
function CS.readKV(file)
    local data
    pcall(function()
        local r = getFileReader(file, false)
        if not r then return end
        data = {}
        local line = r:readLine()
        while line do
            local k, v = parseLine(line)
            if k then data[k] = v end
            line = r:readLine()
        end
        r:close()
    end)
    return data
end

-- helper 1.2.0+ (a version check: older helpers do not write these files)
function CS.helperHas(minVersion)
    local pc = CS.pc
    return pc.fresh and pc.helper ~= nil and not CS.verLess(tostring(pc.helper), minVersion)
end

-- ---------------------------------------------------------------- tick

local function onTick()
    frames = frames + 1
    local now = getTimestampMs()
    if not windowStart then windowStart = now return end
    local dt = now - windowStart
    if dt < 1000 then return end
    addSample(frames * 1000 / dt)
    frames, windowStart = 0, now
    if now - lastHelperRead >= 2000 then
        lastHelperRead = now
        readHelper(now)
    end
end

-- main menu: OnTick does not run there, so read the helper's numbers here
local function onFETick()
    local now = getTimestampMs()
    if now - lastHelperRead >= 2000 then
        lastHelperRead = now
        readHelper(now)
    end
end

CS.loadSettings()
Events.OnTick.Add(onTick)
Events.OnFETick.Add(onFETick)
