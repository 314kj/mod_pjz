--[[ ============================================================
     Kacha B42 [MP]  -  salt preset editor  by PIE

     Create / delete named presets and edit the item ids inside
     them. Presets are the ONLY way salt gets into a machine.
     Saved globally (server GlobalModData in MP) on "Save".
   ============================================================ ]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"

Kacha = Kacha or {}
KachaPreset = ISPanel:derive("KachaPreset")

local FONT = UIFont.Small
local function C(c, a) return c.r, c.g, c.b, (a or c.a or 1) end

function KachaPreset:new()
    local w, h = 420, 470
    local o = ISPanel:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2, w, h)
    setmetatable(o, self); self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = true
    o.titleH = 40
    o.cur = nil
    return o
end

function KachaPreset:createChildren()
    local W = self:getWidth()
    local pad = 14

    self.closeBtn = ISButton:new(W - 30, 8, 22, 22, "X", self, KachaPreset.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.1, b = 0.1, a = 0.6 }
    self:addChild(self.closeBtn)

    -- preset select + new + delete
    local ty = self.titleH + 26
    self.presetBox = ISComboBox:new(pad, ty, 150, 26, self, KachaPreset.onPick); self.presetBox:initialise()
    self:addChild(self.presetBox)
    self.delBtn = ISButton:new(pad + 156, ty, 70, 26, "Delete", self, KachaPreset.onDeletePreset)
    self.delBtn:initialise(); self.delBtn.backgroundColor = { r = 0.45, g = 0.15, b = 0.15, a = 0.8 }
    self:addChild(self.delBtn)

    local ny = ty + 36
    self.nameEntry = ISTextEntryBox:new("", pad, ny, 226, 26); self.nameEntry:initialise(); self.nameEntry:instantiate()
    self:addChild(self.nameEntry)
    self.newBtn = ISButton:new(pad + 232, ny, W - pad - (pad + 232), 26, "New preset", self, KachaPreset.onNewPreset)
    self.newBtn:initialise(); self.newBtn.backgroundColor = { r = 0.20, g = 0.45, b = 0.25, a = 0.8 }
    self:addChild(self.newBtn)

    -- add item id to current preset
    local ay = ny + 46
    self.idEntry = ISTextEntryBox:new("Base.", pad, ay, 226, 26); self.idEntry:initialise(); self.idEntry:instantiate()
    self:addChild(self.idEntry)
    self.addBtn = ISButton:new(pad + 232, ay, W - pad - (pad + 232), 26, "Add item", self, KachaPreset.onAddItem)
    self.addBtn:initialise(); self.addBtn.backgroundColor = { r = 0.20, g = 0.45, b = 0.25, a = 0.8 }
    self:addChild(self.addBtn)

    -- item list + remove
    local ly = ay + 40
    self.list = ISScrollingListBox:new(pad, ly, W - pad * 2, 180)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = 28; self.list.font = FONT; self.list.drawBorder = true
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0.25 }
    self.list.doDrawItem = KachaPreset.drawItem
    self:addChild(self.list)
    self.rmBtn = ISButton:new(pad, ly + 184, 150, 26, "Remove item", self, KachaPreset.onRemoveItem)
    self.rmBtn:initialise(); self.rmBtn.backgroundColor = { r = 0.45, g = 0.15, b = 0.15, a = 0.8 }
    self:addChild(self.rmBtn)

    -- save / close
    self.saveBtn = ISButton:new(W - pad - 150, ly + 184, 150, 26, "Save & Close", self, KachaPreset.onSave)
    self.saveBtn:initialise(); self.saveBtn.backgroundColor = { r = 0.20, g = 0.40, b = 0.75, a = 0.9 }
    self:addChild(self.saveBtn)

    self:populate()
end

function KachaPreset:populate()
    local names = Kacha.presetNames()
    self.presetBox:clear()
    for _, n in ipairs(names) do self.presetBox:addOption(n) end
    -- keep current selection if still present, else first
    local sel = 1
    for i, n in ipairs(names) do if n == self.cur then sel = i end end
    if #names > 0 then
        self.presetBox.selected = sel
        self.cur = names[sel]
    else
        self.cur = nil
    end
    self:refreshItems()
end

function KachaPreset:refreshItems()
    self.list:clear()
    if not self.cur then return end
    local ids = Kacha.presetItems(self.cur)
    if not ids then return end
    for i, id in ipairs(ids) do
        self.list:addItem(id, { idx = i, id = id, name = Kacha.displayName(id), ok = Kacha.itemExists(id) })
    end
end

function KachaPreset:onPick()
    local n = self.presetBox:getOptionText(self.presetBox.selected)
    self.cur = n; self:refreshItems()
end

function KachaPreset:onNewPreset()
    local name = string.trim(self.nameEntry:getText() or "")
    if name == "" then return end
    if Kacha.presetCreate(name) then self.cur = name:gsub("%s+", "_"); self.nameEntry:setText(""); self:populate() end
end

function KachaPreset:onDeletePreset()
    if not self.cur then return end
    Kacha.presetDelete(self.cur); self.cur = nil; self:populate()
end

function KachaPreset:onAddItem()
    if not self.cur then self.warn = "Pick or create a preset first"; self.warnT = 180; return end
    local id = string.trim(self.idEntry:getText() or "")
    if id == "" or id == "Base." then self.idEntry:setText("Base."); return end
    if not Kacha.itemExists(id) then self.warn = "Unknown item: " .. id; self.warnT = 180; return end
    Kacha.presetAddItem(self.cur, id)
    self.idEntry:setText("Base."); self:refreshItems()
end

function KachaPreset:onRemoveItem()
    if not self.cur then return end
    local sel = self.list.selected
    if sel and self.list.items[sel] then Kacha.presetRemoveItemAt(self.cur, self.list.items[sel].item.idx); self:refreshItems() end
end

function KachaPreset:onSave()
    Kacha.persistPresets()
    if Kacha.onPresetsChanged then pcall(Kacha.onPresetsChanged) end
    self:onClose()
end

function KachaPreset:onClose() self:removeFromUIManager(); KachaPreset.instance = nil end

function KachaPreset:drawItem(y, item, alt)
    local d = item.item; if not d then return y + self.itemheight end
    local h = self.itemheight
    if item.index and self.selected == item.index then self:drawRect(0, y, self:getWidth(), h - 1, 0.30, C(Kacha.COL.accent)) end
    local tc = Kacha.tierColor("Salt")
    self:drawRect(6, y + 4, 36, h - 8, 0.92, tc.r, tc.g, tc.b)
    self:drawTextCentre("Salt", 24, y + 6, 1, 1, 1, 1, UIFont.Small)
    self:drawText(d.name or d.id, 50, y + 1, Kacha.COL.text.r, Kacha.COL.text.g, Kacha.COL.text.b, Kacha.COL.text.a, UIFont.Small)
    local idc = d.ok and Kacha.COL.sub or Kacha.COL.bad
    self:drawText(d.id .. (d.ok and "" or "  (not found)"), 50, y + 13, idc.r, idc.g, idc.b, 1, UIFont.Small)
    return y + h
end

function KachaPreset:update()
    ISPanel.update(self)
    if self.warnT and self.warnT > 0 then self.warnT = self.warnT - 1 end
end

function KachaPreset:prerender()
    local W, H = self:getWidth(), self:getHeight()
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, Kacha.COL.accent.a, Kacha.COL.accent.r, Kacha.COL.accent.g, Kacha.COL.accent.b)
    self:drawRect(0, 0, W, self.titleH, Kacha.COL.red.a, Kacha.COL.red.r, Kacha.COL.red.g, Kacha.COL.red.b)
    self:drawText("Salt Preset Editor", 14, 10, Kacha.COL.text.r, Kacha.COL.text.g, Kacha.COL.text.b, Kacha.COL.text.a, UIFont.Medium)
    local acc = Kacha.COL.accent
    self:drawText("Preset", 14, self.titleH + 8, acc.r, acc.g, acc.b, acc.a, UIFont.Small)
    self:drawText("Items in preset  ( equal weight )", 14, self.list:getY() - 18, acc.r, acc.g, acc.b, acc.a, UIFont.Small)
    if self.warnT and self.warnT > 0 and self.warn then
        self:drawTextCentre(self.warn, W / 2, self.titleH + 6, Kacha.COL.bad.r, Kacha.COL.bad.g, Kacha.COL.bad.b, 1, UIFont.Small)
    end
end

function Kacha.openPresetEditor()
    if KachaPreset.instance then KachaPreset.instance:onClose() end
    local p = KachaPreset:new()
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaPreset.instance = p
end

Kacha.__mark("preset")
