--[[ ============================================================
     Kacha B42 [MP]  -  Admin Setting panel (group-centric)  by PIE
     Flow: bind coin -> set cost -> make prize groups (set %) ->
           drop items into a group (they split that % evenly).
           Leftover to 100% becomes salt automatically.
     English UI only (PZ fonts box out Thai).            BUILD=admin-G
   ============================================================ ]]
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"

Kacha = Kacha or {}
KachaAdmin = ISPanel:derive("KachaAdmin")

local PAD = 16

function KachaAdmin:new(obj)
    local w, h = 560, 588
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.obj = obj; o.titleH = 40; o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end


function KachaAdmin:createChildren()
    local W = self:getWidth()
    local d = Kacha.getConfig(self.obj)

    self.closeBtn = ISButton:new(W - 30, 9, 22, 22, "X", self, KachaAdmin.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.7 }
    self:addChild(self.closeBtn)

    -- machine name (shown to players on the spin window)
    self.nameEntry = ISTextEntryBox:new(d.name or "", 150, 8, 190, 24)
    self.nameEntry:initialise(); self.nameEntry:instantiate(); self:addChild(self.nameEntry)
    self.lastName = d.name or ""

    -- ROW 1: coin + cost -------------------------------------------------
    local y1 = self.titleH + 30
    self.coinBox = ISComboBox:new(PAD, y1, 180, 28, self, KachaAdmin.onCoinPick); self.coinBox:initialise()
    for _, c in ipairs(Kacha.COINS) do self.coinBox:addOption(c.label) end
    do local cur = d.tokenItem or "Base.KachaCoin"
       for i, c in ipairs(Kacha.COINS) do if c.item == cur then self.coinBox.selected = i end end end
    self:addChild(self.coinBox)

    self.costEntry = ISTextEntryBox:new(tostring(d.costPerRoll or 1), W - PAD - 60, y1, 60, 28)
    self.costEntry:initialise(); self.costEntry:instantiate(); self.costEntry:setOnlyNumbers(true)
    self:addChild(self.costEntry); self.lastCost = tostring(d.costPerRoll or 1)

    -- GROUPS list --------------------------------------------------------
    local ly = self.titleH + 118
    local lh = 196
    self.list = ISScrollingListBox:new(PAD, ly, W - PAD * 2, lh)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = 40; self.list.drawBorder = true
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0.28 }
    self.list.doDrawItem = KachaAdmin.drawGroupRow
    do
        local this = self
        self.list.onmousedown = function()
            local now = getTimestampMs()
            local i = this.list.selected
            local row = i and this.list.items[i] and this.list.items[i].item
            if this._lcRow == i and this._lcT and (now - this._lcT) < 450 then
                if row and row.ei and Kacha.openGroupEdit then Kacha.openGroupEdit(this.obj, row.ei) end
                this._lcT = nil
            else
                this._lcRow = i; this._lcT = now
            end
        end
    end
    self:addChild(self.list)

    -- CONTROLS on selected group ----------------------------------------
    local cy = ly + lh + 12
    self.addItemBtn = ISButton:new(PAD, cy, 300, 26, "+ Add item to selected group  (browse/search)", self, KachaAdmin.onAddItem)
    self.addItemBtn:initialise(); self.addItemBtn.backgroundColor = { r = 0.18, g = 0.45, b = 0.40, a = 0.95 }
    self:addChild(self.addItemBtn)
    self.rmItemBtn = ISButton:new(PAD + 310, cy, 130, 26, "Del last item", self, KachaAdmin.onDelItem)
    self.rmItemBtn:initialise(); self.rmItemBtn.backgroundColor = { r = 0.35, g = 0.2, b = 0.2, a = 0.9 }
    self:addChild(self.rmItemBtn)

    local cy2 = cy + 34
    self.pctEntry = ISTextEntryBox:new("1", PAD, cy2, 46, 26)
    self.pctEntry:initialise(); self.pctEntry:instantiate(); self.pctEntry:setOnlyNumbers(true); self:addChild(self.pctEntry)
    self.setPctBtn = ISButton:new(PAD + 52, cy2, 64, 26, "Set %", self, KachaAdmin.onSetPct)
    self.setPctBtn:initialise(); self:addChild(self.setPctBtn)
    self.tierBox = ISComboBox:new(PAD + 124, cy2, 74, 26, self, KachaAdmin.onSetTier); self.tierBox:initialise()
    for _, t in ipairs(Kacha.TIERS) do self.tierBox:addOption(t) end
    self:addChild(self.tierBox)
    self.newGrpBtn = ISButton:new(PAD + 206, cy2, 104, 26, "+ New group", self, KachaAdmin.onNewGroup)
    self.newGrpBtn:initialise(); self.newGrpBtn.backgroundColor = { r = 0.18, g = 0.42, b = 0.55, a = 0.95 }
    self:addChild(self.newGrpBtn)
    self.delGrpBtn = ISButton:new(PAD + 316, cy2, 104, 26, "Delete group", self, KachaAdmin.onDelGroup)
    self.delGrpBtn:initialise(); self.delGrpBtn.backgroundColor = { r = 0.5, g = 0.18, b = 0.18, a = 0.9 }
    self:addChild(self.delGrpBtn)

    -- SALT row -----------------------------------------------------------
    local sy = cy2 + 44
    self.presetBox = ISComboBox:new(PAD, sy, 180, 26, self, nil); self.presetBox:initialise(); self:addChild(self.presetBox)
    self.loadBtn = ISButton:new(PAD + 186, sy, 64, 26, "Load", self, KachaAdmin.onLoadPreset)
    self.loadBtn:initialise(); self:addChild(self.loadBtn)
    self.editBtn = ISButton:new(PAD + 254, sy, 96, 26, "Edit presets", self, KachaAdmin.onEditPresets)
    self.editBtn:initialise(); self.editBtn.backgroundColor = { r = 0.3, g = 0.3, b = 0.34, a = 0.9 }; self:addChild(self.editBtn)
    self.clearBtn = ISButton:new(PAD + 354, sy, 64, 26, "Clear", self, KachaAdmin.onClearSalt)
    self.clearBtn:initialise(); self.clearBtn.backgroundColor = { r = 0.4, g = 0.2, b = 0.2, a = 0.9 }; self:addChild(self.clearBtn)
    self.saltRowY = sy

    self:populatePresets()
    self:refresh()
end

function KachaAdmin:populatePresets()
    if not self.presetBox then return end
    self.presetBox:clear()
    for _, n in ipairs(Kacha.presetNames()) do self.presetBox:addOption(n) end
end

function KachaAdmin:onClose() self:removeFromUIManager(); KachaAdmin.instance = nil end

function KachaAdmin:selIndex()
    return (self.list and self.list.selected) or -1
end

function KachaAdmin:update()
    if self.nameEntry then
        local n = self.nameEntry:getText() or ""
        if n ~= self.lastName then self.lastName = n; Kacha.setField(self.obj, "name", n) end
    end
    if self.costEntry then
        local c = self.costEntry:getText() or "1"
        if c ~= self.lastCost then self.lastCost = c; Kacha.setField(self.obj, "costPerRoll", tonumber(c) or 1) end
    end
end

function KachaAdmin:onCoinPick()
    local i = self.coinBox and self.coinBox.selected
    local c = i and Kacha.COINS[i]; if c then Kacha.setToken(self.obj, c.key) end
end

function KachaAdmin:onNewGroup()
    local pct = tonumber(self.pctEntry:getText()) or 1
    local tier = self.tierBox:getOptionText(self.tierBox.selected) or "C"
    local ni = Kacha.addGroup(self.obj, pct, tier)
    self:refresh(); if self.list then self.list.selected = ni end
end
function KachaAdmin:onDelGroup()
    local i = self:selIndex(); if i > 0 then Kacha.removeGroup(self.obj, i); self:refresh() end
end
function KachaAdmin:onSetPct()
    local i = self:selIndex(); if i > 0 then Kacha.setGroupRate(self.obj, i, self.pctEntry:getText()); self:refresh() end
end
function KachaAdmin:onSetTier()
    local i = self:selIndex()
    if i > 0 then Kacha.setGroupTier(self.obj, i, self.tierBox:getOptionText(self.tierBox.selected)); self:refresh() end
end
function KachaAdmin:onAddItem()
    local i = self:selIndex()
    if i <= 0 then self.warn = "Select a group first"; return end
    self.warn = nil
    local obj = self.obj
    if Kacha.openItemPicker then
        Kacha.openItemPicker(function(ft)
            Kacha.addItemToGroup(obj, i, ft)
            if KachaAdmin.instance then KachaAdmin.instance:refresh() end
        end, getPlayer())
    end
end
function KachaAdmin:onDelItem()
    local i = self:selIndex(); if i > 0 then Kacha.removeLastFromGroup(self.obj, i); self:refresh() end
end
function KachaAdmin:onLoadPreset()
    local name = self.presetBox:getOptionText(self.presetBox.selected)
    if not name then return end
    Kacha.setField(self.obj, "saltPreset", name)
    Kacha.loadPreset(self.obj, name); self:refresh()
end
function KachaAdmin:onEditPresets() if Kacha.openPresetEditor then Kacha.openPresetEditor() end end
function KachaAdmin:onClearSalt() Kacha.clearSalt(self.obj); self:refresh() end

function KachaAdmin:refresh()
    self.list:clear()
    for ei, e in ipairs(Kacha.getEntries(self.obj)) do
        local n = #(e.ids or {})
        local names = {}
        for _, id in ipairs(e.ids or {}) do names[#names + 1] = Kacha.displayName(id) end
        self.list:addItem(tostring(ei), {
            ei = ei, rate = tonumber(e.rate) or 0, tier = e.tier or "C",
            eff = (n > 0) and ((tonumber(e.rate) or 0) / n) or 0,
            n = n, names = table.concat(names, ", "),
        })
    end
end

function KachaAdmin:drawGroupRow(y, item, alt)
    local d = item.item; if not d then return y + self.itemheight end
    local h = self.itemheight
    if item.index and self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), h - 1, 0.35, 0.20, 0.42, 0.55)
    end
    local tc = Kacha.tierColor(d.tier)
    -- big rate
    self:drawText(tostring(d.rate) .. "%", 10, y + 9, 0.96, 0.78, 0.30, 1, UIFont.Large)
    -- tier chip
    self:drawRect(62, y + 11, 32, 18, 0.95, tc.r, tc.g, tc.b)
    self:drawTextCentre(d.tier, 78, y + 12, 1, 1, 1, 1, UIFont.Small)
    -- items line
    local line = d.n > 0 and d.names or "(no items yet - add some)"
    if #line > 52 then line = string.sub(line, 1, 50) .. ".." end
    self:drawText(line, 104, y + 5, 0.94, 0.94, 0.96, 1, UIFont.Small)
    local sub = d.n > 0 and (tostring(d.n) .. " item(s), " .. string.format("%.2f", d.eff) .. "% each") or ""
    self:drawText(sub, 104, y + 21, 0.70, 0.70, 0.76, 1, UIFont.Small)
    return y + h
end

function KachaAdmin:prerender()
    local W, H = self:getWidth(), self:getHeight()
    local T, S, A, R = Kacha.COL.text, Kacha.COL.sub, Kacha.COL.accent, Kacha.COL.red
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, A.a, A.r, A.g, A.b)
    self:drawRect(0, 0, W, self.titleH, R.a, R.r, R.g, R.b)
    self:drawText("Kacha Setting", 14, 11, T.r, T.g, T.b, T.a, UIFont.Medium)
    self:drawTextRight("skin " .. tostring(Kacha.machineSkin(self.obj)), W - 40, 14, S.r, S.g, S.b, S.a, UIFont.Small)

    local d = Kacha.getConfig(self.obj)
    self:drawText("PAY WITH  (one per machine)", PAD, self.titleH + 12, S.r, S.g, S.b, S.a, UIFont.Small)
    self:drawTextRight("COST / SPIN", W - PAD, self.titleH + 12, S.r, S.g, S.b, S.a, UIFont.Small)

    local coin = Kacha.coinByItem(d.tokenItem or "Base.KachaCoin")
    self:drawRect(PAD + 186, self.titleH + 32, 22, 24, 1, coin.col.r, coin.col.g, coin.col.b)
    local ctex = getTexture(coin.icon)
    if ctex then self:drawTextureScaled(ctex, PAD + 186, self.titleH + 32, 22, 24, 1, 1, 1, 1) end

    local total = Kacha.mainTotal(self.obj)
    local salt = 100 - total; if salt < 0 then salt = 0 end
    local by = self.titleH + 80
    self:drawText("PRIZE GROUPS", PAD, by, S.r, S.g, S.b, S.a, UIFont.Small)
    local bx = PAD + 216
    local bw = W - PAD - 90 - bx
    self:drawText("Win " .. total .. "%", PAD + 150, by, 0.4, 0.84, 0.75, 1, UIFont.Small)
    self:drawRect(bx, by + 3, bw, 10, 1, 0.06, 0.07, 0.09)
    local wpx = math.min(bw, bw * math.min(100, total) / 100)
    self:drawRect(bx, by + 3, wpx, 10, 1, 0.18, 0.83, 0.72)
    self:drawRect(bx + wpx, by + 3, bw - wpx, 10, 1, 0.23, 0.26, 0.31)
    self:drawTextRight("Salt " .. salt .. "%", W - PAD, by, S.r, S.g, S.b, S.a, UIFont.Small)

    self:drawText("SELECTED GROUP  (or double-click a group to edit items)",
        PAD, self.list:getY() + self.list:getHeight() + 4, S.r, S.g, S.b, S.a, UIFont.Small)
    self:drawText("SALT / CONSOLATION", PAD, self.saltRowY - 16, S.r, S.g, S.b, S.a, UIFont.Small)
    if self.warn then
        self:drawTextRight(self.warn, W - PAD, self.saltRowY - 16, 0.88, 0.35, 0.35, 1, UIFont.Small)
    end
end

function Kacha.openAdmin(obj)
    if Kacha.pushCfg then Kacha.pushCfg(obj) end   -- populate server registry on open
    if KachaAdmin.instance then KachaAdmin.instance:onClose() end
    local p = KachaAdmin:new(obj)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaAdmin.instance = p
end

Kacha.__mark("admin")
