-- Cookie Helper : "My houses" (replaces the vanilla safehouse panel)
-- Left: every house you own / live in / visit, each in its own colour. Right: the selected house -
-- who is in it, what you may do there, highlight, zones, and the owner actions.
if isServer() then return end

require "CookieHelper/CH_Client"

CHelp.Houses = CHelp.Houses or {}
local H = CHelp.Houses
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local t = CHelp.t
local floor = math.floor

local W_ = 940
local H_ = 660
local LIST_W = 320
local CARD_H = 80
local FOOT_H = 28

local Win = UI.Window:derive("CHelpHouses")

local ROLE_STYLE = {
    owner  = { fg = K.acc,   bg = K.accD,   px = "crown" },
    member = { fg = K.info,  bg = K.infoD,  px = "key" },
    guest  = { fg = K.peach, bg = K.peachD, px = "medkit" },
    admin  = { fg = K.text2, bg = K.surf2,  px = "search" },
}

local function rolePill(el, x, y, role, prefix, rightAlign)
    local st = ROLE_STYLE[role] or ROLE_STYLE.admin
    local label = (prefix or "") .. C.houseRoleName(role)
    local w = T.pillW(label, T.FS, { px = st.px })
    if rightAlign then x = x - w end
    T.pill(el, x, y, label, st.fg, st.bg, T.FS, { px = st.px })
    return w
end

local function ago(age)
    if not age then return nil end
    local h = floor(age / 3600000)
    if h < 1 then return t("AgoNow") end
    if h < 48 then return t("AgoHours", h) end
    return t("AgoDays", floor(h / 24))
end

local remCache, remMs = 0, -1
local function removalHours()
    local ms = CHelp.nowMs()
    if remMs >= 0 and ms - remMs < 30000 then return remCache end
    remMs = ms
    local ok, v = pcall(function() return getServerOptions():getInteger("SafeHouseRemovalTime") end)
    remCache = (ok and tonumber(v)) or 0
    return remCache
end

-- online dot + guest timer of one person row, refreshed once a second while drawn
local function liveInfo(d)
    local ms = CHelp.nowMs()
    if d.chkMs and ms - d.chkMs < 1000 then return end
    d.chkMs = ms
    d.online = C.isOnline(d.name)
    local g = C.guests[d.name]
    if g and g.sh == d.key then
        local left = math.max(0, floor(g.exp - C.serverNow()))
        d.extra = C.roleName(g.role) .. " · " .. t("Left", floor(left / 60) .. ":" .. ((left % 60) < 10 and "0" or "") .. tostring(left % 60))
        d.role = "guest"
    else
        d.extra = d.baseExtra
        d.role = d.baseRole
    end
end

-- ------------------------------------------------------------------ build
function Win:createChildren()
    UI.Window.createChildren(self)
    self.listScroll = 0
    self.hits = {}
    local rx = UI.PAD + LIST_W + UI.PAD
    self.rx, self.rw = rx, self.width - rx - UI.PAD
    self.bodyY = UI.HEAD_H + 4
    self.bodyH = self.height - self.bodyY - FOOT_H - 8

    self.allBtn = UI.button(self, self:headRight() - 170, floor((UI.HEAD_H - UI.BTN_H) / 2), 170, "", self, Win.onAll, "sec")
    self.allBtn:setIcon("eye")
    self.headTextRight = self.allBtn:getX() - 280

    -- right panel widgets (positions set in layout)
    local px = rx + 18
    local pw = self.rw - 36
    self.pw = pw
    self.people = UI.makeList(self, px, 0, pw, 120, UI.HS + 26, self, Win.drawPerson, Win.onPerson)
    self.people.rowGap = 4
    self.people.bare = false
    self.people.onMouseDown = function(l, mx, my)
        local row = l:rowAt(mx, my)
        local it = l.items[row]
        if it and it.item.removeHit and mx >= it.item.removeHit then
            self:askRemove(it.item.name)
            return true
        end
        return ISScrollingListBox.onMouseDown(l, mx, my)
    end
    self.addEntry = UI.entry(self, px, 0, 200, "")
    self.addEntry:setPlaceholderText((CHelp.sv("AllowOfflineAdd") or C.isAdmin()) and t("AddHint") or t("AddHintOnline"))
    self.addBtn = UI.button(self, 0, 0, 90, t("Add"), self, Win.onAdd, "pri")
    self.listBtn = UI.button(self, 0, 0, 120, t("PickName"), self, Win.onPickName, "sec")
    self.listBtn:setIcon("userplus")

    self.hlBtn = UI.button(self, px, 0, 200, "", self, Win.onHl, "sec")
    self.hlBtn:setIcon("eye")
    self.zoneBtn = UI.button(self, 0, 0, 150, "", self, Win.onZones, "sec")
    self.zoneBtn:setIcon("crate", true)
    self.findBtn = UI.button(self, 0, 0, 150, t("Menu_Finder"), self, Win.onFinder, "sec")
    self.findBtn:setIcon("search", true)

    self.renameBtn = UI.button(self, px, 0, 140, t("RenameHouse"), self, Win.onRename, "sec")
    self.renameBtn:setIcon("pencil")
    self.transferBtn = UI.button(self, 0, 0, 200, "", self, Win.onTransfer, "sec")
    self.transferBtn:setIcon("swap")
    self.dangerBtn = UI.button(self, 0, 0, 160, "", self, Win.onDanger, "bad")

    C.on("safehouses", self, Win.refresh)
    C.on("guests", self, Win.refresh)
    C.on("msg", self, Win.refresh)
    C.on("highlight", self, Win.layout)
    self:refresh()
end

function Win:onClose()
    C.off(self)
    if H.instance == self then H.instance = nil end
end

-- ------------------------------------------------------------------ data
function Win:refresh()
    C.invalidateHouses()
    local list = {}
    for _, h in ipairs(C.myHouses()) do list[#list + 1] = h end
    if self.extraKey then
        local found = false
        for _, h in ipairs(list) do if h.key == self.extraKey then found = true end end
        local sh = CHelp.shByKey(self.extraKey)
        if not found and sh then
            list[#list + 1] = { sh = sh, key = self.extraKey, role = "admin", color = K.text2, colorName = t("Color_Gray") }
        end
    end
    self.houses = list
    local keep = nil
    for _, h in ipairs(list) do if h.key == self.selKey then keep = h end end
    self.sel = keep or list[1]
    self.selKey = self.sel and self.sel.key or nil
    self:fillPeople()
    self:layout()
end

function Win:fillPeople()
    local keepName = nil
    local it = self.people.items[self.people.selected]
    if it then keepName = it.item.name end
    self.people:clear()
    self.people.selected = 0
    local h = self.sel
    if not h then return end
    local sh = h.sh
    local owner = sh:getOwner()
    local function add(name, role)
        local d = { name = name, role = role, baseRole = role, key = h.key, baseExtra = (name == C.me()) and t("You") or "" }
        liveInfo(d)
        self.people:addItem(name, d)
    end
    add(owner, "owner")
    local players = sh:getPlayers()
    for i = 0, players:size() - 1 do
        local n = players:get(i)
        if n ~= owner then add(n, "member") end
    end
    for i, row in ipairs(self.people.items) do
        if row.item.name == keepName then self.people.selected = i end
    end
end

function Win:myRole()
    local h = self.sel
    if not h then return nil end
    return h.role
end

function Win:canManage()
    local h = self.sel
    if not h then return false end
    return h.role == "owner" or C.isAdmin()
end

function Win:selectedPerson()
    local it = self.people.items[self.people.selected]
    return it and it.item or nil
end

-- ------------------------------------------------------------------ layout of the right panel widgets
function Win:layout()
    local h = self.sel
    local show = h ~= nil
    for _, w in ipairs({ self.people, self.addEntry, self.addBtn, self.listBtn, self.hlBtn, self.zoneBtn, self.findBtn,
        self.renameBtn, self.transferBtn, self.dangerBtn }) do w:setVisible(show) end
    self.allBtn:setTitle(C.showArea and t("HideAll") or t("ShowAll"))
    self.allBtn:setKind(C.showArea and "soft" or "sec")
    if not h then return end
    local px = self.rx + 18
    local pw = self.pw
    local bottom = self.bodyY + self.bodyH - 18
    local role = h.role
    local manage = self:canManage()
    local member = role == "owner" or role == "member" or C.isAdmin()

    -- bottom: actions
    local y = bottom - UI.BTN_H
    self.renameBtn:setVisible(manage)
    self.transferBtn:setVisible(manage)
    self.renameBtn:setX(px) self.renameBtn:setY(y)
    self.transferBtn:setX(px + 150) self.transferBtn:setY(y)
    local person = self:selectedPerson()
    local canGive = person and person.role == "member"
    self.transferBtn:setTitle(canGive and t("TransferTo", person.name) or t("TransferPick"))
    self.transferBtn:setEnable(canGive == true)
    local dangerKey = (role == "owner" or (role == "admin" and C.isAdmin())) and "Release" or (role == "guest" and "EndGuest" or "Leave")
    self.dangerKey = dangerKey
    self.dangerBtn:setTitle(t(dangerKey))
    self.dangerBtn:setIcon(dangerKey == "Release" and "close" or "door")
    self.dangerBtn:setWidth(math.max(140, T.tw(t(dangerKey)) + 56))
    self.dangerBtn:setX(px + pw - self.dangerBtn.width) self.dangerBtn:setY(y)

    -- above: highlight / zones / finder
    y = y - UI.BTN_H - 12
    local lit = C.hl[h.key] == true
    self.hlBtn:setTitle(lit and t("HideHouse") or t("ShowHouseColor", h.colorName))
    self.hlBtn:setKind(lit and "soft" or "sec")
    self.hlBtn:setWidth(math.max(180, T.tw(self.hlBtn.title) + 50))
    self.hlBtn:setX(px) self.hlBtn:setY(y)
    local nz = #C.zonesOf(h.sh)
    self.zoneBtn:setTitle(t("ZonesN", nz))
    self.zoneBtn:setX(self.hlBtn:getX() + self.hlBtn.width + 8) self.zoneBtn:setY(y)
    self.findBtn:setX(self.zoneBtn:getX() + self.zoneBtn.width + 8) self.findBtn:setY(y)
    self.zoneBtn:setVisible(member)
    self.findBtn:setVisible(member)

    -- add member row
    local addY = y - UI.BTN_H - 12
    local canAdd = manage
    self.addEntry:setVisible(canAdd)
    self.addBtn:setVisible(canAdd)
    self.listBtn:setVisible(canAdd)
    local labelW = T.tw(t("AddMember")) + 12
    self.addLabelY = addY
    self.addEntry:setX(px + labelW) self.addEntry:setY(addY)
    self.addEntry:setWidth(pw - labelW - 90 - 120 - 16)
    self.addBtn:setX(px + pw - 90 - 120 - 8) self.addBtn:setY(addY)
    self.listBtn:setX(px + pw - 120) self.listBtn:setY(addY)

    -- people list fills the space between the text block and the add row
    local listTop = self.peopleTop or (self.bodyY + 200)
    local listBottom = (canAdd and addY or (y)) - 12
    self.people:setX(px) self.people:setY(listTop)
    self.people:setWidth(pw)
    self.people:setHeight(math.max(UI.HS + 30, listBottom - listTop))
end

-- ------------------------------------------------------------------ drawing
function Win:drawStats()
    local me = C.me()
    local owned = 0
    for _, h in ipairs(self.houses or {}) do if h.role == "owner" then owned = owned + 1 end end
    local maxO = CHelp.svInt("MaxOwnedSafehouses", 1, 20)
    local mem, guest = 0, 0
    for _, h in ipairs(self.houses or {}) do
        if h.role == "member" then mem = mem + 1 elseif h.role == "guest" then guest = guest + 1 end
    end
    local maxM = CHelp.svInt("MaxMemberships", 0, 50)
    local cells = {
        { px = "crown", label = C.houseRoleName("owner"), v = tostring(owned), of = "/" .. maxO, c = K.acc },
        { px = "key", label = C.houseRoleName("member"), v = tostring(mem), of = maxM > 0 and ("/" .. maxM) or "", c = K.info },
        { px = "medkit", label = C.houseRoleName("guest"), v = tostring(guest), of = "", c = K.peach },
    }
    local x = self.allBtn:getX() - 24
    for i = #cells, 1, -1 do
        local c = cells[i]
        local vw = T.tw(c.v, T.FL) + T.tw(c.of)
        local lw = 18 + T.tw(c.label)
        local cw = math.max(vw, lw)
        x = x - cw
        local y0 = floor((UI.HEAD_H - UI.HS - UI.HL) / 2)
        T.px(self, c.px, x, y0, 16)
        T.text(self, c.label, x + 18, y0, K.text3)
        T.text(self, c.v, x, y0 + UI.HS, c.c, T.FL)
        T.text(self, c.of, x + T.tw(c.v, T.FL), y0 + UI.HS + UI.HL - UI.HS - 2, K.text3)
        x = x - 22
    end
    self.subtitle = (owned < maxO) and t("CanClaimMore", maxO - owned) or t("ClaimFull")
end

function Win:drawCards()
    self.hits = {}
    local x, y0 = UI.PAD, self.bodyY
    local h = self.bodyH
    local list = self.houses or {}
    if #list == 0 then
        T.rrect(self, x, y0, LIST_W, 150, UI.RC, K.surf)
        T.px(self, "house", x + floor((LIST_W - 32) / 2), y0 + 20, 32)
        for i, l in ipairs(T.wrap(t("NoHouses"), LIST_W - 32, T.FS, 4)) do
            T.textC(self, l, x + LIST_W / 2, y0 + 62 + (i - 1) * (UI.HS + 2), K.text2)
        end
        return
    end
    local total = #list * (CARD_H + 8)
    local maxScroll = math.max(0, total - h)
    self.listScroll = math.max(0, math.min(self.listScroll or 0, maxScroll))
    self:setStencilRect(x, y0, LIST_W, h)
    local mx, my = self:getMouseX(), self:getMouseY()
    for i, hs in ipairs(list) do
        local y = y0 + (i - 1) * (CARD_H + 8) - self.listScroll
        if y + CARD_H >= y0 and y <= y0 + h then
            local sel = self.sel and self.sel.key == hs.key
            local card = { x = x, y = y, w = LIST_W, h = CARD_H }
            local hov = T.hot(card, mx, my)
            if sel then T.rring(self, x, y, LIST_W, CARD_H, UI.RC, K.acc, K.surf, 2)
            else T.rrect(self, x, y, LIST_W, CARD_H, UI.RC, hov and K.surf3 or K.surf) end
            -- house slot with its colour dot
            local s = 52
            T.slot(self, x + 12, y + floor((CARD_H - s) / 2), s, nil, "house")
            T.circle(self, x + 12 + s - 12, y + floor((CARD_H - s) / 2) + s - 12, 14, K.surf)
            T.circle(self, x + 12 + s - 10, y + floor((CARD_H - s) / 2) + s - 10, 10, hs.color)
            -- text
            local tx = x + 12 + s + 12
            local eye = { x = x + LIST_W - 46, y = y + floor((CARD_H - 34) / 2), w = 34, h = 34 }
            local tw = eye.x - tx - 8
            local ty = y + 10
            T.text(self, T.fit(hs.sh:getTitle(), tw, T.FS), tx, ty, K.text)
            local pw = rolePill(self, tx, ty + UI.HS + 4, hs.role)
            local sh = hs.sh
            T.text(self, T.fit(t("CardMeta", sh:getW(), sh:getH(), sh:getPlayers():size()), tw - pw - 8), tx + pw + 8, ty + UI.HS + 6, K.text3)
            local age = C.visitAge(sh)
            local note, nc = ago(age), K.text3
            local rem = removalHours()
            if rem > 0 and age then
                local left = rem - age / 3600000
                if left < rem * 0.35 then note, nc = t("ExpireSoon", math.max(0, floor(left))), K.warn end
            end
            if note then T.text(self, T.fit(note, tw), tx, ty + UI.HS * 2 + 12, nc) end
            -- eye toggle
            local lit = C.hl[hs.key] == true
            local eh = T.hot(eye, mx, my)
            T.circle(self, eye.x, eye.y, eye.w, lit and hs.color or (eh and K.surf3 or K.surf2))
            T.icon(self, "eye", eye.x + 8, eye.y + 8, 18, lit and K.onAcc or K.text2)
            self.hits[#self.hits + 1] = { r = eye, kind = "eye", h = hs }
            self.hits[#self.hits + 1] = { r = card, kind = "card", h = hs }
        end
    end
    self:clearStencilRect()
end

function Win:drawPanel()
    local h = self.sel
    local x, y, w = self.rx, self.bodyY, self.rw
    T.rrect(self, x, y, w, self.bodyH, 16, K.surf)
    if not h then return end
    local sh = h.sh
    local px, pw = x + 18, self.pw
    local cy = y + 16
    -- title row
    local d = UI.HM - 6
    T.circle(self, px, cy + 3, d, h.color)
    local pillW = rolePill(self, px + pw, cy + floor((UI.HM - UI.HS - 4) / 2), h.role, t("YouAre"), true)
    T.text(self, T.fit(sh:getTitle(), pw - pillW - d - 20, T.FM), px + d + 10, cy, K.text, T.FM)
    cy = cy + UI.HM + 10
    -- info grid
    local gh = UI.HS * 2 + 16
    T.rrect(self, px, cy, pw, gh, 10, K.bg)
    local cols = {
        { t("Owner"), sh:getOwner() },
        { t("SizeAt"), t("SizeAtV", sh:getW(), sh:getH(), sh:getX(), sh:getY()) },
        { t("LastVisit"), ago(C.visitAge(sh)) or "-" },
    }
    local cw = floor((pw - 24) / 3)
    for i, c in ipairs(cols) do
        local cx = px + 12 + (i - 1) * cw
        T.text(self, c[1], cx, cy + 7, K.text3)
        T.text(self, T.fit(c[2], cw - 10), cx, cy + 9 + UI.HS, K.text)
    end
    cy = cy + gh + 10
    -- expiry warning
    local rem = removalHours()
    local age = C.visitAge(sh)
    if rem > 0 and age then
        local left = rem - age / 3600000
        if left < rem * 0.35 then
            local bh = UI.HS + 14
            T.rrect(self, px, cy, pw, bh, 10, K.warnD)
            T.icon(self, "warn", px + 10, cy + floor((bh - 16) / 2), 16, K.warn)
            T.text(self, T.fit(t("ExpireWarn", math.max(0, floor(left))), pw - 40), px + 34, cy + 7, K.warn)
            cy = cy + bh + 10
        end
    end
    -- what you may do here
    local can = t("Can_" .. (h.role or "admin"))
    local lines = T.wrap(t("YouCan") .. " " .. can, pw, T.FS, 2)
    for _, l in ipairs(lines) do
        T.text(self, l, px, cy, K.text2)
        cy = cy + UI.HS + 2
    end
    cy = cy + 8
    -- respawn in this house (the vanilla Safehouse window's tick box, which this window replaces)
    if h.role == "owner" or h.role == "member" then
        cy = self:drawRespawn(h, px, cy, pw) + 10
    end
    -- people header
    local online = 0
    for _, it in ipairs(self.people.items) do if it.item.online then online = online + 1 end end
    T.text(self, t("PeopleN", #self.people.items), px, cy, K.text2)
    T.textR(self, t("OnlineN", online), px + pw, cy, K.text3)
    cy = cy + UI.HS + 6
    if self.peopleTop ~= cy then
        self.peopleTop = cy
        self:layout()
    end
    -- add member label
    if self.addEntry:getIsVisible() then
        T.text(self, t("AddMember"), px, self.addLabelY + floor((UI.BTN_H - UI.HS) / 2), K.text2)
    end
end

function Win:drawRespawn(h, px, cy, pw)
    local sh = h.sh
    local me = C.me()
    local okR, on = pcall(function() return sh:isRespawnInSafehouse(me) end)
    on = okR and on == true
    local allowed = C.respawnAllowed()
    local main = C.mainHouse()
    local isMain = main ~= nil and CHelp.shKey(main) == h.key
    local active = allowed and (isMain or on)
    local sub
    if not allowed then sub = t("RespawnDisabled")
    elseif not isMain then sub = t("RespawnMainOnly", main and main:getTitle() or "-")
    elseif on then sub = t("RespawnOn")
    else sub = t("RespawnOff") end
    local bh = UI.HS * 2 + 18
    local r = { x = px, y = cy, w = pw, h = bh }
    local hov = active and T.hot(r, self:getMouseX(), self:getMouseY())
    T.rrect(self, px, cy, pw, bh, 10, hov and K.surf2 or K.bg)
    local is = 32
    T.px(self, "bed", px + 10, cy + floor((bh - is) / 2), is, active and 1 or 0.5)
    local tx = px + 10 + is + 10
    T.text(self, T.fit(t("RespawnTitle"), pw - (tx - px) - 64), tx, cy + 7, active and K.text or K.text3)
    T.text(self, T.fit(sub, pw - (tx - px) - 64), tx, cy + 9 + UI.HS, (on and isMain and allowed) and K.acc or K.text3)
    UI.drawSwitch(self, px + pw - 52, cy + floor((bh - 22) / 2), on)
    if not active then T.rrect(self, px + pw - 52, cy + floor((bh - 22) / 2), 40, 22, 11, K.bg, 0.45) end
    if active then self.hits[#self.hits + 1] = { r = r, kind = "respawn", h = h, on = on } end
    return cy + bh
end

function Win:toggleRespawn(h, on)
    local me = C.me()
    local want = not on
    pcall(function() sendSafehouseChangeRespawn(h.sh, me, want) end)
    pcall(function() h.sh:setRespawnInSafehouse(want, me) end)   -- show it right away; the server syncs it
    UI.toast(want and t("Msg_RespawnOn", h.sh:getTitle()) or t("Msg_RespawnOff"), want)
end

function Win.drawPerson(self, list, d, x, y, w, h, hover, sel)
    liveInfo(d)
    local av = h - 12
    T.avatar(list, x + 8, y + 6, av, d.name)
    T.circle(list, x + 8 + av - 9, y + 6 + av - 9, 12, K.surf)
    T.circle(list, x + 8 + av - 7, y + 6 + av - 7, 8, d.online and K.acc or T.rgb("4E6B68"))
    local tx = x + 8 + av + 10
    T.text(list, T.fit(d.name, 160), tx, y + floor((h - UI.HS) / 2), K.text)
    local nx = tx + math.min(160, T.tw(d.name)) + 10
    local pw = rolePill(list, nx, y + floor((h - UI.HS - 4) / 2), d.role)
    local ex = nx + pw + 10
    d.removeHit = nil
    local right = x + w - 10
    if self:canManage() and d.role ~= "owner" then
        local label = t("Remove")
        local bw = T.tw(label) + 20
        local bh = UI.HS + 8
        local bx = right - bw
        local by = y + floor((h - bh) / 2)
        local mx = list:getMouseX()
        local hov = hover and mx >= bx
        T.rrect(list, bx, by, bw, bh, floor(bh / 2), hov and T.rgb("5A2C33") or K.badD)
        T.textC(list, label, bx + bw / 2, by + 4, K.bad)
        d.removeHit = bx
        right = bx - 8
    end
    if d.extra ~= "" then T.text(list, T.fit(d.extra, right - ex), ex, y + floor((h - UI.HS) / 2), K.text3) end
end

function Win:drawBody()
    local ms = CHelp.nowMs()
    if not self.visitMs or ms - self.visitMs > 60000 then
        self.visitMs = ms
        CHelp.toServer("visitsReq", { key = self.extraKey })
    end
    self:drawStats()
    self:drawCards()
    self:drawPanel()
    T.text(self, T.fit(t("HousesFoot"), self.width - UI.PAD * 2), UI.PAD, self.height - FOOT_H, K.text3)
end

-- ------------------------------------------------------------------ input
function Win:onMouseDown(x, y)
    for _, hit in ipairs(self.hits or {}) do
        if T.hot(hit.r, x, y) then
            if hit.kind == "eye" then
                C.toggleHouse(hit.h.sh)
            elseif hit.kind == "respawn" then
                self:toggleRespawn(hit.h, hit.on)
            else
                self.selKey = hit.h.key
                self.sel = hit.h
                C.flash(hit.h.sh)
                self:fillPeople()
                self:layout()
            end
            getSoundManager():playUISound("UISelectListItem")
            return true
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Win:onMouseWheel(del)
    local mx, my = self:getMouseX(), self:getMouseY()
    if mx < UI.PAD + LIST_W then
        self.listScroll = (self.listScroll or 0) + del * 40
        return true
    end
    return false
end

function Win:onPerson(d)
    self:layout()
end

function Win:onAll()
    C.toggleArea()
    self:layout()
end

function Win:onHl()
    if self.sel then C.toggleHouse(self.sel.sh) end
    self:layout()
end

function Win:onZones()
    if self.sel and CHelp.Hub then CHelp.Hub.open(self.sel.sh) end
end

function Win:onFinder()
    if self.sel and CHelp.Finder then CHelp.Finder.open(self.sel.sh) end
end

function Win:onAdd()
    if not self.sel then return end
    local name = CHelp.trim(self.addEntry:getInternalText())
    if name == "" then return end
    CHelp.toServer("addMember", { sh = self.sel.key, name = name })
    self.addEntry:setText("")
end

function Win:onPickName()
    if self.sel then H.openAdd(self.sel.sh) end
end

function Win:askRemove(name)
    if not self.sel then return end
    local key = self.sel.key
    UI.confirm(t("RemoveTitle"), t("RemoveText", name, self.sel.sh:getTitle()), t("Remove"), true, self, function()
        CHelp.toServer("removeMember", { sh = key, name = name })
    end)
end

function Win:onRename()
    if not self.sel then return end
    local key = self.sel.key
    UI.prompt(t("RenameHouse"), t("RenameAsk"), self.sel.sh:getTitle(), t("Save"), self, function(_, text)
        CHelp.toServer("rename", { sh = key, title = text })
    end)
end

function Win:onTransfer()
    local person = self:selectedPerson()
    if not self.sel or not person or person.role ~= "member" then return end
    local key, name = self.sel.key, person.name
    UI.confirm(t("TransferTitle"), t("TransferText", self.sel.sh:getTitle(), name), t("TransferOk"), true, self, function()
        CHelp.toServer("transfer", { sh = key, name = name })
    end)
end

function Win:onDanger()
    local h = self.sel
    if not h then return end
    local sh, key, title = h.sh, h.key, h.sh:getTitle()
    if self.dangerKey == "Release" then
        UI.confirm(t("ReleaseTitle", title), t("ReleaseText"), t("Release"), true, self, function()
            local s = CHelp.shByKey(key)
            if s then
                C.hl[key] = nil
                sendSafehouseRelease(s)
            end
        end)
    elseif self.dangerKey == "Leave" then
        UI.confirm(t("LeaveTitle", title), t("LeaveText", sh:getOwner()), t("Leave"), true, self, function()
            CHelp.toServer("leave", { sh = key })
        end)
    else
        UI.confirm(t("EndGuestTitle", title), t("EndGuestText"), t("EndGuest"), true, self, function()
            C.leaveGuest()
        end)
    end
end

function H.open(key)
    if H.instance then H.instance:close() end
    local sw, shh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(W_, sw - 20), math.min(H_, shh - 20)
    local x, y = UI.center(w, h)
    local win = Win:new(x, y, w, h, t("MyHouses"))
    win.selKey = key
    win.extraKey = key
    win:show()
    H.instance = win
    local sh = key and CHelp.shByKey(key)
    if sh then C.flash(sh) end
    return win
end

-- ------------------------------------------------------------------ add member by name (offline ok)
local A = UI.Window:derive("CHelpAddMember")

function A:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 6 + UI.HS * 2 + 10
    self.entry = UI.entry(self, x, y, w, "")
    self.entry:setPlaceholderText((CHelp.sv("AllowOfflineAdd") or C.isAdmin()) and t("AddHint") or t("AddHintOnline"))
    self.entry.onTextChange = function() self:fill() end
    y = y + UI.BTN_H + 8
    self.listY = y
    self.list = UI.makeList(self, x, y, w, self.height - y - UI.BTN_H - UI.PAD - 10, UI.HS * 2 + 14, self, A.drawRow, A.onPick)
    local by = self.height - UI.BTN_H - UI.PAD
    UI.button(self, x, by, floor(w / 2) - 4, t("Cancel"), self, A.onCancel, "sec")
    UI.button(self, x + floor(w / 2) + 4, by, floor(w / 2) - 4, t("Add"), self, A.onAdd, "pri")
    self.names = {}           -- name -> { n, on, t }
    self.loaded = false
    C.on("known", self, A.onKnown)
    C.on("netusers", self, A.onNetUsers)
    self:request()
end

function A:request()
    self.reqMs = CHelp.nowMs()
    CHelp.toServer("knownReq", {})
    if C.isAdmin() then pcall(requestUsers) end
end

function A:onClose() C.off(self) end

function A:merge(n, on, ts)
    if type(n) ~= "string" or n == "" then return end
    local e = self.names[n]
    if not e then
        e = { n = n, on = false }
        self.names[n] = e
    end
    if on then e.on = true end
    if ts and (not e.t or ts > e.t) then e.t = ts end
end

function A:onKnown(list, now)
    for _, e in pairs(self.names) do e.on = false end
    for _, e in ipairs(list or {}) do self:merge(e.n, e.on, e.t) end
    self.now = now
    self.nowAt = CHelp.nowMs()
    self.loaded = true
    self:fill()
end

-- admins: whole account list of the server (whitelist + user log)
function A:onNetUsers()
    local ok, users = pcall(getUsers)
    if not ok or not users then return end
    for i = 0, users:size() - 1 do
        local u = users:get(i)
        local okN, n = pcall(function() return u:getUsername() end)
        local okO, on = pcall(function() return u:isOnline() end)
        if okN then self:merge(n, okO and on == true, nil) end
    end
    self.loaded = true
    self:fill()
end

function A:fill()
    local q = string.lower(CHelp.trim(self.entry:getInternalText() or ""))
    local rows = {}
    self.total, self.online = 0, 0
    for _, e in pairs(self.names) do
        self.total = self.total + 1
        if e.on then self.online = self.online + 1 end
        if q == "" or string.find(string.lower(e.n), q, 1, true) then
            e.inHouse = self.sh:playerAllowed(e.n)
            rows[#rows + 1] = e
        end
    end
    -- online first, people already in this house last, then by name
    table.sort(rows, function(a, b)
        if a.inHouse ~= b.inHouse then return not a.inHouse end
        if a.on ~= b.on then return a.on end
        return string.lower(a.n) < string.lower(b.n)
    end)
    local keep = self.list.items[self.list.selected]
    keep = keep and keep.item and keep.item.n
    self.list:clear()
    self.list.selected = 0
    for i, e in ipairs(rows) do
        self.list:addItem(e.n, e)
        if e.n == keep then self.list.selected = i end
    end
end

local function seenText(self, ts)
    if not ts or not self.now then return nil end
    local nowS = self.now + floor((CHelp.nowMs() - (self.nowAt or 0)) / 1000)
    local m = floor((nowS - ts) / 60)
    if m < 60 then return t("SeenMin", math.max(1, m)) end
    if m < 48 * 60 then return t("SeenH", floor(m / 60)) end
    return t("SeenD", floor(m / 1440))
end

function A.drawRow(self, list, e, x, y, w, h, hover, sel)
    local av = h - 14
    T.avatar(list, x + 8, y + 7, av, e.n)
    T.circle(list, x + 8 + av - 9, y + 7 + av - 9, 12, K.surf)
    T.circle(list, x + 8 + av - 7, y + 7 + av - 7, 8, e.on and K.acc or T.rgb("4E6B68"))
    local tx = x + av + 20
    local pillTxt, pfg, pbg
    if e.inHouse then
        pillTxt, pfg, pbg = t("InHouse"), K.text3, K.surf2
    elseif e.on then
        pillTxt, pfg, pbg = t("Online"), K.acc, K.accD
    else
        pillTxt, pfg, pbg = t("Offline"), K.text3, K.surf2
    end
    local pw = T.pillW(pillTxt)
    T.pill(list, x + w - pw - 10, y + floor((h - UI.HS - 4) / 2), pillTxt, pfg, pbg)
    local tw = w - (tx - x) - pw - 20
    T.text(list, T.fit(e.n, tw), tx, y + 7, e.inHouse and K.text3 or K.text)
    local sub
    if e.on then sub = t("OnlineNow") else sub = seenText(self, e.t) or t("NeverSeen") end
    T.text(list, T.fit(sub, tw), tx, y + 9 + UI.HS, K.text3)
end

function A:onPick(e)
    if not e or e.inHouse then return end
    self.entry:setText(e.n)
end

function A:onAdd()
    local name = CHelp.trim(self.entry:getInternalText())
    if name == "" then
        local it = self.list.items[self.list.selected]
        if it and it.item and not it.item.inHouse then name = it.item.n end
    end
    if name == "" then return end
    CHelp.toServer("addMember", { sh = CHelp.shKey(self.sh), name = name })
    self:close()
end

function A:onCancel() self:close() end

function A:drawBody()
    -- keep the online dots current while the window is open
    if CHelp.nowMs() - (self.reqMs or 0) > 15000 then self:request() end
    T.text(self, T.fit(t("AddHelp1"), self.width - UI.PAD * 2), UI.PAD, UI.HEAD_H + 6, K.text)
    local line = self.loaded and t("KnownCount", self.total or 0, self.online or 0) or t("KnownLoading")
    T.text(self, T.fit(line, self.width - UI.PAD * 2), UI.PAD, UI.HEAD_H + 8 + UI.HS, K.text3)
    if self.loaded and #self.list.items == 0 then
        local msg = ((self.total or 0) == 0) and t("KnownEmpty") or t("KnownNone")
        for i, l in ipairs(T.wrap(msg, self.width - UI.PAD * 2 - 20)) do
            T.textC(self, l, self.width / 2, self.listY + 24 + (i - 1) * (UI.HS + 4), K.text3)
        end
    end
end

function H.openAdd(sh)
    local w, h = 420, 520
    local x, y = UI.center(w, h)
    local win = A:new(x + 60, y + 20, w, h, t("AddMember"))
    win.subtitle = sh:getTitle()
    win.sh = sh
    win:show()
end
