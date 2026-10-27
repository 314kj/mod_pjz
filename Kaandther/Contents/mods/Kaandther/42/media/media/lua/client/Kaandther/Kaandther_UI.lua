--[[ ============================================================
     kaandther  -  UI  (client only)
     RO-style enhancement window. Target = EQUIPPED weapon.
     Two modes (per weapon):
       attempt    -> success-chance shown, one roll per press
       accumulate -> progress bar fills by random gain per hit
     drawRect/drawRectBorder = alpha FIRST (a,r,g,b); drawText = r,g,b,a
     ============================================================ ]]
require "ISUI/ISContextMenu"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

Kaandther = Kaandther or {}
Kaandther.UI = Kaandther.UI or {}

local PAD, ROWH = 14, 22

local function shortName(ft) if not ft then return "?" end return (ft:gsub("^.-%.", "")) end
-- truncate to a pixel width with an ellipsis (used so long weapon names never overflow)
local function clampText(s, font, maxW)
    s = tostring(s or ""); local tm = getTextManager()
    if tm:MeasureStringX(font, s) <= maxW then return s end
    while #s > 1 and tm:MeasureStringX(font, s .. "...") > maxW do s = s:sub(1, #s - 1) end
    return s .. "..."
end
local function dispName(ft)
    local ok,si=pcall(function() return getScriptManager():getItem(ft) end)
    if ok and si then local n; pcall(function() n=si:getDisplayName() end); if n and n~="" then return n end end
    return shortName(ft)
end

Kaandther.UI.texCache = Kaandther.UI.texCache or {}
-- resolve an item's icon texture (real item first, then script manager; never CreateItem)
local function itemTex(ft, realItem)
    if realItem and realItem.getTex then local t = realItem:getTex(); if t then return t end end
    local c = Kaandther.UI.texCache
    if c[ft] ~= nil then return c[ft] or nil end
    local tex = nil
    local ok, si = pcall(function() return getScriptManager():getItem(ft) end)
    if ok and si then
        pcall(function() tex = si:getNormalTexture() end)
        if not tex then pcall(function() local ic = si:getIcon(); if ic then
            tex = getTexture("Item_" .. ic) or getTexture("item_" .. ic) or getTexture(ic) end end) end
    end
    c[ft] = tex or false
    return tex
end
local function drawIcon(self, ft, x, y, sz, realItem)
    local tex = itemTex(ft, realItem)
    if tex then pcall(function() self:drawTextureScaled(tex, x, y, sz, sz, 1) end) end
    return tex ~= nil
end

require "TimedActions/ISBaseTimedAction"

-- forging action: plays an anim + sound while the window bar counts (cosmetic)
KaandtherForge = ISBaseTimedAction:derive("KaandtherForge")
function KaandtherForge:isValid() return self.character and self.character:getPrimaryHandItem() ~= nil end
function KaandtherForge:update() end
function KaandtherForge:start()
    self.useProgressBar = false
    pcall(function() self:setActionAnim("Loot") end)
    pcall(function() self.sound = self.character:getEmitter():playSound("Hammering") end)
end
function KaandtherForge:stop() ISBaseTimedAction.stop(self) end
function KaandtherForge:perform() ISBaseTimedAction.perform(self) end
function KaandtherForge:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk=true; o.stopOnRun=true; o.maxTime=180; o.useProgressBar=false
    return o
end

KaandtherWindow = ISCollapsableWindow:derive("KaandtherWindow")
local W = KaandtherWindow

function W:state()
    local pl = self.player
    local out = { ready = false }
    local w = pl and pl:getPrimaryHandItem()
    if not w or not instanceof(w, "HandWeapon") then out.msg = "Equip a weapon to enhance"; return out end
    out.weapon, out.name, out.ft = w, w:getName(), w:getFullType()
    local ft = out.ft
    if not Kaandther.Config.isEnhanceable(ft) then out.msg = "This weapon can't be enhanced here"; return out end
    -- current actual stats for BOTH tracks (shown always)
    do
        local md0 = w:getModData()
        local bDmg0 = md0.akaBaseDmg or (w.getMaxDamage and w:getMaxDamage()) or 0
        local bClc0 = md0.akaBaseCLC or (w.getConditionLowerChance and w:getConditionLowerChance()) or 0
        out.curPowerTier = md0.akaPP or 1
        out.curGuardTier = md0.akaGP or 1
        out.curPowerDmg  = bDmg0 * (Kaandther.Config.powerMul(ft, out.curPowerTier) or 1)
        out.curGuardDur  = math.floor(bClc0 * (Kaandther.Config.guardMul(ft, out.curGuardTier) or 1))
        out.powerOn = Kaandther.Config.trackEnabled(ft, "power")
        out.guardOn = Kaandther.Config.trackEnabled(ft, "guard")
    end
    local track = self.track or "power"
    out.track = track
    if not Kaandther.Config.trackEnabled(ft, track) then
        out.msg = (track=="power" and "POWER" or "GUARD") .. " enhancement is off for this weapon"
        out.trackoff = true; return out
    end
    local C = Kaandther.Config
    local md = w:getModData()
    local cur = md[track == "guard" and "akaGP" or "akaPP"] or 1
    out.cur = cur
    if C.isMaxMS(track, cur) then out.msg = "MAX on this track (" .. (C.isStar(cur) and "Event" or ("+"..cur)) .. ")"; out.max = true; return out end
    local step = C.stepFor(ft, track, cur)
    if not step then out.msg = "No tiers on this track"; return out end
    out.step, out.to, out.pct = step, step.to, step.pct
    out.isStar   = C.isStar(step.to)
    out.event    = step.event
    out.progress = md.akaPB or 0
    out.gainMin, out.gainMax, out.missDrop = step.gainMin, step.gainMax, step.missDrop

    -- stat compare (power = damage, guard = durability)
    local baseDmg = md.akaBaseDmg or (w.getMaxDamage and w:getMaxDamage()) or 0
    local baseMin = md.akaBaseMin or (w.getMinDamage and w:getMinDamage()) or 0
    local baseClc = md.akaBaseCLC or (w.getConditionLowerChance and w:getConditionLowerChance()) or 0
    if track == "power" then
        local cm = C.powerMul(ft, cur) or 1
        local tm = step.dmgMul or 1
        out.s1 = { label = "Dmg max", old = ("%.2f"):format(baseDmg*cm), new = ("%.2f"):format(baseDmg*tm) }
        out.s2 = { label = "Dmg min", old = ("%.2f"):format(baseMin*cm), new = ("%.2f"):format(baseMin*tm) }
    else
        local cm = C.guardMul(ft, cur) or 1
        local tm = step.durMul or 1
        out.s1 = { label = "Durability", old = tostring(math.floor(baseClc*cm)), new = tostring(math.floor(baseClc*tm)) }
    end

    local inv = pl:getInventory()
    out.mats = {}
    local allOk = true
    for _, m in ipairs(step.mats) do
        local have = inv:getItemCount(m[1]); if have < m[2] then allOk = false end
        out.mats[#out.mats+1] = { ft = m[1], name = shortName(m[1]), need = m[2], have = have, ok = have >= m[2] }
    end
    if step.cost then
        local have = inv:getItemCount(step.cost.item); if have < step.cost.amount then allOk = false end
        out.mats[#out.mats+1] = { ft = step.cost.item, name = shortName(step.cost.item), need = step.cost.amount, have = have, ok = have >= step.cost.amount, gold = true }
    end
    local blueCost = C.blueCost()
    if blueCost > 0 then
        local have = inv:getItemCount(C.BLUE_ITEM); if have < blueCost then allOk = false end
        out.mats[#out.mats+1] = { ft = C.BLUE_ITEM, name = "Blue", need = blueCost, have = have, ok = have >= blueCost, blue = true }
    end

    -- * event gate
    out.locked = false
    if step.event then
        out.eventActive = C.eventActive()
        out.hasGold = inv:getItemCount(C.GOLD_ITEM) > 0
        out.locked = (not out.eventActive) or (not out.hasGold)
    end
    out.ready = allOk and not out.locked

    out.protect = {}
    for _, p in ipairs(C.PROTECT or {}) do
        out.protect[#out.protect+1] = { ft = p.item, name = p.name or shortName(p.item),
            have = inv:getItemCount(p.item), covers = (p.maxTier == nil or step.to <= p.maxTier) }
    end
    return out
end

function W:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    self.track = self.track or "power"
    local tw = (self.width - PAD*2) / 2
    self.bPower = ISButton:new(PAD, self:titleBarHeight() + 6, tw, 24, "POWER", self, function(s) s.track="power"; s.charge=nil end)
    self.bPower:initialise(); self.bPower:instantiate(); self:addChild(self.bPower)
    self.bGuard = ISButton:new(PAD + tw, self:titleBarHeight() + 6, tw, 24, "GUARD", self, function(s) s.track="guard"; s.charge=nil end)
    self.bGuard:initialise(); self.bGuard:instantiate(); self:addChild(self.bGuard)

    local bh, by = 34, self.height - 34 - PAD
    self.btnUp = ISButton:new(self.width/2 - 82, by, 164, bh, "ENHANCE", self, W.onUpgrade)
    self.btnUp:initialise(); self.btnUp:instantiate(); self:addChild(self.btnUp)
    self.btnTiers = ISButton:new(PAD, by, 84, bh, "TIERS", self, W.onTiers)
    self.btnTiers:initialise(); self.btnTiers:instantiate(); self:addChild(self.btnTiers)
    self.btnClose = ISButton:new(self.width - PAD - 84, by, 84, bh, "CLOSE", self, W.onClose)
    self.btnClose:initialise(); self.btnClose:instantiate(); self:addChild(self.btnClose)
end

function W:onTiers()  Kaandther.UI.openBrowser(self.player) end
function W:onUpgrade()
    local st = self:state()
    if not st.ready or self.charge then return end
    self.charge = { start = getTimestampMs(), dur = 3000 }   -- exactly 3s
    pcall(function() if ISTimedActionQueue and KaandtherForge then ISTimedActionQueue.add(KaandtherForge:new(self.player)) end end)
end
function W:update()
    ISCollapsableWindow.update(self)
    -- close if the player walks away from the station (station windows only; test opener has no key)
    if self.stationKey and Kaandther.Station and Kaandther.Station.nearKey then
        if not Kaandther.Station.nearKey(self.player, self.stationKey, 2) then self:onClose(); return end
    end
    if self.charge then
        if getTimestampMs() - self.charge.start >= self.charge.dur then
            self.charge = nil
            Kaandther.Enhance.attempt(self.player, nil, self.track or "power", self.stationKey)
        end
    end
end
function W:onClose()
    self:setVisible(false); self:removeFromUIManager()
    if Kaandther.UI.instance == self then Kaandther.UI.instance = nil end
end

function W:prerender()
    ISCollapsableWindow.prerender(self)
    local st = self:state()
    local w, top = self.width, self:titleBarHeight()
    local fS, fM, fL = UIFont.Small, UIFont.Medium, UIFont.Large
    local tm = getTextManager()
    local x, iw = PAD, w - PAD*2
    local C = Kaandther.Config

    self:drawRect(0, top, w, self.height - top, 0.92, 0.07, 0.08, 0.10)
    self:drawRectBorder(0, top, w, self.height - top, 0.6, 0.85, 0.72, 0.32)

    local trk = self.track or "power"
    if self.bPower then self.bPower.backgroundColor = (trk=="power") and {r=0.40,g=0.24,b=0.60,a=0.95} or {r=0.16,g=0.17,b=0.20,a=0.85} end
    if self.bGuard then self.bGuard.backgroundColor = (trk=="guard") and {r=0.20,g=0.40,b=0.55,a=0.95} or {r=0.16,g=0.17,b=0.20,a=0.85} end
    local ctop = top + 34

    if st.msg and not st.step then
        local cc = st.max and {1.0,0.82,0.25} or {0.9,0.9,0.65}
        if st.weapon then drawIcon(self, st.ft, w/2-30, ctop+26, 60, st.weapon) end
        self:drawTextCentre(st.msg, w/2, ctop+96, cc[1],cc[2],cc[3],1, fM)
        self.btnUp:setEnable(false)
        return
    end

    local cNext, cCur = C.colorFor(st.to), C.colorFor(st.cur)
    local acc = (st.track == "power")
    local y = ctop

    local isz = 52
    self:drawRect(w/2-isz/2-2, y-2, isz+4, isz+4, 0.9, 0.05,0.06,0.08)
    self:drawRectBorder(w/2-isz/2-2, y-2, isz+4, isz+4, 1, cNext[1],cNext[2],cNext[3])
    drawIcon(self, st.ft, w/2-isz/2, y, isz, st.weapon)
    y = y + isz + 2
    self:drawTextCentre(clampText(st.name or shortName(st.ft), fM, w - 24), w/2, y, 1,1,1,1, fM); y = y+20
    -- current stats for BOTH tracks (live)
    if st.curPowerTier then
        local pOn, gOn = st.powerOn, st.guardOn
        local lp = ("Power +%s  dmg %.2f"):format(tostring(st.curPowerTier), st.curPowerDmg or 0)
        local lg = ("Guard +%s  dur %d"):format(tostring(st.curGuardTier), st.curGuardDur or 0)
        local gap = "    "
        local wlp, wgap = tm:MeasureStringX(fS, lp), tm:MeasureStringX(fS, gap)
        local x0 = w/2 - (wlp + wgap + tm:MeasureStringX(fS, lg))/2
        self:drawText(lp, x0, y, pOn and 0.79 or 0.4, pOn and 0.65 or 0.4, pOn and 0.94 or 0.44, 1, fS)
        self:drawText(lg, x0+wlp+wgap, y, gOn and 0.5 or 0.4, gOn and 0.7 or 0.4, gOn and 0.93 or 0.44, 1, fS)
        y = y + 18
    end

    local sc = C.isStar(st.cur) and "Event" or ("+"..st.cur)
    local sto = C.isStar(st.to) and "Event" or ("+"..st.to)
    local sa = "  >>>  "
    local wc,wa,wt = tm:MeasureStringX(fL,sc), tm:MeasureStringX(fM,sa), tm:MeasureStringX(fL,sto)
    local sx0 = w/2 - (wc+wa+wt)/2
    self:drawText(sc, sx0, y, cCur[1],cCur[2],cCur[3],1, fL)
    self:drawText(sa, sx0+wc, y+5, 0.6,0.6,0.6,1, fM)
    self:drawText(sto, sx0+wc+wa, y, cNext[1],cNext[2],cNext[3],1, fL)
    y = y + 30

    if st.event then
        self:drawRect(x, y, iw, 24, 0.85, 0.16,0.09,0.07)
        self:drawRectBorder(x, y, iw, 24, 0.8, 0.9,0.45,0.3)
        local msg = st.locked and ("* LOCKED - "..((not st.eventActive) and "event closed" or "need Gold ball")) or "* EVENT OPEN - Gold ready"
        self:drawTextCentre(msg, w/2, y+4, 0.95,0.6,0.4,1, fS)
        y = y + 28
    end

    if acc then
        local gH, prog = 22, math.max(0, math.min(100, st.progress))
        self:drawRect(x, y, iw, gH, 0.75, 0.08,0.08,0.09)
        self:drawRect(x, y, iw*(prog/100), gH, 0.95, cNext[1],cNext[2],cNext[3])
        self:drawRectBorder(x, y, iw, gH, 0.8, 0.5,0.5,0.5)
        self:drawTextCentre(("%d / 100%%"):format(prog), w/2, y+3, 1,1,1,1, fS)
        y = y + gH + 2
        self:drawTextCentre(("hit +%d..%d%%   miss -%d%%   100%%=tier up"):format(st.gainMin, st.gainMax, st.missDrop), w/2, y, 0.55,0.58,0.62,1, fS)
        y = y + 18
    else
        local bH = 30
        self:drawRect(x, y, iw, bH, 0.6, 0.09,0.10,0.13)
        self:drawRectBorder(x, y, iw, bH, 0.5, 0.3,0.32,0.36)
        self:drawText("success chance", x+12, y+7, 0.8,0.8,0.85,1, fS)
        local ps = st.pct.."%"
        self:drawText(ps, x+iw-tm:MeasureStringX(fL,ps)-12, y+2, cNext[1],cNext[2],cNext[3],1, fL)
        y = y + bH + 6
    end

    local rows = st.s2 and 2 or 1
    local sbH = 20 + rows*20
    self:drawRect(x, y, iw, sbH, 0.55, 0.09,0.10,0.13)
    self:drawRectBorder(x, y, iw, sbH, 0.4, 0.28,0.30,0.34)
    local function cmp(sdat, ry) if not sdat then return end
        self:drawText(sdat.label, x+12, ry, 0.6,0.62,0.66,1, fS)
        self:drawText(sdat.old, x+100, ry, 0.8,0.8,0.8,1, fS)
        self:drawText(">", x+162, ry, 0.5,0.5,0.5,1, fS)
        self:drawText(sdat.new, x+182, ry, 0.45,0.9,0.5,1, fS)
    end
    cmp(st.s1, y+9); if st.s2 then cmp(st.s2, y+29) end
    y = y + sbH + 8

    self:drawText("MATERIALS", x, y, 0.75,0.8,0.85,1, fS); y = y+18
    local function drawSlot(sx, sy, ft, cntStr, cc2, nm, border)
        self:drawRect(sx, sy, 52, 52, 0.9, 0.06,0.07,0.09)
        self:drawRectBorder(sx, sy, 52, 52, 0.85, border[1],border[2],border[3])
        drawIcon(self, ft, sx+11, sy+7, 30)
        self:drawTextCentre(cntStr, sx+26, sy+54, cc2[1],cc2[2],cc2[3],1, fS)
        if nm then self:drawTextCentre(nm, sx+26, sy+67, 0.5,0.52,0.56,1, fS) end
    end
    local mats = st.mats or {}
    if #mats>0 then
        local rowW = #mats*52 + (#mats-1)*10
        local sx0 = x + (iw-rowW)/2
        for i,m in ipairs(mats) do
            local sx = sx0 + (i-1)*62
            local cc2 = m.ok and {0.45,0.9,0.5} or {1,0.45,0.4}
            local bd = m.gold and {0.5,0.45,0.2} or (m.ok and {0.3,0.33,0.38} or {0.55,0.28,0.28})
            drawSlot(sx, y, m.ft, ("%d/%d"):format(m.have, m.need), cc2, (m.gold and "$ " or "")..m.name, bd)
        end
        y = y + 80
    end

    local prot = st.protect or {}
    if #prot>0 then
        local rowW = #prot*52 + (#prot-1)*24
        local sx0 = x + (iw-rowW)/2
        for i,pp in ipairs(prot) do
            local sx = sx0 + (i-1)*76
            local held = (pp.have or 0)>0
            local red = (pp.ft==C.RED_ITEM)
            local bd = red and {0.6,0.3,0.3} or {0.55,0.48,0.22}
            local cc2 = held and (pp.covers and (red and {1,0.6,0.55} or {1,0.83,0.4}) or {0.5,0.5,0.52}) or {0.45,0.45,0.45}
            drawSlot(sx, y, pp.ft, tostring(pp.have or 0), cc2, (red and "Red" or "Gold"), bd)
        end
        y = y + 76
    end

    if self.charge then
        local frac = math.min(1, (getTimestampMs() - self.charge.start)/self.charge.dur)
        local cy = self.height - 34 - PAD - 24
        self:drawRect(PAD, cy, iw, 18, 0.85, 0.10,0.10,0.12)
        self:drawRect(PAD, cy, iw*frac, 18, 0.95, 0.92,0.62,0.20)
        self:drawRectBorder(PAD, cy, iw, 18, 0.8, 0.6,0.5,0.3)
        self:drawTextCentre("FORGING . . .  "..math.max(1,math.ceil((1-frac)*3)), w/2, cy+1, 0.1,0.09,0.08,1, fS)
        self.btnUp:setEnable(false); self.btnUp:setTitle("...")
    else
        self.btnUp:setTitle(acc and "CHARGE" or "ENHANCE")
        local ready = (st.ready==true)
        self.btnUp:setEnable(ready)
        self.btnUp.backgroundColor = ready and {r=0.20,g=0.50,b=0.26,a=0.95} or {r=0.20,g=0.20,b=0.22,a=0.80}
    end
end

function Kaandther.UI.open(player, stationKey)
    player = player or getPlayer()
    if Kaandther.requestConfig then Kaandther.requestConfig() end
    if Kaandther.Config and Kaandther.Config.load then Kaandther.Config.load() end
    if Kaandther.UI.instance then Kaandther.UI.instance:onClose() end
    local ww, hh = 440, 592
    local win = KaandtherWindow:new(getCore():getScreenWidth()/2 - ww/2, getCore():getScreenHeight()/2 - hh/2, ww, hh)
    win.player, win.stationKey, win.title = player, stationKey, "Enhancement"
    win:initialise(); win:addToUIManager()
    Kaandther.UI.instance = win
    return win
end


--[[ ===== WEAPON TIER BROWSER ============================== ]]
KaandtherBrowser = ISCollapsableWindow:derive("KaandtherBrowser")
local B = KaandtherBrowser

function B:weaponList()
    local list = {}
    for ft, p in pairs(Kaandther.Config.WEAPONS or {}) do if p.enabled then list[#list+1] = ft end end
    table.sort(list); return list
end
function B:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    self.wlScroll=0
    self.btnClose = ISButton:new(self.width - PAD - 90, self.height - 34, 90, 26, "CLOSE", self, B.onClose)
    self.btnClose:initialise(); self.btnClose:instantiate(); self:addChild(self.btnClose)
end
function B:onClose()
    self:setVisible(false); self:removeFromUIManager()
    if Kaandther.UI.browser == self then Kaandther.UI.browser = nil end
end
function B:listGeom() return 8, self:titleBarHeight() + 30, 40, (self.colW or 150) end
function B:onMouseDown(x, y)
    for _, r in ipairs(self.rowsHit or {}) do
        if x >= 6 and x <= 6 + (self.colW or 150) + 6 and y >= r.y - 2 and y <= r.y + 36 then self.selected = r.ft; return true end
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
function B:onMouseWheel(del)
    self.wlScroll = math.max(0, math.min(self.wlMax or 0, (self.wlScroll or 0) + del*28))
    return true
end
function B:prerender()
    ISCollapsableWindow.prerender(self)
    local C = Kaandther.Config
    local fS, fM = UIFont.Small, UIFont.Medium
    local x0, y0, rowH, colW = self:listGeom()
    self:drawText("Weapons", x0, self:titleBarHeight() + 8, 0.8, 0.8, 0.8, 1, fM)
    local list = self.list or {}
    if #list == 0 then self:drawText("(none configured)", x0, y0, 0.7, 0.7, 0.7, 1, fS) end
    local listBottom = self.height - 42
    self:drawRect(x0-4, y0-4, colW+8, listBottom-y0+8, 0.4, 0.04,0.05,0.07)
    self.rowsHit = {}
    for i, ft in ipairs(list) do
        local ry = y0 + (i - 1) * rowH - (self.wlScroll or 0)
        if ry >= y0 - rowH and ry <= listBottom then
            if self.selected == ft then self:drawRect(x0 - 2, ry - 2, colW + 4, rowH, 0.25, 0.4, 0.7, 1) end
            drawIcon(self, ft, x0, ry, 30)
            self:drawText(clampText(dispName(ft), fS, colW - 40), x0 + 36, ry + 8, 1, 1, 1, 1, fS)
            self.rowsHit[#self.rowsHit+1] = { ft=ft, y=ry }
        end
    end
    local content = #list*rowH; self.wlMax = math.max(0, content-(listBottom-y0))
    if (self.wlScroll or 0) > self.wlMax then self.wlScroll=self.wlMax end
    if self.wlMax>0 then local h=listBottom-y0; local bh=math.max(20,h*h/content)
        self:drawRect(x0+colW+2, y0+(h-bh)*((self.wlScroll or 0)/self.wlMax), 4, bh, 0.7, 0.35,0.4,0.5) end
    local rx, ry = x0 + colW + 16, self:titleBarHeight() + 8
    if not self.selected then self:drawText("Select a weapon", rx, y0, 0.7, 0.7, 0.7, 1, fS); return end
    self:drawText(clampText(dispName(self.selected), fM, self.width - rx - 16), rx, ry, 1, 1, 1, 1, fM)
    ry = ry + 24
    self:drawText("POWER  (accumulate - damage)", rx, ry, 0.7,0.6,0.9,1, fS); ry = ry + 18
    for _, m in ipairs({5,10,15,20}) do
        local t = C.tierEntry(self.selected, "power", m)
        if t then local c = C.colorFor(m)
            self:drawText((C.isStar(m) and "*" or ("+"..m)), rx, ry, c[1],c[2],c[3],1, fS)
            self:drawText(("hit %d%%  +%d..%d/hit  dmg x%.2f%s"):format(t.pct or 0, t.gainMin or 0, t.gainMax or 0, t.dmgMul or 1, t.event and "  (EVENT)" or ""), rx+34, ry, 0.85,0.85,0.85,1, fS)
            ry = ry + 17
        end
    end
    ry = ry + 8
    self:drawText("GUARD  (per-attempt - cond. loss resist)", rx, ry, 0.55,0.75,0.9,1, fS); ry = ry + 18
    for _, m in ipairs({5,10,15}) do
        local t = C.tierEntry(self.selected, "guard", m)
        if t then local c = C.colorFor(m)
            self:drawText(("+"..m), rx, ry, c[1],c[2],c[3],1, fS)
            self:drawText(("%d%%  resist x%.2f"):format(t.pct or 0, t.durMul or 1), rx+34, ry, 0.85,0.85,0.85,1, fS)
            ry = ry + 17
        end
    end
end

function Kaandther.UI.openBrowser(player)
    if Kaandther.requestConfig then Kaandther.requestConfig() end
    if Kaandther.Config and Kaandther.Config.load then Kaandther.Config.load() end
    if Kaandther.UI.browser then Kaandther.UI.browser:onClose() end
    local ww, hh = 520, 420
    local win = KaandtherBrowser:new(getCore():getScreenWidth()/2 - ww/2, getCore():getScreenHeight()/2 - hh/2, ww, hh)
    win.colW, win.title, win.player = 150, "Weapon Tiers", player
    win:initialise(); win.list = win:weaponList(); win.selected = win.list[1]
    win:addToUIManager(); Kaandther.UI.browser = win
    return win
end


--[[ ===== CHECK MY WEAPON ================================== ]]
KaandtherCheck = ISCollapsableWindow:derive("KaandtherCheck")
local Cw = KaandtherCheck
function Cw:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    self.btnClose = ISButton:new(self.width/2 - 45, self.height - 34, 90, 26, "CLOSE", self, Cw.onClose)
    self.btnClose:initialise(); self.btnClose:instantiate(); self:addChild(self.btnClose)
end
function Cw:onClose()
    self:setVisible(false); self:removeFromUIManager()
    if Kaandther.UI.check == self then Kaandther.UI.check = nil end
end
function Cw:prerender()
    ISCollapsableWindow.prerender(self)
    local C = Kaandther.Config
    local fS, fM = UIFont.Small, UIFont.Medium
    local top = self:titleBarHeight(); local w = self.width
    self:drawRect(0, top, w, self.height-top, 0.95, 0.07,0.08,0.10)
    self:drawRectBorder(0, top, w, self.height-top, 0.6, 0.85,0.72,0.32)
    local pl = self.player
    local wpn = pl and pl:getPrimaryHandItem()
    local x, y = PAD, top + 12
    if not wpn or not instanceof(wpn,"HandWeapon") then
        self:drawTextCentre("Hold a weapon to check", w/2, top+44, 0.9,0.9,0.65,1, fM); return
    end
    local ft = wpn:getFullType(); local md = wpn:getModData()
    drawIcon(self, ft, x, y, 40, wpn)
    self:drawText(clampText(wpn:getName(), fM, w - x - 60), x+50, y+2, 1,1,1,1, fM)
    self:drawText(clampText(dispName(ft), fS, w - x - 60), x+50, y+22, 0.55,0.57,0.62,1, fS)
    y = y + 52
    self:drawRect(x, y, w-2*x, 1, 0.4, 0.4,0.4,0.45); y = y + 8

    local enh = C.isEnhanceable(ft)
    local pp = md.akaPP or 1
    local gp = md.akaGP or 1
    local baseDmgMax = md.akaBaseDmg or (wpn.getMaxDamage and wpn:getMaxDamage()) or 0
    local baseDmgMin = md.akaBaseMin or (wpn.getMinDamage and wpn:getMinDamage()) or 0
    local baseClc    = md.akaBaseCLC or (wpn.getConditionLowerChance and wpn:getConditionLowerChance()) or 0
    local pm = C.powerMul(ft, pp) or 1
    local gm = C.guardMul(ft, gp) or 1
    local tm = getTextManager()
    local function line(lbl, val, r,g,b)
        self:drawText(lbl, x, y, 0.62,0.64,0.68,1, fS)
        local vs = tostring(val)
        self:drawText(vs, w - x - tm:MeasureStringX(fS, vs), y, r or 0.9, g or 0.9, b or 0.9, 1, fS)
        y = y + 20
    end
    self:drawText("POWER  (damage)", x, y, 0.7,0.6,0.9,1, fS); y = y + 18
    line("   Tier", C.isStar(pp) and "Event" or ("+"..(pp>1 and pp or 0)))
    line("   Damage max", ("%.2f"):format(baseDmgMax*pm), 0.5,0.9,0.55)
    line("   Damage min", ("%.2f"):format(baseDmgMin*pm), 0.5,0.9,0.55)
    y = y + 6
    self:drawText("GUARD  (condition-loss resist)", x, y, 0.55,0.75,0.9,1, fS); y = y + 18
    line("   Tier", "+"..(gp>1 and gp or 0))
    line("   Cond. loss resist", math.floor(baseClc*gm).."   (base "..math.floor(baseClc)..")", 0.5,0.85,0.95)
    self:drawText("higher resist = degrades slower", x, y, 0.5,0.52,0.56,1, fS); y = y + 18
    if not enh then self:drawText("(this weapon isn't set up for enhancement)", x, y, 0.85,0.6,0.4,1, fS) end
end
function Kaandther.UI.openWeaponCheck(player)
    player = player or getPlayer()
    if Kaandther.UI.check then Kaandther.UI.check:onClose() end
    local ww, hh = 330, 330
    local win = KaandtherCheck:new(getCore():getScreenWidth()/2 - ww/2, getCore():getScreenHeight()/2 - hh/2, ww, hh)
    win.player, win.title = player, "Check My Weapon"
    win:initialise(); win:addToUIManager()
    Kaandther.UI.check = win
    return win
end


--[[ ===== SUCCESS SUMMARY (only on a tier-up) ============== ]]

--[[ ===== RESULT SUMMARY (success / fail / protect) ======== ]]
KaandtherResult = ISCollapsableWindow:derive("KaandtherResult")
local Rw = KaandtherResult
function Rw:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    self.btnClose = ISButton:new(self.width/2 - 45, self.height - 34, 90, 26, "OK", self, Rw.onClose)
    self.btnClose:initialise(); self.btnClose:instantiate(); self:addChild(self.btnClose)
end
function Rw:onClose()
    self:setVisible(false); self:removeFromUIManager()
    if Kaandther.UI.result == self then Kaandther.UI.result = nil end
end
function Rw:prerender()
    ISCollapsableWindow.prerender(self)
    local d = self.data or {}
    local fS, fM = UIFont.Small, UIFont.Medium
    local top = self:titleBarHeight()
    self:drawRect(0, top, self.width, self.height - top, 1.0, 0.06, 0.07, 0.09)
    local kc = (d.kind == "success" and Kaandther.Config.colorFor(d.tier or 1))
            or (d.kind == "protect" and { 0.45, 0.7, 1.0 })
            or { 0.88, 0.35, 0.29 }
    self:drawRectBorder(0, top, self.width, self.height - top, 1, kc[1], kc[2], kc[3])
    local x, y = 18, top + 16
    local title = (d.kind == "success" and "SUCCESS") or (d.kind == "protect" and "PROTECTED") or "FAILED"
    local sym   = (d.kind == "success" and "+") or (d.kind == "protect" and "=") or "x"
    self:drawText(sym, x, y-1, kc[1], kc[2], kc[3], 1, fM)
    self:drawText(title, x+18, y, kc[1], kc[2], kc[3], 1, fM); y = y + 24
    self:drawText(("%s    +%s -> +%s"):format(tostring(d.name), tostring(d.from), tostring(d.to)), x, y, 0.85,0.85,0.85, 1, fS); y = y + 20
    self:drawRect(x, y, self.width - 36, 1, 0.5, kc[1], kc[2], kc[3]); y = y + 12
    local function row(label, val, r,g,b)
        self:drawText(label, x, y, 0.6,0.62,0.66, 1, fS)
        local vs = tostring(val); self:drawText(vs, self.width - 32 - getTextManager():MeasureStringX(fS, vs), y, r,g,b, 1, fS); y = y + 20
    end
    row("Attempts this tier", d.tries or 0, 0.9,0.9,0.9)
    row("Fails / misses", d.fails or 0, 1.0,0.6,0.5)
    row("Protects used", d.protects or 0, 0.6,0.8,1.0)
    y = y + 2; self:drawRect(x, y, self.width - 36, 1, 0.3, 0.3,0.3,0.34); y = y + 9
    self:drawText(("%s  -  day %s"):format(tostring(d.user), tostring(d.day)), x, y, 0.5,0.5,0.54, 1, fS); y = y + 18
    local tip = (d.kind == "fail" and "tip: hold a charm to keep your tier") or "screenshot to send admin"
    self:drawText(tip, x, y, (d.kind=="fail") and 0.85 or 0.55, (d.kind=="fail") and 0.6 or 0.7, 0.5, 1, fS)
end
function Kaandther.UI.showResult(d)
    if Kaandther.UI.result then Kaandther.UI.result:onClose() end
    local ww, hh = 312, 226
    local win = KaandtherResult:new(getCore():getScreenWidth()/2 - ww/2, getCore():getScreenHeight()/2 - hh/2, ww, hh)
    win.data = d
    win.title = (d.kind == "success" and ("+" .. tostring(d.tier) .. " Success"))
             or (d.kind == "protect" and "Protected") or "Failed"
    win:initialise(); win:addToUIManager()
    Kaandther.UI.result = win
    return win
end


--[[ ===== RESULT HOOK ====================================== ]]
Kaandther.UI.journey = Kaandther.UI.journey or {}
function Kaandther.Enhance.onResult(args)
    if type(args) ~= "table" then return end
    local ft = args.item or "?"
    local J = Kaandther.UI.journey[ft] or { tries = 0, fails = 0, protects = 0 }
    J.tries = J.tries + 1
    if args.mode == "DOWNGRADE" or args.mode == "MISS" then J.fails = J.fails + 1 end
    if args.mode == "PROTECT" then J.protects = J.protects + 1 end
    Kaandther.UI.journey[ft] = J
    local pl = getPlayer()
    -- sync client's held item so the window updates in realtime (server changed its copy)
    local held = pl and pl:getPrimaryHandItem()
    if held and instanceof(held, "HandWeapon") and held:getFullType() == ft then
        local md = held:getModData()
        local key = (args.track == "guard") and "akaGP" or "akaPP"
        if args.newPlus ~= nil then md[key] = args.newPlus end
        if args.progress ~= nil then md.akaPB = args.progress
        elseif args.ok then md.akaPB = 0 end
    end
    local base = { name = shortName(ft), from = args.cur, tries = J.tries, fails = J.fails, protects = J.protects,
        user = (pl and pl:getUsername()) or "?", day = (getGameTime and getGameTime():getNightsSurvived()) or 0 }
    if args.ok then
        base.kind, base.tier, base.to = "success", args.newPlus, args.newPlus
        Kaandther.UI.showResult(base); Kaandther.UI.journey[ft] = nil
    elseif args.mode == "DOWNGRADE" then
        base.kind, base.tier, base.to = "fail", args.cur, args.newPlus
        Kaandther.UI.showResult(base)
    elseif args.mode == "PROTECT" and args.progress == nil then
        base.kind, base.tier, base.to = "protect", args.cur, args.cur
        Kaandther.UI.showResult(base)
    elseif pl and args.progress ~= nil then
        local p = math.floor(args.progress)
        if args.mode == "MISS" then pl:setHaloNote("Kaandther: MISS   bar " .. p .. "%", 230, 120, 90, 250)
        elseif args.mode == "PROTECT" then pl:setHaloNote("Kaandther: charm saved you   bar " .. p .. "%", 150, 200, 255, 250)
        else pl:setHaloNote("Kaandther: +progress   bar " .. p .. "%", 150, 200, 140, 250) end
    end
end
function Kaandther.Enhance.onReject(why)
    local pl = getPlayer()
    if not pl then return end
    local msg = ({
        mats   = "not enough materials",
        noblue = "need a Blue Mushroom to enhance",
        offline= "station is off",
        event  = "event not active",
        needgold = "need a Gold Mushroom for the event tier",
        trackoff = "this track is off for this weapon",
        max    = "already max on this track",
        toofar = "stand next to the station to enhance",
        offline = "no station here",
    })[why]
    if msg then pl:setHaloNote("Kaandther: " .. msg, 230, 160, 90, 250) end
end
