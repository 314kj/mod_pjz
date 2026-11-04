-- Cookie Helper : client core (state, network, my houses, overlays, right-click menu, guest popup)
if isServer() then return end

require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "CookieHelper/CH_Shared"
require "CookieHelper/CH_UI"

CHelp.Cl = CHelp.Cl or {}
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local t = CHelp.t
local floor = math.floor

C.guests = C.guests or {}       -- username -> { sh, role, exp, title }
C.zones = C.zones or {}         -- shKey -> { zone, ... }
C.offset = C.offset or 0        -- server clock - local clock (seconds)
C.showArea = false              -- light up every house of mine
C.hl = C.hl or {}               -- shKey -> true : light up one house
C.marks = C.marks or {}         -- temporary world highlights
C.listeners = C.listeners or {}
C.asks = C.asks or {}           -- open guest-request popups by id
C.hasAny = CHelp.hasAny

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
    if ok and v == true then return true end
    local p = C.player()
    if p then
        local okR, role = pcall(function() return p:getRole() end)
        if okR and role then
            local okA, a = pcall(function() return role:hasAdminTool() end)
            if okA and a == true then return true end
            -- same rule as the server: staff who may set up safehouses count as admin here
            local okC, c = pcall(function() return role:hasCapability(Capability.CanSetupSafehouses) end)
            if okC and c == true then return true end
        end
    end
    return false
end

-- "owner" / "member" / "guest" / nil
function C.roleIn(sh, user)
    user = user or C.me()
    if not sh or not user then return nil end
    if sh:getOwner() == user then return "owner" end
    if C.guestOf(user, CHelp.shKey(sh)) then return "guest" end
    if sh:playerAllowed(user) then return "member" end
    return nil
end

-- every house I belong to: owned first, then member, then guest. The order picks the colour.
local housesCache, housesMs = nil, 0
function C.invalidateHouses() housesCache = nil end

function C.myHouses()
    local ms = CHelp.nowMs()
    if housesCache and ms - housesMs < 2000 then return housesCache end
    local me = C.me()
    local out = {}
    local function add(sh, role)
        local i = #out + 1
        local col = T.HOUSE[((i - 1) % #T.HOUSE) + 1]
        out[i] = { sh = sh, key = CHelp.shKey(sh), role = role, color = col,
            colorName = t("Color_" .. T.HOUSE_NAMES[((i - 1) % #T.HOUSE_NAMES) + 1]) }
    end
    if me then
        for _, sh in ipairs(CHelp.ownedBy(me)) do add(sh, "owner") end
        local guests = {}
        for _, sh in ipairs(CHelp.memberOf(me)) do
            if C.guestOf(me, CHelp.shKey(sh)) then guests[#guests + 1] = sh else add(sh, "member") end
        end
        for _, sh in ipairs(guests) do add(sh, "guest") end
    end
    housesCache, housesMs = out, ms
    return out
end

function C.houseInfo(sh)
    if not sh then return nil end
    local key = CHelp.shKey(sh)
    for _, h in ipairs(C.myHouses()) do
        if h.key == key then return h end
    end
    return nil
end

function C.houseColor(sh)
    local h = C.houseInfo(sh)
    return h and h.color or K.text2
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
    for _, h in ipairs(C.myHouses()) do
        if h.role ~= "guest" then return h.sh end
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

function C.mark(x1, y1, x2, y2, z, r, g, b, a, ms, label, tag)
    C.marks[#C.marks + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = z, r = r, g = g, b = b, a = a,
        untilMs = CHelp.nowMs() + (ms or 4000), label = label, tag = tag }
end

function C.clearMarks(tag)
    if not tag then C.marks = {} return end
    for i = #C.marks, 1, -1 do if C.marks[i].tag == tag then table.remove(C.marks, i) end end
end

-- light a whole house in its colour for a few seconds (right click, opening its page)
function C.flash(sh, ms)
    if not sh then return end
    C.clearMarks("flash")
    local col = C.houseColor(sh)
    local p = C.player()
    local z = p and floor(p:getZ()) or 0
    C.mark(sh:getX(), sh:getY(), sh:getX2(), sh:getY2(), z, col[1], col[2], col[3], 0.32, ms or 3000, nil, "flash")
end

function C.roleName(role)
    return t("Role_" .. tostring(role))
end

function C.houseRoleName(role)
    return t("HRole_" .. tostring(role))
end

function C.pendingAsks()
    local n = 0
    for _ in pairs(C.asks) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------------ network in
local GOOD = { ReqSent = true, Added = true, AddedFromGuest = true, YouWereAdded = true, ZoneSaved = true,
    HostGuestLeft = true, GuestEnded_left = true, ClaimOk = true, Removed = true, YouLeft = true,
    Transferred = true, YouOwnNow = true, Renamed = true }

local handlers = {}

function handlers.guests(args)
    if args.now then C.offset = tonumber(args.now) - CHelp.now() end
    C.guests = {}
    for user, g in pairs(args.list or {}) do
        C.guests[user] = { sh = g.sh, role = g.role, exp = tonumber(g.exp) or 0, title = g.title }
    end
    C.invalidateHouses()
    C.emit("guests")
end

function handlers.zones(args)
    local list = {}
    for _, z in pairs(args.list or {}) do list[#list + 1] = z end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    C.zones[args.sh] = list
    C.emit("zones", args.sh)
end

C.visits = C.visits or {}
function handlers.visits(args)
    local recv = CHelp.nowMs()
    if type(args.online) == "table" then
        for n, _ in pairs(C.onlineNames) do C.onlineNames[n] = nil end
        for n, v in pairs(args.online) do if v then C.onlineNames[n] = true end end
        C.onlineMs = recv
    end
    for key, v in pairs(args.list or {}) do
        C.visits[key] = { v = tonumber(v) or 0, now = tonumber(args.now) or recv, recv = recv }
    end
    if type(args.main) == "string" then C.mainHouseKey = args.main end
    C.emit("visits")
end

-- the house the game respawns me in: vanilla only checks the first house it finds for a player
-- (SafeHouse.hasSafehouse). The server tells us which one that is; the local list is the fallback.
function C.mainHouse()
    if C.mainHouseKey and C.mainHouseKey ~= "" then
        local sh = CHelp.shByKey(C.mainHouseKey)
        if sh then return sh end
    end
    local p = C.player()
    if not p then return nil end
    local ok, sh = pcall(function() return SafeHouse.hasSafehouse(p) end)
    return ok and sh or nil
end

function C.respawnAllowed()
    local ok, v = pcall(function() return getServerOptions():getBoolean("SafehouseAllowRespawn") end)
    return ok and v == true
end

-- ms since someone of the house was last there (server value when we have it), nil = unknown
function C.visitAge(sh)
    local v = C.visits[CHelp.shKey(sh)]
    if v and v.v > 0 then return (v.now - v.v) + (CHelp.nowMs() - v.recv) end
    local ok, lv = pcall(function() return sh:getLastVisited() end)
    if not ok or not lv or lv <= 0 then return nil end
    return CHelp.nowMs() - lv
end

-- online names reported by the server (the client itself only sees players near it)
C.onlineNames = C.onlineNames or {}
C.onlineMs = C.onlineMs or 0
function C.isOnline(name)
    if not name then return false end
    if C.onlineNames[name] and CHelp.nowMs() - C.onlineMs < 90000 then return true end
    return getPlayerFromUsername(name) ~= nil
end

function handlers.known(args)
    local list = {}
    for _, e in pairs(args.list or {}) do
        if type(e) == "string" then
            list[#list + 1] = { n = e, on = getPlayerFromUsername(e) ~= nil }
        elseif type(e) == "table" and e.n then
            list[#list + 1] = { n = tostring(e.n), on = e.on == true, t = tonumber(e.t) }
        end
    end
    local on = {}
    for _, e in ipairs(list) do if e.on then on[e.n] = true end end
    C.onlineNames, C.onlineMs = on, CHelp.nowMs()
    C.emit("known", list, tonumber(args.now))
end

-- admins can also see the whole account list (whitelist + user log) through the vanilla request
if Events.OnNetworkUsersReceived then Events.OnNetworkUsersReceived.Add(function() C.emit("netusers") end) end

function handlers.msg(args)
    local k = tostring(args.k)
    local good = GOOD[k] or string.sub(k, 1, 9) == "Approved_" or string.sub(k, 1, 13) == "HostApproved_"
    local text = t("Msg_" .. k, args.a, args.b)
    UI.toast(text, good)
    local p = C.player()
    if p then
        if good then HaloTextHelper.addGoodText(p, T.fit(text, 400)) else HaloTextHelper.addBadText(p, T.fit(text, 400)) end
    end
    C.invalidateHouses()
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

Events.OnSafehousesChanged.Add(function()
    C.invalidateHouses()
    C.emit("safehouses")
end)

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
    C.emit("highlight")
end

function C.toggleHouse(sh, on)
    local key = CHelp.shKey(sh)
    if on == nil then on = not C.hl[key] end
    C.hl[key] = on or nil
    C.emit("highlight")
end

-- vanilla refuses a claim when you already belong to any house: we check the rest of its rules here
-- (shown in the menu) and the server checks them all again.
function C.claimState(sq)
    local p = C.player()
    local me = C.me()
    if not p or not sq or not sq:getBuilding() then return nil end
    if SafeHouse.getSafeHouse(sq) then return nil end
    if not CHelp.claimAllowed(p) and not C.isAdmin() then return nil end
    local owned = #CHelp.ownedBy(me)
    local max = CHelp.svInt("MaxOwnedSafehouses", 1, 20)
    if owned >= max and not C.isAdmin() then return { ok = false, why = t("Msg_ClaimLimit", max), owned = owned, max = max } end
    local why = CHelp.claimProblem(sq, p)
    return { ok = why == nil, why = why, owned = owned, max = max }
end

function C.claim(sq)
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    UI.prompt(t("ClaimTitle"), t("ClaimAsk"), (C.me() or "") .. " #" .. tostring(#CHelp.ownedBy(C.me()) + 1), t("Claim"), nil,
        function(_, title)
            CHelp.toServer("claim", { x = x, y = y, z = z, title = title })
        end)
end

-- ------------------------------------------------------------------ guest request popup (for hosts)
local Ask = UI.Window:derive("CHelpAsk")
local ROLE_PX = { doctor = "medkit", builder = "hammer", keeper = "wcan" }

function Ask:createChildren()
    UI.Window.createChildren(self)
    local y = UI.HEAD_H + 6 + UI.HS * 2 + 14
    local w = self.width - UI.PAD * 2
    for _, role in ipairs(CHelp.ROLES) do
        local b = UI.button(self, UI.PAD, y, w, C.roleName(role), self, Ask.onRole, "sec", UI.BTN_H + 8)
        b:setIcon(ROLE_PX[role], true)
        b.role = role
        b.tooltip = t("RoleTip_" .. role)
        y = y + UI.BTN_H + 14
    end
    local d = UI.button(self, UI.PAD, y + 4, w, t("Deny"), self, Ask.onRole, "bad")
    d.role = "deny"
end

function Ask:onRole(btn)
    CHelp.toServer("guestAnswer", { id = self.args.id, role = btn.role })
    self:close()
end

function Ask:onClose()
    C.asks[self.args.id] = nil
    C.emit("asks")
end

function Ask:drawBody()
    local left = math.max(0, 60 - floor((CHelp.nowMs() - self.born) / 1000))
    if left <= 0 then self:close() return end
    local y = UI.HEAD_H + 6
    T.text(self, T.fit(t("AskLine1", self.args.guest), self.width - UI.PAD * 2 - 60), UI.PAD, y, K.text)
    T.text(self, T.fit(t("AskLine2", self.args.title or "", self.args.minutes or 10), self.width - UI.PAD * 2), UI.PAD, y + UI.HS + 4, K.text3)
    T.pill(self, self.width - UI.PAD - T.pillW(tostring(left) .. "s"), y, tostring(left) .. "s", K.warn, K.warnD)
end

function C.openAsk(args)
    if C.asks[args.id] then return end
    local w, h = 380, UI.HEAD_H + 6 + UI.HS * 2 + 14 + (UI.BTN_H + 14) * 3 + 4 + UI.BTN_H + UI.PAD
    local x, y = UI.center(w, h)
    local win = Ask:new(x, y - 80, w, h, t("AskTitle"))
    win.args = args
    win.born = CHelp.nowMs()
    win:show()
    C.asks[args.id] = win
    C.emit("asks")
    getSoundManager():playUISound("UISelectListItem")
end

-- ------------------------------------------------------------------ overlays (one cheap pass per frame)
local ROLE_COL = {
    doctor = K.info,
    builder = K.warn,
    keeper = K.acc,
}
local nameCache, nameCacheMs = {}, 0

local function drawShadowText(x, y, s, c)
    local tm = getTextManager()
    tm:DrawStringCentre(UIFont.Small, x + 1, y + 1, s, 0, 0, 0, 0.85)
    tm:DrawStringCentre(UIFont.Small, x, y, s, c[1], c[2], c[3], 1)
end

local function overlays()
    local p = C.player()
    if not p then return end
    local pz = floor(p:getZ())
    local ms = CHelp.nowMs()

    if C.showArea or CHelp.hasAny(C.hl) then
        for _, h in ipairs(C.myHouses()) do
            if C.showArea or C.hl[h.key] then
                local sh = h.sh
                addAreaHighlight(sh:getX(), sh:getY(), sh:getX2(), sh:getY2(), pz, h.color[1], h.color[2], h.color[3], 0.26)
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
                    drawShadowText(sx, sy - 40 / getCore():getZoom(0), m.label, { m.r, m.g, m.b })
                end
            end
        end
        C.marks = keep
    end

    -- guest timers above heads (visible to everyone nearby)
    if CHelp.hasAny(C.guests) then
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
                local sx = isoToScreenX(0, gp:getX(), gp:getY(), gp:getZ())
                local sy = isoToScreenY(0, gp:getX(), gp:getY(), gp:getZ())
                drawShadowText(sx, sy - 175 / zoom, s, ROLE_COL[g.role] or K.info)
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

-- ------------------------------------------------------------------ right-click menu
local function icon(opt, name)
    if not opt then return end
    local tx = T.tex(name)
    if tx then opt.iconTexture = tx end
end

local function tip(opt, text)
    local tt = ISToolTip:new()
    tt:initialise()
    tt:setVisible(false)
    tt.description = text
    opt.toolTip = tt
end

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
    icon(root, "cookie_32")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local any = false

    -- which house was clicked, and what am I there
    local here = CHelp.shAt(x, y)
    local hereRole = here and C.roleIn(here, me) or nil
    if here and (hereRole or C.isAdmin()) then
        local info = C.houseInfo(here)
        local head = sub:addOption(T.fit(here:getTitle(), 220) .. "  ·  " .. C.houseRoleName(hereRole or "admin"), nil, nil)
        head.notAvailable = true
        icon(head, "circle")
        local col = info and info.color or K.text2
        head.color = { r = col[1], g = col[2], b = col[3] }
        icon(sub:addOption(t("Menu_OpenHouse"), here, function(sh) if CHelp.Houses then CHelp.Houses.open(CHelp.shKey(sh)) end end), "px_house")
        local lit = C.hl[CHelp.shKey(here)] == true
        icon(sub:addOption(lit and t("Menu_HideHouse") or t("Menu_ShowHouse", info and info.colorName or ""), here,
            function(sh) C.toggleHouse(sh) end), "px_search")
        any = true
    end

    local mine = C.pickSafehouse(x, y)
    if mine then
        icon(sub:addOption(C.showArea and t("Menu_HideArea") or t("Menu_ShowArea"), nil, C.toggleArea), "px_search")
        if here == mine and (C.isRealMember(mine) or C.isAdmin()) then
            local cz = C.zoneAt(mine, x, y, z, CHelp.ZONE_COUNT)
            if cz then icon(sub:addOption(t("Menu_OpenCount", cz.name), mine, function(sh) CHelp.Count.open(sh, cz) end), "px_crate") end
            local vz = C.zoneAt(mine, x, y, z, CHelp.ZONE_VEHICLE)
            if vz then icon(sub:addOption(t("Menu_OpenVehicle", vz.name), mine, function(sh) CHelp.Veh.open(sh, vz) end), "px_car") end
        end
        icon(sub:addOption(t("Menu_Zones"), mine, function(sh) if CHelp.Hub then CHelp.Hub.open(sh) end end), "px_crate")
        icon(sub:addOption(t("Menu_Finder"), mine, function(sh) CHelp.Finder.open(sh) end), "px_search")
        any = true
    end

    if #C.myHouses() > 0 then
        icon(sub:addOption(t("Menu_MyHouses"), nil, function() if CHelp.Houses then CHelp.Houses.open() end end), "px_key")
        any = true
    end

    local nAsk = C.pendingAsks()
    if nAsk > 0 then
        icon(sub:addOption(t("DockAsks", nAsk), nil, function()
            for _, w in pairs(C.asks) do w:bringToTop() end
        end), "px_medkit")
        any = true
    end

    local myGuest = C.guests[me]
    if myGuest then
        icon(sub:addOption(t("Menu_LeaveGuest"), nil, C.leaveGuest), "ic_door")
        any = true
    else
        local range = CHelp.svInt("GuestRequestRange", 1, 60)
        local near = CHelp.shNearest(floor(p:getX()), floor(p:getY()), range)
        if near and not near:playerAllowed(me) then
            icon(sub:addOption(t("Menu_RequestGuest", near:getTitle()), near, C.requestGuest), "px_medkit")
            any = true
        end
    end

    -- claiming another house: vanilla only offers it to players with no house at all
    if not here and SafeHouse.hasSafehouse(p) then
        local okC, st = pcall(C.claimState, sq)
        if okC and st then
            local opt = sub:addOption(t("Menu_Claim", st.owned + 1, st.max), sq, C.claim)
            icon(opt, "px_house")
            if not st.ok then
                opt.notAvailable = true
                tip(opt, st.why or "")
            end
            any = true
        end
    end

    if not any then context:removeLastOption() end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorld)

-- ------------------------------------------------------------------ vanilla safehouse panel -> my houses
local function patchVanilla()
    if ISUserPanelUI and not ISUserPanelUI.chPatched then
        ISUserPanelUI.chPatched = true
        local origDown = ISUserPanelUI.onOptionMouseDown
        ISUserPanelUI.onOptionMouseDown = function(self, button, x, y)
            if button and button.internal == "SAFEHOUSEPANEL" and CHelp.Houses then
                CHelp.Houses.open()
                return
            end
            return origDown(self, button, x, y)
        end
        local origCreate = ISUserPanelUI.create
        ISUserPanelUI.create = function(self)
            origCreate(self)
            if self.safehouseBtn then self.safehouseBtn:setTitle(t("MyHouses")) end
        end
    end
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.onViewSafeHouse and not ISWorldObjectContextMenu.chPatched then
        ISWorldObjectContextMenu.chPatched = true
        local origView = ISWorldObjectContextMenu.onViewSafeHouse
        ISWorldObjectContextMenu.onViewSafeHouse = function(worldobjects, safehouse, player)
            if CHelp.Houses and safehouse then
                CHelp.Houses.open(CHelp.shKey(safehouse))
                return
            end
            return origView(worldobjects, safehouse, player)
        end
    end
end
Events.OnGameStart.Add(patchVanilla)
