--[[ ============================================================
     Kacha B42 [MP]  -  searchable item picker (icon + name)  by PIE
     Type to filter, shows icon + display name, click to pick.
     Style follows the Kaandther/Traka picker.        BUILD=picker-A
   ============================================================ ]]
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"

Kacha = Kacha or {}
KachaItemPicker = ISPanel:derive("KachaItemPicker")

local CACHE = nil   -- { {ft, name, icon(Texture)} , ... } built once
local function buildCache()
    if CACHE then return CACHE end
    CACHE = {}
    local ok = pcall(function()
        local all = getScriptManager():getAllItems()
        for i = 0, all:size() - 1 do
            local it = all:get(i)
            local mod = it:getModuleName() or "Base"
            local nm  = it:getName()
            if nm and not string.find(nm, "KachaFX") then
                local ft = mod .. "." .. nm
                local tex = nil
                pcall(function() tex = it:getNormalTexture() end)
                if not tex then pcall(function() tex = getTexture("Item_" .. (it:getIcon() or "")) end) end
                CACHE[#CACHE + 1] = { ft = ft, name = it:getDisplayName() or nm, low = (it:getDisplayName() or nm):lower(), ftlow = ft:lower(), icon = tex }
            end
        end
    end)
    if not ok then CACHE = {} end
    return CACHE
end

function KachaItemPicker:new(onPick, player)
    local w, h = 380, 460
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.onPick = onPick; o.player = player; o.titleH = 36; o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

function KachaItemPicker:createChildren()
    local W = self:getWidth()
    self.closeBtn = ISButton:new(W - 28, 8, 20, 20, "X", self, KachaItemPicker.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.7 }
    self:addChild(self.closeBtn)

    self.search = ISTextEntryBox:new("", 12, self.titleH + 8, W - 24, 26)
    self.search:initialise(); self.search:instantiate()
    self.search.onTextChange = function() self:applyFilter() end
    self:addChild(self.search)

    self.list = ISScrollingListBox:new(12, self.titleH + 42, W - 24, self:getHeight() - self.titleH - 88)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = 34; self.list.drawBorder = true
    self.list.doDrawItem = KachaItemPicker.drawRow
    self:addChild(self.list)

    local by = self:getHeight() - 40
    self.heldBtn = ISButton:new(12, by, 130, 28, "Held item", self, KachaItemPicker.onHeld)
    self.heldBtn:initialise(); self:addChild(self.heldBtn)
    self.selBtn = ISButton:new(W - 12 - 90, by, 90, 28, "Select", self, KachaItemPicker.onSelect)
    self.selBtn:initialise(); self.selBtn.backgroundColor = { r = 0.18, g = 0.45, b = 0.40, a = 0.95 }; self:addChild(self.selBtn)

    self:applyFilter()
end

function KachaItemPicker:applyFilter()
    local q = (self.search:getText() or ""):lower()
    local rows = buildCache()
    self.list:clear()
    local shown = 0
    for _, r in ipairs(rows) do
        if q == "" or string.find(r.low, q, 1, true) or string.find(r.ftlow, q, 1, true) then
            self.list:addItem(r.name, r)
            shown = shown + 1
            if shown >= 300 then break end
        end
    end
end

function KachaItemPicker:drawRow(y, item, alt)
    local r = item.item; if not r then return y + self.itemheight end
    local h = self.itemheight
    if item.index and self.selected == item.index then self:drawRect(0, y, self:getWidth(), h - 1, 0.35, 0.2, 0.42, 0.55) end
    if r.icon then self:drawTextureScaled(r.icon, 6, y + 3, 26, 26, 1, 1, 1, 1) end
    self:drawText(r.name, 40, y + 3, 0.94, 0.94, 0.96, 1, UIFont.Small)
    self:drawText(r.ft, 40, y + 17, 0.62, 0.62, 0.68, 1, UIFont.Small)
    return y + h
end

function KachaItemPicker:pick(ft)
    if ft and self.onPick then self.onPick(ft) end
    self:onClose()
end
function KachaItemPicker:onSelect()
    local sel = self.list.selected
    local row = sel and self.list.items[sel] and self.list.items[sel].item
    if row then self:pick(row.ft) end
end
function KachaItemPicker:onHeld()
    local pl = self.player
    local it = pl and pl.getPrimaryHandItem and pl:getPrimaryHandItem()
    if it and it.getFullType then self:pick(it:getFullType()) end
end
function KachaItemPicker:onClose() self:removeFromUIManager(); KachaItemPicker.instance = nil end

function KachaItemPicker:prerender()
    local W, H = self:getWidth(), self:getHeight()
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, Kacha.COL.accent.a, Kacha.COL.accent.r, Kacha.COL.accent.g, Kacha.COL.accent.b)
    self:drawRect(0, 0, W, self.titleH, Kacha.COL.red.a, Kacha.COL.red.r, Kacha.COL.red.g, Kacha.COL.red.b)
    self:drawText("Pick an item (search)", 12, 9, Kacha.COL.text.r, Kacha.COL.text.g, Kacha.COL.text.b, 1, UIFont.Medium)
end

function Kacha.openItemPicker(onPick, player)
    if KachaItemPicker.instance then KachaItemPicker.instance:onClose() end
    local p = KachaItemPicker:new(onPick, player)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaItemPicker.instance = p
    return p
end

Kacha.__mark("picker")
