--[[ ============================================================
     kaandther  -  RO-style item enhancement for B42 Multiplayer
     DUAL-TRACK:
       POWER  = accumulate% (damage min+max)  ladder 1/5/10/15/20(EVENT *)
       GUARD  = per-attempt (durability)       ladder 1/5/10/15
     charm  = prevents a TIER DROP (both tracks). Red <=15, Gold all + unlock *
     event  = admin toggle; * tier needs event ON + Gold ball in hand
     ============================================================ ]]
Kaandther = Kaandther or {}
local K = Kaandther
K.VERSION = "0.13.2"
K.BUILD   = "kaandther-0.13.2-register-license"

--[[ 1) ORIGIN ============================================== ]]
K.Origin = K.Origin or {}
local O = K.Origin
local function djb2(s) local h=5381 for i=1,#s do h=((h*33)+string.byte(s,i))%4294967296 end return h end
local FRAG = { {107,97,97,110,100,116,104,101,114}, {65,75,65}, {80,105,101} }
local function frag(t) local b={} for i=1,#t do b[i]=string.char(t[i]) end return table.concat(b) end
function O.token() return frag(FRAG[1])..":"..frag(FRAG[2])..":"..frag(FRAG[3]) end
O.EXPECTED_SEAL = 1725873910
function O.stamp(md) if type(md)=="table" then md.akaOrigin=O.token(); md.akaSeal=O.EXPECTED_SEAL end end
function O.verify(md) return type(md)=="table" and md.akaOrigin==O.token() and md.akaSeal==O.EXPECTED_SEAL end
function O.selfCheck()
    local live=djb2(O.token()); local ok=(live==O.EXPECTED_SEAL)
    print(("[kaandther] origin self-check: %s (seal=%d)"):format(ok and "OK" or "TAMPERED", live)); return ok
end
function K.isSP() return (not isClient()) and (not isServer()) end
function K.side() if K.isSP() then return "SP" end if isServer() then return "SERVER" end return "CLIENT" end
local function isAuthority() return isServer() or K.isSP() end

--[[ 2) CONFIG ============================================== ]]
K.Config = K.Config or {}
local C = K.Config

C.STAR = 20
C.POWER_MS = { 1, 5, 10, 15, C.STAR }
C.GUARD_MS = { 1, 5, 10, 15 }
C.COLOR = { [1]={0.70,0.70,0.70}, [5]={0.30,0.60,1.00}, [10]={0.65,0.35,0.95}, [15]={1.00,0.80,0.20}, [20]={1.00,0.45,0.30} }

C.RED_ITEM  = "Base.kaandther_red_ball"
C.GOLD_ITEM = "Base.kaandther_gold_ball"
C.BLUE_ITEM = "Base.kaandther_blue_mushroom"
C.BLUECOST = (C.BLUECOST~=nil) and C.BLUECOST or 1      -- fallback only; sandbox is the source of truth
C.BLUEDROP = (C.BLUEDROP~=nil) and C.BLUEDROP or 0.03
C.RED_MAX  = 15                                        -- Red mushroom only covers up to +15
-- all four numbers live in server Sandbox now (Kaandther page). Fallbacks used only pre-init / SP without sandbox.
function C.blueCost()  local sv=SandboxVars and SandboxVars.Kaandther; if sv and sv.BlueCost~=nil  then return sv.BlueCost end      return C.BLUECOST or 1 end
function C.blueDrop()  local sv=SandboxVars and SandboxVars.Kaandther; if sv and sv.BlueDrop~=nil  then return sv.BlueDrop/100 end   return C.BLUEDROP or 0 end
function C.redGuard()  local sv=SandboxVars and SandboxVars.Kaandther; if sv and sv.RedGuard~=nil  then return sv.RedGuard end       return 50  end
function C.goldGuard() local sv=SandboxVars and SandboxVars.Kaandther; if sv and sv.GoldGuard~=nil then return sv.GoldGuard end      return 100 end

C.WEAPONS = C.WEAPONS or {}
C.PROTECT = C.PROTECT or {}
C.PRESETS = C.PRESETS or {}
C.EVENT   = C.EVENT or { active = false }
C.CATORDER = C.CATORDER or { "blunt","shortblade","longblade","axe","spear","firearm","improvised","other" }
C.CUSTOM   = C.CUSTOM or {}   -- name -> {cat=<numbers category>, weapons={ft,...}}

function C.defaultProtect()
    return {
        { item=C.RED_ITEM,  name="Red Mushroom Ball",  maxTier=15 },   -- up to +15
        { item=C.GOLD_ITEM, name="Gold Mushroom Ball", maxTier=nil },  -- all + unlocks *
    }
end
function C.defaultWeapon()
    return {
        enabled = true,
        power = { on = true, tiers = {
            { tier=5,  pct=85, gainMin=8, gainMax=15, missDrop=8,  dmgMul=1.10, mats={{"Base.ScrapMetal",3}}, cost={item="Base.Nails",amount=2} },
            { tier=10, pct=70, gainMin=6, gainMax=12, missDrop=12, dmgMul=1.25, mats={{"Base.ScrapMetal",5}}, cost={item="Base.Nails",amount=4} },
            { tier=15, pct=55, gainMin=4, gainMax=9,  missDrop=15, dmgMul=1.50, mats={{"Base.ScrapMetal",8}}, cost={item="Base.Nails",amount=6} },
            { tier=20, pct=40, gainMin=2, gainMax=5,  missDrop=20, dmgMul=1.80, event=true, mats={{"Base.ScrapMetal",12}}, cost={item="Base.kaandther_gold_ball",amount=1} },
        }},
        guard = { on = true, tiers = {
            { tier=5,  pct=80, durMul=1.3, mats={{"Base.ScrapMetal",2}}, cost=nil },
            { tier=10, pct=50, durMul=1.7, mats={{"Base.ScrapMetal",4}}, cost=nil },
            { tier=15, pct=25, durMul=2.2, mats={{"Base.ScrapMetal",6}}, cost=nil },
        }},
    }
end
function C.defaultWeapons() return { ["Base.BaseballBat"] = C.defaultWeapon() } end

-- lookups ------------------------------------------------------
function C.profile(ft) return ft and C.WEAPONS and C.WEAPONS[ft] or nil end
function C.isEnhanceable(ft) local p=C.profile(ft) return p~=nil and p.enabled==true end
function C.colorFor(p) return C.COLOR[p] or C.COLOR[1] end
function C.msList(track) return track=="guard" and C.GUARD_MS or C.POWER_MS end
function C.trackTiers(ft, track)
    local p=C.profile(ft); if not p then return nil end
    local tk=p[track]; return tk and tk.tiers or nil
end
function C.tierEntry(ft, track, m)
    local tiers=C.trackTiers(ft, track); if not tiers then return nil end
    for _,t in ipairs(tiers) do if t.tier==m then return t end end
    return nil
end
function C.nextMS(track, cur)
    local ms=C.msList(track)
    for i=1,#ms do if ms[i]==cur then return ms[i+1] end end
    return nil
end
function C.prevMS(track, cur)
    local ms=C.msList(track)
    for i=1,#ms do if ms[i]==cur then return ms[i-1] or ms[1] end end
    return ms[1]
end
function C.isMaxMS(track, cur) local ms=C.msList(track); return cur==ms[#ms] end
function C.isStar(m) return m==C.STAR end

-- step from cur -> next for a track
function C.stepFor(ft, track, cur)
    local nxt=C.nextMS(track, cur); if not nxt then return nil end
    local t=C.tierEntry(ft, track, nxt); if not t then return nil end
    return { to=nxt, pct=t.pct or 0, mats=t.mats or {}, cost=t.cost, event=t.event==true,
             gainMin=t.gainMin or 6, gainMax=t.gainMax or 12, missDrop=t.missDrop or 0,
             dmgMul=t.dmgMul, durMul=t.durMul }
end
function C.powerMul(ft, plus) local t=C.tierEntry(ft,"power",plus); return t and t.dmgMul or nil end
function C.guardMul(ft, plus) local t=C.tierEntry(ft,"guard",plus); return t and t.durMul or nil end

function C.eventActive() return C.EVENT and C.EVENT.active==true end
function C.trackEnabled(ft, track)
    local w=C.profile(ft); if not w then return false end
    local tk=w[track]; return tk~=nil and tk.on~=false
end
function C.catOf(ft)
    local w=C.profile(ft)
    if w and w.cat then return w.cat end
    if Kaandther.Presets and Kaandther.Presets.categoryOf then return Kaandther.Presets.categoryOf(ft) end
    return "other"
end

-- charm chooser: which held mushroom guards this attempt, and its % chance to block a drop.
-- Gold preferred (covers ALL tiers, chance = GoldGuard). Red only up to +RED_MAX (chance = RedGuard).
-- returns  item, chancePercent   (or nil if none applies)
function C.chooseCharm(inv, toTier)
    if inv:getItemCount(C.GOLD_ITEM)>0 then return C.GOLD_ITEM, C.goldGuard() end
    if inv:getItemCount(C.RED_ITEM)>0 and toTier<=C.RED_MAX then return C.RED_ITEM, C.redGuard() end
    return nil
end
function C.hasGold(inv) return inv:getItemCount(C.GOLD_ITEM)>0 end

-- persistence --------------------------------------------------
-- migrate an old single-track weapon {tiers=...,mode=...} -> dual-track {power,guard}
local function migrateWeapon(w)
    if type(w)~="table" then return w end
    if w.power or w.guard then w.power=w.power or {tiers={}}; w.guard=w.guard or {tiers={}}; return w end
    local power={tiers={}}; local guard={tiers={}}
    if type(w.tiers)=="table" then
        for _,t in ipairs(w.tiers) do
            power.tiers[#power.tiers+1]={ tier=t.tier, pct=t.pct or 85, gainMin=t.gainMin or 6, gainMax=t.gainMax or 12,
                missDrop=t.missDrop or 10, dmgMul=t.dmgMul or 1, mats=t.mats or {}, cost=t.cost, event=(t.tier==20) or nil }
            if t.clcMul then guard.tiers[#guard.tiers+1]={ tier=t.tier, pct=t.pct or 80, durMul=t.clcMul, mats=t.mats or {}, cost=t.cost } end
        end
    end
    power.on=true; guard.on=true; w.power=power; w.guard=guard; w.tiers=nil; w.mode=nil
    return w
end
function C.migrateAll()
    for ft,w in pairs(C.WEAPONS or {}) do
        C.WEAPONS[ft]=migrateWeapon(w)
        if type(C.WEAPONS[ft])=="table" and not C.WEAPONS[ft].cat then
            local cat="other"
            if Kaandther.Presets and Kaandther.Presets.categoryOf then pcall(function() cat=Kaandther.Presets.categoryOf(ft) end) end
            C.WEAPONS[ft].cat=cat
        end
    end
end

function C.modData() if not ModData or not ModData.getOrCreate then return nil end return ModData.getOrCreate("kaandther_Config") end
function C.load()
    local md=C.modData(); if not md then return C end
    if isAuthority() then
        if type(md.WEAPONS)~="table" then md.WEAPONS=C.defaultWeapons() end
        if type(md.PROTECT)~="table" then md.PROTECT=C.defaultProtect() end
        if type(md.PRESETS)~="table" then md.PRESETS={} end
        if type(md.EVENT)~="table" then md.EVENT={active=false} end
        if type(md.CATORDER)~="table" then md.CATORDER=C.CATORDER end
        if type(md.CUSTOM)~="table" then md.CUSTOM={} end
        if md.BLUECOST==nil then md.BLUECOST=C.BLUECOST end
        if md.BLUEDROP==nil then md.BLUEDROP=C.BLUEDROP end
    end
    C.WEAPONS=md.WEAPONS or {}; C.PROTECT=md.PROTECT or C.defaultProtect()
    C.PRESETS=md.PRESETS or {}; C.EVENT=md.EVENT or {active=false}
    C.CATORDER=md.CATORDER or C.CATORDER
    C.CUSTOM=md.CUSTOM or {}
    if md.BLUECOST~=nil then C.BLUECOST=md.BLUECOST end
    if md.BLUEDROP~=nil then C.BLUEDROP=md.BLUEDROP end
    C.migrateAll()                       -- convert any old single-track weapons
    if isAuthority() then md.WEAPONS=C.WEAPONS end
    return C
end
function C.save()
    local md=C.modData(); if not md then return end
    md.WEAPONS,md.PROTECT,md.PRESETS,md.EVENT,md.CATORDER,md.CUSTOM = C.WEAPONS,C.PROTECT,C.PRESETS,C.EVENT,C.CATORDER,C.CUSTOM
    md.BLUECOST,md.BLUEDROP = C.BLUECOST,C.BLUEDROP
    if isAuthority() and ModData.transmit then ModData.transmit("kaandther_Config") end
end

--[[ 3) STATS =============================================== ]]
K.Stats = K.Stats or {}
local S = K.Stats
-- weapon display prefix: "(<power>)(<guard>) " -> e.g. (+10)(+5), (Event)(+5), (+10)(+0).
-- power star tier shows "Event"; a track still at base shows "+0". nil = no enhancement.
function K.namePrefix(pp, gp)
    pp = pp or 1; gp = gp or 1
    if pp <= 1 and gp <= 1 then return nil end
    local ps = C.isStar(pp) and "Event" or ("+" .. (pp > 1 and pp or 0))
    local gs = "+" .. (gp > 1 and gp or 0)
    return "(" .. ps .. ")(" .. gs .. ") "
end
local function captureBase(item, md)
    if md.akaBaseDmg==nil and item.getMaxDamage then md.akaBaseDmg=item:getMaxDamage() end
    if md.akaBaseMin==nil and item.getMinDamage then md.akaBaseMin=item:getMinDamage() end
    if md.akaBaseCLC==nil and item.getConditionLowerChance then md.akaBaseCLC=item:getConditionLowerChance() end
    if md.akaBaseName==nil and item.getName then md.akaBaseName=item:getName() end
end
function S.apply(item)
    if not item or not instanceof(item,"HandWeapon") then return end
    local md=item:getModData(); captureBase(item, md)
    local ft=item:getFullType()
    local pw = md.akaPP and C.powerMul(ft, md.akaPP) or nil
    local gd = md.akaGP and C.guardMul(ft, md.akaGP) or nil
    local dm = pw or 1
    if md.akaBaseDmg and item.setMaxDamage then item:setMaxDamage(md.akaBaseDmg*dm) end
    if md.akaBaseMin and item.setMinDamage then item:setMinDamage(md.akaBaseMin*dm) end
    if md.akaBaseCLC and item.setConditionLowerChance then item:setConditionLowerChance(math.floor(md.akaBaseCLC*(gd or 1))) end
    if md.akaBaseName and item.setName then
        local pref = K.namePrefix(md.akaPP, md.akaGP)
        item:setName(pref and (pref..md.akaBaseName) or md.akaBaseName)
    end
end
local lastPrimary={}
Events.OnPlayerUpdate.Add(function(player)
    if not player then return end
    local idx=player:getPlayerNum(); local w=player:getPrimaryHandItem()
    if w~=lastPrimary[idx] then lastPrimary[idx]=w if w then S.apply(w) end end
end)
local scanTick=0
Events.OnTick.Add(function()
    scanTick=scanTick+1; if scanTick<60 then return end scanTick=0
    local pl=getPlayer(); if not pl then return end
    local inv=pl:getInventory(); if not inv then return end
    local items=inv:getItems()
    for i=0,items:size()-1 do
        local it=items:get(i)
        if it and instanceof(it,"HandWeapon") then
            local md=it:getModData()
            if md and ((md.akaPP and md.akaPP>1) or (md.akaGP and md.akaGP>1)) then
                local want=K.namePrefix(md.akaPP, md.akaGP)
                if want and it:getName():sub(1,#want)~=want then S.apply(it) end
            end
        end
    end
end)

--[[ 5) ENHANCE ============================================= ]]
K.Enhance = K.Enhance or {}
local E = K.Enhance
E.POWER, E.GUARD = "power", "guard"

local function plusKey(track) return track=="guard" and "akaGP" or "akaPP" end
local function curOf(md, track) return md[plusKey(track)] or 1 end

function E.resolveTarget(player,item) if item then return item end return player and player:getPrimaryHandItem() or nil end
local function hasMats(inv, step)
    for _,m in ipairs(step.mats) do if inv:getItemCount(m[1])<m[2] then return false end end
    if step.cost and inv:getItemCount(step.cost.item)<step.cost.amount then return false end
    return true
end
local function removeOneServer(inv,item) if not item then return end inv:Remove(item) sendRemoveItemFromContainer(inv,item) end
local function removeTypeServer(inv, fullType)
    local it=inv:FindAndReturn(fullType)
    if not it and inv.getFirstTypeRecurse then it=inv:getFirstTypeRecurse(fullType) end
    if not it and inv.getItemFromType then it=inv:getItemFromType(fullType) end
    if it then removeOneServer(inv,it); return true end
    return false
end
local function consumeServer(inv,step)
    for _,m in ipairs(step.mats) do for _=1,m[2] do removeOneServer(inv,inv:FindAndReturn(m[1])) end end
    if step.cost then for _=1,step.cost.amount do removeOneServer(inv,inv:FindAndReturn(step.cost.item)) end end
end
local function randSpan(a,b) return a+ZombRand(math.max(1,(b-a)+1)) end

-- rebuild weapon carrying condition + BOTH track plus values + power bar
local function rebuild(player, inv, w, ppNew, pbNew, gpNew)
    local ftype=w:getFullType(); local cond=(w.getCondition and w:getCondition()) or nil
    local om=w:getModData()
    if player:getPrimaryHandItem()==w then player:setPrimaryHandItem(nil) end
    removeOneServer(inv,w)
    local nw=inv:AddItem(ftype); local md=nw:getModData()
    md.akaPP = (ppNew and ppNew~=1) and ppNew or nil
    md.akaPB = pbNew
    md.akaGP = (gpNew and gpNew~=1) and gpNew or nil
    -- carry any base captures
    md.akaBaseDmg,md.akaBaseMin,md.akaBaseCLC,md.akaBaseName = om.akaBaseDmg,om.akaBaseMin,om.akaBaseCLC,om.akaBaseName
    K.Origin.stamp(md)
    if cond and nw.setCondition then nw:setCondition(cond) end
    S.apply(nw); sendAddItemToContainer(inv,nw)
    return nw
end
local function reject(player, why) sendServerCommand(player,"kaandther","result",{fail=why}) end

local function serverAttempt(player, args)
    local key=args and args.key
    local track=(args and args.track)=="guard" and "guard" or "power"
    if not (K.Station and K.Station.isEnabledKey(key)) then return reject(player,"offline") end
    if key and K.Station and K.Station.nearKey and not K.Station.nearKey(player, key, 2) then return reject(player,"toofar") end
    local w=player:getPrimaryHandItem()
    if not w or not instanceof(w,"HandWeapon") then return reject(player,"notarget") end
    local ft=w:getFullType()
    if not C.isEnhanceable(ft) then return reject(player,"notconfig") end
    if not C.trackTiers(ft, track) then return reject(player,"notrack") end
    if not C.trackEnabled(ft, track) then return reject(player,"trackoff") end
    local inv=player:getInventory()
    local md=w:getModData()
    local cur=curOf(md, track)
    if C.isMaxMS(track, cur) then return reject(player,"max") end
    local step=C.stepFor(ft, track, cur)
    if not step then return reject(player,"nostep") end
    -- * event gating
    if step.event then
        if not C.eventActive() then return reject(player,"event") end
        if not C.hasGold(inv) then return reject(player,"needgold") end
    end
    if not hasMats(inv, step) then return reject(player,"mats") end
    local blueCost = C.blueCost()
    if blueCost > 0 and inv:getItemCount(C.BLUE_ITEM) < blueCost then return reject(player,"noblue") end
    consumeServer(inv, step)
    if blueCost > 0 then for _=1,blueCost do removeOneServer(inv, inv:FindAndReturn(C.BLUE_ITEM)) end end

    if track=="power" then
        -- charm held is consumed EVERY attempt; on a would-be drop it rolls its % to block (Red=RedGuard, Gold=GoldGuard)
        local charm, chChance = C.chooseCharm(inv, step.to)
        if charm then removeTypeServer(inv,charm); print("[kaandther][SV] charm consumed (power): "..tostring(charm).." @"..tostring(chChance).."%") end
        local hit=ZombRand(100) < step.pct
        local prog=md.akaPB or 0
        local saved=false
        if hit then prog=prog+randSpan(step.gainMin,step.gainMax)
        else
            prog=prog-step.missDrop
            if prog<0 then
                if charm and ZombRand(100) < (chChance or 0) then prog=0; saved=true   -- charm blocked the drop
                else
                    local pv=C.prevMS("power",cur)
                    rebuild(player,inv,w,pv,60,md.akaGP)
                    if key and K.Station then K.Station.appendLog(key,{u=player:getUsername(),item=(ft:gsub("^.-%.","")),from=cur,to=pv,res="DOWNGRADE"}) end
                    return sendServerCommand(player,"kaandther","result",{ok=false,mode="DOWNGRADE",track="power",cur=cur,newPlus=pv,item=ft,progress=60})
                end
            end
        end
        if prog>=100 then
            rebuild(player,inv,w,step.to,nil,md.akaGP)
            if key and K.Station then K.Station.appendLog(key,{u=player:getUsername(),item=(ft:gsub("^.-%.","")),from=cur,to=step.to,res="SUCCESS"}) end
            return sendServerCommand(player,"kaandther","result",{ok=true,mode="SUCCESS",track="power",cur=cur,newPlus=step.to,item=ft,progress=0,star=C.isStar(step.to)})
        else
            md.akaPB=prog
            if w.transmitModData then w:transmitModData() end
            local res=saved and "PROTECT" or (hit and "PROGRESS" or "MISS")
            if key and K.Station then K.Station.appendLog(key,{u=player:getUsername(),item=(ft:gsub("^.-%.","")),from=cur,to=cur,res=res}) end
            return sendServerCommand(player,"kaandther","result",{ok=false,mode=res,track="power",cur=cur,newPlus=cur,item=ft,progress=prog})
        end
    else
        -- GUARD: per-attempt; charm consumed every attempt, rolls its % to block a downgrade
        local charm, chChance = C.chooseCharm(inv, step.to)
        if charm then removeTypeServer(inv,charm); print("[kaandther][SV] charm consumed (guard): "..tostring(charm).." @"..tostring(chChance).."%") end
        local ok=ZombRand(100)<step.pct
        local newPlus,res
        if ok then newPlus,res=step.to,"SUCCESS"
        else
            if charm and ZombRand(100) < (chChance or 0) then newPlus,res=cur,"PROTECT"
            else newPlus,res=C.prevMS("guard",cur),"DOWNGRADE" end
        end
        rebuild(player,inv,w,md.akaPP,md.akaPB,newPlus)
        if key and K.Station then K.Station.appendLog(key,{u=player:getUsername(),item=(ft:gsub("^.-%.","")),from=cur,to=newPlus,res=res}) end
        return sendServerCommand(player,"kaandther","result",{ok=(res=="SUCCESS"),mode=res,track="guard",cur=cur,newPlus=newPlus,pct=step.pct,item=ft})
    end
end

function E.attempt(player, item, track, stationKey)
    player=player or getPlayer(); track=track or "power"
    local w=E.resolveTarget(player,item)
    if not w or not instanceof(w,"HandWeapon") then print("[kaandther] no weapon"); return end
    if not C.isEnhanceable(w:getFullType()) then print("[kaandther] not configured"); return end
    if not K.isSP() then sendClientCommand(player,"kaandther","attempt",{key=stationKey,track=track}); return end
    -- SP: reuse server logic with a stub sender captured by onResult
    serverAttempt(player,{key=stationKey,track=track})
end

local function serverGiveMats(player, track)
    track = track=="guard" and "guard" or "power"
    local w=player:getPrimaryHandItem(); local ft=(w and instanceof(w,"HandWeapon")) and w:getFullType() or nil
    local cur=(w and curOf(w:getModData(),track)) or 1
    local step=ft and C.stepFor(ft,track,cur); if not step then print("[kaandther][SV] giveMats: no step"); return end
    local inv=player:getInventory()
    for _,m in ipairs(step.mats) do for _=1,m[2] do sendAddItemToContainer(inv,inv:AddItem(m[1])) end end
    if step.cost then for _=1,step.cost.amount do sendAddItemToContainer(inv,inv:AddItem(step.cost.item)) end end
end

Events.OnClientCommand.Add(function(module,command,player,args)
    if module~="kaandther" then return end
    if command=="attempt" then serverAttempt(player,args)
    elseif command=="giveMats" then serverGiveMats(player, args and args.track)
    elseif command=="getcfg" then C.load(); sendServerCommand(player,"kaandther","cfgdata",{ w=C.WEAPONS, p=C.PROTECT, e=C.EVENT, co=C.CATORDER, cu=C.CUSTOM, bc=C.BLUECOST, bd=C.BLUEDROP })
    elseif command=="give" then
        local lvl=player.getAccessLevel and tostring(player:getAccessLevel()):lower()
        if lvl=="admin" or lvl=="moderator" or lvl=="gm" then
            local inv=player:getInventory(); for _=1,(args.n or 1) do sendAddItemToContainer(inv, inv:AddItem(args.item)) end
        end
    elseif command=="stats" then
        local lines=(K.Station and K.Station.computeStats and K.Station.computeStats()) or {"[kaandther] no stats"}
        sendServerCommand(player,"kaandther","cfgReload",{lines=lines})
    elseif command=="setco" then K.Admin.serverApply(player,{op="setCatOrder",list=args.list})
    elseif command=="cfg" then K.Admin.serverApply(player,args) end
end)

Events.OnServerCommand.Add(function(module,command,args)
    if module~="kaandther" then return end
    if command=="result" then
        if args.fail then print("[kaandther] rejected: "..tostring(args.fail)); K.Enhance.onReject(args.fail); return end
        K.Enhance.onResult(args)
        local pl=getPlayer()
        if pl then local inv=pl:getInventory(); local items=inv:getItems()
            for i=0,items:size()-1 do local it=items:get(i)
                if it and instanceof(it,"HandWeapon") then local m=it:getModData() if m and (m.akaPP or m.akaGP) then S.apply(it) end end end end
    elseif command=="cfgdata" then
        local md=C.modData()
        if md then if type(args.w)=="table" then md.WEAPONS=args.w end if type(args.p)=="table" then md.PROTECT=args.p end if type(args.e)=="table" then md.EVENT=args.e end if type(args.co)=="table" then md.CATORDER=args.co end if type(args.cu)=="table" then md.CUSTOM=args.cu end if args.bc~=nil then md.BLUECOST=args.bc end if args.bd~=nil then md.BLUEDROP=args.bd end end
        C.WEAPONS=args.w or C.WEAPONS or {}; C.PROTECT=(type(args.p)=="table" and args.p) or C.PROTECT
        C.EVENT=(type(args.e)=="table" and args.e) or C.EVENT or {active=false}
        C.CATORDER=(type(args.co)=="table" and args.co) or C.CATORDER
        C.CUSTOM=(type(args.cu)=="table" and args.cu) or C.CUSTOM or {}
        if args.bc~=nil then C.BLUECOST=args.bc end
        if args.bd~=nil then C.BLUEDROP=args.bd end
        local n=0 for _ in pairs(C.WEAPONS) do n=n+1 end
        print("[kaandther] config received ("..n.." weapons, event="..tostring(C.eventActive())..")")
    elseif command=="cfgReload" then
        C.load(); if args.lines then for _,l in ipairs(args.lines) do print(l) end end
    end
end)
function K.Enhance.onResult(_) end
function K.Enhance.onReject(_) end

function E.giveTestMats(player, track)
    player=player or getPlayer(); track=track or "power"
    if K.isSP() then
        local w=E.resolveTarget(player,nil); local ft=w and instanceof(w,"HandWeapon") and w:getFullType() or nil
        local cur=(w and curOf(w:getModData(),track)) or 1
        local step=ft and C.stepFor(ft,track,cur); if not step then return end
        local inv=player:getInventory()
        for _,m in ipairs(step.mats) do for _=1,m[2] do inv:AddItem(m[1]) end end
        if step.cost then for _=1,step.cost.amount do inv:AddItem(step.cost.item) end end
    else sendClientCommand(player,"kaandther","giveMats",{track=track}) end
end

function K.requestConfig()
    if not isClient() then return end
    if ModData and ModData.request then pcall(function() ModData.request("kaandther_Config") end) end
    local pl=getPlayer(); if pl then sendClientCommand(pl,"kaandther","getcfg",{}) end
end

--[[ 6) ADMIN ============================================== ]]
K.Admin = K.Admin or {}
local A = K.Admin
local function staffNow()
    local pl=getPlayer(); local lvl=pl and pl.getAccessLevel and tostring(pl:getAccessLevel()):lower()
    return lvl=="admin" or lvl=="moderator" or lvl=="gm" or K.isSP()
end
local function dcopy(v) if type(v)~="table" then return v end local o={} for k,val in pairs(v) do o[k]=dcopy(val) end return o end
local function ensureWeapon(ft)
    local w=C.WEAPONS[ft]
    if not w then w=C.defaultWeapon(); C.WEAPONS[ft]=w end
    w.power=w.power or {tiers={}}; w.guard=w.guard or {tiers={}}
    if w.power.on==nil then w.power.on=true end
    if w.guard.on==nil then w.guard.on=true end
    if not w.cat then local cat="other"; if Kaandther.Presets and Kaandther.Presets.categoryOf then pcall(function() cat=Kaandther.Presets.categoryOf(ft) end) end w.cat=cat end
    return w
end
local function setTierEntry(ft,track,tier,t)
    local w=ensureWeapon(ft); tier=tonumber(tier); if not tier then return end
    local tk=(track=="guard") and w.guard or w.power
    local e={ tier=tier, pct=tonumber(t and t.pct) or 0,
              dmgMul=tonumber(t and t.dmgMul) or nil, durMul=tonumber(t and t.durMul) or nil,
              gainMin=tonumber(t and t.gainMin) or 6, gainMax=tonumber(t and t.gainMax) or 12,
              missDrop=tonumber(t and t.missDrop) or 0, mats=(t and t.mats) or {}, cost=(t and t.cost) or nil,
              event=(t and t.event)==true or nil }
    for i,ex in ipairs(tk.tiers) do if ex.tier==tier then tk.tiers[i]=e; return end end
    table.insert(tk.tiers,e); table.sort(tk.tiers,function(a1,b1) return a1.tier<b1.tier end)
end
local function applyOp(a)
    local op=a.op
    if op=="addWeapon" then local w=ensureWeapon(a.ft); w.enabled=(a.enabled~=false)
    elseif op=="removeWeapon" then C.WEAPONS[a.ft]=nil
    elseif op=="enable" then if C.WEAPONS[a.ft] then C.WEAPONS[a.ft].enabled=(a.on==true) end
    elseif op=="setTier" then setTierEntry(a.ft,a.track,a.tier,a.t)
    elseif op=="removeTier" then local w=C.WEAPONS[a.ft]; local tk=w and ((a.track=="guard") and w.guard or w.power)
        if tk and tk.tiers then for i=#tk.tiers,1,-1 do if tk.tiers[i].tier==tonumber(a.tier) then table.remove(tk.tiers,i) end end end
    elseif op=="setProtect" then if type(a.list)=="table" then C.PROTECT=dcopy(a.list) end
    elseif op=="setEvent" then C.EVENT={active=(a.on==true)}
    elseif op=="setCat" then if C.WEAPONS[a.ft] then C.WEAPONS[a.ft].cat=a.cat end
    elseif op=="setCatOrder" then if type(a.list)=="table" then C.CATORDER=a.list end
    elseif op=="setBlue" then if a.cost~=nil then C.BLUECOST=math.max(0,math.floor(tonumber(a.cost) or 0)) end
                              if a.drop~=nil then C.BLUEDROP=math.max(0,math.min(1,tonumber(a.drop) or 0)) end
    elseif op=="setTrackOn" then local w=ensureWeapon(a.ft); if w[a.track] then w[a.track].on=(a.on==true) end
    elseif op=="saveCustom" then if a.name then C.CUSTOM[a.name]={cat=a.cat, weapons=a.weapons or {}} end
    elseif op=="delCustom" then if a.name then C.CUSTOM[a.name]=nil end
    elseif op=="reset" then C.WEAPONS=C.defaultWeapons(); C.PROTECT=C.defaultProtect(); C.EVENT={active=false}
    elseif op=="copyWeapon" then if C.WEAPONS[a.src] then C.WEAPONS[a.dst]=dcopy(C.WEAPONS[a.src]) end
    elseif op=="savePreset" then if a.name then C.PRESETS[a.name]={WEAPONS=dcopy(C.WEAPONS),PROTECT=dcopy(C.PROTECT)} end
    elseif op=="loadPreset" then local pr=a.name and C.PRESETS[a.name]
        if pr then C.WEAPONS=dcopy(pr.WEAPONS or {}); C.PROTECT=dcopy(pr.PROTECT or C.defaultProtect()) end
    end
end
function A.applyLocal(a) applyOp(a); C.save() end
local function route(op,data)
    data=data or {}; data.op=op
    if not staffNow() then print("[kaandther] admin: staff only"); return end
    A.applyLocal(data)
    if not K.isSP() then sendClientCommand(getPlayer(),"kaandther","cfg",data) end
end
function A.addWeapon(ft,en) route("addWeapon",{ft=ft,enabled=(en~=false)}) end
function A.removeWeapon(ft) route("removeWeapon",{ft=ft}) end
function A.enable(ft,on) route("enable",{ft=ft,on=(on~=false)}) end
function A.setTier(ft,track,tier,t) route("setTier",{ft=ft,track=track,tier=tier,t=t}) end
function A.removeTier(ft,track,tier) route("removeTier",{ft=ft,track=track,tier=tier}) end
function A.setProtect(list) route("setProtect",{list=list}) end
function A.setEvent(on) route("setEvent",{on=(on==true)}) end
function A.resetConfig() route("reset",{}) end
function A.setCat(ft,cat) route("setCat",{ft=ft,cat=cat}) end
function A.setTrackOn(ft,track,on) route("setTrackOn",{ft=ft,track=track,on=(on==true)}) end
function A.saveCustom(name,cat,weapons) route("saveCustom",{name=name,cat=cat,weapons=weapons}) end
function A.setBlue(cost,drop) route("setBlue",{cost=cost,drop=drop}) end
function A.delCustom(name) route("delCustom",{name=name}) end
function A.setCatOrder(list)
    if not staffNow() then return end
    A.applyLocal({op="setCatOrder",list=list})
    if not K.isSP() then sendClientCommand(getPlayer(),"kaandther","setco",{list=list}) end
end
function A.giveBundle()
    if not staffNow() then return end
    local items={"Base.ScrapMetal","Base.ScrapMetal","Base.Nails","Base.SmallSheetMetal","Base.DuctTape","Base.Screws","Base.Twine","Base.WeldingRods",C.RED_ITEM,C.GOLD_ITEM,C.BLUE_ITEM}
    for _,it in ipairs(items) do A.give(it, (it==C.GOLD_ITEM or it==C.RED_ITEM) and 3 or (it==C.BLUE_ITEM and 30 or 10)) end
end
function A.copyWeapon(s,d) route("copyWeapon",{src=s,dst=d}) end
-- copy one tier's config to EVERY tier of a track (+5/+10/+15[/+20]); event flag kept only on the star tier
function A.copyTierToAll(ft, track, t)
    if not ft or not t then return end
    local ms = C.msList(track)
    for _,m in ipairs(ms) do
        if m > 1 then
            local tt = dcopy(t); tt.tier = m
            if track=="power" then tt.event = (m==C.STAR) or nil end
            A.setTier(ft, track, m, tt)
        end
    end
end
function A.savePreset(n) route("savePreset",{name=n}) end
function A.loadPreset(n) route("loadPreset",{name=n}) end
local function seedTiers(ft) local w=C.defaultWeapon(); w.enabled=true; C.WEAPONS[ft]=nil
    A.addWeapon(ft)
    for _,t in ipairs(w.power.tiers) do A.setTier(ft,"power",t.tier,t) end
    for _,t in ipairs(w.guard.tiers) do A.setTier(ft,"guard",t.tier,t) end
end
function A.addHeld()
    local pl=getPlayer(); local wp=pl and pl:getPrimaryHandItem()
    if not wp or not instanceof(wp,"HandWeapon") then if pl then pl:setHaloNote("Kaandther: hold a weapon first",230,160,90,250) end return end
    local ft=wp:getFullType(); seedTiers(ft)
    if pl then pl:setHaloNote("Kaandther: added "..(ft:gsub("^.-%.","")),150,220,150,250) end
end
function A.addType(ft) if not ft or ft=="" then return end if not ft:find("%.") then ft="Base."..ft end seedTiers(ft)
    local pl=getPlayer(); if pl then pl:setHaloNote("Kaandther: added "..(ft:gsub("^.-%.","")),150,220,150,250) end end
function A.give(item,n) if not staffNow() then return end local pl=getPlayer()
    if K.isSP() then local inv=pl:getInventory() for _=1,(n or 1) do inv:AddItem(item) end else sendClientCommand(pl,"kaandther","give",{item=item,n=n or 1}) end end
function A.giveCharms() A.give(C.RED_ITEM,3); A.give(C.GOLD_ITEM,3) end
function A.toggleEvent() A.setEvent(not C.eventActive()) end

local function dumpLines()
    local L={ "[kaandther] === ตั้งค่าอาวุธทั้งหมด (Event="..(C.eventActive() and "เปิด" or "ปิด")..") ===" }
    local n=0
    for ft,w in pairs(C.WEAPONS) do n=n+1
        L[#L+1]=("  อาวุธ: %s  [%s]"):format(ft, w.enabled and "เปิดใช้งาน" or "ปิด")
        for _,tk in ipairs({{"POWER (พลังโจมตี)",w.power},{"GUARD (ความทนทาน)",w.guard}}) do
            for _,t in ipairs(tk[2] and tk[2].tiers or {}) do
                L[#L+1]=("     %s  เทียร์ +%d | โอกาสสำเร็จ %s%% | %s"):format(tk[1], t.tier,
                    tostring(t.pct or 0),
                    t.dmgMul and ("ดาเมจ x"..t.dmgMul) or (t.durMul and ("ต้านการเสื่อม x"..t.durMul) or "-"))
            end
        end
    end
    if n==0 then L[#L+1]="  (ยังไม่มีอาวุธที่ตั้งค่า)" end
    L[#L+1]="[kaandther] === จบการแสดงผล ==="
    return L
end
function A.dump() if K.isSP() then for _,l in ipairs(dumpLines()) do print(l) end else route("dump",{}) end end
function A.stats() if not staffNow() then return end local pl=getPlayer()
    if K.isSP() then local ln=K.Station and K.Station.computeStats and K.Station.computeStats() or {} for _,l in ipairs(ln) do print(l) end
    else sendClientCommand(pl,"kaandther","stats",{}) end end

function A.serverApply(player, a)
    if player and player.getAccessLevel and not K.isSP() then
        local lvl=tostring(player:getAccessLevel()):lower()
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
    end
    C.load(); applyOp(a); C.save()
    if player and not K.isSP() then
        sendServerCommand(player,"kaandther","cfgdata",{ w=C.WEAPONS, p=C.PROTECT, e=C.EVENT, co=C.CATORDER, cu=C.CUSTOM, bc=C.BLUECOST, bd=C.BLUEDROP })
    end
end

--[[ 4) BOOT =============================================== ]]
local function spriteSelfTest()
    local name="aka_table_plus_0"
    local hs=IsoSpriteManager and IsoSpriteManager.instance and IsoSpriteManager.instance:getSprite(name)~=nil
    local ht=(getTexture and getTexture(name)~=nil) or false
    print(("[kaandther] sprite '%s': getSprite=%s getTexture=%s [%s]"):format(name,tostring(hs),tostring(ht),K.side()))
end
local function boot()
    print(("[kaandther] BUILD=%s loaded (%s)"):format(K.BUILD,K.side()))
    O.selfCheck(); C.load(); spriteSelfTest(); K.requestConfig()
end
Events.OnGameStart.Add(boot)
if Events.OnServerStarted then Events.OnServerStarted.Add(boot) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(function() K.requestConfig() end) end

-- blue mushroom drop from zombies (server-authoritative, rate from sandbox)
if Events and Events.OnZombieDead then
    Events.OnZombieDead.Add(function(zombie)
        if not (isServer() or (Kaandther.isSP and Kaandther.isSP())) then return end
        if not zombie then return end
        local rate = Kaandther.Config.blueDrop()
        if rate <= 0 then return end
        if ZombRand(10000) < rate*10000 then
            pcall(function()
                local sq = zombie.getSquare and zombie:getSquare()
                if sq then
                    sq:AddWorldInventoryItem(Kaandther.Config.BLUE_ITEM, 0.5, 0.5, 0.0)
                    print("[kaandther][SV] blue mushroom dropped (rate "..tostring(rate)..")")
                end
            end)
        end
    end)
    print("[kaandther][SV] zombie blue-drop hook registered")
end
