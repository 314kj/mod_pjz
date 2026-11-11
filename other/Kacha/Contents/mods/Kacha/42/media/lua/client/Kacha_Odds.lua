--[[ ============================================================
     Kacha B42 [MP]  -  Items / Odds (player)  by PIE
     Top: featured rares (S/SS/SS+) as icons + % under each.
     Below: ALL items as a grid, 4 per row, with % .
     Item-icon textures (reliable).  English UI.      BUILD=odds-C
   ============================================================ ]]
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"

Kacha = Kacha or {}
KachaOdds = ISPanel:derive("KachaOdds")

local RARE = { S = true, SS = true, ["SS+"] = true }
local PERROW = 4

function KachaOdds:new(obj)
    local w, h = 470, 566
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.obj = obj; o.titleH = 38; o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.rareTop = o.titleH + 52
    o.rareH = 96
    return o
end

function KachaOdds:createChildren()
    local W, H = self:getWidth(), self:getHeight()
    self.closeBtn = ISButton:new(W - 30, 8, 22, 22, "X", self, KachaOdds.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.7 }
    self:addChild(self.closeBtn)

    local ly = self.rareTop + self.rareH + 30
    self.list = ISScrollingListBox:new(12, ly, W - 24, H - ly - 34)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = 78; self.list.drawBorder = true
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0.25 }
    self.list.doDrawItem = KachaOdds.drawGridRow
    self:addChild(self.list)
    self:refresh()
end

function KachaOdds:onClose() self:removeFromUIManager(); KachaOdds.instance = nil end

function KachaOdds:refresh()
    local rows, salt = Kacha.buildOdds(self.obj)
    self.salt = salt
    self.rares = {}
    local all = {}
    for _, r in ipairs(rows) do
        for _, it in ipairs(r.items) do
            local cell = { id = it.id, name = it.name, tier = r.tier, pct = r.eff, tex = Kacha.itemTexture(it.id) }
            all[#all + 1] = cell
            if RARE[r.tier] then self.rares[#self.rares + 1] = cell end
        end
    end
    self.list:clear()
    local row = {}
    for i, c in ipairs(all) do
        row[#row + 1] = c
        if #row == PERROW then self.list:addItem("r", { cells = row }); row = {} end
    end
    if #row > 0 then self.list:addItem("r", { cells = row }) end
    self.allCount = #all
    -- featured rares wrap 5 per row, up to 2 rows; grid moves down to fit
    local rr = math.ceil(math.min(#self.rares, 10) / 5)
    if rr < 1 then rr = 1 end
    self.rareRows = rr
    self.rareH = rr * 92 + 6
    local ly = self.rareTop + self.rareH + 30
    if self.list then self.list:setY(ly); self.list:setHeight(self:getHeight() - ly - 34) end
end

local function pctStr(p)
    if p >= 1 then return string.format("%.1f", p) .. "%" end
    return string.format("%.2f", p) .. "%"
end

function KachaOdds:drawGridRow(y, item, alt)
    -- self = list
    local cells = item.item and item.item.cells; if not cells then return y + self.itemheight end
    local h = self.itemheight
    local cw = self:getWidth() / PERROW
    for i, c in ipairs(cells) do
        local cx = (i - 1) * cw
        local tc = Kacha.tierColor(c.tier)
        if c.tex then self:drawTextureScaled(c.tex, cx + cw / 2 - 22, y + 6, 44, 44, 1, 1, 1, 1) end
        self:drawRect(cx + cw / 2 + 8, y + 6, 22, 14, 0.92, tc.r, tc.g, tc.b)
        self:drawTextCentre(c.tier, cx + cw / 2 + 19, y + 6, 1, 1, 1, 1, UIFont.Small)
        local nm = c.name or c.id
        if #nm > 12 then nm = string.sub(nm, 1, 11) .. ".." end
        self:drawTextCentre(nm, cx + cw / 2, y + 52, 0.9, 0.92, 0.96, 1, UIFont.Small)
        self:drawTextCentre(pctStr(c.pct), cx + cw / 2, y + 63, 0.22, 0.74, 0.98, 1, UIFont.Small)
    end
    return y + h
end

function KachaOdds:prerender()
    local W, H = self:getWidth(), self:getHeight()
    local T, S, A, R = Kacha.COL.text, Kacha.COL.sub, Kacha.COL.accent, Kacha.COL.red
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, A.a, A.r, A.g, A.b)
    self:drawRect(0, 0, W, self.titleH, R.a, R.r, R.g, R.b)
    self:drawText("Items / Odds", 12, 10, 1, 1, 1, 1, UIFont.Medium)

    local d = Kacha.getConfig(self.obj)
    local coin = Kacha.coinByItem(d.tokenItem or "Base.KachaCoin")
    local ctex = Kacha.coinTexture(coin)
    if ctex then self:drawTextureScaled(ctex, 12, self.titleH + 6, 20, 20, 1, 1, 1, 1) end
    self:drawText("Spin with " .. coin.label .. "  -  " .. (tonumber(d.costPerRoll) or 1) .. " / spin",
        38, self.titleH + 8, coin.col.r, coin.col.g, coin.col.b, 1, UIFont.Small)

    -- featured rares
    self:drawText("FEATURED  ( S / SS / SS+ )", 12, self.rareTop - 16, Kacha.COL.gold.r, Kacha.COL.gold.g, Kacha.COL.gold.b, 1, UIFont.Small)
    self:drawRect(12, self.rareTop, W - 24, self.rareH, 0.5, 0.05, 0.10, 0.20)
    self:drawRectBorder(12, self.rareTop, W - 24, self.rareH, 1, A.r, A.g, A.b)
    local rares = self.rares or {}
    if #rares == 0 then
        self:drawTextCentre("no rare items configured yet", W / 2, self.rareTop + self.rareH / 2 - 6, S.r, S.g, S.b, 1, UIFont.Small)
    else
        local perRow = 5
        local shown = math.min(#rares, perRow * (self.rareRows or 1))
        local slot = (W - 24) / perRow
        for i = 1, shown do
            local c = rares[i]
            local rr = math.floor((i - 1) / perRow)
            local ci = (i - 1) % perRow
            local cx = 12 + ci * slot + slot / 2
            local ry = self.rareTop + 8 + rr * 92
            local tc = Kacha.tierColor(c.tier)
            if c.tex then self:drawTextureScaled(c.tex, cx - 24, ry, 48, 48, 1, 1, 1, 1) end
            self:drawRect(cx + 8, ry - 2, 26, 15, 0.95, tc.r, tc.g, tc.b)
            self:drawTextCentre(c.tier, cx + 21, ry - 2, 1, 1, 1, 1, UIFont.Small)
            self:drawTextCentre(pctStr(c.pct), cx, ry + 50, tc.r, tc.g, tc.b, 1, UIFont.Medium)
            local nm = c.name or c.id; if #nm > 10 then nm = string.sub(nm, 1, 9) .. ".." end
            self:drawTextCentre(nm, cx, ry + 70, S.r, S.g, S.b, 1, UIFont.Small)
        end
        if #rares > shown then self:drawTextRight("+" .. (#rares - shown), W - 18, self.rareTop + 4, S.r, S.g, S.b, 1, UIFont.Small) end
    end

    self:drawText("ALL ITEMS  ( per single spin )", 12, self.rareTop + self.rareH + 12, S.r, S.g, S.b, 1, UIFont.Small)
    self:drawTextRight("Salt band  " .. (self.salt or 0) .. "%", W - 14, H - 24, S.r, S.g, S.b, 1, UIFont.Small)
end

function Kacha.openOdds(obj)
    if KachaOdds.instance then KachaOdds.instance:onClose() end
    local p = KachaOdds:new(obj)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaOdds.instance = p
end

Kacha.__mark("odds")
