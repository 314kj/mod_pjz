-- Cookie Mission - Dock: one screen button that groups the other mods' buttons
-- Finds Cookie Quest, Cookie Express, Kuraya and any other mod button on the sidebar or floating
-- on screen, hides the ones the player chose to group, and opens them from one glass popup.
-- Other mods are never edited: their buttons are only hidden/shown and their own click is called.
require "CM_UI_Kit"
require "CM_UI_Board"

local C = CMUI.C
local T = CMC.txt

CMDock = CMDock or {}
CMDock.cfg = CMDock.cfg or {}       -- id -> "group" | "origin"
CMDock.entries = {}                 -- detected targets (rebuilt every scan)
CMDock.hidden = CMDock.hidden or {} -- element -> true while we hide it
local CFG_FILE = "CookieMission_dock.txt"

-- ===================================================================== settings (per player, this machine)
function CMDock.load()
    CMDock.cfg = {}
    pcall(function()
        local r = getFileReader(CFG_FILE, false)
        if not r then return end
        while true do
            local line = r:readLine()
            if not line then break end
            local eq = string.find(line, "=", 1, true)
            if eq then CMDock.cfg[string.sub(line, 1, eq - 1)] = string.sub(line, eq + 1) end
        end
        r:close()
    end)
end

function CMDock.save()
    pcall(function()
        local w = getFileWriter(CFG_FILE, true, false)
        for _, k in ipairs(CM.sortedKeys(CMDock.cfg)) do w:writeln(k .. "=" .. tostring(CMDock.cfg[k])) end
        w:close()
    end)
end

function CMDock.modeOf(e)
    local m = CMDock.cfg[e.id]
    if m == "group" or m == "origin" then return m end
    return e.def or "origin"
end

function CMDock.setMode(e, mode)
    CMDock.cfg[e.id] = mode
    CMDock.save()
    CMDock.enforce(true)
end

-- ===================================================================== helpers
local function texOf(path)
    if not path then return nil end
    local ok, t = pcall(getTexture, path)
    if ok and t then return t end
    return nil
end

local function texName(t)
    if not t then return nil end
    local ok, n = pcall(function() return t:getName() end)
    if ok and n then return tostring(n) end
    return nil
end

local function visible(el)
    local ok, v = pcall(function() return el:isVisible() end)
    return ok and v == true
end

local function setVis(el, v)
    pcall(function() el:setVisible(v) end)
end

-- click a hidden element the way its own mouse handlers expect
local function pokeElement(el)
    if not el then return end
    if el.forceClick then
        local ok = pcall(el.forceClick, el)
        if ok then return end
    end
    if el.onclick then
        local ok = pcall(el.onclick, el.target, el)
        if ok then return end
    end
    local w, h = el.width or 10, el.height or 10
    pcall(function() el:onMouseDown(w / 2, h / 2) end)
    pcall(function() el:onMouseUp(w / 2, h / 2) end)
end

local function sidebar()
    return ISEquippedItem and ISEquippedItem.instance or nil
end

-- vanilla sidebar buttons: known fields, or an icon under media/ui (Sidebar art)
-- every child ISEquippedItem:initialise() adds in 42.x (hand slots first, then the buttons)
local VANILLA_FIELDS = { mainHand = true, offHand = true, invBtn = true, healthBtn = true, craftingBtn = true,
    buildBtn = true, movableBtn = true, movableTooltip = true, searchBtn = true, zoneBtn = true, mapBtn = true,
    debugBtn = true, arfBtn = true, safetyBtn = true, radialIcon = true, clientBtn = true, adminBtn = true,
    warManagerBtn = true, craftBtn = true, mainBtn = true, userPanelBtn = true, chatBtn = true }
local GAP = 15 -- vanilla spacing: UI_BORDER_SPACING + 5

local function vanillaSet(inst)
    local set = {}
    for k, v in pairs(inst) do
        if type(k) == "string" and VANILLA_FIELDS[k] and type(v) == "table" then set[v] = true end
    end
    return set
end

local function isVanillaButton(inst, el, vset)
    if vset[el] then return true end
    local n = texName(el.image)
    if n and (string.find(n, "media/ui/", 1, true) or string.find(n, "Sidebar", 1, true)) then return true end
    return false
end

-- ===================================================================== known mods (adapters)
local KNOWN = {}

KNOWN[#KNOWN + 1] = function(out)
    -- Cookie Quest: sidebar button inst.cqBtn or its floating icon
    if not CQIcon then return end
    local inst = sidebar()
    local els = {}
    if inst and inst.cqBtn then els[#els + 1] = inst.cqBtn end
    if CQIcon.float then els[#els + 1] = CQIcon.float end
    out[#out + 1] = {
        id = "cq", name = T("IGUI_CM_Dock_cq"), def = "group", els = els, where = "known",
        tex = texOf("media/textures/CookieQuest/cq_icon_on.png"),
        click = function() if CQIcon.click then CQIcon.click() end end,
        context = function() if CQIcon.context then CQIcon.context() end end,
        badge = function()
            local ok, v = pcall(function() return CQIcon.hasNew and CQIcon.hasNew() end)
            return ok and v and "!" or nil
        end,
    }
end

KNOWN[#KNOWN + 1] = function(out)
    -- Cookie Express: floating house button CKX.UI.btn
    if not (CKX and CKX.UI) then return end
    local ui = CKX.UI
    out[#out + 1] = {
        id = "ckx", name = T("IGUI_CM_Dock_ckx"), def = "group", els = { ui.btn }, where = "known",
        tex = texOf("media/ui/CookieExpress/ckx_house_btn.png"),
        click = function() if ui.toggle then ui.toggle() end end,
        badge = function()
            local n = CKX.Cl and CKX.Cl.count or 0
            if n and n > 0 then return tostring(n > 99 and "99+" or n) end
            return nil
        end,
    }
end

KNOWN[#KNOWN + 1] = function(out)
    -- Kuraya: floating shop button KRFloat.instance
    if not KRFloat then return end
    local el = KRFloat.instance
    out[#out + 1] = {
        id = "kuraya", name = T("IGUI_CM_Dock_kuraya"), def = "group", els = { el }, where = "known",
        tex = (el and el.tex) or texOf("media/textures/Kuraya/shop_button.png"),
        click = function() if KRShopUI and KRShopUI.toggle then KRShopUI.toggle() end end,
        badge = function()
            if KRClient and (KRClient.saleCount or 0) > 0 then return "!" end
            return nil
        end,
    }
end

-- ===================================================================== scan
local SKIP_TYPES = { "Window", "Toast", "Splash", "Tooltip", "Context", "Hud", "HUD", "Fade", "Panel_", "Modal",
    "Dialog", "Popup", "Menu", "Bar", "Loading" }

local function skipType(t)
    t = tostring(t or "")
    for _, s in ipairs(SKIP_TYPES) do if string.find(t, s, 1, true) then return true end end
    return false
end

local function ownsClick(el)
    if el.onclick then return true end
    local mu = el.onMouseUp
    if mu == nil then return false end
    if ISPanel and mu == ISPanel.onMouseUp then return false end
    if ISUIElement and mu == ISUIElement.onMouseUp then return false end
    return true
end

local function nameFor(el, fallback)
    local n = el.internal or el.tooltip or el.title or el.name
    if type(n) ~= "string" or n == "" then n = fallback end
    if #n > 28 then n = string.sub(n, 1, 28) end
    return n
end

function CMDock.scan()
    local out = {}
    for _, fn in ipairs(KNOWN) do pcall(fn, out) end
    local taken = {}
    for _, e in ipairs(out) do for _, el in ipairs(e.els or {}) do if el then taken[el] = true end end end
    if CMDock.btn then taken[CMDock.btn] = true end
    if CMDock.float then taken[CMDock.float] = true end
    if CMDock.pop then taken[CMDock.pop] = true end
    -- other mods' sidebar buttons
    local inst = sidebar()
    if inst and inst.children then
        local vset = vanillaSet(inst)
        local n = 0
        local kids = {}
        for _, el in pairs(inst.children) do
            if type(el) == "table" then kids[#kids + 1] = el end
        end
        table.sort(kids, function(a, b) return (CMDock.origY[a] or a.y or 0) < (CMDock.origY[b] or b.y or 0) end)
        for _, el in ipairs(kids) do
            if not taken[el] and not isVanillaButton(inst, el, vset) and ownsClick(el) then
                n = n + 1
                local id = "sb:" .. tostring(el.Type or "btn") .. ":" .. tostring(texName(el.image) or el.internal or n)
                out[#out + 1] = { id = id, name = nameFor(el, tostring(el.Type or "Sidebar")), def = "origin",
                    els = { el }, where = "sidebar", tex = el.image, click = function() pokeElement(el) end }
                taken[el] = true
            end
        end
    end
    -- other mods' floating buttons (small top-level elements that handle their own click)
    local okL, list = pcall(function() return UIManager.getUI() end)
    if okL and list then
        local n = list:size()
        for i = 0, n - 1 do
            local okT, el = pcall(function() return list:get(i):getTable() end)
            if okT and type(el) == "table" and not taken[el] and el ~= inst then
                local w, h = el.width or 0, el.height or 0
                if w >= 16 and h >= 16 and w <= 140 and h <= 140 and not skipType(el.Type) and ownsClick(el)
                    and (visible(el) or CMDock.hidden[el]) then
                    local tx = el.tex or el.image or el.texture or el.icon
                    if type(tx) ~= "userdata" then tx = nil end
                    local id = "fl:" .. tostring(el.Type or "panel") .. ":" .. tostring(texName(tx) or "")
                    out[#out + 1] = { id = id, name = nameFor(el, tostring(el.Type or "Button")), def = "origin",
                        els = { el }, where = "float", tex = tx, click = function() pokeElement(el) end }
                    taken[el] = true
                end
            end
        end
    end
    CMDock.entries = out
    CMDock.scannedAt = CMC.ms()
    return out
end

-- ===================================================================== sidebar layout
CMDock.origY = CMDock.origY or {}

-- vanilla buttons stay; the dock button sits right under them; mod buttons left at origin follow
local function relayout()
    local inst = sidebar()
    if not inst or not inst.children then return end
    local vset = vanillaSet(inst)
    local bottom = 0
    local mods = {}
    for _, el in pairs(inst.children) do
        if type(el) == "table" then
            if isVanillaButton(inst, el, vset) then
                if visible(el) then bottom = math.max(bottom, (el.y or 0) + (el.height or 0)) end
            elseif el ~= CMDock.btn then
                if CMDock.origY[el] == nil then CMDock.origY[el] = el.y or 0 end
                mods[#mods + 1] = el
            end
        end
    end
    table.sort(mods, function(a, b) return (CMDock.origY[a] or 0) < (CMDock.origY[b] or 0) end)
    local y = bottom + GAP
    if CMDock.btn and visible(CMDock.btn) then
        if CMDock.btn.y ~= y then CMDock.btn:setY(y) end
        y = y + CMDock.btn.height + GAP
    end
    for _, el in ipairs(mods) do
        if visible(el) then
            if el.y ~= y then pcall(function() el:setY(y) end) end
            y = y + (el.height or 0) + GAP
        end
    end
    if inst:getHeight() < y then inst:setHeight(y) end
end

-- hide grouped buttons, give back the ones set to origin
local lastEnforce = 0
function CMDock.enforce(force)
    local t = CMC.ms()
    if not force and t - lastEnforce < 400 then return end
    lastEnforce = t
    if force or t - (CMDock.scannedAt or 0) > 5000 then CMDock.scan() end
    local changed = false
    for _, e in ipairs(CMDock.entries) do
        local grouped = CMDock.modeOf(e) == "group"
        for _, el in ipairs(e.els or {}) do
            if el then
                if grouped then
                    if visible(el) then setVis(el, false); CMDock.hidden[el] = true; changed = true end
                elseif CMDock.hidden[el] then
                    setVis(el, true); CMDock.hidden[el] = nil; changed = true
                end
            end
        end
    end
    if changed or force then relayout() end
end

function CMDock.grouped()
    local out = {}
    -- Cookie Mission itself is always the first tile
    out[1] = { id = "cm", name = T("IGUI_CM_Dock_cm"), tex = CMUI.tex("cm_icon"),
        click = function() CMBoard.toggle() end, context = function() CMIcon.context() end,
        badge = function()
            if CMC.run() then return "!" end
            if CMIcon.hasNew() then return "!" end
            return nil
        end }
    for _, e in ipairs(CMDock.entries) do
        if CMDock.modeOf(e) == "group" then out[#out + 1] = e end
    end
    return out
end

local function anyBadge()
    for _, e in ipairs(CMDock.grouped()) do
        if e.badge then
            local ok, b = pcall(e.badge)
            if ok and b then return true end
        end
    end
    return false
end

-- ===================================================================== dock button
function CMDock.drawButton(el, w, h, over)
    local s = math.min(w, h)
    local x, y = (w - s) / 2, (h - s) / 2
    local tex = CMUI.tex("cm_icon")
    local a = 1
    if CMC.run() then a = 0.75 + 0.25 * math.sin(CMC.ms() / 220) end
    if over then el:drawTextureScaled(CMUI.tex("cm_glow"), x - s * 0.2, y - s * 0.2, s * 1.4, s * 1.4, 0.45, C.accent[1], C.accent[2], C.accent[3]) end
    if tex then el:drawTextureScaledAspect(tex, x, y, s, s, a, 1, 1, 1)
    else el:drawRect(x + 4, y + 4, s - 8, s - 8, 0.9, C.accent[1], C.accent[2], C.accent[3]) end
    if anyBadge() then
        local d = math.max(8, math.floor(s * 0.22))
        el:drawRect(x + s - d - 2, y + 2, d, d, 1, C.bad[1], C.bad[2], C.bad[3])
    end
end

function CMDock.tooltip()
    local names = {}
    for _, e in ipairs(CMDock.grouped()) do names[#names + 1] = e.name end
    return T("IGUI_CM_Dock_Tip") .. "\n" .. table.concat(names, ", ")
end

function CMDock.context()
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    ctx:addOption(T("IGUI_CM_Ctx_Open"), nil, function() CMBoard.open() end)
    ctx:addOption(T("IGUI_CM_Stream_On"), nil, function() CMDock.setStream(true) end)
    ctx:addOption(T("IGUI_CM_Dock_Settings"), nil, function() CMDock.openSettings() end)
    if CMC.isAdmin() then
        ctx:addOption(T("IGUI_CM_Ctx_Admin"), nil, function() if CMAdmin then CMAdmin.toggle() end end)
    end
end

-- floating fallback when the sidebar is too long for the screen
CMDock.Float = ISPanel:derive("CMDock_Float")
local F = CMDock.Float
function F:new(x, y, s)
    local o = ISPanel.new(self, x, y, s, s)
    o.background = false
    return o
end
function F:prerender() end
function F:render() CMDock.drawButton(self, self.width, self.height, self:isMouseOver()) end
function F:onMouseDown(x, y) self.held = true; self.moved = false; return true end
function F:onMouseMove(dx, dy)
    if self.held then self.moved = true; self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
end
F.onMouseMoveOutside = F.onMouseMove
function F:onMouseUp(x, y)
    if not self.moved then CMDock.togglePop(self) end
    self.held = false; self.moved = false
    return true
end
function F:onMouseUpOutside() self.held = false; self.moved = false end
function F:onRightMouseUp() CMDock.context(); return true end

local function makeSide(inst)
    if inst.cmBtn then return inst.cmBtn end
    local ref = inst.invBtn
    local w = ref and ref:getWidth() or 48
    local h = ref and ref:getHeight() or 48
    local x = ref and ref:getX() or 2
    local btn = ISButton:new(x, inst:getHeight() + GAP, w, h, "", nil, function() end)
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.internal = "CookieDockBtn"
    btn.onclick = function() CMDock.togglePop(btn) end
    btn.render = function(self)
        self.tooltip = CMDock.tooltip()
        CMDock.drawButton(self, self:getWidth(), self:getHeight(), self:isMouseOver())
        if ISButton.updateTooltip then ISButton.updateTooltip(self) end
    end
    btn.onRightMouseUp = function() CMDock.context(); return true end
    inst:addChild(btn)
    inst.cmBtn = btn
    return btn
end

function CMDock.apply()
    if CMDock.stream and CMDock.stream.on then return end
    local inst = sidebar()
    local btn = inst and makeSide(inst)
    CMDock.inst = inst
    CMDock.btn = btn
    CMDock.enforce(true)
    local float = btn == nil
    if btn then
        local ok, bottom = pcall(function() return btn:getAbsoluteY() + btn:getHeight() end)
        if ok and bottom and bottom > getCore():getScreenHeight() - 4 then float = true end
    end
    if float then
        if btn then btn:setVisible(false) end
        if not CMDock.float then
            local s = btn and btn:getWidth() or 48
            CMDock.float = F:new(getCore():getScreenWidth() - s - 60, 200, s)
            CMDock.float:initialise()
            CMDock.float:instantiate()
            CMDock.float:addToUIManager()
        end
        CMDock.float:setVisible(true)
    else
        if btn then btn:setVisible(true) end
        if CMDock.float then CMDock.float:setVisible(false) end
    end
    relayout()
end

-- ===================================================================== popup (glass tray of tiles)
CMDock.Pop = CMUI.Window:derive("CMDock_Pop")
local P = CMDock.Pop

function P:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.headerH = 0
    return o
end
function P:drawFrame() end
function P:onMouseDownOutside(x, y)
    -- clicking the dock button again is handled by togglePop; anything else closes the tray
    if CMDock.pop == self and not (self.anchor and self.anchor:isMouseOver()) then self:close() end
end
function P:onRightMouseUp(x, y)
    local h = self:findHit(x, y)
    if h and h.ctx then pcall(h.ctx) end
    return true
end

function P:drawBody()
    local S = CMUI.S
    local tiles = CMDock.grouped()
    local ts = S(64)
    local gap = S(8)
    local pad = S(10)
    local cols = math.max(1, math.min(#tiles + 2, 5))
    local rows = math.ceil((#tiles + 2) / cols)
    local w = pad * 2 + cols * ts + (cols - 1) * gap
    local h = pad * 2 + rows * ts + (rows - 1) * gap
    if math.abs(self.width - w) > 1 then self:setWidth(w) end
    if math.abs(self.height - h) > 1 then self:setHeight(h) end
    CMUI.glow(self, w / 2, S(4), w * 0.5, S(30), C.accent, 0.20)
    CMUI.rbox(self, 0, 0, w, h, C.bg, 0.82, 12)
    CMUI.glass(self, 0, 0, w, h, { tint = C.panel, a = 0.30, rad = 12, rim = C.line, rimA = 0.6 })
    local all = {}
    for i = 1, #tiles do all[i] = tiles[i] end
    all[#all + 1] = { id = "_stream", name = T("IGUI_CM_Stream_Tile"), tex = CMUI.tex("cm_stream"), tint = C.gold, click = function() CMDock.setStream(true) end }
    all[#all + 1] = { id = "_gear", name = T("IGUI_CM_Dock_Gear"), gear = true, click = function() CMDock.openSettings() end }
    for i, e in ipairs(all) do
        local c = (i - 1) - math.floor((i - 1) / cols) * cols
        local r = math.floor((i - 1) / cols)
        local x = pad + c * (ts + gap)
        local y = pad + r * (ts + gap)
        local over = self:hit(x, y, ts, ts, function()
            local pop = CMDock.pop
            if pop then pop:close() end
            if e.click then
                local ok, err = pcall(e.click)
                if not ok then CM.log("dock click " .. tostring(e.id) .. ": " .. tostring(err)) end
            end
        end, e.name)
        local hit = self.hits[#self.hits]
        if hit then hit.ctx = e.context end
        if over then CMUI.glow(self, x + ts / 2, y + ts / 2, ts * 0.7, ts * 0.7, C.accent, 0.35) end
        CMUI.rbox(self, x, y, ts, ts, over and C.panel3 or C.panel2, over and 0.7 or 0.45, 10)
        CMUI.rborder(self, x, y, ts, ts, over and C.gold or C.line, over and 0.9 or 0.4, 10)
        local is = ts - S(22)
        local ix, iy = x + (ts - is) / 2, y + S(4)
        if e.gear then
            CMUI.textC(self, "+", x + ts / 2, iy + (is - CMUI.fh(UIFont.Large)) / 2, C.dim, 1, UIFont.Large)
        elseif e.tex then
            local tc = e.tint or C.white
            self:drawTextureScaledAspect(e.tex, ix, iy, is, is, 1, tc[1], tc[2], tc[3])
        else
            CMUI.textC(self, string.upper(string.sub(tostring(e.name), 1, 1)), x + ts / 2, iy + (is - CMUI.fh(UIFont.Large)) / 2,
                C.gold, 1, UIFont.Large)
        end
        CMUI.textC(self, CMUI.fit(e.name, UIFont.Small, ts - S(4)), x + ts / 2, y + ts - CMUI.fh(UIFont.Small) - S(3), C.text, 1, UIFont.Small)
        if e.badge then
            local ok, b = pcall(e.badge)
            if ok and b then
                local bw = math.max(S(14), CMUI.tw(UIFont.Small, b) + S(8))
                CMUI.rbox(self, x + ts - bw - S(2), y + S(2), bw, CMUI.fh(UIFont.Small) + 2, C.bad, 0.95, 7)
                CMUI.textC(self, b, x + ts - bw / 2 - S(2), y + S(3), C.white, 1, UIFont.Small)
            end
        end
    end
end

function CMDock.togglePop(anchor)
    if CMDock.pop then CMDock.pop:close(); return end
    CMDock.enforce(true)
    CMUI.k = CMUI.fontScale()
    local ax, ay, aw = 60, 200, 48
    pcall(function() ax, ay, aw = anchor:getAbsoluteX(), anchor:getAbsoluteY(), anchor:getWidth() end)
    local pop = P:new(ax + aw + 8, ay, 120, 80)
    pop.anchor = anchor
    pop.onClosed = function() CMDock.pop = nil end
    pop:show()
    CMDock.pop = pop
end

-- ===================================================================== settings window
CMDock.Set = CMUI.Window:derive("CMDock_Set")
local SW = CMDock.Set

function SW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Dock_Settings")
    o.titleIcon = "cm_icon"
    return o
end

function SW:drawBody()
    local S = CMUI.S
    local pad = S(16)
    local top = self.headerH + S(12)
    local w = self.width - pad * 2
    -- stream mode card
    local sh = S(84)
    CMUI.glow(self, pad + w / 2, top + sh / 2, w * 0.55, sh, C.accent, 0.10)
    CMUI.glass(self, pad, top, w, sh, { tint = C.panel, a = 0.42, rad = 10, rim = C.accent, rimA = 0.5 })
    local is = S(36)
    local ic = CMUI.tex("cm_stream")
    if ic then self:drawTextureScaledAspect(ic, pad + S(10), top + S(9), is, is, 1, C.gold[1], C.gold[2], C.gold[3]) end
    local tx = pad + is + S(20)
    CMUI.text(self, T("IGUI_CM_Stream"), tx, top + S(8), C.text, 1, UIFont.Medium)
    CMUI.text(self, CMUI.fit(T("IGUI_CM_Stream_Hint"), UIFont.Small, w - is - S(170)), tx, top + S(10) + CMUI.fh(UIFont.Medium), C.dim)
    CMUI.btn(self, pad + w - S(132), top + S(12), S(120), S(30), T("IGUI_CM_Stream_On"), function() CMDock.setStream(true) end,
        "primary", { tip = T("IGUI_CM_Stream_KeyTip") })
    local cy = top + sh - S(30)
    local cx = pad + S(12)
    CMUI.text(self, T("IGUI_CM_Stream_Keep"), cx, cy + S(3), C.faint)
    cx = cx + CMUI.tw(UIFont.Small, T("IGUI_CM_Stream_Keep")) + S(10)
    for _, k in ipairs(CMDock.STREAM_KEEP) do
        local on = CMDock.keepOpt(k)
        local lbl = T("IGUI_CM_Stream_K_" .. k)
        local bw = CMUI.tw(UIFont.Small, lbl) + S(22)
        CMUI.btn(self, cx, cy, bw, S(22), lbl, function() CMDock.setKeepOpt(k, not on) end, on and "sel" or "ghost",
            { rad = 11, tip = (k == "chat") and T("IGUI_CM_Stream_ChatTip") or nil })
        cx = cx + bw + S(6)
    end
    top = top + sh + S(14)
    top = top + CMUI.para(self, T("IGUI_CM_Dock_Help"), pad, top, w, C.dim, UIFont.Small, 3) + S(10)
    CMUI.btnA(self, pad, top, S(26), T("IGUI_CM_Dock_Rescan"), function() CMDock.enforce(true) end, "ghost")
    top = top + S(36)
    self:form("dockset", pad, top, w, self.height - top - S(12), function(y)
        local rowH = S(40)
        if #CMDock.entries == 0 then
            CMUI.text(self, T("IGUI_CM_Dock_None"), pad, y, C.faint)
        end
        for _, e in ipairs(CMDock.entries) do
            CMUI.glass(self, pad, y, w - S(14), rowH, { tint = C.panel, a = 0.35, rad = 8, rimA = 0.25, shine = 0.3 })
            local is = rowH - S(12)
            if e.tex then self:drawTextureScaledAspect(e.tex, pad + S(8), y + S(6), is, is, 1, 1, 1, 1)
            else CMUI.textC(self, string.upper(string.sub(tostring(e.name), 1, 1)), pad + S(8) + is / 2, y + (rowH - CMUI.fh(UIFont.Medium)) / 2, C.gold, 1, UIFont.Medium) end
            CMUI.text(self, CMUI.fit(e.name, UIFont.Small, w - S(300)), pad + is + S(18), y + S(5), C.text)
            CMUI.text(self, T("IGUI_CM_Dock_W_" .. tostring(e.where)), pad + is + S(18), y + S(5) + CMUI.fh(UIFont.Small), C.faint)
            local mode = CMDock.modeOf(e)
            local bw = S(110)
            local bx = pad + w - S(14) - bw * 2 - S(16)
            CMUI.btn(self, bx, y + S(7), bw, rowH - S(14), T("IGUI_CM_Dock_Group"), function() CMDock.setMode(e, "group") end,
                mode == "group" and "primary" or "ghost")
            CMUI.btn(self, bx + bw + S(6), y + S(7), bw, rowH - S(14), T("IGUI_CM_Dock_Origin"), function() CMDock.setMode(e, "origin") end,
                mode == "origin" and "sel" or "ghost")
            y = y + rowH + S(6)
        end
    end)
end

function SW:onClosed() CMDock.setWin = nil end

function CMDock.openSettings()
    if CMDock.setWin then CMDock.setWin:bringToTop(); return end
    CMDock.enforce(true)
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(560, 560)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = SW:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    win:show()
    CMDock.setWin = win
end

-- ===================================================================== stream mode
-- Clean screen for streaming / screenshots: only the minimap, hotbar, inventory windows and the clock stay.
-- HUD-like things stay hidden while it is on; windows are hidden once and the player can open them again.
-- Everything we hid is shown again when it turns off. Nothing is saved: a new session starts with it off.
local ST = CMDock.stream or { on = false, hid = {}, at = 0, last = 0 }
CMDock.stream = ST

local KEEP_TYPES = { "MiniMap", "Minimap", "Hotbar", "ISInventoryPage", "Clock", "ContextMenu", "ToolTip", "Tooltip",
    "Modal", "Dialog", "TextBox", "Radial", "Wheel", "WorldMap", "Loading", "Death", "Respawn", "CMFade", "CMHud", "CMDock_Ghost", "CMGame" }
CMDock.STREAM_KEEP = { "chat", "moodle", "dash", "hud" }

function CMDock.keepOpt(k) return CMDock.cfg["stream." .. k] == "1" end

function CMDock.setKeepOpt(k, v)
    CMDock.cfg["stream." .. k] = v and "1" or "0"
    CMDock.save()
    if ST.on then pcall(CMDock.streamTick, false) end
end

function CMDock.streamHidesHud() return ST.on and not CMDock.keepOpt("hud") end

local function hasAny(t, list)
    for _, s in ipairs(list) do if string.find(t, s, 1, true) then return true end end
    return false
end

local function isWindow(el)
    if el.closeButton or el.pinButton or el.resizeWidget then return true end
    if string.find(tostring(el.Type or ""), "Window", 1, true) then return true end
    if type(el.headerH) == "number" and el.headerH > 0 then return true end
    return (el.width or 0) >= 320 and (el.height or 0) >= 240
end

-- keep | hud (kept hidden) | win (hidden once) | chat (shown only while typing)
function CMDock.streamClass(el, java)
    if java then
        local s = tostring(el)
        if string.find(s, "Moodle", 1, true) then return CMDock.keepOpt("moodle") and "keep" or "hud" end
        if string.find(s, "SpeedControls", 1, true) then return "hud" end
        return "keep"
    end
    if el == CMDock.ghost then return "keep" end
    local t = tostring(el.Type or "")
    if hasAny(t, KEEP_TYPES) then return "keep" end
    if string.find(t, "ISChat", 1, true) then return CMDock.keepOpt("chat") and "keep" or "chat" end
    if string.find(t, "Moodle", 1, true) then return CMDock.keepOpt("moodle") and "keep" or "hud" end
    if string.find(t, "Dashboard", 1, true) then return CMDock.keepOpt("dash") and "keep" or "hud" end
    if isWindow(el) then return "win" end
    return "hud"
end

local HUD_WORDS = { "Hud", "HUD", "Toast", "Tracker", "Notif", "Indicator", "Overlay", "Dashboard", "Moodle", "Float",
    "Btn", "Button", "Icon", "Sidebar", "ISEquippedItem", "SpeedControls" }

local function hudLike(el)
    if el == CMDock.float then return true end
    return hasAny(tostring(el.Type or ""), HUD_WORDS)
end

local function chatTyping()
    if not ISChat then return false end
    if ISChat.focused == true then return true end
    return ISChat.instance ~= nil and ISChat.instance.focused == true
end

function CMDock.streamTick(first)
    local okL, list = pcall(function() return UIManager.getUI() end)
    if not okL or not list then return end
    local seen = {}
    local n = list:size()
    for i = 0, n - 1 do
        local jel = list:get(i)
        local okT, tbl = pcall(function() return jel:getTable() end)
        local java = not (okT and type(tbl) == "table")
        local el = java and jel or tbl
        if el then
            seen[el] = true
            local okC, cls = pcall(CMDock.streamClass, el, java)
            if not okC then cls = "keep" end
            local mine = ST.hid[el]
            if cls == "keep" then
                if mine then setVis(el, true); ST.hid[el] = nil end
            elseif cls == "chat" then
                if chatTyping() then
                    if mine and not visible(el) then setVis(el, true) end
                elseif visible(el) then
                    setVis(el, false); ST.hid[el] = "chat"
                end
            elseif cls == "win" then
                if first then
                    if visible(el) then setVis(el, false); ST.hid[el] = "win" end
                elseif mine and visible(el) then
                    ST.hid[el] = nil -- the player opened it again, it is theirs now
                end
            elseif visible(el) then
                -- HUD: hide everything at the start; later only what comes back or looks like a HUD,
                -- so a panel the player opens on purpose is never fought
                if first or mine == "hud" or java or hudLike(el) then
                    setVis(el, false); ST.hid[el] = "hud"
                end
            end
        end
    end
    -- forget things that left the screen for good (closed windows, finished toasts)
    local gone = {}
    for el, _ in pairs(ST.hid) do if not seen[el] then gone[#gone + 1] = el end end
    for _, el in ipairs(gone) do ST.hid[el] = nil end
end

-- the only thing left of the dock: a faint button where the dock was, click = back to normal
CMDock.Ghost = ISPanel:derive("CMDock_Ghost")
local G = CMDock.Ghost
function G:new(x, y, s)
    local o = ISPanel.new(self, x, y, s, s)
    o.background = false
    return o
end
function G:prerender() end
function G:render()
    local s = self.width
    local over = self:isMouseOver()
    local age = CMC.ms() - (ST.at or 0)
    local intro = age < 5000
    local a = 0.16
    if over then a = 1 elseif intro then a = 0.9 end
    if over or intro then CMUI.glow(self, s / 2, s / 2, s * 1.3, s * 1.3, C.accent, 0.35 * a) end
    local tex = CMUI.tex("cm_stream")
    if tex then self:drawTextureScaledAspect(tex, 0, 0, s, s, a, C.gold[1], C.gold[2], C.gold[3])
    else self:drawRect(4, 4, s - 8, s - 8, a, C.accent[1], C.accent[2], C.accent[3]) end
    if over or intro then
        local la = 1
        if not over then la = math.max(0, math.min(1, (5000 - age) / 1000)) end
        local label = over and T("IGUI_CM_Stream_Exit") or T("IGUI_CM_Stream_Intro")
        local fh = CMUI.fh(UIFont.Small)
        local tw = CMUI.tw(UIFont.Small, label) + 18
        local ly = math.floor((s - fh - 8) / 2)
        CMUI.rbox(self, s + 6, ly, tw, fh + 8, C.bg, 0.82 * la, 7)
        CMUI.rborder(self, s + 6, ly, tw, fh + 8, C.line, 0.6 * la, 7)
        CMUI.text(self, label, s + 15, ly + 4, C.text, la)
    end
end
function G:onMouseDown(x, y) return true end
function G:onMouseUp(x, y) CMDock.setStream(false); return true end
function G:onRightMouseDown(x, y) return true end
function G:onRightMouseUp(x, y) CMDock.setStream(false); return true end

function CMDock.showGhost(on)
    if CMDock.ghost then
        pcall(function() CMDock.ghost:setVisible(false); CMDock.ghost:removeFromUIManager() end)
        CMDock.ghost = nil
    end
    if not on then return end
    local x, y, s = 10, 140, 32
    local ref = nil
    if CMDock.float and visible(CMDock.float) then ref = CMDock.float
    elseif CMDock.btn and visible(CMDock.btn) and sidebar() and visible(sidebar()) then ref = CMDock.btn end
    if ref then
        pcall(function() x, y, s = ref:getAbsoluteX(), ref:getAbsoluteY(), math.floor(ref:getWidth() * 0.7) end)
    end
    s = math.max(24, math.min(48, s))
    local g = G:new(x, y, s)
    g:initialise()
    g:instantiate()
    g:addToUIManager()
    pcall(function() g:setAlwaysOnTop(true) end)
    CMDock.ghost = g
end

function CMDock.setStream(on)
    on = on == true
    if on == (ST.on == true) then return end
    if on then
        if CMDock.pop then CMDock.pop:close() end
        if CMDock.setWin then CMDock.setWin:close() end
        CMDock.showGhost(true)
        ST.on = true
        ST.hid = {}
        ST.at = CMC.ms()
        ST.last = ST.at
        CMDock.streamTick(true)
    else
        ST.on = false
        local back = ST.hid
        ST.hid = {}
        for el, _ in pairs(back) do setVis(el, true) end
        CMDock.showGhost(false)
        local ok, err = pcall(CMDock.apply)
        if not ok then CM.log("dock apply error: " .. tostring(err)) end
    end
end

-- optional hotkey: Options > Mods > Cookie Mission (unbound by default)
local function initOptions()
    if CMDock.opt or not (PZAPI and PZAPI.ModOptions) then return end
    local ok, o = pcall(function() return PZAPI.ModOptions:create("CookieMission", "Cookie Mission") end)
    if not ok or not o then return end
    pcall(function() o:addKeyBind("streamKey", getText("IGUI_CM_Opt_StreamKey"), 0, getText("IGUI_CM_Opt_StreamKeyTip")) end)
    CMDock.opt = o
end

function CMDock.streamKey()
    local o = CMDock.opt
    if not o then return 0 end
    local ok, v = pcall(function() return o:getOption("streamKey"):getValue() end)
    if ok and type(v) == "number" then return v end
    return 0
end

Events.OnCreateUI.Add(initOptions)
Events.OnKeyPressed.Add(function(key)
    local k = CMDock.streamKey()
    if not k or k == 0 or key ~= k then return end
    if chatTyping() or not getPlayer() then return end
    CMDock.setStream(not ST.on)
end)

-- ===================================================================== install
local pending = false
local waitTicks = 0
local function onTickInstall()
    if not pending then return end
    if not (ISEquippedItem and ISEquippedItem.instance) then return end
    if ST.on then return end -- stream mode was turned on by hotkey first: set the dock up when it ends
    -- give the other mods a moment to add their own buttons first
    waitTicks = waitTicks + 1
    if waitTicks < 30 then return end
    pending = false
    Events.OnTick.Remove(onTickInstall)
    local ok, err = pcall(CMDock.apply)
    if not ok then CM.log("dock install error: " .. tostring(err)) end
end

Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum ~= 0 then return end
    CMDock.load()
    pending = true
    waitTicks = 0
    Events.OnTick.Add(onTickInstall)
end)

-- keep grouped buttons hidden even when their mod shows them again (respawn, resolution change)
Events.OnTick.Add(function()
    if ST.on then
        local t = CMC.ms()
        if t - (ST.last or 0) < 300 then return end
        ST.last = t
        local okS, errS = pcall(CMDock.streamTick, false)
        if not okS then CM.log("stream error: " .. tostring(errS)) end
        return
    end
    if pending or not CMDock.btn and not CMDock.float then return end
    -- the game rebuilds the sidebar when the player changes the sidebar size option
    local inst = sidebar()
    if inst and inst ~= CMDock.inst then
        local okA, errA = pcall(CMDock.apply)
        if not okA then CM.log("dock apply error: " .. tostring(errA)) end
        return
    end
    local ok, err = pcall(CMDock.enforce, false)
    if not ok then CM.log("dock error: " .. tostring(err)) end
end)

Events.OnResolutionChange.Add(function()
    if ST.on then return end
    if sidebar() and (CMDock.btn or CMDock.float) then pcall(CMDock.apply) end
end)

-- respawn with it on: give everything back, the dock is set up again by the install step
Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum ~= 0 or not ST.on then return end
    ST.on = false
    local back = ST.hid
    ST.hid = {}
    for el, _ in pairs(back) do setVis(el, true) end
    CMDock.showGhost(false)
end)

return CMDock
