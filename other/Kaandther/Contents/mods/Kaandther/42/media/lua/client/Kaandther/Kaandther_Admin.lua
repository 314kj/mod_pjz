--[[ ============================================================
     kaandther  -  ADMIN PANEL (client, staff)  -- clean redesign
     Left: weapons grouped by category (collapsible, drag to reorder)
           + P/G dots.  Right: clean per-tier editor with result preview.
     Add / Import open separate windows (Kaandther_AdminWindows.lua).
     Defensive throughout (pcall around risky bits) - UI must not break.
     ============================================================ ]]
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

Kaandther = Kaandther or {}
Kaandther.UI = Kaandther.UI or {}
local PAD, LEFTW = 12, 200
local MATROWS = 4
local CATLABEL = { blunt="Blunt", shortblade="Short Blade", longblade="Long Blade", axe="Axe",
                   spear="Spear", firearm="Firearm", improvised="Improvised", other="Other", event="\226\152\133 EVENT" }

local function shortName(ft) if not ft then return "?" end return (ft:gsub("^.-%.", "")) end
local function num(box, dflt) return tonumber(box and box:getText()) or dflt or 0 end
local function txt(box) return box and box:getText() or "" end

-- item icon resolver (script-manager only; never CreateItem -> no exceptions)
Kaandther.UI.texCache = Kaandther.UI.texCache or {}
local function itemTex(ft)
    local c=Kaandther.UI.texCache
    if c[ft]~=nil then return c[ft] or nil end
    local tex=nil
    local ok,si=pcall(function() return getScriptManager():getItem(ft) end)
    if ok and si then
        pcall(function() tex=si:getNormalTexture() end)
        if not tex then pcall(function() local ic=si:getIcon(); if ic then
            tex=getTexture("Item_"..ic) or getTexture("item_"..ic) or getTexture(ic) end end) end
    end
    c[ft]=tex or false; return tex
end
local function drawIcon(self, ft, x, y, sz)
    local tex=itemTex(ft)
    if tex then pcall(function() self:drawTextureScaled(tex,x,y,sz,sz,1) end) end
end
Kaandther.UI.drawIcon = drawIcon           -- reused by add/import windows
Kaandther.UI.itemBaseStats = function(ft)
    local dmax,dmin,clc=0,0,0
    local ok,si=pcall(function() return getScriptManager():getItem(ft) end)
    if ok and si then
        pcall(function() dmax=si:getMaxDamage() or 0 end)
        pcall(function() dmin=si:getMinDamage() or 0 end)
        pcall(function() clc=si:getConditionLowerChance() or 0 end)
    end
    return dmax or 0, dmin or 0, clc or 0
end

KaandtherAdmin = ISCollapsableWindow:derive("KaandtherAdmin")
local P = KaandtherAdmin

local function mkEntry(self, x, y, w, numeric)
    local e=ISTextEntryBox:new("", x, y, w, 22); e:initialise(); e:instantiate(); e.font=UIFont.Small
    if numeric then e:setOnlyNumbers(true) end
    self:addChild(e); return e
end
local function mkBtn(self, x, y, w, h, label, fn)
    local b=ISButton:new(x, y, w, h, label, self, fn); b:initialise(); b:instantiate(); self:addChild(b); return b
end

function P:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    local top=self:titleBarHeight()
    local rx=PAD+LEFTW+14
    local ew=self.width-rx-PAD
    self.track=self.track or "power"; self.tier=self.tier or 5
    self.collapsed=self.collapsed or {}
    self.listScroll=self.listScroll or 0
    self.L={ top=top, rx=rx, ew=ew }

    -- header controls
    self.bEnabled=mkBtn(self, rx+40, top+34, 70, 22, "Enabled", P.onToggleEnabled)
    self.bTrackP =mkBtn(self, rx+116, top+34, 74, 22, "POWER", function(s) s.track="power"; s.tier=5; s:populate() end)
    self.bTrackG =mkBtn(self, rx+194, top+34, 74, 22, "GUARD", function(s) s.track="guard"; s.tier=5; s:populate() end)
    self.bEvent  =mkBtn(self, rx+ew-96, top+34, 96, 22, "EVENT", function() Kaandther.Admin.toggleEvent() end)
    self.bT5 =mkBtn(self, rx,     top+66, 46, 22, "+5",  function(s) s.tier=5;  s:populate() end)
    self.bT10=mkBtn(self, rx+50,  top+66, 46, 22, "+10", function(s) s.tier=10; s:populate() end)
    self.bT15=mkBtn(self, rx+100, top+66, 46, 22, "+15", function(s) s.tier=15; s:populate() end)
    self.bT20=mkBtn(self, rx+150, top+66, 66, 22, "\226\152\133 Event", function(s) s.tier=20; s:populate() end)
    self.bTrackOn=mkBtn(self, rx+ew-92, top+66, 92, 22, "Track: ON", function(s)
        local w=s.sel and Kaandther.Config.profile(s.sel); if not w then return end
        local tk=w[s.track or "power"]; Kaandther.Admin.setTrackOn(s.sel, s.track or "power", not (tk and tk.on~=false)); s.refreshTick=12 end)

    -- editor fields
    local fy=top+108
    self.ePct =mkEntry(self, rx+180, fy,     56, true)
    self.eGMin=mkEntry(self, rx+180, fy+34,  44, true)
    self.eGMax=mkEntry(self, rx+232, fy+34,  44, true)
    self.eMiss=mkEntry(self, rx+330, fy+34,  44, true)
    self.eMul =mkEntry(self, rx+180, fy+68,  56, false)
    self.L.fy=fy
    -- materials
    local my=fy+126
    self.eMatItem,self.eMatCnt={},{}
    for i=1,MATROWS do local ry=my+(i-1)*24
        self.eMatItem[i]=mkEntry(self, rx+44, ry, ew-108, false)
        self.eMatCnt[i] =mkEntry(self, rx+ew-56, ry, 56, true)
    end
    self.L.my=my
    local cy=my+MATROWS*24+18
    self.eCostItem=mkEntry(self, rx+44, cy, ew-108, false)
    self.eCostCnt =mkEntry(self, rx+ew-56, cy, 56, true)
    self.L.cy=cy
    self.bCopy =mkBtn(self, rx, cy+28, 130, 24, "Copy weapon", P.onCopy)
    self.bPaste=mkBtn(self, rx+138, cy+28, 150, 24, "Paste weapon (all tiers)", P.onPaste)
    self.bSaveTier=mkBtn(self, rx, cy+56, ew, 26, "Save Tier", P.onSaveTier)
    -- charms (Red/Gold) + Blue mushroom are configured in server Sandbox now.
    -- shown read-only in prerender; no editable fields here.
    self.L.py=cy+96

    -- left buttons
    self.bAdd   =mkBtn(self, PAD, self.height-64, (LEFTW-6)/2, 24, "+ Add", function() if Kaandther.UI.openAdd then Kaandther.UI.openAdd(self) end end)
    self.bImport=mkBtn(self, PAD+(LEFTW-6)/2+6, self.height-64, (LEFTW-6)/2, 24, "Import", function() if Kaandther.UI.openImport then Kaandther.UI.openImport(self) end end)
    self.bRemove=mkBtn(self, PAD, self.height-36, LEFTW, 24, "Remove Selected", P.onRemove)

    -- bottom bar
    self.bGiveC=mkBtn(self, rx, self.height-36, 100, 24, "Give Charms", function() Kaandther.Admin.giveCharms() end)
    self.bGiveM=mkBtn(self, rx+106, self.height-36, 96, 24, "Give Mats", function() Kaandther.Admin.giveBundle() end)
    self.bClose=mkBtn(self, self.width-PAD-70, self.height-36, 70, 24, "Close", P.onClose)

    self:refreshList(); self:populate()
end

-- build ordered groups: { {cat=, weapons={ft,...}}, ... }
function P:groups()
    local byCat={}
    for ft,w in pairs(Kaandther.Config.WEAPONS or {}) do
        local c=(w and w.cat) or "other"
        byCat[c]=byCat[c] or {}; byCat[c][#byCat[c]+1]=ft
    end
    for _,l in pairs(byCat) do table.sort(l) end
    local order=Kaandther.Config.CATORDER or {}
    local seen={}; local groups={}
    for _,c in ipairs(order) do if byCat[c] then groups[#groups+1]={cat=c,weapons=byCat[c]}; seen[c]=true end end
    for c,l in pairs(byCat) do if not seen[c] then groups[#groups+1]={cat=c,weapons=l} end end
    return groups
end

function P:refreshList() self.grp=self:groups()
    if not self.sel or not Kaandther.Config.WEAPONS[self.sel] then
        self.sel=nil
        for _,g in ipairs(self.grp) do if g.weapons[1] then self.sel=g.weapons[1]; break end end
    end
end

function P:populate()
    local track=self.track or "power"
    local t=self.sel and Kaandther.Config.tierEntry(self.sel, track, self.tier)
    local function set(e,v) if e then e:setText(v==nil and "" or tostring(v)) end end
    set(self.ePct, t and t.pct)
    set(self.eMul, t and (track=="guard" and t.durMul or t.dmgMul))
    set(self.eGMin,t and t.gainMin); set(self.eGMax,t and t.gainMax); set(self.eMiss,t and t.missDrop)
    for i=1,MATROWS do local m=t and t.mats and t.mats[i]
        set(self.eMatItem[i], m and m[1]); set(self.eMatCnt[i], m and m[2]) end
    set(self.eCostItem, t and t.cost and t.cost.item); set(self.eCostCnt, t and t.cost and t.cost.amount)
end

-- ---- left list hit-test rows (built in prerender) ----
function P:onMouseDown(x, y)
    local rows=self.rows or {}
    for _,r in ipairs(rows) do
        if x>=8 and x<=PAD+LEFTW and y>=r.y-2 and y<=r.y+r.h-2 then
            if r.type=="grip" then self.dragCat=r.cat; self.dragFrom=r.idx; return true
            elseif r.type=="header" then self.collapsed[r.cat]=not self.collapsed[r.cat]; return true
            elseif r.type=="weapon" then self.sel=r.ft; self.track="power"; self.tier=5; self:populate(); return true end
        end
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
function P:onMouseUp(x, y)
    if self.dragCat then
        local ok=pcall(function()
            local target=self.dropIdx
            if target then
                local order={}
                for _,c in ipairs(Kaandther.Config.CATORDER or {}) do if c~=self.dragCat then order[#order+1]=c end end
                table.insert(order, math.max(1,math.min(#order+1,target)), self.dragCat)
                Kaandther.Admin.setCatOrder(order); self:refreshList()
            end
        end)
        self.dragCat=nil; self.dropIdx=nil
        return true
    end
    return ISCollapsableWindow.onMouseUp(self, x, y)
end

function P:onMouseWheel(del)
    self.listScroll = math.max(0, math.min(self.maxScroll or 0, (self.listScroll or 0) + del*24))
    return true
end
function P:prerender()
    ISCollapsableWindow.prerender(self)
    local L=self.L; if not L then return end
    local w,top=self.width, L.top
    local fS,fM=UIFont.Small,UIFont.Medium
    self:drawRect(0, top, w, self.height-top, 0.93, 0.07,0.08,0.10)
    self:drawRectBorder(0, top, w, self.height-top, 0.6, 0.85,0.72,0.32)
    self:drawRect(PAD+LEFTW+2, top, 1, self.height-top, 0.5, 0.3,0.3,0.34)

    -- ===== LEFT: grouped list (bounded + scrollable) =====
    self:drawText("drag = reorder | wheel = scroll", PAD, top+6, 0.42,0.45,0.5,1, fS)
    local listTop, listBottom = top+24, self.height-102
    self:drawRect(PAD-2, listTop-2, LEFTW+4, listBottom-listTop+4, 0.5, 0.04,0.05,0.07)
    self.rows={}
    local ly=listTop - (self.listScroll or 0); local ordIdx=0
    local mouseY = 0; pcall(function() mouseY=self:getMouseY() end)
    local function vis(y) return y>=listTop-22 and y<=listBottom end
    for _,g in ipairs(self.grp or {}) do
        ordIdx=ordIdx+1
        local collapsed=self.collapsed[g.cat]
        if vis(ly) then
            if self.dragCat and self.dragCat~=g.cat and mouseY>=ly-6 and mouseY<ly+8 then self.dropIdx=ordIdx; self:drawRect(PAD, ly-2, LEFTW, 2, 1, 0.29,0.56,0.88) end
            local isEvt=(g.cat=="event")
            self:drawRect(PAD, ly, LEFTW, 20, 0.85, isEvt and 0.16 or 0.12, isEvt and 0.12 or 0.13, isEvt and 0.07 or 0.16)
            self:drawText("=", PAD+4, ly+3, 0.4,0.42,0.46,1, fS)
            self:drawText(collapsed and ">" or "v", PAD+16, ly+3, 0.6,0.62,0.66,1, fS)
            self:drawText((CATLABEL[g.cat] or g.cat).."  ("..#g.weapons..")", PAD+28, ly+3, isEvt and 0.9 or 0.72, isEvt and 0.63 or 0.75, isEvt and 0.44 or 0.8, 1, fS)
            self.rows[#self.rows+1]={type="grip", cat=g.cat, idx=ordIdx, y=ly, h=20}
            self.rows[#self.rows+1]={type="header", cat=g.cat, y=ly, h=20}
        end
        ly=ly+22
        if not collapsed then
            for _,ft in ipairs(g.weapons) do
                if vis(ly) then
                    if self.sel==ft then self:drawRect(PAD, ly-1, LEFTW, 22, 0.3, 0.25,0.4,0.6) end
                    drawIcon(self, ft, PAD+18, ly, 18)
                    self:drawText(shortName(ft), PAD+40, ly+2, 0.9,0.9,0.9,1, fS)
                    local wp=Kaandther.Config.WEAPONS[ft]
                    local hp=wp and wp.power and wp.power.tiers and #wp.power.tiers>0 and wp.power.on~=false
                    local hg=wp and wp.guard and wp.guard.tiers and #wp.guard.tiers>0 and wp.guard.on~=false
                    self:drawRect(PAD+LEFTW-24, ly+6, 7, 7, 1, hp and 0.66 or 0.22, hp and 0.46 or 0.22, hp and 0.94 or 0.24)
                    self:drawRect(PAD+LEFTW-14, ly+6, 7, 7, 1, hg and 0.35 or 0.22, hg and 0.6 or 0.22, hg and 0.87 or 0.24)
                    self.rows[#self.rows+1]={type="weapon", ft=ft, y=ly, h=22}
                end
                ly=ly+22
            end
        end
    end
    -- scroll bounds + bar
    local content=(ly + (self.listScroll or 0)) - listTop
    self.maxScroll=math.max(0, content-(listBottom-listTop))
    if (self.listScroll or 0) > self.maxScroll then self.listScroll=self.maxScroll end
    if self.maxScroll>0 then
        local h=listBottom-listTop; local bh=math.max(20, h*h/content)
        local by=listTop + (h-bh)*((self.listScroll or 0)/self.maxScroll)
        self:drawRect(PAD+LEFTW-3, by, 4, bh, 0.7, 0.35,0.4,0.5)
    end
    if self.dragCat then self:drawText("dragging "..(CATLABEL[self.dragCat] or self.dragCat).."...", PAD, self.height-92, 0.6,0.7,0.85,1, fS) end

    -- ===== RIGHT: editor =====
    local rx,ew,fy=L.rx,L.ew,L.fy
    local p=self.sel and Kaandther.Config.profile(self.sel)
    if self.sel then drawIcon(self, self.sel, rx, top+8, 24) end
    self:drawText(self.sel and shortName(self.sel) or "(no weapon - Add / Import)", rx+(self.sel and 30 or 0), top+12, 1,1,1,1, fM)
    if p then
        local hp=p.power and p.power.tiers and #p.power.tiers>0
        local hg=p.guard and p.guard.tiers and #p.guard.tiers>0
        self:drawText("P", rx+ew-64, top+13, hp and 0.66 or 0.4, hp and 0.46 or 0.4, hp and 0.94 or 0.4, 1, fS)
        self:drawText(hp and "set" or "-", rx+ew-52, top+13, 0.55,0.6,0.55,1, fS)
        self:drawText("G", rx+ew-30, top+13, hg and 0.35 or 0.4, hg and 0.6 or 0.4, hg and 0.87 or 0.4, 1, fS)
        self:drawText(hg and "set" or "-", rx+ew-18, top+13, 0.55,0.6,0.55,1, fS)
    end

    local function paint(b,on) if b then b.backgroundColor=on and {r=0.16,g=0.4,b=0.6,a=0.95} or {r=0.2,g=0.2,b=0.22,a=0.85} end end
    local trk=self.track or "power"
    paint(self.bEnabled, p and p.enabled)
    paint(self.bTrackP, trk=="power"); paint(self.bTrackG, trk=="guard")
    if self.bEvent then
        local evon = Kaandther.Config.eventActive()
        self.bEvent:setTitle(evon and "EVENT: ON" or "EVENT: OFF")
        self.bEvent.backgroundColor = evon and {r=0.18,g=0.55,b=0.25,a=0.97} or {r=0.55,g=0.20,b=0.20,a=0.97}
    end
    if self.bT20 then self.bT20:setVisible(trk=="power") end
    paint(self.bT5,self.tier==5); paint(self.bT10,self.tier==10); paint(self.bT15,self.tier==15); paint(self.bT20,self.tier==20)

    local isP=(trk=="power")
    self:drawText(isP and "Success each charge" or "Success each attempt", rx, fy+4, 0.62,0.64,0.68,1, fS)
    self:drawText("%", rx+240, fy+4, 0.6,0.6,0.6,1, fS)
    if isP then
        self:drawText("Progress per hit", rx, fy+38, 0.62,0.64,0.68,1, fS)
        self:drawText("-", rx+224, fy+38, 0.6,0.6,0.6,1, fS)
        self:drawText("% miss -", rx+280, fy+38, 0.62,0.64,0.68,1, fS)
        self:drawText("%", rx+378, fy+38, 0.6,0.6,0.6,1, fS)
    end
    -- damage/durability result preview
    self:drawText(isP and "Damage x" or "Cond. loss resist x", rx, fy+72, 0.62,0.64,0.68,1, fS)
    if self.sel then
        local dmax,dmin,clc=Kaandther.UI.itemBaseStats(self.sel)
        local mul=tonumber(txt(self.eMul)) or 1
        if isP then
            self:drawText(("%.2f"):format(dmax), rx+250, fy+72, 0.55,0.57,0.6,1, fS)
            self:drawText(">", rx+300, fy+72, 0.5,0.5,0.5,1, fS)
            self:drawText(("%.2f"):format(dmax*mul), rx+318, fy+72, 0.45,0.9,0.5,1, fS)
        else
            if clc and clc > 0 then
                self:drawText(tostring(math.floor(clc)), rx+250, fy+72, 0.55,0.57,0.6,1, fS)
                self:drawText(">", rx+300, fy+72, 0.5,0.5,0.5,1, fS)
                self:drawText(tostring(math.floor(clc*mul)), rx+318, fy+72, 0.45,0.9,0.5,1, fS)
            else
                self:drawText(("x%.2f  applied to the weapon's real durability"):format(mul), rx+250, fy+72, 0.55,0.72,0.62,1, fS)
            end
        end
    end
    -- hide power-only fields when guard
    if self.eGMin then self.eGMin:setVisible(isP); self.eGMax:setVisible(isP); self.eMiss:setVisible(isP) end

    self:drawText("Materials for "..(self.tier==20 and "\226\152\133" or ("+"..self.tier)), rx, L.my-16, 0.7,0.75,0.8,1, fS)
    for i=1,MATROWS do local ry=L.my+(i-1)*24
        local ftv=txt(self.eMatItem[i])
        if ftv~="" then drawIcon(self, ftv, rx+18, ry+1, 20) end
    end
    self:drawText("Cost ($) - blank = none", rx, L.cy-16, 0.7,0.75,0.8,1, fS)

    local py=L.py
    local C2=Kaandther.Config
    self:drawText("Charms & Blue Mushroom: server Sandbox (Kaandther page)", rx, py+2, 0.55,0.57,0.62,1, fS)
    self:drawText(("Red guard %d%%     Gold guard %d%%"):format(C2.redGuard(), C2.goldGuard()), rx, py+22, 0.9,0.66,0.6,1, fS)
    self:drawText(("Blue / attempt %d     Zombie drop %d%%"):format(C2.blueCost(), math.floor(C2.blueDrop()*100+0.5)), rx, py+40, 0.55,0.72,0.9,1, fS)
    if KaandtherAdmin.clip then self:drawText("copied weapon: "..shortName(KaandtherAdmin.clip), rx, py+58, 0.5,0.7,0.55,1, fS) end
    if self.bSaveTier then self.bSaveTier.backgroundColor={r=0.20,g=0.50,b=0.26,a=0.95} end
    -- per-track on state on the toggle + track tabs dim if off
    if p and self.bTrackOn then
        local tk=p[trk]; local on=tk and tk.on~=false
        self.bTrackOn:setTitle(on and "Track: ON" or "Track: OFF")
        self.bTrackOn.backgroundColor= on and {r=0.2,g=0.5,b=0.26,a=0.95} or {r=0.5,g=0.2,b=0.2,a=0.95}
    end
end

-- ---- actions ----
function P:onToggleEnabled() local p=Kaandther.Config.profile(self.sel); if not p then return end
    Kaandther.Admin.enable(self.sel, not (p.enabled==true)); self.refreshTick=12 end
function P:onSaveTier()
    if not self.sel then return end
    local track=self.track or "power"
    local mats={}
    for i=1,MATROWS do local it=txt(self.eMatItem[i]):gsub("%s+",""); local n=tonumber(txt(self.eMatCnt[i]))
        if it~="" and n and n>0 then mats[#mats+1]={it,n} end end
    local cost=nil; local ci=txt(self.eCostItem):gsub("%s+",""); local cn=tonumber(txt(self.eCostCnt))
    if ci~="" and cn and cn>0 then cost={item=ci,amount=cn} end
    local t={ pct=num(self.ePct), mats=mats, cost=cost }
    if track=="power" then t.dmgMul=num(self.eMul,1); t.gainMin=num(self.eGMin,6); t.gainMax=num(self.eGMax,12); t.missDrop=num(self.eMiss,0); t.event=(self.tier==20) or nil
    else t.durMul=num(self.eMul,1) end
    Kaandther.Admin.setTier(self.sel, track, self.tier, t); self.refreshTick=12
end
function P:onRemove() if self.sel then Kaandther.Admin.removeWeapon(self.sel); self.sel=nil; self:refreshList(); self:populate(); self.refreshTick=12 end end
function P:onCopy() if self.sel then KaandtherAdmin.clip=self.sel end end
function P:onPaste() if self.sel and KaandtherAdmin.clip and KaandtherAdmin.clip~=self.sel then
    Kaandther.Admin.copyWeapon(KaandtherAdmin.clip, self.sel); self:refreshList(); self:populate(); self.refreshTick=12 end end
function P:onClose() self:setVisible(false); self:removeFromUIManager(); if Kaandther.UI.admin==self then Kaandther.UI.admin=nil end end

function P:update()
    ISCollapsableWindow.update(self)
    if self.refreshTick then self.refreshTick=self.refreshTick-1
        if self.refreshTick<=0 then self.refreshTick=nil
            if Kaandther.Config.load then Kaandther.Config.load() end
            self:refreshList(); self:populate() end end
    if not self.grp or #self.grp==0 then self.emptyTick=(self.emptyTick or 0)+1
        if self.emptyTick>=15 then self.emptyTick=0
            if Kaandther.requestConfig then Kaandther.requestConfig() end
            if Kaandther.Config.load then Kaandther.Config.load() end
            self:refreshList(); self:populate() end end
end

function Kaandther.UI.openAdmin(player)
    if Kaandther.requestConfig then Kaandther.requestConfig() end
    if Kaandther.Config and Kaandther.Config.load then Kaandther.Config.load() end
    if Kaandther.UI.admin then Kaandther.UI.admin:onClose() end
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local ww,hh=640, math.min(600, sh-60)
    local win=KaandtherAdmin:new(sw/2-ww/2, math.max(20, sh/2-hh/2), ww, hh)
    win.title, win.player="Kaandther - Admin", player
    win:initialise(); win:addToUIManager()
    Kaandther.UI.admin=win
    return win
end
