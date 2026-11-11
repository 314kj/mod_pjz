--[[ ============================================================
  PROJECT DUNKA [MP] -- Item Picker (search + scroll + icons)  KACHASIG
  Type in the search box to filter; scroll the list; click a row to
  pick. onPick(fullType). Used by DunKa Config to add slip loot.
============================================================ ]]--

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"

DunKaItemPicker = ISPanel:derive("DunKaItemPicker")

local W, H  = 470, 570
local ROWH  = 40
local CAP   = 500
local SBX, SBY, SBH = 12, 38, 30    -- search box rect

local ALL
local function buildAll()
    if ALL then return ALL end
    ALL = {}
    local sm = getScriptManager()
    local items = sm and sm:getAllItems()
    if items then
        for i=0, items:size()-1 do
            local it = items:get(i)
            local ft
            pcall(function() ft = it:getFullName() end)
            if ft then
                local disp = ft
                pcall(function() disp = it:getDisplayName() or ft end)
                ALL[#ALL+1] = { ft=ft, name=disp, item=it, key=(disp.." "..ft):lower() }
            end
        end
    end
    table.sort(ALL, function(a,b) return a.name < b.name end)
    return ALL
end

local function boxText(box)
    if not box then return "" end
    local t
    pcall(function() t = box.getInternalText and box:getInternalText() end)
    if t == nil then pcall(function() t = box.getText and box:getText() end) end
    return t or ""
end

-- robust icon getter (script items expose the icon differently across builds)
local function itemTex(it)
    local t
    pcall(function() t = it.getNormalTexture and it:getNormalTexture() end)
    if t then return t end
    pcall(function() t = it.getTex and it:getTex() end)
    if t then return t end
    local ic
    pcall(function() ic = it.getIcon and it:getIcon() end)
    if ic and ic ~= "" then
        for _, nm in ipairs({ "Item_"..ic, "media/textures/Item_"..ic..".png", "media/inventory/Item_"..ic..".png", ic }) do
            pcall(function() if not t then t = getTexture(nm) end end)
            if t then return t end
        end
    end
    return nil
end
local texCache = {}
local function ftTex(item, ft)
    if texCache[ft] ~= nil then return texCache[ft] or nil end
    local t = item and itemTex(item)
    texCache[ft] = t or false
    return t
end

function DunKaItemPicker.openFor(onPick)
    if DunKaItemPicker.instance then pcall(function() DunKaItemPicker.instance:close() end) end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = DunKaItemPicker:new((sw-W)/2, (sh-H)/2)
    o.onPick = onPick
    o:initialise(); o:instantiate(); o:addToUIManager()
    DunKaItemPicker.instance = o
    return o
end

function DunKaItemPicker:new(x, y)
    local o = ISPanel.new(self, x, y, W, H)
    o:noBackground()
    o.moveWithMouse = false          -- so clicks focus the search box instead of dragging
    o.scroll = 0
    o.filtered = {}
    o.lastSearch = "\0"
    return o
end

function DunKaItemPicker:createChildren()
    self.search = ISTextEntryBox:new("", SBX+4, SBY+3, W-SBX*2-8, SBH-6)
    self.search:initialise(); self.search:instantiate()
    self.search.font = UIFont.Medium
    self:addChild(self.search)
    if JoypadState and self.search.setSelectable then self.search:setSelectable(true) end
    self:refilter("")
end

function DunKaItemPicker:refilter(q)
    q = (q or ""):lower()
    local all = buildAll()
    local out = {}
    if q == "" then
        for i=1, math.min(#all, CAP) do out[i] = all[i] end
    else
        for _, e in ipairs(all) do
            if e.key:find(q, 1, true) then out[#out+1] = e; if #out >= CAP then break end end
        end
    end
    self.filtered = out
    self.scroll = 0
    self.lastSearch = q
end

function DunKaItemPicker:listRect() return 12, 78, W-24, H-90 end
function DunKaItemPicker:maxVis() local _,_,_,lh = self:listRect(); return math.floor(lh/ROWH) end

function DunKaItemPicker:close()
    DunKaItemPicker.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end

function DunKaItemPicker:prerender()
    ISPanel.prerender(self)
    local t = boxText(self.search)
    if t:lower() ~= self.lastSearch then self:refilter(t) end
end

function DunKaItemPicker:render()
    self:drawRect(0,0,W,H, 0.97, 0.07,0.07,0.08)
    self:drawRectBorder(0,0,W,H, 1, 0.55,0.42,0.2)
    self:drawRect(0,0,W,30, 1, 0.13,0.11,0.09)
    self:drawText("Pick an item", 12, 7, 0.95,0.85,0.5, 1, UIFont.Medium)
    self:drawText("X", W-22, 6, 0.9,0.7,0.7, 1, UIFont.Medium)

    -- search field frame (the ISTextEntryBox child renders on top)
    self:drawRect(SBX, SBY, W-SBX*2, SBH, 1, 0.14,0.14,0.16)
    self:drawRectBorder(SBX, SBY, W-SBX*2, SBH, 1, 0.5,0.42,0.25)
    if boxText(self.search) == "" then
        self:drawText("type to search...", SBX+10, SBY+7, 0.45,0.45,0.42, 1, UIFont.Small)
    end

    local lx, ly, lw, lh = self:listRect()
    self:drawRect(lx, ly, lw, lh, 1, 0.04,0.04,0.05)
    local n = #self.filtered
    local maxv = self:maxVis()
    local start = math.floor(self.scroll) + 1
    for k = 0, maxv-1 do
        local idx = start + k
        local e = self.filtered[idx]
        if e then
            local ry = ly + k*ROWH
            self:drawRectBorder(lx, ry, lw, ROWH, 0.3, 0.3,0.25,0.15)
            local tex = ftTex(e.item, e.ft)
            if tex then self:drawTextureScaled(tex, lx+5, ry+4, 32, 32, 1, 1,1,1)
            else self:drawRectBorder(lx+5, ry+4, 32, 32, 0.4, 0.4,0.35,0.25) end
            self:drawText(e.name, lx+46, ry+4,  0.92,0.92,0.85, 1, UIFont.Medium)
            self:drawText(e.ft,   lx+46, ry+23, 0.5,0.5,0.47,   1, UIFont.Small)
        end
    end
    if n > maxv then
        self:drawText(start.."-"..math.min(start+maxv-1, n).." / "..n, lx+lw-140, ly-16, 0.6,0.6,0.55, 1, UIFont.Small)
    elseif n == 0 then
        self:drawText("no matches", lx+10, ly+10, 0.6,0.6,0.6, 1, UIFont.Medium)
    end
end

function DunKaItemPicker:onMouseWheel(del)
    local maxv = self:maxVis()
    self.scroll = math.max(0, math.min(self.scroll + del*2, math.max(0, #self.filtered - maxv)))
    return true
end

function DunKaItemPicker:idxAt(x, y)
    local lx, ly, lw, lh = self:listRect()
    if x < lx or x > lx+lw or y < ly or y > ly+lh then return nil end
    return math.floor(self.scroll) + 1 + math.floor((y-ly)/ROWH)
end

function DunKaItemPicker:onMouseDown(x, y)
    if x >= W-24 and y <= 28 then self:close(); return true end
    local idx = self:idxAt(x, y)
    local e = idx and self.filtered[idx]
    if e then
        if self.onPick then pcall(function() self.onPick(e.ft) end) end
        self:close()
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end
function DunKaItemPicker:onRightMouseDown(x, y) self:close(); return true end

print("[DunKa] ItemPicker loaded")
