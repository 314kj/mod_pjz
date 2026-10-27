-- CookieWatch_Server.lua  (Cookie Cheetah)
-- Bridge between the CookieWatch tool (outside the game) and players.
--   tool  -> Zomboid/Lua/CookieWatch_notice.txt -> this file -> sendServerCommand -> client popup
--   this file -> Zomboid/Lua/CookieWatch_status.txt (player count + names) -> tool
-- Logs in English only (console.txt mangles Thai).

if not isServer() then return end

CookieWatchServer = CookieWatchServer or {}
local S = CookieWatchServer

S.NOTICE_FILE = "CookieWatch_notice.txt"
S.STATUS_FILE = "CookieWatch_status.txt"
S.POLL_MS = 2000
S.STATUS_MS = 10000

S.lastId = nil
S.cur = nil
S.nextPoll = 0
S.nextStatus = 0

local function readKV(name)
    local r = getFileReader(name, false)
    if not r then return nil end
    local t = {}
    local line = r:readLine()
    while line ~= nil do
        local k, v = string.match(line, "^%s*([%w_]+)%s*=(.*)$")
        if k then t[k] = v end
        line = r:readLine()
    end
    r:close()
    return t
end

local function nowMs()
    return getTimestampMs()
end

local function remainSec(cur)
    local closeAt = tonumber(cur.close_at)
    if not closeAt then return 0 end
    local r = math.floor((closeAt - nowMs()) / 1000)
    if r < 0 then r = 0 end
    return r
end

local function isActive(cur)
    if not cur or cur.kind == "clear" then return false end
    local exp = tonumber(cur.expire_at) or tonumber(cur.close_at)
    return exp ~= nil and exp > nowMs()
end

local function buildArgs(cur)
    return {
        id = cur.id,
        kind = cur.kind or "show",
        remain = remainSec(cur),
        l1 = cur.line1 or "",
        l2 = cur.line2 or "",
        l3 = cur.line3 or "",
        mini = cur.mini or "",
        popup = tonumber(cur.popup_sec) or 15,
        alpha = tonumber(cur.bg_alpha) or 0.6,
        accent = cur.accent or "#FFB454",
        showmini = cur.show_mini or "true",
    }
end

function S.poll()
    local t = readKV(S.NOTICE_FILE)
    if not t or not t.id or t.id == S.lastId then return end
    S.lastId = t.id
    S.cur = t
    if t.kind == "clear" then
        sendServerCommand("CookieWatch", "Notice", { id = t.id, kind = "clear" })
        print("[CookieWatch] notice cleared id=" .. tostring(t.id))
        return
    end
    if isActive(t) then
        sendServerCommand("CookieWatch", "Notice", buildArgs(t))
        print("[CookieWatch] notice sent id=" .. tostring(t.id) .. " kind=" .. tostring(t.kind) .. " remain=" .. tostring(remainSec(t)))
    end
end

function S.writeStatus()
    local list = getOnlinePlayers()
    local n = 0
    local names = ""
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local u = p and p:getUsername()
            if u then
                n = n + 1
                if names ~= "" then names = names .. "\t" end
                names = names .. u
            end
        end
    end
    local w = getFileWriter(S.STATUS_FILE, true, false)
    if not w then return end
    w:write("players=" .. tostring(n) .. "\n")
    w:write("names=" .. names .. "\n")
    w:close()
end

local function safe(fn, label)
    local ok, err = pcall(fn)
    if not ok then print("[CookieWatch] " .. label .. " error: " .. tostring(err)) end
end

local function onTick()
    local t = nowMs()
    if t >= S.nextPoll then
        S.nextPoll = t + S.POLL_MS
        safe(S.poll, "poll")
    end
    if t >= S.nextStatus then
        S.nextStatus = t + S.STATUS_MS
        safe(S.writeStatus, "status")
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "CookieWatch" then return end
    if command == "Sync" and isActive(S.cur) then
        sendServerCommand(player, "CookieWatch", "Notice", buildArgs(S.cur))
    end
end

Events.OnTick.Add(onTick)
Events.EveryOneMinute.Add(onTick) -- backup timer; throttled by the same real-time check
Events.OnClientCommand.Add(onClientCommand)

print("[CookieWatch] server bridge loaded")
