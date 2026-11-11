--[[ ============================================================
     kaandther  -  CATEGORY PRESETS (base-game weapons)
     Recommended dual-track configs per weapon type + a base-game
     fullType -> category map. Used by import / bulk-apply.
       POWER = accumulate (dmg)  : pct(hit) gainMin gainMax miss dmgMul
       GUARD = per-attempt (dur) : pct durMul
     Numbers scale by class: light/cheap upgrade easier (lower ceiling),
     heavy/premium harder (higher ceiling). * = event tier (Gold-gated).
     ============================================================ ]]
Kaandther = Kaandther or {}
local K = Kaandther
K.Presets = K.Presets or {}
local Pr = K.Presets

-- per-category numbers: power {tier,hit,gMin,gMax,miss,dmg}  guard {tier,pct,dur}
local NUM = {
    shortblade = {
        power = { {5,90,10,18,6,1.12}, {10,74,7,13,10,1.28}, {15,56,5,10,14,1.50}, {20,42,3,6,18,1.85} },
        guard = { {5,84,1.25}, {10,54,1.6}, {15,30,2.0} } },
    longblade = {
        power = { {5,85,8,15,8,1.15}, {10,68,6,11,12,1.35}, {15,50,4,8,16,1.60}, {20,38,2,5,20,2.00} },
        guard = { {5,80,1.3}, {10,50,1.7}, {15,26,2.2} } },
    blunt = {
        power = { {5,88,9,16,7,1.10}, {10,70,6,12,11,1.25}, {15,52,4,9,15,1.45}, {20,40,2,5,19,1.80} },
        guard = { {5,86,1.35}, {10,58,1.8}, {15,32,2.4} } },   -- durability-leaning
    axe = {
        power = { {5,82,8,14,9,1.18}, {10,64,5,10,13,1.40}, {15,46,4,7,17,1.70}, {20,34,2,4,22,2.10} },
        guard = { {5,78,1.3}, {10,48,1.7}, {15,24,2.2} } },
    spear = {
        power = { {5,86,9,15,8,1.12}, {10,66,6,11,13,1.30}, {15,48,4,8,17,1.55}, {20,36,2,5,21,1.90} },
        guard = { {5,72,1.2}, {10,42,1.5}, {15,20,1.9} } },   -- weaker guard (spears break)
    firearm = {
        power = { {5,80,7,13,10,1.12}, {10,60,5,9,14,1.28}, {15,42,3,7,18,1.50}, {20,30,2,4,24,1.80} },
        guard = { {5,76,1.25}, {10,46,1.6}, {15,24,2.0} } },
    improvised = {
        power = { {5,92,12,20,5,1.08}, {10,76,8,14,9,1.18}, {15,58,5,10,13,1.35} },  -- no *
        guard = { {5,80,1.2}, {10,50,1.5} } },
}

-- materials per category / tier
local BASEMAT = "Base.ScrapMetal"
local SECOND  = { longblade="Base.SmallSheetMetal", axe="Base.SmallSheetMetal", blunt="Base.DuctTape", spear="Base.Twine", firearm="Base.Screws" }
local AMT     = { [5]=2, [10]=3, [15]=5, [20]=8 }
local NAILS   = { [5]=2, [10]=3, [15]=4 }
local function matsFor(cat, tier)
    local mats = { { BASEMAT, AMT[tier] or 2 } }
    if tier >= 15 and SECOND[cat] then mats[#mats+1] = { SECOND[cat], tier==20 and 2 or 1 } end
    local cost = (tier==20) and { item=K.Config.GOLD_ITEM, amount=1 } or (NAILS[tier] and { item="Base.Nails", amount=NAILS[tier] })
    return mats, cost
end

-- build a full weapon profile from a category
function Pr.buildProfile(cat)
    local n = NUM[cat]; if not n then return nil end
    local prof = { enabled=true, power={tiers={}}, guard={tiers={}} }
    for _,t in ipairs(n.power) do
        local mats,cost = matsFor(cat, t[1])
        prof.power.tiers[#prof.power.tiers+1] = { tier=t[1], pct=t[2], gainMin=t[3], gainMax=t[4], missDrop=t[5],
            dmgMul=t[6], event=(t[1]==20) or nil, mats=mats, cost=cost }
    end
    for _,t in ipairs(n.guard) do
        local mats,cost = matsFor(cat, t[1])
        prof.guard.tiers[#prof.guard.tiers+1] = { tier=t[1], pct=t[2], durMul=t[3], mats=mats, cost=cost }
    end
    return prof
end
function Pr.categories() local c={} for k in pairs(NUM) do c[#c+1]=k end table.sort(c) return c end

-- base-game fullType -> category (common B42 weapons; runtime detector fills the rest)
Pr.MAP = {
    -- blunt
    ["Base.BaseballBat"]="blunt", ["Base.BaseballBatNails"]="blunt", ["Base.Crowbar"]="blunt",
    ["Base.Pipe"]="blunt", ["Base.MetalPipe"]="blunt", ["Base.LeadPipe"]="blunt", ["Base.PipeWrench"]="blunt",
    ["Base.Wrench"]="blunt", ["Base.Nightstick"]="blunt", ["Base.PoolCue"]="blunt", ["Base.WoodenMallet"]="blunt",
    ["Base.Hammer"]="blunt", ["Base.BallPeenHammer"]="blunt", ["Base.ClubHammer"]="blunt", ["Base.Sledgehammer"]="blunt", ["Base.Sledgehammer2"]="blunt",
    -- short blade
    ["Base.HuntingKnife"]="shortblade", ["Base.KitchenKnife"]="shortblade", ["Base.MeatCleaver"]="shortblade",
    ["Base.Screwdriver"]="shortblade", ["Base.LetterOpener"]="shortblade", ["Base.IcePick"]="shortblade",
    ["Base.Scalpel"]="shortblade", ["Base.HandFork"]="shortblade", ["Base.ButterKnife"]="shortblade", ["Base.Fork"]="shortblade", ["Base.Spoon"]="shortblade",
    -- long blade
    ["Base.Machete"]="longblade", ["Base.Katana"]="longblade",
    -- axe
    ["Base.Axe"]="axe", ["Base.HandAxe"]="axe", ["Base.WoodAxe"]="axe", ["Base.Hatchet"]="axe", ["Base.PickAxe"]="axe",
    -- spear
    ["Base.SpearCrafted"]="spear", ["Base.SpearScrewdriver"]="spear", ["Base.SpearKnife"]="spear",
    ["Base.SpearMachete"]="spear", ["Base.Spear"]="spear",
    -- improvised
    ["Base.TreeBranch"]="improvised", ["Base.Plank"]="improvised", ["Base.WoodenStick"]="improvised",
    ["Base.Rake"]="improvised", ["Base.GardenHoe"]="improvised", ["Base.Shovel"]="improvised", ["Base.Shovel2"]="improvised",
    -- firearm
    ["Base.Pistol"]="firearm", ["Base.Pistol2"]="firearm", ["Base.Pistol3"]="firearm", ["Base.Revolver"]="firearm",
    ["Base.Revolver_Short"]="firearm", ["Base.Revolver_Long"]="firearm", ["Base.Shotgun"]="firearm",
    ["Base.ShotgunSawnoff"]="firearm", ["Base.VarmintRifle"]="firearm", ["Base.HuntingRifle"]="firearm", ["Base.AssaultRifle"]="firearm", ["Base.AssaultRifle2"]="firearm",
}

-- runtime category detection: map first, then item Categories, else improvised
function Pr.categoryOf(ft)
    if Pr.MAP[ft] then return Pr.MAP[ft] end
    local ok, si = pcall(function() return getScriptManager():getItem(ft) end)
    if ok and si and si.getCategories then
        local cats = si:getCategories()
        local set = {}
        if cats then for i=0,cats:size()-1 do set[tostring(cats:get(i)):lower()]=true end end
        if set["axe"] then return "axe" end
        if set["spear"] then return "spear" end
        if set["smallblade"] or set["shortblade"] then return "shortblade" end
        if set["longblade"] then return "longblade" end
        if set["smallblunt"] or set["blunt"] then return "blunt" end
        if set["firearm"] then return "firearm" end
    end
    return "improvised"
end

--[[ admin helpers: apply a category preset to weapons ]]
function Kaandther.Admin.applyCategory(ft, cat)
    local prof = Pr.buildProfile(cat); if not prof then print("[kaandther] no preset: "..tostring(cat)); return end
    Kaandther.Admin.addWeapon(ft)
    Kaandther.Admin.setCat(ft, cat)
    for _,t in ipairs(prof.power.tiers) do Kaandther.Admin.setTier(ft,"power",t.tier,t) end
    for _,t in ipairs(prof.guard.tiers) do Kaandther.Admin.setTier(ft,"guard",t.tier,t) end
    print("[kaandther] "..ft.." -> preset '"..cat.."'")
end
function Kaandther.Admin.applyHeldCategory()
    local pl=getPlayer(); local w=pl and pl:getPrimaryHandItem()
    if not w or not instanceof(w,"HandWeapon") then if pl then pl:setHaloNote("Kaandther: hold a weapon first",230,160,90,250) end return end
    local ft=w:getFullType(); local cat=Pr.categoryOf(ft)
    Kaandther.Admin.applyCategory(ft, cat)
    if pl then pl:setHaloNote("Kaandther: "..(ft:gsub("^.-%.","")).." = "..cat,150,220,150,250) end
end
function Kaandther.Admin.importCategory(cat)
    local n=0
    for ft,c in pairs(Kaandther.Presets.MAP) do if c==cat then Kaandther.Admin.applyCategory(ft,cat); n=n+1 end end
    print("[kaandther] imported "..n.." '"..cat.."' weapons")
    local pl=getPlayer(); if pl and pl.setHaloNote then pl:setHaloNote("Kaandther: imported "..n.." "..cat,150,220,150,250) end
end
function Kaandther.Admin.importAll()
    for _,cat in ipairs(Kaandther.Presets.categories()) do Kaandther.Admin.importCategory(cat) end
end

-- make add default to the category preset (configures BOTH power + guard)
function Kaandther.Admin.addHeld() Kaandther.Admin.applyHeldCategory() end
function Kaandther.Admin.addType(ft)
    if not ft or ft=="" then return end
    if not ft:find("%.") then ft="Base."..ft end
    Kaandther.Admin.applyCategory(ft, Kaandther.Presets.categoryOf(ft))
end

-- apply a custom set: weapons grouped under `name`, numbers from `numbersCat`
function Kaandther.Admin.applyCustom(name, numbersCat, weapons)
    local prof = Pr.buildProfile(numbersCat or "improvised"); if not prof then return end
    for _,ft in ipairs(weapons or {}) do
        if ft and ft~="" then
            Kaandther.Admin.addWeapon(ft); Kaandther.Admin.setCat(ft, name)
            for _,t in ipairs(prof.power.tiers) do Kaandther.Admin.setTier(ft,"power",t.tier,t) end
            for _,t in ipairs(prof.guard.tiers) do Kaandther.Admin.setTier(ft,"guard",t.tier,t) end
        end
    end
    Kaandther.Admin.saveCustom(name, numbersCat, weapons)
    print("[kaandther] custom set '"..tostring(name).."' -> "..#(weapons or {}).." weapons ("..tostring(numbersCat).." numbers)")
end
