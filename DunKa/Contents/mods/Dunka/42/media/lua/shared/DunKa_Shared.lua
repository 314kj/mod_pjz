--[[ ============================================================
   ____              _  __
  |  _ \ _   _ _ __ | |/ /__ _
  | | | | | | | '_ \| ' // _` |    PROJECT  DUNKA  [MP]
  | |_| | |_| | | | | . \ (_| |    shared : ranks / config /
  |____/ \__,_|_| |_|_|\_\__,_|    cooldown / staggered spawn
 ============================================================
  Runs on server, client, and singleplayer.
  Authoritative spawn + cooldown live here so SP works with no
  server file, and the MP server file just forwards to it.
============================================================ ]]--

DunKa = DunKa or {}

----------------------------------------------------------------
-- Rank definitions (slip rewards are fixed; zombie counts are
-- sandbox-overridable via DunKa.getRankCount)
----------------------------------------------------------------
DunKa.RANKS = {
    C = { id="C", item="Base.DunKa_KeyC", baseCount=50,  dropLoot=true,  slips={ White=2 } },
    B = { id="B", item="Base.DunKa_KeyB", baseCount=100, dropLoot=false, slips={ White=2, Yellow=1 } },
    A = { id="A", item="Base.DunKa_KeyA", baseCount=200, dropLoot=false, slips={ White=2, Yellow=1, Blue=1 } },
    S = { id="S", item="Base.DunKa_KeyS", baseCount=400, dropLoot=false, slips={ White=3, Yellow=3, Blue=3 } },
}
-- evaluation order high -> low (for "auto pick" / menu ordering)
DunKa.RANK_ORDER = { "S", "A", "B", "C" }

DunKa.SLIP_ITEM = {
    White  = "Base.DunKa_SlipWhite",
    Yellow = "Base.DunKa_SlipYellow",
    Blue   = "Base.DunKa_SlipBlue",
}

-- =====================================================================
--  SLIP LOOT TABLES  (edit by hand)
--  Right-click a slip -> "Open Slip" -> consumes 1 slip -> rolls loot.
--   rolls  = how many item-picks handed out per slip opened
--   weight = relative chance of that entry (bigger = more common)
--   min/max= quantity range for that entry
--  Unknown item ids are skipped safely, so tweak freely.
-- =====================================================================
DunKa.SLIP_LOOT = {
    White = {   -- common
        rolls = 2,
        loot = {
            { item = "Base.Nails",        min = 5, max = 15, weight = 30 },
            { item = "Base.RippedSheets", min = 2, max = 6,  weight = 25 },
            { item = "Base.TinnedBeans",  min = 1, max = 2,  weight = 20 },
            { item = "Base.Bandage",      min = 1, max = 3,  weight = 15 },
            { item = "Base.Screwdriver",  min = 1, max = 1,  weight = 10 },
        },
    },
    Yellow = {  -- uncommon
        rolls = 2,
        loot = {
            { item = "Base.Screws",      min = 5, max = 12, weight = 25 },
            { item = "Base.DuctTape",    min = 1, max = 2,  weight = 20 },
            { item = "Base.Pills",       min = 1, max = 2,  weight = 20 },
            { item = "Base.Hammer",      min = 1, max = 1,  weight = 15 },
            { item = "Base.Battery",     min = 1, max = 2,  weight = 12 },
            { item = "Base.Antibiotics", min = 1, max = 1,  weight = 8  },
        },
    },
    Blue = {    -- rare
        rolls = 3,
        loot = {
            { item = "Base.Bullets9mm",   min = 5, max = 15, weight = 25 },
            { item = "Base.SheetMetal",   min = 1, max = 3,  weight = 20 },
            { item = "Base.Wrench",       min = 1, max = 1,  weight = 18 },
            { item = "Base.HuntingKnife", min = 1, max = 1,  weight = 15 },
            { item = "Base.Pistol",       min = 1, max = 1,  weight = 12 },
            { item = "Base.Axe",          min = 1, max = 1,  weight = 10 },
        },
    },
}

-- ---------- live slip config (admin-editable, persisted in ModData) ----------
-- seeded once from SLIP_LOOT above; after that the admin editor owns it.
function DunKa.getSlipConfig()
    local md = ModData.getOrCreate("DunKaSlipCfg")
    if not md._init then
        for color, def in pairs(DunKa.SLIP_LOOT) do
            local c = { rolls = def.rolls or 1, guaranteed = {}, random = {} }
            for _, e in ipairs(def.loot or {}) do
                c.random[#c.random+1] = { item=e.item, min=e.min or 1, max=e.max or e.min or 1, weight=e.weight or 10 }
            end
            md[color] = c
        end
        md._init = true
    end
    -- migrate any legacy .loot -> .random ; ensure both tables exist
    for _, color in ipairs({ "White", "Yellow", "Blue" }) do
        local c = md[color]
        if c then
            c.guaranteed = c.guaranteed or {}
            c.random = c.random or {}
            if c.loot then
                for _, e in ipairs(c.loot) do c.random[#c.random+1] = e end
                c.loot = nil
            end
        end
    end
    return md
end
function DunKa.setSlipColor(color, rolls, guaranteed, random)
    local md = DunKa.getSlipConfig()
    md[color] = { rolls = math.max(1, rolls or 1), guaranteed = guaranteed or {}, random = random or {} }
end

-- roll a color's table -> list of { item = fulltype, qty = n }
function DunKa.rollSlipLoot(color)
    local def = DunKa.getSlipConfig()[color]; if not def then return {} end
    local out = {}
    -- guaranteed: always given
    for _, g in ipairs(def.guaranteed or {}) do
        out[#out+1] = { item = g.item, qty = g.qty or g.min or 1 }
    end
    -- random: roll `rolls` times weighted
    local pool = def.random or {}
    for _ = 1, (def.rolls or 1) do
        local total = 0
        for _, e in ipairs(pool) do total = total + (e.weight or 1) end
        if total <= 0 then break end
        local r = ZombRand(total) + 1
        local acc = 0
        for _, e in ipairs(pool) do
            acc = acc + (e.weight or 1)
            if r <= acc then
                local mn, mx = e.min or 1, e.max or e.min or 1
                local qty = mn
                if mx > mn then qty = mn + ZombRand(mx - mn + 1) end
                out[#out+1] = { item = e.item, qty = qty }
                break
            end
        end
    end
    return out
end

-- consume 1 slip of color from player, roll + give loot (server/SP authoritative)
function DunKa.openSlip(player, color)
    if not (player and DunKa.getSlipConfig()[color]) then return false, "bad" end
    local inv = player:getInventory(); if not inv then return false, "bad" end
    local ft = DunKa.SLIP_ITEM[color]
    local slip = ft and inv:FindAndReturn(ft)
    if not slip then return false, "no_slip" end
    inv:Remove(slip)
    if sendRemoveItemFromContainer then pcall(function() sendRemoveItemFromContainer(inv, slip) end) end
    local gained = DunKa.rollSlipLoot(color)
    local sm = getScriptManager()
    for _, g in ipairs(gained) do
        if sm and sm:FindItem(g.item) then
            for _ = 1, (g.qty or 1) do
                local it = inv:AddItem(g.item)
                if it and sendAddItemToContainer then pcall(function() sendAddItemToContainer(inv, it) end) end
            end
        end
    end
    return true, gained
end

-- sprite name painted by the horde box tile (from horde_aka.tiles ; registered
-- in mod.info via  pack=horde_aka  +  tiledef=horde_aka 337 )
DunKa.CABINET_SPRITE = "horde_aka_0"

----------------------------------------------------------------
-- env helpers
----------------------------------------------------------------
function DunKa.isSP()
    return (not isClient()) and (not isServer())
end

local function sv()
    return SandboxVars and SandboxVars.DunKa or nil
end

local function svInt(key, fallback)
    local s = sv()
    local v = s and s[key]
    if type(v) == "number" then return v end
    return fallback
end

----------------------------------------------------------------
-- config readers (live from sandbox, safe fallbacks)
----------------------------------------------------------------
function DunKa.getCooldownMs()    return svInt("CooldownMinutes", 10) * 60 * 3000 end
function DunKa.getRadius()        return svInt("SpawnRadius", 13) end
function DunKa.getSafetyCap()     return svInt("SafetyCap", 500) end
function DunKa.getTickInterval()  return math.max(1, svInt("SpawnTickInterval", 6)) end

-- per-player Boss Music toggle (client preference, stored on the player)
function DunKa.bossMusicOn(player)
    player = player or (getPlayer and getPlayer())
    local md = player and player.getModData and player:getModData()
    return not (md and md.DunKaBossMusic == false)        -- default ON
end
function DunKa.toggleBossMusic(player)
    player = player or (getPlayer and getPlayer())
    local md = player and player:getModData(); if not md then return true end
    md.DunKaBossMusic = (md.DunKaBossMusic == false) and true or false
    if player.setHaloNote then player:setHaloNote("Boss Music: "..(md.DunKaBossMusic~=false and "ON" or "OFF"), 250,240,150, 200) end
    return md.DunKaBossMusic ~= false
end

-- Boss Fight music. Plays on the summoner's client at normal volume and is
-- NOT tied to the UI panel, so closing the terminal does not stop it.
function DunKa.playBoss(player)
    if not DunKa.bossMusicOn(player) then print("[DunKa][SFX] boss music toggled OFF"); return end
    local sm = getSoundManager(); if not sm then print("[DunKa][SFX] no soundManager"); return end
    local sq = player and player.getSquare and player:getSquare()
    print("[DunKa][SFX] playBoss firing, sq="..tostring(sq~=nil))
    if sq then sm:PlayWorldSound("DunKa_BossFight", sq, 0, 5, 5, false)
    else sm:playUISound("DunKa_BossFight") end
end

-- ---------- per-box usage log (admin-viewable) ----------
local function logKey(x,y,z) return tostring(x).."_"..tostring(y).."_"..tostring(z) end
function DunKa.logUse(x,y,z, user, rankId)
    local md = ModData.getOrCreate("DunKaLog")
    local k = logKey(x,y,z); md[k] = md[k] or {}
    local gt = getGameTime()
    local h  = (gt and gt.getWorldAgeHours and gt:getWorldAgeHours()) or 0
    local day = math.floor(h/24) + 1
    local hh = (gt and gt:getHour()) or 0
    local mm = (gt and gt:getMinutes()) or 0
    table.insert(md[k], { u = tostring(user or "?"),
                          t = string.format("Day %d  %02d:%02d", day, hh, mm),
                          r = tostring(rankId) })
    while #md[k] > 40 do table.remove(md[k], 1) end
end
function DunKa.getLog(x,y,z)
    local md = ModData.getOrCreate("DunKaLog")
    return md[logKey(x,y,z)] or {}
end

function DunKa.getRankCount(rankId)
    local key = "Count" .. tostring(rankId)
    local rdef = DunKa.RANKS[rankId]
    return svInt(key, rdef and rdef.baseCount or 0)
end

----------------------------------------------------------------
-- GLOBAL cooldown (linked across every cabinet on the server)
-- stored in transmitted ModData; real-world ms (getTimestampMs)
----------------------------------------------------------------
local GLOBAL_KEY = "DunKa_Global"

function DunKa.getGlobal()
    local md = ModData.getOrCreate(GLOBAL_KEY)
    if md.lastFireMs == nil then md.lastFireMs = 0 end
    return md
end

function DunKa.nowMs()
    -- real-world clock (NOT in-game time) so cooldown = wall-clock minutes
    return getTimestampMs()
end

function DunKa.cooldownRemainingMs()
    local md  = DunKa.getGlobal()
    local cd  = DunKa.getCooldownMs()
    if cd <= 0 then return 0 end
    local rem = (md.lastFireMs + cd) - DunKa.nowMs()
    return rem > 0 and rem or 0
end

function DunKa.isOnCooldown()
    return DunKa.cooldownRemainingMs() > 0
end

function DunKa.stampFire()
    local md = DunKa.getGlobal()
    md.lastFireMs = DunKa.nowMs()
    -- per project rule: transmit after EVERY write so it survives chunk unload
    if not DunKa.isSP() then ModData.transmit(GLOBAL_KEY) end
end

----------------------------------------------------------------
-- staggered ring spawn worker (server / SP authoritative)
----------------------------------------------------------------
DunKa._jobs = DunKa._jobs or {}     -- list of active spawn jobs
DunKa._tick = 0

-- queue a horde to spawn around a cabinet square
function DunKa.enqueueSpawn(cx, cy, cz, total, rankId)
    total = math.min(total, DunKa.getSafetyCap())
    if total <= 0 then return end
    local dirs    = 8
    local perDir  = math.ceil(total / dirs)
    table.insert(DunKa._jobs, {
        cx = cx, cy = cy, cz = cz or 0,
        remaining = total,
        perDir = perDir,
        dirs = dirs,
        i = 0,
        rankId = rankId,
        dropLoot = DunKa.RANKS[rankId] and DunKa.RANKS[rankId].dropLoot or false,
    })
end

local function spawnBatch(job)
    local vzm = VirtualZombieManager and VirtualZombieManager.instance
    if not vzm then
        print("[DunKa] VirtualZombieManager.instance unavailable - cannot spawn")
        job.remaining = 0
        return
    end

    local R     = DunKa.getRadius()
    local angle = (2 * math.pi) * (job.i / job.dirs)
    local px    = math.floor(job.cx + R * math.cos(angle) + 0.5)
    local py    = math.floor(job.cy + R * math.sin(angle) + 0.5)
    local n     = math.min(job.perDir, job.remaining)

    local ok = false
    -- only spawn if the ring point is a legal spawn square
    local canSpawn = false
    pcall(function() canSpawn = vzm:canSpawnAt(px, py, job.cz) end)

    if canSpawn and n > 0 then
        -- createHordeFromTo(spawnX, spawnY, targetX, targetY, count)
        -- zombies appear at the ring point and walk toward the cabinet
        ok = pcall(function()
            vzm:createHordeFromTo(px, py, job.cx, job.cy, n)
        end)
        if not ok then
            print("[DunKa] createHordeFromTo failed at "..px..","..py)
        end
    end

    if ok then
        job.remaining = job.remaining - n
    end
    job.i = job.i + 1

    -- when we have gone all the way round once, if zombies remain,
    -- start another lap (handles counts > dirs*perDir rounding)
    if job.i >= job.dirs then job.i = 0 end
end

function DunKa._onTick()
    if #DunKa._jobs == 0 then return end
    DunKa._tick = DunKa._tick + 1
    if (DunKa._tick % DunKa.getTickInterval()) ~= 0 then return end

    local job = DunKa._jobs[1]
    spawnBatch(job)
    if job.remaining <= 0 then
        table.remove(DunKa._jobs, 1)
        print("[DunKa] horde spawn job complete")
    end
end

-- register the worker everywhere; it idles when no jobs are queued
Events.OnTick.Add(DunKa._onTick)

----------------------------------------------------------------
-- core: validate + fire (authoritative). returns ok, reason, remMs
----------------------------------------------------------------
function DunKa.processUse(player, x, y, z, rankId)
    local rdef = DunKa.RANKS[rankId]
    if not rdef then return false, "invalid_rank" end

    -- cooldown (global / linked)
    if DunKa.isOnCooldown() then
        return false, "cooldown", DunKa.cooldownRemainingMs()
    end

    -- server-side card possession check (anti-dupe / anti-exploit)
    if player and player.getInventory then
        local inv = player:getInventory()
        if inv and inv:getItemCount(rdef.item) < 1 then
            return false, "no_card"
        end
    end

    -- must be able to actually spawn somewhere, else don't charge the card (no free slips)
    do
        local vzm = VirtualZombieManager and VirtualZombieManager.instance
        if vzm then
            local R = DunKa.getRadius()
            local canAny = false
            for i = 0, 7 do
                local a = (2*math.pi)*(i/8)
                local px = math.floor(x + R*math.cos(a) + 0.5)
                local py = math.floor(y + R*math.sin(a) + 0.5)
                local ok = false
                pcall(function() ok = vzm:canSpawnAt(px, py, z or 0) end)
                if ok then canAny = true; break end
            end
            if not canAny then return false, "cant_spawn" end
        end
    end

    -- commit: stamp cooldown FIRST (so a race can't double-fire), then spawn
    DunKa.stampFire()
    local total = DunKa.getRankCount(rankId)
    DunKa.enqueueSpawn(x, y, z, total, rankId)

    -- loud world noise so nearby zombies are pulled toward the box (radius 20)
    pcall(function() addSound(player, x, y, z, 20, 50) end)

    -- record who used this box, when, and which rank (admin-viewable)
    pcall(function()
        DunKa.logUse(x, y, z, player and player.getUsername and player:getUsername(), rankId)
    end)

    return true, "ok"
end

----------------------------------------------------------------
-- reward application (runs on the player's own client / SP)
----------------------------------------------------------------
-- ---------- per-rank slip reward (admin-editable, persisted) ----------
-- how many of each slip colour a rank hands out on summon (0 = none required)
function DunKa.getRankConfig()
    local md = ModData.getOrCreate("DunKaRankCfg")
    if not md._init then
        for _, rid in ipairs(DunKa.RANK_ORDER) do
            local rdef = DunKa.RANKS[rid]
            local sl = (rdef and rdef.slips) or {}
            md[rid] = { White = sl.White or 0, Yellow = sl.Yellow or 0, Blue = sl.Blue or 0 }
        end
        md._init = true
    end
    return md
end
function DunKa.setRankReward(rank, white, yellow, blue)
    local md = DunKa.getRankConfig()
    md[rank] = { White = math.max(0, white or 0), Yellow = math.max(0, yellow or 0), Blue = math.max(0, blue or 0) }
end

function DunKa.applyReward(player, rankId)
    local rdef = DunKa.RANKS[rankId]
    if not (player and rdef) then return end
    local inv = player:getInventory()
    if not inv then return end

    -- consume ONE key card (B42 MP-safe: Remove + sync global; direct in SP)
    local card = inv:FindAndReturn(rdef.item)
    if card then
        inv:Remove(card)
        if sendRemoveItemFromContainer then
            pcall(function() sendRemoveItemFromContainer(inv, card) end)
        end
    end

    -- grant slips from the live per-rank config (fixed order W,Y,B)
    local rcfg = DunKa.getRankConfig()[rankId] or {}
    local sm = getScriptManager()
    for _, color in ipairs({ "White", "Yellow", "Blue" }) do
        local qty = rcfg[color]
        if qty and qty > 0 then
            local ft = DunKa.SLIP_ITEM[color]
            if ft and sm and sm:FindItem(ft) then
                for _ = 1, qty do
                    local it = inv:AddItem(ft)
                    if it and sendAddItemToContainer then
                        pcall(function() sendAddItemToContainer(inv, it) end)
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
-- small on-screen notify
----------------------------------------------------------------
function DunKa.notify(player, text)
    if not player then return end
    local done = pcall(function()
        HaloTextHelper.addText(player, text)
    end)
    if not done then pcall(function() player:Say(text) end) end
end

function DunKa.fmtRemaining(ms)
    local s = math.ceil((ms or 0) / 3000)
    local m = math.floor(s / 60)
    s = s % 60
    return string.format("%d:%02d", m, s)
end


----------------------------------------------------------------
-- authoritative world placement of the box (server / SP)
-- server-created objects replicate to clients reliably, unlike the
-- client-side deprecated transmitCompleteItemToServer brush path.
----------------------------------------------------------------
-- ---------- box registry (persisted) so boxes regenerate if destroyed ----------
function DunKa._boxList()
    local md = ModData.getOrCreate("DunKaBoxes")
    md.list = md.list or {}
    return md.list
end
function DunKa.registerBox(x,y,z)
    local list = DunKa._boxList()
    for _,b in ipairs(list) do if b.x==x and b.y==y and b.z==z then return end end
    table.insert(list, {x=x,y=y,z=z})
end
function DunKa.unregisterBox(x,y,z)
    local list = DunKa._boxList()
    for i=#list,1,-1 do local b=list[i]; if b.x==x and b.y==y and b.z==z then table.remove(list,i) end end
end
function DunKa.squareHasBox(sq)
    local objs = sq and sq:getObjects(); if not objs then return false end
    for i=0,objs:size()-1 do
        local o = objs:get(i)
        local md = o.getModData and o:getModData()
        if md and md.DunKaCabinet then return true end
        local spr = o.getSprite and o:getSprite()
        local nm = spr and spr.getName and spr:getName()
        if nm == DunKa.CABINET_SPRITE then return true end
    end
    return false
end

-- low-level placer (no diagnostics / registry side-effects)
function DunKa.placeBoxObject(x, y, z, cosmetic)
    local cell = getCell() or (getWorld() and getWorld():getCell())
    local sq = cell and cell:getGridSquare(x, y, z)
    if not (cell and sq) then return false end
    if DunKa.squareHasBox(sq) then return true end
    return (pcall(function()
        local obj = IsoObject.new(cell, sq, DunKa.CABINET_SPRITE)
        sq:AddTileObject(obj)
        local md = obj:getModData(); if md then md.DunKaCabinet = true end
        sq:RecalcProperties()
        if sq.RecalcAllWithNeighbours then sq:RecalcAllWithNeighbours(true) end
        -- only the authoritative side transmits; clients place cosmetically
        if not cosmetic and sq.transmitAddObjectToSquare then
            sq:transmitAddObjectToSquare(obj, sq:getObjects():indexOf(obj))
        end
    end))
end

-- box list received from the server (used by clients to draw boxes locally)
DunKa._clientBoxes = DunKa._clientBoxes or {}

-- regen watcher: re-place any registered box whose square lost it
DunKa._boxRegenTick = 0
function DunKa._boxRegen()
    DunKa._boxRegenTick = (DunKa._boxRegenTick or 0) + 1
    if (DunKa._boxRegenTick % 60) ~= 0 then return end
    local cell = getCell() or (getWorld() and getWorld():getCell())
    if not cell then return end
    local authoritative = (not isClient()) or isServer()   -- server or singleplayer
    local list = authoritative and DunKa._boxList() or DunKa._clientBoxes
    for _,b in ipairs(list or {}) do
        local sq = cell:getGridSquare(b.x, b.y, b.z)
        if sq and not DunKa.squareHasBox(sq) then
            DunKa.placeBoxObject(b.x, b.y, b.z, not authoritative)
        end
    end
end
Events.OnTick.Add(DunKa._boxRegen)

function DunKa.doPlaceBox(x, y, z)
    print("[DunKa] doPlaceBox ENTER x="..tostring(x).." y="..tostring(y).." z="..tostring(z))
    -- is the sprite actually registered on THIS side (server cares most)?
    local hasSpr = IsoSpriteManager and IsoSpriteManager.instance
                   and IsoSpriteManager.instance:getSprite(DunKa.CABINET_SPRITE) ~= nil
    print("[DunKa] sprite '"..DunKa.CABINET_SPRITE.."' registered here = "..tostring(hasSpr))

    local cell = getCell() or (getWorld() and getWorld():getCell())
    local sq = cell and cell:getGridSquare(x, y, z)
    if not cell then print("[DunKa] doPlaceBox FAILED: no cell on this side"); return false, "no_cell" end
    if not sq then print("[DunKa] doPlaceBox FAILED: square not loaded at "..x..","..y..","..z); return false, "no_square" end

    local ok = DunKa.placeBoxObject(x, y, z)
    if not ok then
        print("[DunKa] doPlaceBox FAILED at "..x..","..y..","..z)
        return false, "place_failed"
    end
    DunKa.registerBox(x, y, z)               -- track for regen (indestructible)
    print("[DunKa] doPlaceBox OK at " .. x .. "," .. y .. "," .. z)
    return true
end