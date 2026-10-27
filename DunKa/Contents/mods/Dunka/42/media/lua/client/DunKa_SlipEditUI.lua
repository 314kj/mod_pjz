--[[ ============================================================
  PROJECT DUNKA [MP] -- Slip Rewards Editor (admin)   KACHASIG
  Right-click box (admin) -> "Edit Slip Rewards".
  Pick a colour tab, add the item in your hand, tune qty/weight,
  set rolls, Save. Saved to server ModData -> changeable anytime.
  openSlip gives items server-side (no ghosts).
============================================================ ]]--

require "ISUI/ISPanel"

DunKaSlipEditUI = ISPanel:derive("DunKaSlipEditUI")

local W, H     = 580, 560
local COLORS   = { "White", "Yellow", "Blue" }
local ROWH     = 34
local LIST_Y   = 120
local MAXROWS  = 9

local function hit(x,y, rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end

function DunKaSlipEditUI:initialise() ISPanel.initialise(self) end

function DunKaSlipEditUI.openFor(cfg)
    if DunKaSlipEditUI.instance then pcall(function() DunKaSlipEditUI.instance:close() end) end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = DunKaSlipEditUI:new((sw-W)/2, (sh-H)/2, cfg)
    o:initialise(); o:addToUIManager()
    DunKaSlipEditUI.instance = o
    return o
end

function DunKaSlipEditUI:new(x, y, cfg)
    local o = ISPanel.new(self, x, y, W, H)
    o:noBackground(); o.moveWithMouse = true
    o.cfg = cfg or {}
    o.color = "White"
    for _, c in ipairs(COLORS) do
        o.cfg[c] = o.cfg[c] or { rolls = 1, loot = {} }
        o.cfg[c].loot = o.cfg[c].loot or {}
    end
    return o
end

function DunKaSlipEditUI:close()
    DunKaSlipEditUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end
function DunKaSlipEditUI:onRightMouseDown(x,y) self:close(); return true end

-- draw a button box (hit-tested separately in onMouseDown by same coords)
function DunKaSlipEditUI:btn(label, x, y, w, h, primary)
    self:drawRect(x, y, w, h, 0.9, primary and 0.14 or 0.20, primary and 0.30 or 0.16, primary and 0.12 or 0.10)
    self:drawRectBorder(x, y, w, h, 0.9, 0.55, 0.45, 0.25)
    self:drawTextCentre(label, x + w/2, y + h/2 - 8, 0.95, 0.9, 0.75, 1, UIFont.Small)
end

function DunKaSlipEditUI:render()
    self:drawRect(0, 0, W, H, 0.96, 0.07, 0.07, 0.08)
    self:drawRectBorder(0, 0, W, H, 1, 0.55, 0.42, 0.2)
    self:drawRect(0, 0, W, 30, 1, 0.13, 0.11, 0.09)
    self:drawText("Slip Rewards Editor  (admin)", 14, 7, 0.95, 0.85, 0.5, 1, UIFont.Medium)
    self:drawText("X", W-22, 6, 0.9, 0.7, 0.7, 1, UIFont.Medium)

    -- colour tabs
    local tw = (W-40)/3
    for i, c in ipairs(COLORS) do
        local tx = 20 + (i-1)*tw
        local sel = (self.color == c)
        self:drawRect(tx, 40, tw-6, 30, 1, sel and 0.32 or 0.15, sel and 0.26 or 0.13, sel and 0.10 or 0.10)
        self:drawRectBorder(tx, 40, tw-6, 30, 1, 0.5, 0.4, 0.2)
        self:drawTextCentre(c, tx + (tw-6)/2, 47, sel and 1 or 0.7, sel and 0.9 or 0.7, sel and 0.5 or 0.6, 1, UIFont.Small)
    end

    local cc = self.cfg[self.color]
    -- rolls control
    self:drawText("Rolls per open:", 20, 84, 0.85, 0.85, 0.8, 1, UIFont.Small)
    self:btn("-", 168, 82, 24, 22)
    self:drawTextCentre(tostring(cc.rolls or 1), 208, 84, 1, 0.9, 0.5, 1, UIFont.Medium)
    self:btn("+", 224, 82, 24, 22)

    -- column headers
    self:drawText("Item", 24, LIST_Y-16, 0.6, 0.6, 0.55, 1, UIFont.Small)
    self:drawText("Qty", 302, LIST_Y-16, 0.6, 0.6, 0.55, 1, UIFont.Small)
    self:drawText("Weight", 420, LIST_Y-16, 0.6, 0.6, 0.55, 1, UIFont.Small)
    self:drawRect(14, LIST_Y-2, W-28, 1, 0.5, 0.5, 0.4, 0.25)

    local loot = cc.loot
    if #loot == 0 then
        self:drawText("No rewards yet. Hold an item, then 'Add item in hand'.", 24, LIST_Y+6, 0.7, 0.7, 0.7, 1, UIFont.Small)
    end
    for i = 1, math.min(#loot, MAXROWS) do
        local e = loot[i]
        local y = LIST_Y + (i-1)*ROWH
        self:drawText((tostring(e.item):gsub("^.*%.", "")), 24, y+6, 0.9, 0.9, 0.85, 1, UIFont.Small)
        -- qty
        self:btn("-", 290, y+3, 22, 22)
        self:drawTextCentre(tostring(e.min or 1), 328, y+6, 1, 0.9, 0.6, 1, UIFont.Small)
        self:btn("+", 344, y+3, 22, 22)
        -- weight
        self:btn("-", 410, y+3, 22, 22)
        self:drawTextCentre(tostring(e.weight or 10), 450, y+6, 0.7, 0.9, 1, 1, UIFont.Small)
        self:btn("+", 466, y+3, 22, 22)
        -- remove
        self:btn("X", 520, y+3, 26, 22)
    end
    if #loot > MAXROWS then
        self:drawText("(" .. (#loot - MAXROWS) .. " more - remove some to see them)", 24, LIST_Y + MAXROWS*ROWH + 4, 0.6, 0.6, 0.6, 1, UIFont.Small)
    end

    self:btn("Browse items...", 20, H-42, 200, 30)
    self:btn("Save " .. self.color, 380, H-42, 180, 30, true)
end

function DunKaSlipEditUI:onMouseDown(x, y)
    if hit(x, y, W-24, 4, 24, 24) then self:close(); return true end
    local tw = (W-40)/3
    for i, c in ipairs(COLORS) do
        if hit(x, y, 20 + (i-1)*tw, 40, tw-6, 30) then self.color = c; return true end
    end
    local cc = self.cfg[self.color]
    if hit(x, y, 168, 82, 24, 22) then cc.rolls = math.max(1, (cc.rolls or 1) - 1); return true end
    if hit(x, y, 224, 82, 24, 22) then cc.rolls = math.min(10, (cc.rolls or 1) + 1); return true end
    local loot = cc.loot
    for i = 1, math.min(#loot, MAXROWS) do
        local e = loot[i]; local ry = LIST_Y + (i-1)*ROWH
        if hit(x, y, 290, ry+3, 22, 22) then e.min = math.max(1, (e.min or 1) - 1); e.max = e.min; return true end
        if hit(x, y, 344, ry+3, 22, 22) then e.min = math.min(99, (e.min or 1) + 1); e.max = e.min; return true end
        if hit(x, y, 410, ry+3, 22, 22) then e.weight = math.max(1, (e.weight or 10) - 5); return true end
        if hit(x, y, 466, ry+3, 22, 22) then e.weight = math.min(999, (e.weight or 10) + 5); return true end
        if hit(x, y, 520, ry+3, 26, 22) then table.remove(loot, i); return true end
    end
    if hit(x, y, 20, H-42, 200, 30) then
        local me = self
        DunKaItemPicker.openFor(function(ft)
            for _, e in ipairs(me.cfg[me.color].loot) do if e.item == ft then return end end
            table.insert(me.cfg[me.color].loot, { item = ft, min = 1, max = 1, weight = 10 })
        end)
        return true
    end
    if hit(x, y, 380, H-42, 180, 30) then self:save(); return true end
    return ISPanel.onMouseDown(self, x, y)
end

function DunKaSlipEditUI:addHeld()
    local pl = getPlayer(); if not pl then return end
    local item = pl:getPrimaryHandItem() or pl:getSecondaryHandItem()
    if not item then DunKa.notify(pl, "Hold an item in your hand first"); return end
    local ft = item:getFullType()
    for _, e in ipairs(self.cfg[self.color].loot) do
        if e.item == ft then DunKa.notify(pl, "Already in the list"); return end
    end
    table.insert(self.cfg[self.color].loot, { item = ft, min = 1, max = 1, weight = 10 })
end

function DunKaSlipEditUI:save()
    local pl = getPlayer()
    local cc = self.cfg[self.color]
    local loot = {}
    for _, e in ipairs(cc.loot) do
        loot[#loot+1] = { item = e.item, min = e.min or 1, max = e.max or e.min or 1, weight = e.weight or 10 }
    end
    if DunKa.isSP() then
        DunKa.setSlipColor(self.color, cc.rolls, loot)
    else
        sendClientCommand(pl, "DunKa", "setSlipCfg", { color = self.color, rolls = cc.rolls, loot = loot })
    end
    if pl then pl:setHaloNote(self.color .. " slip rewards saved", 150, 230, 150, 250) end
end

print("[DunKa] SlipEditUI loaded")
