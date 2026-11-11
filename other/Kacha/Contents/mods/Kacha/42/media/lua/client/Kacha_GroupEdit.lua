--[[ ============================================================
     Kacha B42 [MP]  -  Group item editor (admin)  by PIE
     Double-click a prize group -> tick items -> Delete selected.
     English UI only.                                 BUILD=gedit-A
   ============================================================ ]]
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"

Kacha = Kacha or {}
KachaGroupEdit = ISPanel:derive("KachaGroupEdit")

function KachaGroupEdit:new(obj, ei)
    local w, h = 340, 420
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.obj = obj; o.ei = ei; o.titleH = 36; o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.sel = {}   -- ii -> true
    return o
end

function KachaGroupEdit:createChildren()
    local W, H = self:getWidth(), self:getHeight()
    self.closeBtn = ISButton:new(W - 28, 8, 20, 20, "X", self, KachaGroupEdit.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.7 }
    self:addChild(self.closeBtn)

    self.list = ISScrollingListBox:new(12, self.titleH + 8, W - 24, H - self.titleH - 56)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = 40; self.list.drawBorder = true
    self.list.doDrawItem = KachaGroupEdit.drawRow
    local this = self
    self.list.onmousedown = function() this:onRowClick() end
    self:addChild(self.list)

    self.delBtn = ISButton:new(12, H - 40, 180, 30, "Delete selected (0)", self, KachaGroupEdit.onDelete)
    self.delBtn:initialise(); self.delBtn.backgroundColor = { r = 0.5, g = 0.16, b = 0.16, a = 0.95 }
    self:addChild(self.delBtn)
    self.doneBtn = ISButton:new(W - 12 - 100, H - 40, 100, 30, "Done", self, KachaGroupEdit.onClose)
    self.doneBtn:initialise(); self.doneBtn.backgroundColor = { r = 0.16, g = 0.30, b = 0.55, a = 0.9 }
    self:addChild(self.doneBtn)

    self:refresh()
end

function KachaGroupEdit:refresh()
    self.list:clear()
    local d = Kacha.getConfig(self.obj)
    local e = d.entries and d.entries[self.ei]
    if not e then self:onClose(); return end
    self.tier = e.tier; self.rate = e.rate
    for ii, id in ipairs(e.ids or {}) do
        self.list:addItem(id, { ii = ii, id = id, name = Kacha.displayName(id), tex = Kacha.itemTexture(id) })
    end
    self:updateDelLabel()
end

function KachaGroupEdit:updateDelLabel()
    local n = 0; for _ in pairs(self.sel) do n = n + 1 end
    if self.delBtn then self.delBtn:setTitle("Delete selected (" .. n .. ")") end
end

function KachaGroupEdit:onRowClick()
    local rowIdx = self.list.selected
    local row = rowIdx and self.list.items[rowIdx] and self.list.items[rowIdx].item
    if row then
        if self.sel[row.ii] then self.sel[row.ii] = nil else self.sel[row.ii] = true end
        self:updateDelLabel()
    end
end

function KachaGroupEdit:drawRow(y, item, alt)
    -- self here is the LIST (doDrawItem is a list method)
    local d = item.item; if not d then return y + self.itemheight end
    local h = self.itemheight
    local parent = self.parent
    local on = parent and parent.sel and parent.sel[d.ii]
    -- checkbox
    self:drawRect(10, y + 11, 18, 18, 1, 0.06, 0.09, 0.15)
    if on then self:drawRect(12, y + 13, 14, 14, 1, 0.22, 0.74, 0.98) end
    self:drawRectBorder(10, y + 11, 18, 18, 1, 0.5, 0.56, 0.66)
    -- icon
    if d.tex then self:drawTextureScaled(d.tex, 34, y + 5, 30, 30, 1, 1, 1, 1) end
    self:drawText(d.name or d.id, 72, y + 4, 0.94, 0.94, 0.96, 1, UIFont.Small)
    self:drawText(d.id, 72, y + 19, 0.6, 0.62, 0.7, 1, UIFont.Small)
    return y + h
end

function KachaGroupEdit:onDelete()
    local iis = {}
    for ii in pairs(self.sel) do iis[#iis + 1] = ii end
    if #iis == 0 then return end
    Kacha.removeItemsFromGroup(self.obj, self.ei, iis)
    self.sel = {}
    if KachaAdmin.instance then KachaAdmin.instance:refresh() end
    -- entry may have collapsed; if gone, close
    local d = Kacha.getConfig(self.obj)
    if not (d.entries and d.entries[self.ei]) then self:onClose() else self:refresh() end
end

function KachaGroupEdit:onClose()
    if KachaAdmin.instance then KachaAdmin.instance:refresh() end
    self:removeFromUIManager(); KachaGroupEdit.instance = nil
end

function KachaGroupEdit:prerender()
    local W, H = self:getWidth(), self:getHeight()
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, Kacha.COL.accent.a, Kacha.COL.accent.r, Kacha.COL.accent.g, Kacha.COL.accent.b)
    self:drawRect(0, 0, W, self.titleH, Kacha.COL.red.a, Kacha.COL.red.r, Kacha.COL.red.g, Kacha.COL.red.b)
    self:drawText("Edit group  " .. tostring(self.rate or "?") .. "%  " .. tostring(self.tier or ""), 12, 9,
        1, 1, 1, 1, UIFont.Medium)
end

function Kacha.openGroupEdit(obj, ei)
    if KachaGroupEdit.instance then KachaGroupEdit.instance:removeFromUIManager() end
    local p = KachaGroupEdit:new(obj, ei)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaGroupEdit.instance = p
end

Kacha.__mark("gedit")
