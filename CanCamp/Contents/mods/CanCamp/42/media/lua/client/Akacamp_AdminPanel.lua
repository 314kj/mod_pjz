--[[ Akacamp Admin Panel v3 - top tab bar, one page per tab, fixed-size, English. ]]
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "Akacamp_Util"

AkacampAdmin = AkacampAdmin or {}
AkacampPanel = ISCollapsableWindow:derive("AkacampPanel")

local COL = {
    bg     = {0.10,0.11,0.13,0.97},
    line   = {0.28,0.50,0.70,0.55},
    title  = {0.60,0.82,1.0,1.0},
    text   = {0.88,0.90,0.94,1.0},
    dim    = {0.58,0.62,0.70,1.0},
    btn    = {0.16,0.30,0.45,0.45},
    tabOn  = {0.22,0.45,0.66,0.85},
    tabOff = {0.14,0.16,0.20,0.6},
}
local function rgba(t) return {r=t[1],g=t[2],b=t[3],a=t[4]} end
local function c4(t) return t[1],t[2],t[3],t[4] end

local PAD, W, PW, PH = 14, 430, 430, 470
local TABS = { "Registry", "Build", "Give", "Recipe", "Toll" }

function AkacampPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.cfg = self.cfg or { recipe = {}, toll = {} }
    self.recipeSize = "small"
    self.tollSize   = "small"
    self.tabWidgets = {}     -- [tab] = { widgets }
    self.curTab = "Registry"

    local top = self:titleBarHeight() + 6
    -- tab bar
    local tw = (W - PAD*2 - (#TABS-1)*4) / #TABS
    self.tabBtns = {}
    for i, name in ipairs(TABS) do
        local b = ISButton:new(PAD + (i-1)*(tw+4), top, tw, 24, name, self,
            function(s) s:setTab(name) end)
        b:initialise(); b:instantiate(); b.font = UIFont.Small
        b.borderColor = rgba(COL.line); b.textColor = rgba(COL.text)
        b.backgroundColor = rgba(COL.tabOff)
        self:addChild(b); self.tabBtns[name] = b
    end
    self.bodyY = top + 24 + 10

    self:buildRegistry()
    self:buildBuild()
    self:buildGive()
    self:buildRecipe()
    self:buildToll()

    self:setTab("Registry")
    sendClientCommand(getPlayer(), "Akacamp", "admin_registry", {})
    sendClientCommand(getPlayer(), "Akacamp", "get_config", {})
end

----------------------------------------------------------------- helpers
function AkacampPanel:tag(tab, w) self.tabWidgets[tab] = self.tabWidgets[tab] or {}; table.insert(self.tabWidgets[tab], w); return w end
function AkacampPanel:label(tab, text, x, y, font, col)
    col = col or COL.title
    local l = ISLabel:new(x, y, 16, text, col[1], col[2], col[3], col[4], font or UIFont.Small, true)
    l:initialise(); self:addChild(l); return self:tag(tab, l)
end
function AkacampPanel:styleBtn(b, bg)
    b.borderColor = rgba(COL.line); b.textColor = rgba(COL.text)
    b.backgroundColor = rgba(bg or COL.btn); b.font = UIFont.Small
end
function AkacampPanel:button(tab, text, x, y, w, h, fn)
    local b = ISButton:new(x, y, w, h, text, self, fn)
    b:initialise(); b:instantiate(); self:styleBtn(b); self:addChild(b); return self:tag(tab, b)
end
function AkacampPanel:listBox(tab, x, y, w, h, ih, drawFn)
    local lb = ISScrollingListBox:new(x, y, w, h)
    lb:initialise(); lb:instantiate()
    lb.itemheight = ih; lb.font = UIFont.Small; lb.drawBorder = true
    lb.doDrawItem = drawFn
    self:addChild(lb); return self:tag(tab, lb)
end
function AkacampPanel:textBox(tab, default, x, y, w, h, numbers)
    local t = ISTextEntryBox:new(default, x, y, w, h)
    t:initialise(); t:instantiate()
    if numbers then t:setOnlyNumbers(true) end
    self:addChild(t); return self:tag(tab, t)
end
function AkacampPanel:sizeSelector(tab, x, y, getSel, onSel)
    local iw = W - PAD*2
    local bw = (iw - 3*6) / 4
    local btns = {}
    for i, sz in ipairs(Akacamp.SIZES) do
        local b = ISButton:new(x+(i-1)*(bw+6), y, bw, 22, sz, self, function() onSel(sz) end)
        b:initialise(); b:instantiate(); self:styleBtn(b); self:addChild(b); self:tag(tab, b)
        btns[sz] = b
    end
    return btns
end

----------------------------------------------------------------- TAB: Registry
function AkacampPanel:buildRegistry()
    local x, y, iw = PAD, self.bodyY, W - PAD*2
    self:label("Registry", "TENT REGISTRY", x, y, UIFont.Medium); y = y + 24
    self.listReg = self:listBox("Registry", x, y, iw, 270, 22, function(lb, yy, item)
        local s = item.item
        local sel = (lb.selected == item.index)
        if sel then lb:drawRect(0, yy, lb.width, lb.itemheight, 0.25, c4(COL.tabOn)) end
        lb:drawText("#"..tostring(s.id), 8, yy+4, c4(COL.text))
        lb:drawText(s.size, 64, yy+4, c4(COL.dim))
        lb:drawText(s.owner or "(free)", 168, yy+4, c4(s.owner and COL.title or COL.dim))
        lb:drawRectBorder(0, yy, lb.width, lb.itemheight, 0.18, c4(COL.line))
        return yy + lb.itemheight
    end)
    y = y + 270 + 8
    local bw3 = (iw - 12) / 3
    self:button("Registry", "Warp to slot", x, y, bw3, 26, self.onWarpSlot)
    self:button("Registry", "Clear reg.",   x+bw3+6, y, bw3, 26, self.onClearReg)
    self:button("Registry", "Delete slot",  x+(bw3+6)*2, y, bw3, 26, self.onDeleteSlot)
end
function AkacampPanel:onWarpSlot()
    local s = self:selSlot()
    if s then sendClientCommand(getPlayer(), "Akacamp", "admin_warp", {slotId=s.id}) end
end
function AkacampPanel:selSlot()
    local lb = self.listReg
    local sel = lb and lb.selected
    if not sel or sel < 1 or not lb.items[sel] then return nil end
    return lb.items[sel].item
end
function AkacampPanel:onClearReg()
    local s = self:selSlot()
    if s then sendClientCommand(getPlayer(), "Akacamp", "admin_remove", {slotId=s.id}) end
end
function AkacampPanel:onDeleteSlot()
    local s = self:selSlot()
    if s then sendClientCommand(getPlayer(), "Akacamp", "admin_delete", {slotId=s.id}) end
end

----------------------------------------------------------------- TAB: Build
function AkacampPanel:buildBuild()
    local x, y, iw = PAD, self.bodyY, W - PAD*2
    self:label("Build", "BUILD TENT (at your position)", x, y, UIFont.Medium); y = y + 26
    self:label("Build", "Stand where you want it, then pick a size.", x, y); y = y + 24
    local bw = (iw - 6) / 2; local bh = 40
    local order = Akacamp.SIZES
    for i, sz in ipairs(order) do
        local col = (i-1) % 2; local row = math.floor((i-1)/2)
        self:button("Build", "Build "..sz, x+col*(bw+6), y+row*(bh+8), bw, bh,
            function() sendClientCommand(getPlayer(), "Akacamp", "admin_pump", {size=sz}) end)
    end
end

----------------------------------------------------------------- TAB: Give
function AkacampPanel:buildGive()
    local x, y, iw = PAD, self.bodyY, W - PAD*2
    self:label("Give", "GIVE TENT KIT (to yourself)", x, y, UIFont.Medium); y = y + 26
    local bw = (iw - 6) / 2; local bh = 40
    for i, sz in ipairs(Akacamp.SIZES) do
        local col = (i-1) % 2; local row = math.floor((i-1)/2)
        self:button("Give", "Give "..sz.." kit", x+col*(bw+6), y+row*(bh+8), bw, bh,
            function() sendClientCommand(getPlayer(), "Akacamp", "admin_giveKit", {size=sz}) end)
    end
end

----------------------------------------------------------------- shared ingredient editor (Recipe / Toll)
function AkacampPanel:ingredientTab(tab, titleText, getSize, setSize, getStore, cmd)
    local x, y, iw = PAD, self.bodyY, W - PAD*2
    self:label(tab, titleText, x, y, UIFont.Medium); y = y + 26
    self:label(tab, "Size:", x, y); 
    local lblSize = self:label(tab, getSize(), x+iw-60, y)
    y = y + 20
    local btns = self:sizeSelector(tab, x, y, getSize, function(sz)
        setSize(sz); lblSize:setName(sz); self:refreshIng(tab)
    end); y = y + 28
    local lb = self:listBox(tab, x, y, iw, 150, 20, function(l, yy, item)
        local g = item.item
        local sel = (l.selected == item.index)
        if sel then l:drawRect(0, yy, l.width, l.itemheight, 0.25, c4(COL.tabOn)) end
        l:drawText((g.item or "?").."   x"..tostring(g.count or 1), 8, yy+3, c4(COL.text))
        return yy + l.itemheight
    end); y = y + 158
    local tItem  = self:textBox(tab, "Base.Money", x, y, iw*0.52, 24, false)
    local tCount = self:textBox(tab, "1", x+iw*0.52+6, y, iw*0.14, 24, true)
    self:button(tab, "Add", x+iw*0.66+12, y, iw*0.30, 24, function(s) s:onAddIng(tab) end); y = y + 30
    self:button(tab, "Remove selected", x, y, iw*0.48, 24, function(s) s:onDelIng(tab) end)
    self:button(tab, "Save "..tab:lower(), x+iw*0.52, y, iw*0.48, 24, function(s) s:onSaveIng(tab, cmd) end)
    -- stash refs
    self[tab.."_lb"]    = lb
    self[tab.."_item"]  = tItem
    self[tab.."_count"] = tCount
    self[tab.."_store"] = getStore
    self[tab.."_size"]  = getSize
end
function AkacampPanel:curList(tab)
    local size = self[tab.."_size"]()
    local store = self[tab.."_store"]()
    store[size] = store[size] or {}
    return store[size]
end
function AkacampPanel:refreshIng(tab)
    local lb = self[tab.."_lb"]; if not lb then return end
    lb:clear()
    for _, g in ipairs(self:curList(tab)) do lb:addItem(g.item, g) end
end
function AkacampPanel:onAddIng(tab)
    local id = self[tab.."_item"]:getText()
    local n  = tonumber(self[tab.."_count"]:getText()) or 1
    if id and id ~= "" then table.insert(self:curList(tab), {item=id, count=n}); self:refreshIng(tab) end
end
function AkacampPanel:onDelIng(tab)
    local lb = self[tab.."_lb"]; local sel = lb and lb.selected
    local list = self:curList(tab)
    if sel and sel >= 1 and list[sel] then table.remove(list, sel); self:refreshIng(tab) end
end
function AkacampPanel:onSaveIng(tab, cmd)
    local size = self[tab.."_size"]()
    sendClientCommand(getPlayer(), "Akacamp", cmd, { size=size, recipe=self:curList(tab), toll=self:curList(tab) })
end

function AkacampPanel:buildRecipe()
    self:ingredientTab("Recipe", "CANVAS -> ZIP RECIPE",
        function() return self.recipeSize end,
        function(s) self.recipeSize = s end,
        function() return self.cfg.recipe end,
        "admin_setRecipe")
end
function AkacampPanel:buildToll()
    self:ingredientTab("Toll", "ENTRY TOLL (charged each warp in)",
        function() return self.tollSize end,
        function(s) self.tollSize = s end,
        function() return self.cfg.toll end,
        "admin_setToll")
end

----------------------------------------------------------------- tab switching
function AkacampPanel:setTab(name)
    self.curTab = name
    for tab, ws in pairs(self.tabWidgets) do
        local show = (tab == name)
        for _, w in ipairs(ws) do w:setVisible(show) end
    end
    for tab, b in pairs(self.tabBtns) do
        b.backgroundColor = rgba(tab == name and COL.tabOn or COL.tabOff)
    end
    if name == "Recipe" or name == "Toll" then self:refreshIng(name) end
end

function AkacampPanel:prerender()
    self:drawRect(0, 0, self.width, self.height, COL.bg[4], COL.bg[1], COL.bg[2], COL.bg[3])
    ISCollapsableWindow.prerender(self)
end

----------------------------------------------------------------- refresh from server
function AkacampPanel:refreshRegistry(slots)
    if not self.listReg then return end
    self.listReg:clear()
    if slots then
        local arr = {}; for _,s in pairs(slots) do table.insert(arr, s) end
        table.sort(arr, function(a,b) return a.id < b.id end)
        for _,s in ipairs(arr) do self.listReg:addItem(tostring(s.id), s) end
    end
end

----------------------------------------------------------------- singleton
function AkacampAdmin.open()
    if AkacampAdmin.panel then AkacampAdmin.panel:removeFromUIManager(); AkacampAdmin.panel = nil end
    local p = AkacampPanel:new(getCore():getScreenWidth()/2 - PW/2, 100, PW, PH)
    p:initialise(); p.title = "Akacamp Admin"; p.resizable = false
    p:addToUIManager()
    AkacampAdmin.panel = p
end
function AkacampAdmin.onRegistry(args) if AkacampAdmin.panel then AkacampAdmin.panel:refreshRegistry(args.slots) end end
function AkacampAdmin.onConfig(args)
    local p = AkacampAdmin.panel; if not p then return end
    p.cfg.recipe = args.recipe or {}
    p.cfg.toll   = args.toll or {}
    if p.curTab == "Recipe" then p:refreshIng("Recipe") end
    if p.curTab == "Toll"   then p:refreshIng("Toll") end
end

local function staffClient(pl)
    local lvl = pl and pl.getAccessLevel and pl:getAccessLevel()
    return lvl and Akacamp.STAFF[tostring(lvl):lower()]
end
Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
    if test then return end
    local pl = getSpecificPlayer(player); if not pl then return end
    if staffClient(pl) then
        context:addOption("Akacamp Admin Panel", nil, function() AkacampAdmin.open() end)
    end
end)
print("[AKA][CL] Akacamp admin panel v3 (tabs) loaded")
