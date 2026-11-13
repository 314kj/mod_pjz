-- Cookie Exchange : the Cookie Shop window
-- Left: one tab per category, then "Buy-back" and (admins) "Admin". Right: the rows of that tab.
-- Rows are drawn by hand; clicks are hit-tested against the button boxes saved while drawing.
-- Buying anything from $1,000 up needs a second click within 3 seconds (button turns to Confirm).
-- Admin: edit / delete on every row, + item / + category / edit category / + buy-back, wallets +/-.

require "CookieExchange/CX_Const"
require "CookieExchange/CX_ShopDefs"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"

CXShopWindow = ISPanel:derive("CXShopWindow")
CXShopList = ISPanel:derive("CXShopList")
CXShopForm = ISPanel:derive("CXShopForm")

local FONT_S = getTextManager():getFontHeight(UIFont.Small)
local FONT_M = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 12
local W, H = 460, 560
local TAB_W = 118
local TAB_H = math.max(FONT_S + 12, 28)
local ROW_H = math.max(FONT_S * 2 + 14, 46)
local BTN_W, BTN_H = 76, math.max(FONT_S + 8, 24)
local SMALL_W = 44
local ARM_MS = 3000
local ARM_FROM = 1000    -- dollars: from here a buy needs a confirm click

local GOLD = { r = 1, g = 0.85, b = 0.4 }

local function T(key, ...) return getText(key, ...) end

local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return os.time() * 1000
end

local texCache = {}
local function iconTex(ft)
    if not ft then return nil end
    if texCache[ft] ~= nil then return texCache[ft] or nil end
    local tex = nil
    pcall(function()
        local si = getScriptManager():FindItem(ft)
        if si then
            tex = si:getNormalTexture()
            if not tex and si:getIcon() then tex = getTexture("Item_" .. si:getIcon()) end
        end
    end)
    texCache[ft] = tex or false
    return tex
end

local function textW(s, font)
    return getTextManager():MeasureStringX(font or UIFont.Small, tostring(s))
end

-- ==============================================================================
-- list panel (one per window, content follows the selected tab)
-- ==============================================================================
function CXShopList:new(x, y, w, h, win)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.win = win
    o.scroll = 0
    o.hits = {}
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.15 }
    return o
end

function CXShopList:onMouseWheel(del)
    self.scroll = math.max(0, self.scroll + del * ROW_H)
    return true
end

function CXShopList:hit(x, y, w, h, fn)
    self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

-- a drawn button; registers its box for clicks
function CXShopList:button(x, y, w, h, label, fn, hot)
    local hover = self:isMouseOver() and self:getMouseX() >= x and self:getMouseX() < x + w
        and self:getMouseY() >= y and self:getMouseY() < y + h
    local a = hover and 0.55 or 0.3
    if hot then self:drawRect(x, y, w, h, a + 0.2, 0.75, 0.45, 0.1)
    else self:drawRect(x, y, w, h, a, 0.25, 0.25, 0.25) end
    self:drawRectBorder(x, y, w, h, 0.6, 1, 1, 1)
    self:drawTextCentre(label, x + w / 2, y + (h - FONT_S) / 2, 1, 1, 1, 1, UIFont.Small)
    if fn then self:hit(x, y, w, h, fn) end
end

function CXShopList:onMouseDown(x, y)
    for i = #self.hits, 1, -1 do
        local b = self.hits[i]
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            pcall(b.fn)
            return true
        end
    end
    return true
end

function CXShopList:prerender()
    ISPanel.prerender(self)
    self:setStencilRect(0, 0, self.width, self.height)
end

function CXShopList:render()
    ISPanel.render(self)
    self.hits = {}
    local tab = self.win.tab
    local y = 6 - self.scroll
    if tab == "@sell" then y = self:drawSell(y)
    elseif tab == "@admin" then y = self:drawAdmin(y)
    else y = self:drawItems(y, tab) end
    local content = y + self.scroll
    local maxScroll = math.max(0, content - self.height + 6)
    if self.scroll > maxScroll then self.scroll = maxScroll end
    self:clearStencilRect()
end

local function adminBar(self, y, buttons)
    local x = 8
    for _, b in ipairs(buttons) do
        local w = math.max(SMALL_W, textW(b[1]) + 14)
        self:button(x, y, w, BTN_H, b[1], b[2])
        x = x + w + 6
    end
    return y + BTN_H + 8
end

function CXShopList:drawItems(y, catId)
    local shop = CX.shop
    if not shop then
        self:drawText("...", 10, y, 1, 1, 1, 0.8, UIFont.Small)
        return y + ROW_H
    end
    local win = self.win
    if shop.admin then
        y = adminBar(self, y, {
            { T("IGUI_CX_AddItem"), function() win:openForm("item", nil, catId) end },
            { T("IGUI_CX_EditCat"), function() win:openForm("cat", win:catById(catId)) end },
            { T("IGUI_CX_DelCat"), function() win:armOrRun("delcat:" .. catId, function() CX.shopSend("a_delcat", { id = catId }) end) end },
        })
    end
    local any = false
    for _, r in ipairs(shop.items or {}) do
        if r.cat == catId then
            any = true
            y = self:drawItemRow(y, r)
        end
    end
    if not any then
        self:drawText(T("IGUI_CX_Empty"), 10, y + 4, 0.7, 0.7, 0.7, 1, UIFont.Small)
        y = y + ROW_H
    end
    return y
end

function CXShopList:drawItemRow(y, r)
    local win = self.win
    local w = self.width
    self:drawRect(4, y, w - 8, ROW_H - 4, 0.25, 0.1, 0.1, 0.1)
    local tex = iconTex(r.icon)
    if tex then
        self:drawTextureScaledAspect(tex, 10, y + (ROW_H - 4 - 32) / 2, 32, 32, 1, 1, 1, 1)
    elseif r.kind == "trait" then
        local sign = string.sub(r.spec or "", 1, 1) == "-" and "-" or "+"
        self:drawTextCentre(sign, 26, y + (ROW_H - 4 - FONT_M) / 2, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Medium)
    end
    local tx = 50
    self:drawText(r.name, tx, y + 5, 1, 1, 1, 1, UIFont.Small)
    local mine = (CX.shop.mine or {})[r.id] or 0
    local line2 = CX.money(r.price * 100)
    local soldOut = false
    if r.limit and r.limit > 0 then
        local left = math.max(0, r.limit - mine)
        soldOut = left <= 0
        line2 = line2 .. "   " .. T("IGUI_CX_Left", tostring(left), tostring(r.limit))
    end
    self:drawText(line2, tx, y + 7 + FONT_S, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Small)

    local bx = w - 10 - BTN_W
    local by = y + (ROW_H - 4 - BTN_H) / 2
    if soldOut then
        self:drawTextCentre(T("IGUI_CX_SoldOut"), bx + BTN_W / 2, by + (BTN_H - FONT_S) / 2, 0.7, 0.7, 0.7, 1, UIFont.Small)
    elseif r.cat == CX.KIT_CAT then
        self:drawTextCentre(T("IGUI_CX_KitRow"), bx + BTN_W / 2, by + (BTN_H - FONT_S) / 2, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Small)
    else
        local armed = win:isArmed("buy:" .. r.id)
        self:button(bx, by, BTN_W, BTN_H, armed and T("IGUI_CX_Confirm") or T("IGUI_CX_Buy"), function()
            local go = function() CX.shopSend("buy", { id = r.id, price = r.price }); CX.shopStatus = "..." end
            if r.price >= ARM_FROM then win:armOrRun("buy:" .. r.id, go) else go() end
        end, armed)
    end
    if CX.shop.admin then
        local ex = bx - 6 - SMALL_W * 2 - 4
        self:button(ex, by, SMALL_W, BTN_H, T("IGUI_CX_Edit"), function() win:openForm("item", r) end)
        local armedDel = win:isArmed("del:" .. r.id)
        self:button(ex + SMALL_W + 4, by, SMALL_W, BTN_H, armedDel and "?" or T("IGUI_CX_Delete"), function()
            win:armOrRun("del:" .. r.id, function() CX.shopSend("a_delrow", { id = r.id }) end)
        end, armedDel)
    end
    return y + ROW_H
end

function CXShopList:drawSell(y)
    local shop = CX.shop
    local win = self.win
    if not shop then return y end
    self:drawText(T("IGUI_CX_SellHint"), 10, y, 1, 0.6, 0.15, 1, UIFont.Small)
    y = y + FONT_S + 8
    if shop.admin then
        y = adminBar(self, y, { { T("IGUI_CX_AddSell"), function() win:openForm("sell", nil) end } })
    end
    for _, s in ipairs(shop.sell or {}) do
        self:drawRect(4, y, self.width - 8, ROW_H - 4, 0.25, 0.1, 0.1, 0.1)
        local tex = iconTex(s.ft)
        if tex then self:drawTextureScaledAspect(tex, 10, y + (ROW_H - 4 - 32) / 2, 32, 32, 1, 1, 1, 1) end
        self:drawText(CX.itemName(s.ft), 50, y + 5, 1, 0.6, 0.15, 1, UIFont.Small)
        self:drawText(CX.money(s.price * 100) .. " " .. T("IGUI_CX_Each"), 50, y + 7 + FONT_S, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Small)
        if shop.admin then
            local by = y + (ROW_H - 4 - BTN_H) / 2
            local ex = self.width - 10 - SMALL_W * 2 - 4
            self:button(ex, by, SMALL_W, BTN_H, T("IGUI_CX_Edit"), function() win:openForm("sell", s) end)
            local armedDel = win:isArmed("dels:" .. s.ft)
            self:button(ex + SMALL_W + 4, by, SMALL_W, BTN_H, armedDel and "?" or T("IGUI_CX_Delete"), function()
                win:armOrRun("dels:" .. s.ft, function() CX.shopSend("a_delsell", { ft = s.ft }) end)
            end, armedDel)
        end
        y = y + ROW_H
    end
    return y
end

function CXShopList:drawAdmin(y)
    local win = self.win
    y = adminBar(self, y, {
        { T("IGUI_CX_AddCat"), function() win:openForm("cat", nil) end },
        { T("IGUI_CX_Reload"), function() CX.shopSend("a_reload") end },
        { T("IGUI_CX_Refresh"), function() CX.shopSend("a_wallets") end },
    })
    self:drawText(T("IGUI_CX_Wallets"), 10, y, 1, 1, 1, 0.9, UIFont.Small)
    y = y + FONT_S + 6
    local rowH = FONT_S + 8
    for _, e in ipairs(CX.wallets or {}) do
        local sel = win.pick == e.n
        if sel then self:drawRect(4, y, self.width - 8, rowH, 0.35, 0.75, 0.45, 0.1) end
        self:drawText(tostring(e.n), 10, y + 4, 1, 1, 1, 1, UIFont.Small)
        local m = CX.money(e.c)
        self:drawText(m, self.width - 12 - textW(m), y + 4, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Small)
        self:hit(4, y, self.width - 8, rowH, function() win.pick = e.n end)
        y = y + rowH
    end
    return y
end

-- ==============================================================================
-- window
-- ==============================================================================
function CXShopWindow:new(x, y)
    local o = ISPanel:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.88 }
    o.borderColor = { r = GOLD.r, g = GOLD.g, b = GOLD.b, a = 0.6 }
    o.tab = nil
    o.tabBtns = {}
    o.armed = {}
    o.shownVer = nil
    return o
end

function CXShopWindow:createChildren()
    ISPanel.createChildren(self)
    self.closeBtn = ISButton:new(self.width - PAD - 24, PAD - 2, 24, 22, "X", self, CXShopWindow.close)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    self.top = PAD + FONT_M + 12
    self.statusY = self.height - PAD - FONT_S
    local listX = PAD + TAB_W + 8
    local bottom = self.statusY - 8

    -- admin wallet controls sit under the list, only on the Admin tab
    local ctrlY = bottom - TAB_H
    self.amt = ISTextEntryBox:new("", listX, ctrlY, 110, TAB_H)
    self.amt:initialise()
    self.amt:instantiate()
    self.amt:setOnlyNumbers(true)
    self:addChild(self.amt)
    self.plusBtn = ISButton:new(listX + 116, ctrlY, 90, TAB_H, T("IGUI_CX_Give"), self, CXShopWindow.onAdjust)
    self.plusBtn.internal = "+"
    self.plusBtn:initialise()
    self:addChild(self.plusBtn)
    self.minusBtn = ISButton:new(listX + 212, ctrlY, 90, TAB_H, T("IGUI_CX_Take"), self, CXShopWindow.onAdjust)
    self.minusBtn.internal = "-"
    self.minusBtn:initialise()
    self:addChild(self.minusBtn)
    self.ctrlY = ctrlY

    self.list = CXShopList:new(listX, self.top, self.width - listX - PAD, bottom - self.top, self)
    self.list:initialise()
    self:addChild(self.list)
    self:onCatalog()
end

function CXShopWindow:catById(id)
    for _, c in ipairs((CX.shop and CX.shop.cats) or {}) do
        if c.id == id then return c end
    end
    return nil
end

function CXShopWindow:tabs()
    local out = {}
    for _, c in ipairs((CX.shop and CX.shop.cats) or {}) do out[#out + 1] = { id = c.id, name = c.name } end
    out[#out + 1] = { id = "@sell", name = T("IGUI_CX_BuyBack") }
    if CX.shop and CX.shop.admin then out[#out + 1] = { id = "@admin", name = T("IGUI_CX_Admin") } end
    return out
end

function CXShopWindow:selectTab(id)
    self.tab = id
    self.list.scroll = 0
    for _, b in ipairs(self.tabBtns) do
        local on = b.internal == id
        b.backgroundColor = on and { r = 0.75, g = 0.45, b = 0.1, a = 0.8 } or { r = 0, g = 0, b = 0, a = 0.6 }
    end
    local adm = id == "@admin"
    self.amt:setVisible(adm)
    self.plusBtn:setVisible(adm)
    self.minusBtn:setVisible(adm)
    local bottom = (adm and self.ctrlY or self.statusY) - 8
    self.list:setHeight(bottom - self.top)
    if adm then CX.shopSend("a_wallets") end
end

function CXShopWindow:onTab(btn)
    self:selectTab(btn.internal)
end

-- rebuild the tab buttons when the catalog changes
function CXShopWindow:onCatalog()
    if not self.list then return end
    local ver = CX.shop and CX.shop.ver or -1
    local admin = CX.shop and CX.shop.admin or false
    if self.shownVer == ver and self.shownAdmin == admin then return end
    self.shownVer, self.shownAdmin = ver, admin
    for _, b in ipairs(self.tabBtns) do self:removeChild(b) end
    self.tabBtns = {}
    local tabs = self:tabs()
    local y = self.top
    local keep = false
    for _, t in ipairs(tabs) do
        local b = ISButton:new(PAD, y, TAB_W, TAB_H, t.name, self, CXShopWindow.onTab)
        b.internal = t.id
        b:initialise()
        b.borderColor = { r = 1, g = 1, b = 1, a = 0.25 }
        self:addChild(b)
        self.tabBtns[#self.tabBtns + 1] = b
        if t.id == self.tab then keep = true end
        y = y + TAB_H + 4
    end
    self:selectTab(keep and self.tab or (tabs[1] and tabs[1].id))
end

function CXShopWindow:isArmed(key)
    local t = self.armed[key]
    return t ~= nil and nowMs() < t
end

-- first click arms, second click (within 3 s) runs
function CXShopWindow:armOrRun(key, fn)
    if self:isArmed(key) then
        self.armed[key] = nil
        fn()
    else
        self.armed = {}
        self.armed[key] = nowMs() + ARM_MS
    end
end

function CXShopWindow:onAdjust(btn)
    local amt = tonumber((string.gsub(self.amt:getText() or "", "[^%d]", "")))
    if not self.pick then CX.shopStatus = T("IGUI_CX_PickWallet"); CX.shopOk = false; return end
    if not amt or amt < 1 then CX.shopStatus = T("IGUI_CX_Shop_BadAmount"); CX.shopOk = false; return end
    CX.shopSend("a_adjust", { who = self.pick, amt = amt, sign = btn.internal })
    CX.shopStatus = "..."
end

function CXShopWindow:openForm(kind, row, catId)
    if self.form then self.form:close() end
    local f = CXShopForm:new(self:getAbsoluteX() + 30, self:getAbsoluteY() + 60, kind, row, catId)
    f:initialise()
    f:addToUIManager()
    self.form = f
end

function CXShopWindow:render()
    ISPanel.render(self)
    self:drawText(T("IGUI_CX_ShopTitle") .. "   " .. (CX.bal and CX.money(CX.bal) or "..."), PAD, PAD, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Medium)
    if self.tab == "@admin" and self.pick then
        self:drawText(tostring(self.pick), self.amt:getX(), self.ctrlY - FONT_S - 4, 1, 1, 1, 0.9, UIFont.Small)
    end
    if CX.shopStatus then
        local g = CX.shopOk and 1 or 0.55
        self:drawText(CX.shopStatus, PAD, self.statusY, CX.shopOk and 0.55 or 1, g, 0.55, 1, UIFont.Small)
    end
end

function CXShopWindow:close()
    if self.form then self.form:close() end
    self:setVisible(false)
    self:removeFromUIManager()
    CX.shopWindow = nil
end

function CX.toggleShop()
    if CX.shopWindow then
        CX.shopWindow:close()
        return
    end
    CX.shopStatus = nil
    local x = getCore():getScreenWidth() / 2 - W / 2
    local y = getCore():getScreenHeight() / 2 - H / 2
    local w = CXShopWindow:new(x, y)
    w:initialise()
    w:addToUIManager()
    CX.shopWindow = w
    CX.shopSend("shop")
    CX.shopSend("hello")
end

-- ==============================================================================
-- "Gives" suggestions: type in the box, pick from a scrolling list under it
-- Lists come from this build (script manager / AnimalDefinitions / trait registry), read once per
-- session. The server still checks every row on save, so a list that cannot be read only means
-- the admin types the id by hand.
-- ==============================================================================
local SUG_ROWS = 12
local SUG_BAR = 12      -- scrollbar strip on the right: click or drag it
local SUG_H = math.max(FONT_S * 2 + 6, 34)
local lists = {}

local function jlist(v)
    local out = {}
    if v == nil then return out end
    local ok, n = pcall(function() return v:size() end)
    if not ok or type(n) ~= "number" then return out end
    for i = 0, n - 1 do
        local okG, e = pcall(function() return v:get(i) end)
        if okG and e ~= nil then out[#out + 1] = e end
    end
    return out
end

local function addRow(out, seen, v, label, ft)
    if not v or v == "" or seen[v] then return end
    seen[v] = true
    label = (label and label ~= "") and label or v
    local row = { v = v, label = label, ft = ft, l = string.lower(label .. " " .. v) }
    out[#out + 1] = row
    return row
end

local BUILD = {}

function BUILD.item(out, seen)
    local ok, all = pcall(function() return getScriptManager():getAllItems() end)
    for _, si in ipairs(ok and jlist(all) or {}) do
        local okF, ft = pcall(function() return si:getFullName() end)
        if okF and type(ft) == "string" then
            local okD, dn = pcall(function() return si:getDisplayName() end)
            addRow(out, seen, ft, okD and dn and tostring(dn) or nil, ft)
        end
    end
end

function BUILD.car(out, seen)
    local ok, all = pcall(function() return getScriptManager():getAllVehicleScripts() end)
    for _, sc in ipairs(ok and jlist(all) or {}) do
        local okF, fn = pcall(function() return sc:getFullName() end)
        if not (okF and type(fn) == "string" and string.find(fn, ".", 1, true)) then
            okF, fn = pcall(function() return sc:getModule():getName() .. "." .. sc:getName() end)
        end
        if okF and type(fn) == "string" then addRow(out, seen, fn, nil, nil) end
    end
end

function BUILD.pet(out, seen)
    local defs = type(AnimalDefinitions) == "table" and (type(AnimalDefinitions.animals) == "table"
        and AnimalDefinitions.animals or AnimalDefinitions) or {}
    for typ, def in pairs(defs) do
        if type(typ) == "string" and type(def) == "table" then
            addRow(out, seen, typ, nil, nil)
            if type(def.breeds) == "table" then
                for breed in pairs(def.breeds) do
                    if type(breed) == "string" then
                        addRow(out, seen, typ .. ":" .. breed, typ .. " (" .. breed .. ")", nil)
                    end
                end
            end
        end
    end
end

-- trait ids are written the way the server reads them (+base:fastlearner); a name that does not
-- go back through CharacterTrait.get is left out rather than guessed
function BUILD.trait(out, seen)
    local ok, all = pcall(function() return CharacterTraitDefinition.getTraits() end)
    for _, def in ipairs(ok and jlist(all) or {}) do
        local okT, t = pcall(function() return def:getType() end)
        if okT and t then
            local id = string.lower(tostring(t))
            if not string.find(id, ":", 1, true) then id = "base:" .. id end
            local okR, back = pcall(function() return CharacterTrait.get(ResourceLocation.of(id)) end)
            if okR and back ~= nil then
                local okL, label = pcall(function() return getText(def:getLabel()) end)
                local row = addRow(out, seen, id, okL and label and tostring(label) or nil, nil)
                if row then
                    local okX, tex = pcall(function() return def:getTexture() end)
                    if okX and tex then row.tex = tex end
                    local okC, cost = pcall(function() return def:getCost() end)
                    row.bad = okC and type(cost) == "number" and cost < 0
                end
            end
        end
    end
end

local function listFor(kind)
    if lists[kind] then return lists[kind] end
    local out, seen = {}, {}
    if BUILD[kind] then pcall(BUILD[kind], out, seen) end
    table.sort(out, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.v < b.v
    end)
    lists[kind] = out
    return out
end

-- the part of the box the list searches and replaces: the last line of an item list, the whole
-- box for the rest; a count ("x3") and a trait sign stay as typed
local function splitSpec(kind, text)
    local head, body = "", text
    if kind == "item" then
        local a = string.match(text, "^(.*,)%s*[^,]*$")
        if a then head = a .. " "; body = string.sub(text, #a + 1) end
    end
    body = string.gsub(string.gsub(body, "^%s+", ""), "%s+$", "")
    local sign, tail = "", ""
    if kind == "trait" then
        sign = string.match(body, "^[%+%-]") or "+"
        body = string.gsub(body, "^[%+%-]%s*", "")
    else
        local b, n = string.match(body, "^(.-)%s+[xX](%d+)$")
        if b then body = b; tail = " x" .. n end
    end
    return head .. sign, body, tail
end

CXSuggest = ISPanel:derive("CXSuggest")

function CXSuggest:new(form, box)
    local o = ISPanel:new(0, 0, box:getWidth(), SUG_H * SUG_ROWS + 2)
    setmetatable(o, self)
    self.__index = self
    o.form = form
    o.box = box
    o.rows = {}
    o.scroll = 0
    o.backgroundColor = { r = 0.03, g = 0.03, b = 0.03, a = 0.97 }
    o.borderColor = { r = GOLD.r, g = GOLD.g, b = GOLD.b, a = 0.8 }
    return o
end

function CXSuggest:refresh()
    local kind = self.form:specKind()
    local _, q = splitSpec(kind, self.box:getText() or "")
    q = string.lower(q)
    local rows = {}
    for _, r in ipairs(listFor(kind)) do
        if q == "" or string.find(r.l, q, 1, true) then rows[#rows + 1] = r end
    end
    self.rows = rows
    self.kind = kind
    self.scroll = 0
end

function CXSuggest:place()
    local h = SUG_H * math.max(1, math.min(SUG_ROWS, #self.rows)) + 2
    self:setX(self.box:getAbsoluteX())
    self:setWidth(math.max(self.box:getWidth(), 420))
    self:setY(self.box:getAbsoluteY() + self.box:getHeight() + 2)
    self:setHeight(h)
end

function CXSuggest:onMouseWheel(del)
    local maxS = math.max(0, #self.rows - SUG_ROWS)
    self.scroll = math.max(0, math.min(maxS, self.scroll + del))
    return true
end

function CXSuggest:barTo(y)
    local maxS = math.max(0, #self.rows - SUG_ROWS)
    if maxS == 0 then return end
    local f = math.max(0, math.min(1, (y - 1) / math.max(1, self.height - 2)))
    self.scroll = math.floor(f * maxS + 0.5)
end

function CXSuggest:onMouseDown(x, y)
    if #self.rows > SUG_ROWS and x >= self.width - SUG_BAR then
        self.dragBar = true
        self:barTo(y)
        return true
    end
    local i = math.floor((y - 1) / SUG_H) + 1 + self.scroll
    local r = self.rows[i]
    if r then
        local head, _, tail = splitSpec(self.kind, self.box:getText() or "")
        if self.kind == "trait" then
            head = string.gsub(head, "[%+%-]$", "") .. (r.bad and "-" or "+")
        end
        if self.kind == "item" then
            -- keep the list open: the next click adds another line to the pack
            self.box:setText(head .. r.v .. tail .. ", ")
            self.form.sugDirty = true
        else
            self.box:setText(head .. r.v .. tail)
            self.form.sugShut = true
            self:setVisible(false)
        end
    end
    return true
end

function CXSuggest:onMouseMove(dx, dy)
    if self.dragBar then self:barTo(self:getMouseY()) end
end

function CXSuggest:onMouseMoveOutside(dx, dy)
    if self.dragBar then self:barTo(self:getMouseY()) end
end

function CXSuggest:onMouseUp(x, y) self.dragBar = false; return true end
function CXSuggest:onMouseUpOutside(x, y) self.dragBar = false end

function CXSuggest:render()
    ISPanel.render(self)
    if #self.rows == 0 then
        self:drawText(T("IGUI_CX_NoMatch"), 8, (SUG_H - FONT_S) / 2, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end
    local mx, my = self:getMouseX(), self:getMouseY()
    for k = 1, math.min(SUG_ROWS, #self.rows - self.scroll) do
        local r = self.rows[k + self.scroll]
        local y = 1 + (k - 1) * SUG_H
        if self:isMouseOver() and my >= y and my < y + SUG_H and mx >= 0 and mx < self.width then
            self:drawRect(1, y, self.width - 2, SUG_H, 0.35, 0.75, 0.45, 0.1)
        end
        local tx = 6
        local tex = r.tex or (r.ft and iconTex(r.ft))
        if tex then
            self:drawTextureScaledAspect(tex, 4, y + 2, SUG_H - 4, SUG_H - 4, 1, 1, 1, 1)
            tx = SUG_H + 6
        end
        if self.kind == "trait" then
            local tag = r.bad and T("IGUI_CX_TraitRemove") or T("IGUI_CX_TraitBuy")
            local tw = getTextManager():MeasureStringX(UIFont.Small, tag)
            if r.bad then
                self:drawText(tag, self.width - SUG_BAR - tw - 6, y + 2, 1, 0.45, 0.4, 1, UIFont.Small)
            else
                self:drawText(tag, self.width - SUG_BAR - tw - 6, y + 2, 0.45, 0.9, 0.5, 1, UIFont.Small)
            end
        end
        self:drawText(r.label, tx, y + 2, 1, 1, 1, 1, UIFont.Small)
        if r.label ~= r.v then
            self:drawText(r.v, tx, y + 2 + FONT_S, 0.6, 0.6, 0.6, 1, UIFont.Small)
        end
    end
    if #self.rows > SUG_ROWS then
        local barH = math.max(24, self.height * SUG_ROWS / #self.rows)
        local barY = (self.height - barH) * self.scroll / (#self.rows - SUG_ROWS)
        self:drawRect(self.width - SUG_BAR, 1, SUG_BAR - 1, self.height - 2, 0.5, 0.15, 0.15, 0.15)
        self:drawRect(self.width - SUG_BAR + 2, barY, SUG_BAR - 5, barH, 0.85, GOLD.r, GOLD.g, GOLD.b)
    end
end

-- ==============================================================================
-- admin form: item row / category / buy-back row
-- ==============================================================================
local FORM_W = 400
local LABEL_W = 90

function CXShopForm:new(x, y, kind, row, catId)
    local o = ISPanel:new(x, y, FORM_W, 100)
    setmetatable(o, self)
    self.__index = self
    o.kind = kind          -- "item" | "cat" | "sell"
    o.row = row            -- nil = new
    o.catId = catId
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.95 }
    o.borderColor = { r = GOLD.r, g = GOLD.g, b = GOLD.b, a = 0.8 }
    o.fields = {}
    o.labels = {}
    return o
end

function CXShopForm:entry(key, label, text, numbers)
    local y = self.nextY
    local e = ISTextEntryBox:new(tostring(text or ""), PAD + LABEL_W, y, FORM_W - PAD * 2 - LABEL_W, TAB_H)
    e:initialise()
    e:instantiate()
    if numbers then e:setOnlyNumbers(true) end
    self:addChild(e)
    self.fields[key] = e
    self.labels[#self.labels + 1] = { text = label, y = y }
    self.nextY = y + TAB_H + 6
    return e
end

function CXShopForm:combo(key, label, options, selected)
    local y = self.nextY
    local c = ISComboBox:new(PAD + LABEL_W, y, FORM_W - PAD * 2 - LABEL_W, TAB_H, self, CXShopForm.onCombo)
    c:initialise()
    self:addChild(c)
    for _, op in ipairs(options) do c:addOptionWithData(op.text, op.data) end
    for i, op in ipairs(options) do
        if op.data == selected then c.selected = i end
    end
    self.fields[key] = c
    self.labels[#self.labels + 1] = { text = label, y = y }
    self.nextY = y + TAB_H + 6
    return c
end

function CXShopForm:onCombo()
    self.sugDirty = true
end

function CXShopForm:specKind()
    local c = self.fields.kind
    return c and c:getOptionData(c.selected) or "item"
end

-- the list shows while the Gives box has focus (or the mouse is on the list) and hides after a pick
-- until the admin types again
function CXShopForm:update()
    ISPanel.update(self)
    local s = self.sug
    if not s then return end
    local box = self.fields.spec
    local want = not self.sugShut and self:isVisible() and box and (box:isFocused() or s:isMouseOver())
    if want then
        if self.sugDirty or s.kind ~= self:specKind() or not s:isVisible() then
            s:refresh()
            self.sugDirty = false
        end
        s:place()
        if not s:isVisible() then s:setVisible(true) end
        s:bringToTop()
    elseif s:isVisible() then
        s:setVisible(false)
    end
end

function CXShopForm:createChildren()
    ISPanel.createChildren(self)
    self.nextY = PAD + FONT_M + 10
    local r = self.row or {}
    if self.kind == "item" then
        local idBox = self:entry("id", T("IGUI_CX_F_Id"), r.id)
        if self.row then idBox:setEditable(false) end
        local cats = {}
        for _, c in ipairs((CX.shop and CX.shop.cats) or {}) do cats[#cats + 1] = { text = c.name, data = c.id } end
        self:combo("cat", T("IGUI_CX_F_Cat"), cats, r.cat or self.catId)
        self:entry("name", T("IGUI_CX_F_Name"), r.name)
        local kinds = {}
        for _, k in ipairs(CX.KINDS) do kinds[#kinds + 1] = { text = T("IGUI_CX_Kind_" .. k), data = k } end
        self:combo("kind", T("IGUI_CX_F_Kind"), kinds, r.kind or "item")
        local spec = self:entry("spec", T("IGUI_CX_F_Spec"), r.spec)
        spec.onTextChange = function() self.sugShut = false; self.sugDirty = true end
        self.sug = CXSuggest:new(self, spec)
        self.sug:initialise()
        self.sug:setVisible(false)
        self.sug:addToUIManager()
        self.helpY = self.nextY
        self.nextY = self.nextY + FONT_S + 8
        self:entry("price", T("IGUI_CX_F_Price"), r.price, true)
        self:entry("limit", T("IGUI_CX_F_Limit"), r.limit or 0, true)
    elseif self.kind == "cat" then
        local idBox = self:entry("id", T("IGUI_CX_F_Id"), r.id)
        if self.row then idBox:setEditable(false) end
        self:entry("name", T("IGUI_CX_F_Name"), r.name)
    else
        local ftBox = self:entry("ft", T("IGUI_CX_F_Item"), r.ft)
        if self.row then ftBox:setEditable(false) end
        self:entry("price", T("IGUI_CX_F_Price"), r.price, true)
    end
    local y = self.nextY + 4
    self.saveBtn = ISButton:new(PAD, y, 120, TAB_H, T("IGUI_CX_Save"), self, CXShopForm.onSave)
    self.saveBtn:initialise()
    self:addChild(self.saveBtn)
    self.cancelBtn = ISButton:new(FORM_W - PAD - 120, y, 120, TAB_H, T("IGUI_CX_Cancel"), self, CXShopForm.close)
    self.cancelBtn:initialise()
    self:addChild(self.cancelBtn)
    self:setHeight(y + TAB_H + PAD)
end

local function txt(e) return e and e:getText() or "" end
local function data(c) return c and c:getOptionData(c.selected) or nil end

function CXShopForm:onSave()
    local f = self.fields
    if self.kind == "item" then
        CX.shopSend("a_saverow", { edit = self.row ~= nil, row = {
            id = txt(f.id), cat = data(f.cat), name = txt(f.name), kind = data(f.kind),
            spec = txt(f.spec), price = tonumber(txt(f.price)), limit = tonumber(txt(f.limit)) or 0,
        } })
    elseif self.kind == "cat" then
        CX.shopSend("a_savecat", { cat = { id = txt(f.id), name = txt(f.name) } })
    else
        CX.shopSend("a_savesell", { sell = { ft = txt(f.ft), price = tonumber(txt(f.price)) } })
    end
    CX.shopStatus = "..."
    self:close()
end

function CXShopForm:render()
    ISPanel.render(self)
    local title = self.kind == "cat" and T("IGUI_CX_FormCat") or (self.kind == "sell" and T("IGUI_CX_FormSell") or T("IGUI_CX_FormItem"))
    self:drawText(title, PAD, PAD, GOLD.r, GOLD.g, GOLD.b, 1, UIFont.Medium)
    for _, l in ipairs(self.labels) do
        self:drawText(l.text, PAD, l.y + (TAB_H - FONT_S) / 2, 1, 1, 1, 0.9, UIFont.Small)
    end
    if self.helpY then
        local k = data(self.fields.kind) or "item"
        self:drawText(T("IGUI_CX_Help_" .. k), PAD + LABEL_W, self.helpY, 0.7, 0.7, 0.7, 1, UIFont.Small)
    end
end

function CXShopForm:close()
    if self.sug then
        self.sug:setVisible(false)
        self.sug:removeFromUIManager()
        self.sug = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if CX.shopWindow and CX.shopWindow.form == self then CX.shopWindow.form = nil end
end
