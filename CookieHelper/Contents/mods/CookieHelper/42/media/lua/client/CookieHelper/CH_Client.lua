-- Cookie Helper : client core (state, network, overlays, context menu, guest popup)
if isServer() then return end

require "ISUI/ISContextMenu"
require "CookieHelper/CH_Shared"
require "CookieHelper/CH_UI"

CHelp.Cl = CHelp.Cl or {}
local C = CHelp.Cl
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

C.guests = C.guests or {}       -- username -> { sh, role, exp, title }
C.zones = C.zones or {}         -- shKey -> { zone, ... }
C.offset = C.offset or 0        -- server clock - local clock (seconds)
C.showArea = false
C.marks = C.marks or {}         -- temporary world highlights { x1,y1,x2,y2,z,r,g,b,a,untilMs, label }
C.listeners = C.listeners or {}
C.asks = C.asks or {}           -- open guest-request popups by id

-- ------------------------------------------------------------------ tiny event bus for windows
function C.on(evt, owner, fn)
    C.listeners[evt] = C.listeners[evt] or {}
    C.listeners[evt][owner] = fn
end

function C.off(owner)
    for _, l in pairs(C.listeners) do l[owner] = nil end
end

function C.emit(evt, a, b)
    local l = C.listeners[evt]
    if not l then return end
    for owner, fn in pairs(l) do
        local ok, err = pcall(fn, owner, a, b)
        if not ok then CHelp.log("listener " .. tostring(evt) .. " failed: " .. tostring(err)) end
    end
end

-- ------------------------------------------------------------------ helpers
function C.player() return getSpecificPlayer(0) end
function C.me()
    local p = C.player()
    return p and p:getUsername() or nil
end
function C.serverNow() return CHelp.now() + (C.offset or 0) end

function C.guestOf(user, key)
    local g = C.guests[user]
    return g ~= nil and g.sh == key
end

function C.isRealMember(sh, user)
    user = user or C.me()
    if not sh or not user then return false end
    if not sh:playerAllowed(user) then return false end
    return not C.guestOf(user, CHelp.shKey(sh))
end

function C.isAdmin()
    if CHelp.isSP() then return true end
    local ok, v = pcall(isAdmin)
    return ok and v == true
end

-- the safehouse the helper should work on: the one under the cursor/player, else the first owned one
function C.pickSafehouse(x, y)
    local me = C.me()
    if x and y then
        local sh = CHelp.shAt(x, y)
        if sh and (C.isRealMember(sh, me) or C.isAdmin()) then return sh end
    end
    local p = C.player()
    if p then
        local sh = CHelp.shAt(floor(p:getX()), floor(p:getY()))
        if sh and (C.isRealMember(sh, me) or C.isAdmin()) then return sh end
    end
    for _, sh in ipairs(CHelp.shListFor(me)) do
        if C.isRealMember(sh, me) then return sh end
    end
    return nil
end

function C.zonesOf(sh)
    return C.zones[CHelp.shKey(sh)] or {}
end

function C.zoneAt(sh, x, y, z, kind)
    for _, zn in ipairs(C.zonesOf(sh)) do
        if (not kind or zn.kind == kind) and zn.z == z and CHelp.rectHas(zn, x, y) then return zn end
    end
    return nil
end

function C.mark(x1, y1, x2, y2, z, r, g, b, a, ms, label)
    C.marks[#C.marks + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = z, r = r, g = g, b = b, a = a,
        untilMs = CHelp.nowMs() + (ms or 4000), label = label }
end

function C.clearMarks(tag)
    if not tag then C.marks = {} return end
    for i = #C.marks, 1, -1 do if C.marks[i].tag == tag then table.remove(C.marks, i) end end
end

function C.roleName(role)
    return t("Role_" .. tostring(role))
end

-- ------------------------------------------------------------------ network in
local GOOD = { ReqSent = true, Added = true, AddedFromGuest = true, YouWereAdded = true, ZoneSaved = true,
    HostGuestLeft = true, GuestEnded_left = true }

local handlers = {}

function handlers.guests(args)
    if args.now then C.offset = tonumber(args.now) - CHelp.now() end
    C.guests = {}
    for user, g in pairs(args.list or {}) do
        C.guests[user] = { sh = g.sh, role = g.role, exp = tonumber(g.exp) or 0, title = g.title }
    end
    C.emit("guests")
end

function handlers.zones(args)
    local list = {}
    for _, z in pairs(args.list or {}) do list[#list + 1] = z end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    C.zones[args.sh] = list
    C.emit("zones", args.sh)
end

function handlers.known(args)
    local list = {}
    for _, n in pairs(args.list or {}) do list[#list + 1] = n end
    table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
    C.emit("known", list)
end

function handlers.msg(args)
    local k = tostring(args.k)
    local good = GOOD[k] or string.sub(k, 1, 9) == "Approved_" or string.sub(k, 1, 13) == "HostApproved_"
    local text = t("Msg_" .. k, args.a, args.b)
    UI.toast(text, good)
    local p = C.player()
    if p then
        if good then HaloTextHelper.addGoodText(p, UI.fit(text, 400)) else HaloTextHelper.addBadText(p, UI.fit(text, 400)) end
    end
    C.emit("msg", k)
end

function handlers.guestAsk(args)
    if C.openAsk then C.openAsk(args) end
end

function handlers.guestAskClose(args)
    local w = C.asks[args.id]
    if w then w:close() end
end

function handlers.vehList(args)
    local list = {}
    for _, n in pairs(args.list or {}) do list[#list + 1] = n end
    C.emit("vehList", list)
end

function handlers.vehData(args)
    local items, extra = {}, {}
    for _, v in pairs(args.items or {}) do items[#items + 1] = v end
    for _, v in pairs(args.extra or {}) do extra[#extra + 1] = v end
    C.emit("vehData", args.veh, { items = items, extra = extra, known = args.items ~= nil })
end

function C.onCommand(cmd, args)
    local f = handlers[cmd]
    if f then
        local ok, err = pcall(f, args or {})
        if not ok then CHelp.log("client " .. tostring(cmd) .. " failed: " .. tostring(err)) end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CHelp.NET then return end
    C.onCommand(command, args)
end)

local helloSent = false
local function sayHello()
    if helloSent then return end
    if not C.player() then return end
    helloSent = true
    CHelp.toServer("hello", { v = CHelp.VERSION })
end
Events.OnGameStart.Add(sayHello)
Events.OnCreatePlayer.Add(function() sayHello() end)

Events.OnSafehousesChanged.Add(function() C.emit("safehouses") end)

-- ------------------------------------------------------------------ actions
function C.requestGuest(sh)
    CHelp.toServer("guestRequest", { sh = CHelp.shKey(sh) })
end

function C.leaveGuest()
    CHelp.toServer("guestEnd", { user = C.me() })
end

function C.toggleArea()
    C.showArea = not C.showArea
    UI.toast(C.showArea and t("Msg_AreaOn") or t("Msg_AreaOff"), true)
end

-- ------------------------------------------------------------------ guest request popup (for hosts)
local Ask = UI.Window:derive("CHelpAsk")

function Ask:createChildren()
    UI.Window.createChildren(self)
    local y = UI.HEAD_H + UI.PAD + UI.HS * 2 + 16
    local w = self.width - UI.PAD * 2
    self.btns = {}
    for i, role in ipairs(CHelp.ROLES) do
        local b = UI.button(self, UI.PAD, y, w, C.roleName(role), self, Ask.onRole, "mint")
        b.role = role
        b.tooltip = t("RoleTip_" .. role)
        y = y + UI.BTN_H + 6
    end
    local d = UI.button(self, UI.PAD, y + 4, w, t("Deny"), self, Ask.onRole, "red")
    d.role = "deny"
end

function Ask:onRole(btn)
    CHelp.toServer("guestAnswer", { id = self.args.id, role = btn.role })
    self:close()
end

function Ask:onClose()
    C.asks[self.args.id] = nil
end

function Ask:drawBody()
    local left = math.max(0, 60 - floor((CHelp.nowMs() - self.born) / 1000))
    if left <= 0 then self:close() return end
    UI.text(self, UI.fit(t("AskLine1", self.args.guest), self.width - 20), UI.PAD, UI.HEAD_H + UI.PAD, UI.C.text)
    UI.text(self, UI.fit(t("AskLine2", self.args.title or "", self.args.minutes or 10), self.width - 20),
        UI.PAD, UI.HEAD_H + UI.PAD + UI.HS + 4, UI.C.muted)
    UI.textR(self, tostring(left) .. "s", self.width - UI.PAD, UI.HEAD_H + UI.PAD, UI.C.gold)
end

function C.openAsk(args)
    if C.asks[args.id] then return end
    local w, h = 360, UI.HEAD_H + UI.PAD * 2 + UI.HS * 2 + 16 + (UI.BTN_H + 6) * 4 + 8
    local x, y = UI.center(w, h)
    local win = Ask:new(x, y - 80, w, h, t("AskTitle"))
    win.args = args
    win.born = CHelp.nowMs()
    win:show()
    C.asks[args.id] = win
    getSoundManager():playUISound("UISelectListItem")
end

-- ------------------------------------------------------------------ overlays (one cheap pass per frame)
local ROLE_COL = {
    doctor = { 0.55, 0.85, 1.0 },
    builder = { 1.0, 0.80, 0.38 },
    keeper = { 0.56, 0.88, 0.63 },
}
local nameCache, nameCacheMs = {}, 0

local function drawShadowText(x, y, s, r, g, b)
    local tm = getTextManager()
    tm:DrawStringCentre(UIFont.Small, x + 1, y + 1, s, 0, 0, 0, 0.85)
    tm:DrawStringCentre(UIFont.Small, x, y, s, r, g, b, 1)
end

local function overlays()
    local p = C.player()
    if not p then return end
    local pz = floor(p:getZ())
    local ms = CHelp.nowMs()

    if C.showArea then
        for _, sh in ipairs(CHelp.shListFor(C.me())) do
            if C.isRealMember(sh) then
                addAreaHighlight(sh:getX(), sh:getY(), sh:getX2(), sh:getY2(), pz, 0.55, 1.0, 0.55, 0.28)
            end
        end
    end

    if #C.marks > 0 then
        local keep = {}
        for _, m in ipairs(C.marks) do
            if m.untilMs > ms then
                keep[#keep + 1] = m
                if m.z == pz then addAreaHighlight(m.x1, m.y1, m.x2, m.y2, m.z, m.r, m.g, m.b, m.a) end
                if m.label and m.z == pz then
                    local sx = isoToScreenX(0, m.x1 + 0.5, m.y1 + 0.5, m.z)
                    local sy = isoToScreenY(0, m.x1 + 0.5, m.y1 + 0.5, m.z)
                    drawShadowText(sx, sy - 40 / getCore():getZoom(0), m.label, m.r, m.g, m.b)
                end
            end
        end
        C.marks = keep
    end

    -- guest timers above heads (visible to everyone nearby)
    if next(C.guests) ~= nil then
        if ms - nameCacheMs > 1000 then
            nameCacheMs = ms
            nameCache = {}
            for user, _ in pairs(C.guests) do nameCache[user] = getPlayerFromUsername(user) end
        end
        local now = C.serverNow()
        local zoom = getCore():getZoom(0)
        for user, g in pairs(C.guests) do
            local gp = nameCache[user]
            if gp and gp:getCurrentSquare() and math.abs(gp:getZ() - p:getZ()) < 1
                and math.abs(gp:getX() - p:getX()) < 40 and math.abs(gp:getY() - p:getY()) < 40 then
                local left = math.max(0, floor(g.exp - now))
                local mm, ss = floor(left / 60), left % 60
                local s = C.roleName(g.role) .. "  " .. tostring(mm) .. ":" .. (ss < 10 and "0" or "") .. tostring(ss)
                local col = ROLE_COL[g.role] or ROLE_COL.doctor
                local sx = isoToScreenX(0, gp:getX(), gp:getY(), gp:getZ())
                local sy = isoToScreenY(0, gp:getX(), gp:getY(), gp:getZ())
                drawShadowText(sx, sy - 175 / zoom, s, col[1], col[2], col[3])
            end
        end
    end
end

Events.OnPreUIDraw.Add(function()
    local ok, err = pcall(overlays)
    if not ok then
        CHelp.log("overlay error: " .. tostring(err))
        C.marks = {}
    end
end)

-- ------------------------------------------------------------------ context menu
local function onFillWorld(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    local p = getSpecificPlayer(playerNum)
    if not p then return end
    local sq = nil
    for _, o in ipairs(worldobjects) do
        if o and o.getSquare and o:getSquare() then sq = o:getSquare() break end
    end
    sq = sq or p:getCurrentSquare()
    if not sq then return end
    local me = p:getUsername()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()

    local root = context:addOption(t("Menu_Root"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local any = false

    local myGuest = C.guests[me]
    if myGuest then
        sub:addOption(t("Menu_LeaveGuest"), nil, C.leaveGuest)
        any = true
    end

    local mine = C.pickSafehouse(x, y)
    if mine then
        sub:addOption(t("Menu_Open"), mine, function(sh) if CHelp.Hub then CHelp.Hub.open(sh) end end)
        sub:addOption(C.showArea and t("Menu_HideArea") or t("Menu_ShowArea"), nil, C.toggleArea)
        if CHelp.shAt(x, y) == mine then
            local cz = C.zoneAt(mine, x, y, z, CHelp.ZONE_COUNT)
            if cz then sub:addOption(t("Menu_OpenCount", cz.name), mine, function(sh) CHelp.Count.open(sh, cz) end) end
            local vz = C.zoneAt(mine, x, y, z, CHelp.ZONE_VEHICLE)
            if vz then sub:addOption(t("Menu_OpenVehicle", vz.name), mine, function(sh) CHelp.Veh.open(sh, vz) end) end
        end
        sub:addOption(t("Menu_Finder"), mine, function(sh) CHelp.Finder.open(sh) end)
        any = true
    end

    if not myGuest then
        local range = CHelp.svInt("GuestRequestRange", 1, 60)
        local near = CHelp.shNearest(floor(p:getX()), floor(p:getY()), range)
        if near and not near:playerAllowed(me) then
            sub:addOption(t("Menu_RequestGuest", near:getTitle()), near, C.requestGuest)
            any = true
        end
    end

    if not any then context:removeLastOption() end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorld)
