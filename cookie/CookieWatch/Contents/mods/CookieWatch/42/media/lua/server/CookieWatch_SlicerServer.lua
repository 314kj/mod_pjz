-- CookieWatch: server side of the Cookie Slicer chat switch (client/CookieWatch_SlicerChat.lua).
-- !onslice / !offslice write Zomboid/Lua/CookieSlicer_mode.txt ("on" / "off"); the Cookie
-- Slicer agent (v4+) reads it within 5 s. Of this file and cookie\CookieSlicer.mode next to the
-- agent (slicer-on/off.bat) the one changed last counts. !slice reads
-- Zomboid/Lua/CookieSlicer_status.txt, which the agent writes. Admins only (checked here again).
if isClient() then return end

local MODULE = "CookieSlicer"
local MODE_FILE = "CookieSlicer_mode.txt"
local STATUS_FILE = "CookieSlicer_status.txt"
local AFTER_MS = 7000 -- the agent looks every 5 s

local function allowed(player)
    local ok, yes = pcall(function()
        local r = player and player:getRole()
        return r ~= nil and r:hasCapability(Capability.ChangeAndReloadServerOptions)
    end)
    return ok and yes == true
end

local function readStatus()
    local ok, text = pcall(function()
        local r = getFileReader(STATUS_FILE, false)
        if not r then return nil end
        local lines = {}
        local line = r:readLine()
        while line and #lines < 4 do
            line = string.gsub(line, "\r", "")
            if line ~= "" then lines[#lines + 1] = line end
            line = r:readLine()
        end
        r:close()
        return table.concat(lines, "\n")
    end)
    if ok and text and text ~= "" then return text end
    return "Cookie Slicer: no status file yet (agent v4 not running?)"
end

local function reply(player, text, box)
    pcall(function() sendServerCommand(player, MODULE, "reply", { text = text, box = box }) end)
end

local function writeMode(word)
    local ok = pcall(function()
        local w = getFileWriter(MODE_FILE, true, false)
        if not w then error("no writer") end
        w:write(word)
        w:close()
    end)
    return ok
end

-- answer again once the agent has had time to read the file
local pending = {}
local function onTick()
    if #pending == 0 then return end
    local now = getTimestampMs()
    for i = #pending, 1, -1 do
        local p = pending[i]
        if now >= p.due then
            table.remove(pending, i)
            reply(p.player, readStatus(), false)
        end
    end
    if #pending == 0 then Events.OnTick.Remove(onTick) end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    if not allowed(player) then return end
    local name = player:getUsername() or "?"
    if command == "slice" then
        reply(player, readStatus(), true)
    elseif command == "onslice" or command == "offslice" then
        local word = command == "onslice" and "on" or "off"
        if not writeMode(word) then
            reply(player, "Cookie Slicer: could not write Zomboid/Lua/" .. MODE_FILE, false)
            return
        end
        print("[CookieWatch] Cookie Slicer switch " .. word .. " by " .. name)
        reply(player, "Cookie Slicer: " .. string.upper(word) .. " requested (takes up to 5 s)", false)
        if #pending == 0 then Events.OnTick.Add(onTick) end
        pending[#pending + 1] = { player = player, due = getTimestampMs() + AFTER_MS }
    end
end

Events.OnClientCommand.Add(onClientCommand)
