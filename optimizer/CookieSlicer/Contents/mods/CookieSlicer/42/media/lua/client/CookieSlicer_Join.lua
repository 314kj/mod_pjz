-- Cookie Slicer (client): "before you join" - a small panel next to the game's server list
-- (and its "connecting" screen) with what can stop a join, and what to do about it:
--   - the helper, the game's RAM, the PC's free RAM, ProjectZomboid64.json (from the helper)
--   - why the last join failed: what the game said when it refused (Lua events below) and
--     what the helper found in the game's log (CookieSlicer_diag.txt; _prev = the game start
--     before this one, e.g. the game closed while loading)
-- Collapsed to one line at the top right when it would cover the server list; opens by
-- itself when a new problem shows up. The same fixes are shown by the helper on the
-- loading screen (texts UI_CookieSlicer_Fix_*).
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
if isServer() then return end

require "ISUI/ISPanel"
require "CookieSlicer_UI"

local CS = CookieSlicer
if not CS or not CookieSlicerWindow or not CS.ui then return end
local U = CS.ui
local C, T, fh, tw, fit, wrap, gb = U.C, U.T, U.fh, U.tw, U.fit, U.wrap, U.gb

-- ================================================================ why a join failed (Lua)

-- the game's own messages (in the player's language) -> problem code. A message with
-- %1 is matched by its longest fixed part. Raw words cover messages that arrive untranslated.
local RULES = {
    { code = "already", keys = { "UI_OnConnectFailed_AlreadyConnected" }, raw = { "AlreadyConnected" } },
    { code = "banned", keys = { "UI_OnConnectFailed_Banned", "UI_OnConnectFailed_BannedReason", "UI_servers_SteamIDBanned" }, raw = { "Banned" } },
    { code = "version", keys = { "UI_OnConnectFailed_ClientVersionMismatch" }, raw = { "ClientVersionMismatch", "does not match server version" } },
    { code = "access", keys = { "UI_OnConnectFailed_AccessDenied", "UI_OnConnectFailed_InvalidServerPassword", "UI_servers_InvalidServerPassword",
        "UI_OnConnectFailed_InvalidUsername", "UI_OnConnectFailed_UnknownUsername", "UI_OnConnectFailed_UserPasswordRequired",
        "UI_OnConnectFailed_InvalidUsernamePassword", "UI_OnConnectFailed_NonAsciiCharacters" },
      raw = { "AccessDenied", "InvalidServerPassword", "Wrong username", "Unknown account" } },
    { code = "full", keys = { "UI_OnConnectFailed_ServerFull" }, raw = { "ServerFull" } },
    { code = "ping", keys = { "UI_OnConnectFailed_Ping" }, raw = { "ping is too high" } },
    { code = "modmissing", keys = { "UI_OnConnectFailed_ModRequired" }, raw = { "is not installed" } },
    { code = "workshop", keys = { "UI_OnConnectFailed_CreateQueryUGCDetailsRequest", "UI_ServerWorkshopItemError_VersionMismatch" }, raw = { "Workshop" } },
    { code = "files", keys = { "UI_GameLoad_KickChecksum" }, raw = { "Checksum" } },
    { code = "net", keys = { "UI_OnConnectFailed_ConnectionLost", "UI_OnConnectFailed_FailedTCPTest", "UI_servers_ServerFailedToRespond",
        "UI_OnConnectFailed_UnknownHost", "UI_OnConnectFailed_QueueNotFound", "UI_servers_connectionfailed" },
      raw = { "ConnectionLost", "FailedTCPTest", "ServerFailedToRespond", "UnknownHost" } },
}

-- the longest fixed part of a game text (around its %1 / %2)
local partCache = {}
local function fixedPart(key)
    if partCache[key] then return partCache[key] end
    local best = false
    pcall(function()
        local mark = "#CSARG#"
        local s = getText(key, mark, mark)
        if not s or s == key then return end
        s = s .. mark
        local from = 1
        while true do
            local a, b = string.find(s, mark, from, true)
            if not a then break end
            local part = string.sub(s, from, a - 1)
            part = string.gsub(part, "^%s+", "")
            part = string.gsub(part, "%s+$", "")
            if #part >= 4 and (not best or #part > #best) then best = part end
            from = b + 1
        end
    end)
    if best then partCache[key] = best end -- (a text not there yet is looked up again next time)
    return best
end

function CS.classifyJoin(msg)
    if not msg or msg == "" then return nil end
    for _, r in ipairs(RULES) do
        for _, k in ipairs(r.keys) do
            local part = fixedPart(k)
            if part and string.find(msg, part, 1, true) then return r.code end
        end
        for _, w in ipairs(r.raw) do
            if string.find(msg, w, 1, true) then return r.code end
        end
    end
    return "joinfail" -- the game's own message is shown with it
end

local function connecting()
    local ms = MainScreen and MainScreen.instance
    return ms and ms.connectToServer and ms.connectToServer:isVisible() and not getPlayer()
end

-- the first message after the join button counts (the game does the same: later ones
-- are "disconnected" with no reason)
local function record(msg)
    if not connecting() then return end
    if CS.joinFail and CS.joinFail.t >= (CS.joinAttemptT or 0) and CS.joinFail.code ~= "joinfail" then return end
    local code = CS.classifyJoin(msg)
    if not code then return end
    local detail = ""
    if code == "modmissing" then detail = string.match(msg, '"(.-)"') or "" end
    CS.joinFail = { code = code, msg = msg, detail = detail, t = getTimestampMs() }
end

local function onConnectFailed(message, detail)
    if message == "ServerWorkshopItemsCancelled" then return end
    local m = tostring(message or "")
    if detail and detail ~= "" then m = m .. " " .. tostring(detail) end
    record(m)
end

local function onConnectionStateChanged(state, message, arg)
    if state == "Failed" then
        local m = message and message ~= "" and (getText("UI_servers_" .. message) .. " " .. message) or getText("UI_servers_connectionfailed")
        record(m)
    elseif state == "ClientVersionMismatch" then
        record("ClientVersionMismatch " .. tostring(message or ""))
    elseif state == "Disconnected" then
        record(getText("UI_servers_connectionfailed") .. " " .. tostring(message or ""))
    end
end

Events.OnConnectFailed.Add(onConnectFailed)
Events.OnDisconnect.Add(onConnectFailed)
Events.OnConnectionStateChanged.Add(onConnectionStateChanged)

-- ================================================================ what to show

local function readDiag(file)
    local d = CS.readKV(file)
    if not d then return nil end
    local out = { t = tonumber(d.t) or 0, list = {} }
    for i = 1, tonumber(d.n) or 0 do
        local code, count, last, detail = string.match(tostring(d["p" .. i] or ""), "^([%w_]+)|(%d+)|(%d+)|?(.*)$")
        if code then out.list[#out.list + 1] = { code = code, count = tonumber(count), last = tonumber(last), detail = detail or "" } end
    end
    return out
end

local diagCache, diagReadT = nil, 0
local function diags()
    local now = getTimestampMs()
    if not diagCache or now - diagReadT > 2000 then
        diagReadT = now
        diagCache = { cur = readDiag("CookieSlicer_diag.txt"), prev = readDiag("CookieSlicer_diag_prev.txt") }
    end
    return diagCache
end

-- fix steps for one problem code (title, then up to three numbered steps)
local function steps(code)
    local out = {}
    for i = 1, 3 do
        local key = "Fix_" .. code .. "_" .. i
        local s = T(key)
        if s ~= "UI_CookieSlicer_" .. key and s ~= "" then out[#out + 1] = tostring(i) .. ". " .. s end
    end
    return out
end

local function hasIssue(list, name)
    for part in string.gmatch(tostring(list or ""), "[^,]+") do
        if part == name or string.sub(part, 1, #name + 1) == name .. ":" then return true end
    end
    return false
end

-- rows: { level = "ok" / "warn" / "bad" / "dim", label, value, steps = {}, btn = {label, fn, arg} }
-- problems: the same, for what went wrong
function CS.joinCheck()
    local pc = CS.pc
    local rows, problems = {}, {}
    local has12 = CS.helperHas(CS.JOIN_HELPER_MIN)
    -- helper
    if pc.fresh and pc.helper then
        if U.verLess(tostring(pc.helper), CS.HELPER_LATEST) then
            rows[#rows + 1] = { level = "warn", label = T("J_helper"), value = T("Ver_helperOld", tostring(pc.helper), CS.HELPER_LATEST) }
        else
            rows[#rows + 1] = { level = "ok", label = T("J_helper"), value = T("Ver_helperOn", tostring(pc.helper)) }
        end
    elseif pc.present then
        rows[#rows + 1] = { level = "warn", label = T("J_helper"), value = T("Ver_helperStopped") }
    else
        rows[#rows + 1] = { level = "dim", label = T("J_helper"), value = T("J_helperNone") }
    end
    if pc.fresh then
        -- game RAM
        local max, rec, nxt = tonumber(pc.heap_max_mb), tonumber(pc.heap_recommend_mb), tonumber(pc.heap_next_mb)
        if max and rec then
            local r = { label = T("J_ram"), value = T("J_ramV", gb(max), gb(rec)) }
            if nxt then
                r.level, r.value = "ok", T("Ver_heapNext", gb(max), gb(nxt))
            elseif max < rec - 256 then
                r.level = "warn"
                r.btn = { label = T("J_ramBtn", gb(rec)), fn = function() CS.requestHeap(rec) end }
            else
                r.level = "ok"
            end
            rows[#rows + 1] = r
        end
        -- PC RAM
        local free, total = tonumber(pc.ram_free_mb), tonumber(pc.ram_total_mb)
        if free and total then
            local low = free < 1500
            rows[#rows + 1] = { level = low and "warn" or "ok", label = T("J_pcram"), value = T("J_pcramV", gb(free), gb(total)),
                                steps = low and { T("J_pcramLow") } or nil }
        end
        -- ProjectZomboid64.json
        if has12 and pc.json_file and pc.json_file ~= "none" then
            local issue = tostring(pc.json_issue or "")
            local r = { label = T("J_json"), level = "ok", value = T("J_jsonOk") }
            if hasIssue(issue, "broken") then
                r.level, r.value = "bad", T("J_jsonBroken")
            elseif hasIssue(issue, "pzopt") or hasIssue(issue, "aot") then
                r.level, r.value, r.steps = "bad", T("Fix_pzopt"), steps("pzopt")
            end
            local agent = string.match(issue, "agent:([^,]+)")
            if agent and r.level == "ok" then r.level, r.value = "warn", T("J_jsonAgent", agent) end
            rows[#rows + 1] = r
        end
    end

    -- why the last join failed: the game's own message (this session)
    local seen = {}
    local f = CS.joinFail
    if f then
        local title = T("Fix_" .. f.code)
        if f.detail ~= "" then title = title .. ": " .. f.detail end
        problems[#problems + 1] = { level = "bad", label = T("J_last"), value = title, steps = steps(f.code),
                                    said = f.msg ~= "" and T("J_gameSaid", f.msg) or nil, key = f.code }
        seen[f.code] = true
    end
    -- what the helper found in the log since the last join attempt
    local d = has12 and diags() or {}
    local failed = f ~= nil
    if d.cur then
        for _, p in ipairs(d.cur.list) do
            if p.code ~= "luamod" and not seen[p.code] then
                seen[p.code] = true
                failed = true
                local title = T("Fix_" .. p.code)
                if p.detail ~= "" then title = title .. ": " .. p.detail end
                problems[#problems + 1] = { level = "bad", label = T("J_last"), value = title, steps = steps(p.code), key = p.code }
            end
        end
        -- mod errors only matter when the join failed
        for _, p in ipairs(d.cur.list) do
            if p.code == "luamod" and failed then
                problems[#problems + 1] = { level = "warn", label = T("J_last"), value = T("Fix_luamod") .. ": " .. p.detail, steps = steps("luamod"), key = "luamod" }
            end
        end
    end
    -- the game start before this one (it may have closed while loading)
    if d.prev and (getTimestampMs() - d.prev.t) < 2 * 24 * 3600 * 1000 then
        for _, p in ipairs(d.prev.list) do
            if p.code ~= "luamod" and not seen[p.code] then
                seen[p.code] = true
                problems[#problems + 1] = { level = "warn", label = T("J_prev"), value = T("Fix_" .. p.code), steps = steps(p.code), key = "prev_" .. p.code }
                break
            end
        end
    end
    return rows, problems
end

-- ================================================================ the panel

CookieSlicerJoinPanel = CookieSlicerWindow:derive("CookieSlicerJoinPanel")

local LEVEL = { ok = C.mint, warn = C.warn, bad = C.bad, dim = C.faint }

function CookieSlicerJoinPanel:new()
    local o = ISPanel:new(0, 0, 420, 60)
    setmetatable(o, self)
    self.__index = self
    o.F = U.FONTS_SMALL
    o.pad = 12
    o.gap = 8
    o.hits, o.tips = {}, {}
    o.backgroundColor = { r = C.bg[1], g = C.bg[2], b = C.bg[3], a = 0.95 }
    o.borderColor = { r = C.mint[1], g = C.mint[2], b = C.mint[3], a = 0.8 }
    o.open = tonumber(CS.settings.jopen) == 1
    o.seenKeys = {}
    return o
end

-- where it goes: in the free space right of the game's screen when it fits there,
-- else a single line at the top right (open: over the right part of the list)
function CookieSlicerJoinPanel:place(target)
    local sw = getCore():getScreenWidth()
    local right = target:getX() + target:getWidth()
    local space = sw - right - 24
    if space >= 300 then
        self.docked = true
        self.px, self.py, self.pw = right + 12, target:getY(), math.min(space, 460)
    else
        self.docked = false
        self.pw = math.min(440, math.floor(sw * 0.4))
        self.px, self.py = sw - self.pw - 12, 8
    end
end

function CookieSlicerJoinPanel:render()
    ISPanel.render(self)
    self.hits = {}
    local F, p, gap = self.F, self.pad, self.gap
    local rows, problems = CS.joinCheck()
    local bad = 0
    for _, r in ipairs(rows) do if r.level == "bad" or r.level == "warn" then bad = bad + 1 end end
    for _, r in ipairs(problems) do if r.level == "bad" or r.level == "warn" then bad = bad + 1 end end
    -- a problem that was not there a moment ago opens it (hidden again: stays hidden)
    local keys = {}
    for _, r in ipairs(problems) do keys[r.key or r.value] = true end
    for _, r in ipairs(rows) do if r.level == "bad" then keys[r.label] = true end end
    for k in pairs(keys) do
        if not self.seenKeys[k] then self.open = true end
    end
    self.seenKeys = keys
    local open = self.open or self.docked
    local W = self.pw
    local statusText = bad > 0 and T("J_issues", tostring(bad)) or T("J_ready")
    local sc = bad > 0 and (#problems > 0 and C.bad or C.warn) or C.mint

    -- head: title, status, open / close
    local hh = fh(F.body) + 14
    self:rect(0, 0, W, hh, C.head)
    self:rect(10, math.floor(hh / 2) - 4, 8, 8, sc)
    local title = T("J_title")
    self:text(title, 26, 7, C.text, F.body)
    local tg = open and T("J_hide") or T("J_show")
    local tgw = tw(tg, F.small) + 20
    if not self.docked then
        self:button(W - tgw - 6, 4, tgw, hh - 8, tg, F.small, CookieSlicerJoinPanel.onToggle, nil, "ghost")
    end
    local sx = W - (self.docked and 10 or (tgw + 16))
    self:textR(fit(statusText, F.small, sx - 26 - tw(title, F.body) - 12), sx, 7 + fh(F.body) - fh(F.small), sc, F.small)
    if not open then
        self:hit(0, 0, W, hh, CookieSlicerJoinPanel.onToggle)
        self:setGeom(W, hh)
        return
    end
    self:rect(0, hh, W, 2, C.mint)

    local y = hh + 2 + gap
    local cw = W - 2 * p
    local function drawRow(r)
        local lc = LEVEL[r.level] or C.text
        self:rect(p, y + math.floor((fh(F.small) - 6) / 2), 6, 6, lc)
        self:text(fit(r.label, F.small, cw - 14), p + 12, y, C.dim, F.small)
        y = y + fh(F.small) + 2
        for _, l in ipairs(wrap(r.value, F.small, cw - 12)) do
            self:text(l, p + 12, y, r.level == "dim" and C.dim or (r.level == "ok" and C.text or lc), F.small)
            y = y + fh(F.small) + 2
        end
        if r.said then
            for _, l in ipairs(wrap(r.said, F.small, cw - 12)) do
                self:text(l, p + 12, y, C.faint, F.small)
                y = y + fh(F.small) + 2
            end
        end
        for _, s in ipairs(r.steps or {}) do
            for i, l in ipairs(wrap(s, F.small, cw - 24)) do
                self:text(l, p + (i == 1 and 12 or 24), y, C.soft, F.small)
                y = y + fh(F.small) + 2
            end
        end
        if r.btn then
            local bh = fh(F.small) + 10
            local bw = math.min(cw - 12, tw(r.btn.label, F.small) + 28)
            self:button(p + 12, y + 2, bw, bh, r.btn.label, F.small, function() r.btn.fn() end, nil, "primary")
            y = y + bh + 4
        end
        y = y + gap - 2
    end
    for _, r in ipairs(rows) do drawRow(r) end
    self:rect(p, y, cw, 1, C.line)
    y = y + gap
    if #problems == 0 then
        self:text(fit(T("J_lastNone"), F.small, cw), p, y, C.dim, F.small)
        y = y + fh(F.small) + gap
    else
        for _, r in ipairs(problems) do drawRow(r) end
    end
    if CS.helperHas(CS.JOIN_HELPER_MIN) then
        for _, l in ipairs(wrap(T("Fix_Foot"), F.small, cw)) do
            self:text(l, p, y, C.faint, F.small)
            y = y + fh(F.small) + 2
        end
    end
    self:setGeom(W, y + p - 4)
end

function CookieSlicerJoinPanel:setGeom(w, h)
    local sh = getCore():getScreenHeight()
    h = math.min(h, sh - self.py - 8)
    if self.x ~= self.px then self:setX(self.px) end
    if self.y ~= self.py then self:setY(self.py) end
    if math.abs(self.width - w) > 1 then self:setWidth(w) end
    if math.abs(self.height - h) > 1 then self:setHeight(h) end
end

function CookieSlicerJoinPanel:onToggle()
    self.open = not self.open
    CS.settings.jopen = self.open and 1 or 0
    CS.saveSettings()
end

function CookieSlicerJoinPanel:onMouseDown(x, y)
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            h.fn(self, h.arg, x, y)
            return true
        end
    end
    return true
end

function CookieSlicerJoinPanel:onMouseMove(dx, dy) end
function CookieSlicerJoinPanel:onMouseMoveOutside(dx, dy) end
function CookieSlicerJoinPanel:onMouseUp(x, y) return true end
function CookieSlicerJoinPanel:onMouseUpOutside(x, y) end

-- ================================================================ when to show it

local wasConnecting = false

local function target()
    local ms = MainScreen and MainScreen.instance
    if not ms or getPlayer() or not ms:isVisible() then return nil end
    if ms.connectToServer and ms.connectToServer:isVisible() then return ms.connectToServer end
    if ms.multiplayer and ms.multiplayer:isVisible() then return ms.multiplayer end
    return nil
end

local function onFETick()
    local now = connecting()
    if now and not wasConnecting then
        -- a new join attempt: the old reason no longer counts
        CS.joinAttemptT = getTimestampMs()
        CS.joinFail = nil
    end
    wasConnecting = now and true or false
    local t = target()
    local p = CS.joinPanel
    if t then
        if not p then
            p = CookieSlicerJoinPanel:new()
            p:initialise()
            p:addToUIManager()
            CS.joinPanel = p
        end
        p:place(t)
        if not p:isVisible() then
            p:setVisible(true)
            p:bringToTop()
        end
    elseif p and p:isVisible() then
        p:setVisible(false)
    end
end

local function onGameStart()
    local p = CS.joinPanel
    if p then
        p:setVisible(false)
        p:removeFromUIManager()
        CS.joinPanel = nil
    end
end

Events.OnFETick.Add(onFETick)
Events.OnGameStart.Add(onGameStart)
