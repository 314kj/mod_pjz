--[[ ============================================================
  PROJECT DUNKA [MP] -- Unified Config (admin)   KACHASIG
  One window, two tabs:
    Slip loot   : per colour -> Guaranteed (always) + Random (weighted)
    Rank rewards: per rank -> how many W/Y/B slips on summon
  Save and close writes everything to server ModData (no ghosts).
============================================================ ]]--

require "ISUI/ISPanel"
require "DunKa_ItemPicker"

DunKaConfigUI = ISPanel:derive("DunKaConfigUI")

local W, H   = 600, 604
local COLORS = { "White", "Yellow", "Blue" }
local RANKS  = { "C", "B", "A", "S" }
local ROWH   = 30
local G_CAP, R_CAP = 4, 5

local function hit(x,y, rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end

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
local function ftTex(ft)
    if texCache[ft] ~= nil then return texCache[ft] or nil end
    local it = getScriptManager() and getScriptManager():getItem(ft)
    local t = it and itemTex(it)
    texCache[ft] = t or false
    return t
end
local function shortName(ft) return (tostring(ft):gsub("^.*%.", "")) end

function DunKaConfigUI:initialise() ISPanel.initialise(self) end

function DunKaConfigUI.openFor(slipCfg, rankCfg)
    if DunKaConfigUI.instance then pcall(function() DunKaConfigUI.instance:close() end) end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = DunKaConfigUI:new((sw-W)/2, (sh-H)/2, slipCfg, rankCfg)
    o:initialise(); o:addToUIManager()
    DunKaConfigUI.instance = o
    return o
end

function DunKaConfigUI:new(x, y, slipCfg, rankCfg)
    local o = ISPanel.new(self, x, y, W, H)
    o:noBackground(); o.moveWithMouse = true
    o.tab   = "slip"
    o.color = "White"
    o.slip  = slipCfg or {}
    o.rank  = rankCfg or {}
    for _, c in ipairs(COLORS) do
        o.slip[c] = o.slip[c] or {}
        o.slip[c].rolls = o.slip[c].rolls or 1
        o.slip[c].guaranteed = o.slip[c].guaranteed or {}
        o.slip[c].random = o.slip[c].random or {}
    end
    for _, r in ipairs(RANKS) do
        o.rank[r] = o.rank[r] or {}
        o.rank[r].White  = o.rank[r].White  or 0
        o.rank[r].Yellow = o.rank[r].Yellow or 0
        o.rank[r].Blue   = o.rank[r].Blue   or 0
    end
    return o
end

function DunKaConfigUI:close()
    DunKaConfigUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end
function DunKaConfigUI:onRightMouseDown(x,y) self:close(); return true end

function DunKaConfigUI:btn(label, x, y, w, h, kind)
    local r,g,b = 0.2,0.16,0.1
    if kind=="save" then r,g,b = 0.64,0.18,0.18 elseif kind=="add" then r,g,b = 0.11,0.16,0.09 end
    self:drawRect(x, y, w, h, 0.92, r,g,b)
    self:drawRectBorder(x, y, w, h, 0.92, kind=="save" and 0.89 or 0.5, 0.4, kind=="save" and 0.29 or 0.25)
    self:drawTextCentre(label, x+w/2, y+h/2-8, 0.95,0.9,0.75, 1, UIFont.Small)
end
function DunKaConfigUI:stepper(x, y, val, vr,vg,vb)
    self:btn("-", x, y, 20, 20)
    self:drawTextCentre(tostring(val), x+38, y+1, vr or 1, vg or 0.9, vb or 0.6, 1, UIFont.Medium)
    self:btn("+", x+56, y, 20, 20)
end
local function stepMinus(x,y,px,py) return hit(px,py, x,y,20,20) end
local function stepPlus(x,y,px,py) return hit(px,py, x+56,y,20,20) end

-- ================= render =================
function DunKaConfigUI:render()
    self:drawRect(0,0,W,H, 0.97, 0.07,0.07,0.08)
    self:drawRectBorder(0,0,W,H, 1, 0.55,0.42,0.2)
    self:drawRect(0,0,W,30, 1, 0.13,0.11,0.09)
    self:drawText("DunKa config  (admin)", 14, 7, 0.95,0.55,0.55, 1, UIFont.Medium)
    self:drawText("X", W-22, 6, 0.9,0.7,0.7, 1, UIFont.Medium)

    -- top tabs
    for i, t in ipairs({ {"slip","Slip loot"}, {"rank","Rank rewards"} }) do
        local tx = 20 + (i-1)*((W-40)/2 + 0)
        local tw = (W-44)/2
        local sel = (self.tab == t[1])
        self:drawRect(tx, 38, tw, 28, 1, sel and 0.30 or 0.13, sel and 0.12 or 0.12, sel and 0.12 or 0.13)
        self:drawRectBorder(tx, 38, tw, 28, 1, 0.5,0.4,0.2)
        self:drawTextCentre(t[2], tx+tw/2, 45, sel and 1 or 0.65, sel and 0.8 or 0.65, sel and 0.8 or 0.6, 1, UIFont.Small)
    end

    if self.tab == "slip" then self:renderSlip() else self:renderRank() end

    self:btn("Save and close", W-170, H-38, 150, 28, "save")
end

function DunKaConfigUI:renderSlip()
    local cc = self.slip[self.color]
    -- colour subtabs
    for i, c in ipairs(COLORS) do
        local tx = 20 + (i-1)*((W-40)/3)
        local tw = (W-44)/3
        local sel = (self.color == c)
        self:drawRect(tx, 76, tw, 24, 1, sel and 0.26 or 0.13, sel and 0.2 or 0.12, sel and 0.10 or 0.13)
        self:drawRectBorder(tx, 76, tw, 24, 1, 0.5,0.4,0.2)
        self:drawTextCentre(c, tx+tw/2, 81, sel and 1 or 0.7, sel and 0.9 or 0.7, sel and 0.5 or 0.6, 1, UIFont.Small)
    end

    -- GUARANTEED
    self:drawText("GUARANTEED  (always given)", 20, 110, 0.59,0.77,0.35, 1, UIFont.Small)
    local gy = 130
    for i = 1, math.min(#cc.guaranteed, G_CAP) do
        local e = cc.guaranteed[i]; local y = gy + (i-1)*ROWH
        local tex = ftTex(e.item)
        if tex then self:drawTextureScaled(tex, 20, y, 24, 24, 1,1,1,1) end
        self:drawText(shortName(e.item), 52, y+4, 0.9,0.9,0.85, 1, UIFont.Small)
        self:drawText("qty", 300, y+6, 0.5,0.5,0.47, 1, UIFont.Small)
        self:stepper(326, y+2, e.min or 1, 0.59,0.77,0.35)
        self:btn("X", 430, y+2, 22, 20)
    end
    if #cc.guaranteed == 0 then self:drawText("none", 52, gy+4, 0.5,0.5,0.5, 1, UIFont.Small) end
    self:btn("+ Add guaranteed", 20, gy + G_CAP*ROWH + 4, 160, 22, "add")

    -- RANDOM
    local ry0 = gy + G_CAP*ROWH + 36
    self:drawText("RANDOM  (rolled by weight)", 20, ry0-16, 0.94,0.62,0.15, 1, UIFont.Small)
    self:drawText("rolls:", 300, ry0-16, 0.5,0.5,0.47, 1, UIFont.Small)
    self:stepper(340, ry0-18, cc.rolls or 1, 0.94,0.62,0.15)
    local total = 0
    for _, e in ipairs(cc.random) do total = total + (e.weight or 1) end
    for i = 1, math.min(#cc.random, R_CAP) do
        local e = cc.random[i]; local y = ry0 + (i-1)*ROWH
        local tex = ftTex(e.item)
        if tex then self:drawTextureScaled(tex, 20, y, 24, 24, 1,1,1,1) end
        self:drawText(shortName(e.item), 52, y+4, 0.9,0.9,0.85, 1, UIFont.Small)
        self:drawText("q", 210, y+6, 0.5,0.5,0.47, 1, UIFont.Small)
        self:stepper(224, y+2, e.min or 1, 0.59,0.77,0.35)
        self:drawText("w", 320, y+6, 0.5,0.5,0.47, 1, UIFont.Small)
        self:stepper(334, y+2, e.weight or 10, 0.5,0.7,1)
        local pct = total > 0 and math.floor((e.weight or 1)/total*100 + 0.5) or 0
        self:drawText(pct.."%", 434, y+6, 0.94,0.62,0.15, 1, UIFont.Small)
        self:btn("X", 480, y+2, 22, 20)
    end
    if #cc.random == 0 then self:drawText("none", 52, ry0+4, 0.5,0.5,0.5, 1, UIFont.Small) end
    self:btn("+ Add random", 20, ry0 + R_CAP*ROWH + 4, 160, 22, "add")
end

function DunKaConfigUI:renderRank()
    self:drawText("Slips each rank gives on summon.  0 = colour not given.", 20, 84, 0.6,0.6,0.55, 1, UIFont.Small)
    self:drawText("White",  180, 108, 0.85,0.85,0.8, 1, UIFont.Small)
    self:drawText("Yellow", 330, 108, 0.9,0.85,0.4, 1, UIFont.Small)
    self:drawText("Blue",   480, 108, 0.5,0.7,0.95, 1, UIFont.Small)
    for ri, r in ipairs(RANKS) do
        local y = 130 + (ri-1)*46
        self:drawText("Rank "..r, 24, y+2, 0.94,0.62,0.15, 1, UIFont.Large)
        self:stepper(160, y, self.rank[r].White)
        self:stepper(310, y, self.rank[r].Yellow)
        self:stepper(460, y, self.rank[r].Blue)
    end
end

-- ================= input =================
function DunKaConfigUI:onMouseDown(x, y)
    if hit(x,y, W-24,4, 24,24) then self:close(); return true end
    -- top tabs
    if hit(x,y, 20,38,(W-44)/2,28) then self.tab="slip"; return true end
    if hit(x,y, 20+((W-40)/2),38,(W-44)/2,28) then self.tab="rank"; return true end
    -- save
    if hit(x,y, W-170,H-38,150,28) then self:save(); return true end

    if self.tab == "slip" then return self:slipClick(x,y) else return self:rankClick(x,y) end
end

function DunKaConfigUI:slipClick(x, y)
    local cc = self.slip[self.color]
    -- colour subtabs
    for i, c in ipairs(COLORS) do
        local tx = 20 + (i-1)*((W-40)/3)
        if hit(x,y, tx,76,(W-44)/3,24) then self.color=c; return true end
    end
    local gy = 130
    -- guaranteed rows
    for i = 1, math.min(#cc.guaranteed, G_CAP) do
        local e = cc.guaranteed[i]; local ry = gy + (i-1)*ROWH
        if stepMinus(326,ry+2,x,y) then e.min=math.max(1,(e.min or 1)-1); e.max=e.min; return true end
        if stepPlus(326,ry+2,x,y)  then e.min=math.min(99,(e.min or 1)+1); e.max=e.min; return true end
        if hit(x,y,430,ry+2,22,20) then table.remove(cc.guaranteed,i); return true end
    end
    if hit(x,y, 20, gy+G_CAP*ROWH+4, 160, 22) then
        local me=self; DunKaItemPicker.openFor(function(ft)
            for _,e in ipairs(me.slip[me.color].guaranteed) do if e.item==ft then return end end
            table.insert(me.slip[me.color].guaranteed, { item=ft, min=1, max=1 })
        end); return true
    end
    -- random
    local ry0 = gy + G_CAP*ROWH + 36
    if stepMinus(340,ry0-18,x,y) then cc.rolls=math.max(1,(cc.rolls or 1)-1); return true end
    if stepPlus(340,ry0-18,x,y)  then cc.rolls=math.min(10,(cc.rolls or 1)+1); return true end
    for i = 1, math.min(#cc.random, R_CAP) do
        local e = cc.random[i]; local ry = ry0 + (i-1)*ROWH
        if stepMinus(224,ry+2,x,y) then e.min=math.max(1,(e.min or 1)-1); e.max=e.min; return true end
        if stepPlus(224,ry+2,x,y)  then e.min=math.min(99,(e.min or 1)+1); e.max=e.min; return true end
        if stepMinus(334,ry+2,x,y) then e.weight=math.max(1,(e.weight or 10)-5); return true end
        if stepPlus(334,ry+2,x,y)  then e.weight=math.min(999,(e.weight or 10)+5); return true end
        if hit(x,y,480,ry+2,22,20) then table.remove(cc.random,i); return true end
    end
    if hit(x,y, 20, ry0+R_CAP*ROWH+4, 160, 22) then
        local me=self; DunKaItemPicker.openFor(function(ft)
            for _,e in ipairs(me.slip[me.color].random) do if e.item==ft then return end end
            table.insert(me.slip[me.color].random, { item=ft, min=1, max=1, weight=10 })
        end); return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function DunKaConfigUI:rankClick(x, y)
    local cols = { {"White",160}, {"Yellow",310}, {"Blue",460} }
    for ri, r in ipairs(RANKS) do
        local ry = 130 + (ri-1)*46
        for _, c in ipairs(cols) do
            if stepMinus(c[2],ry,x,y) then self.rank[r][c[1]]=math.max(0,(self.rank[r][c[1]] or 0)-1); return true end
            if stepPlus(c[2],ry,x,y)  then self.rank[r][c[1]]=math.min(9,(self.rank[r][c[1]] or 0)+1); return true end
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

function DunKaConfigUI:save()
    local pl = getPlayer()
    for _, c in ipairs(COLORS) do
        local cc = self.slip[c]
        local g, rnd = {}, {}
        for _, e in ipairs(cc.guaranteed) do g[#g+1]   = { item=e.item, min=e.min or 1, max=e.max or e.min or 1 } end
        for _, e in ipairs(cc.random)     do rnd[#rnd+1]= { item=e.item, min=e.min or 1, max=e.max or e.min or 1, weight=e.weight or 10 } end
        if DunKa.isSP() then DunKa.setSlipColor(c, cc.rolls, g, rnd)
        else sendClientCommand(pl, "DunKa", "setSlipCfg", { color=c, rolls=cc.rolls, guaranteed=g, random=rnd }) end
    end
    for _, r in ipairs(RANKS) do
        local rc = self.rank[r]
        if DunKa.isSP() then DunKa.setRankReward(r, rc.White, rc.Yellow, rc.Blue)
        else sendClientCommand(pl, "DunKa", "setRankCfg", { rank=r, white=rc.White, yellow=rc.Yellow, blue=rc.Blue }) end
    end
    self:close()
end

print("[DunKa] ConfigUI loaded")
