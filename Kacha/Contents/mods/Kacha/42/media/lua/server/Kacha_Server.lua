--[[ ============================================================
     Kacha B42 [MP]  -  server (authoritative ROLL)  by PIE
   ============================================================ ]]

Kacha = Kacha or {}

function Kacha.reg() return ModData.getOrCreate("KachaReg") end
function Kacha.regKey(x, y, z) return tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z) end

-- integer anchor table (hot-path safe: no string keys / no table alloc in LoadGridsquare)
Kacha.anchor = Kacha.anchor or {}
local function setAnchor(x, y, z, skin)
    Kacha.anchor[x] = Kacha.anchor[x] or {}
    Kacha.anchor[x][y] = { z = z, skin = skin }
end
local function rebuildAnchors()
    Kacha.anchor = {}
    local r = Kacha.reg()
    for k, e in pairs(r) do
        if type(e) == "table" and e.place and e.skin then
            local sx, sy, sz = string.match(k, "^(-?%d+)_(-?%d+)_(-?%d+)$")
            if sx then setAnchor(tonumber(sx), tonumber(sy), tonumber(sz), e.skin) end
        end
    end
end

-- create the machine tile on the SERVER so every client sees it + it persists.
-- fully pcall-guarded: a wrong call logs, it never crashes the server.
function Kacha.placeMachine(x, y, z, sprite)
    local cell = getCell(); if not cell then return false end
    local sq = cell:getGridSquare(x, y, z); if not sq then return false end
    if Kacha.getSqKacha(sq) then return true end   -- already present
    local o = nil
    local ok = pcall(function() o = IsoObject.new(cell, sq, sprite, sprite) end)
    if (not ok) or (not o) then ok = pcall(function() o = IsoObject.new(cell, sq, sprite) end) end
    if not o then print("[Kacha][SV] place FAILED (IsoObject.new) " .. tostring(sprite)); return false end
    pcall(function() sq:AddSpecialObject(o) end)
    pcall(function() if getSprite then local s = getSprite(sprite); if s and o.setSprite then o:setSprite(s) end end end)
    if AKA and AKA.Indestructible and AKA.Indestructible.harden then pcall(AKA.Indestructible.harden, o) end
    pcall(function() if o.transmitCompleteItemToClients then o:transmitCompleteItemToClients() end end)
    pcall(function() local ch = sq:getChunk(); if ch and ch.setModified then ch:setModified(true) end end)
    local r = Kacha.reg(); local k = Kacha.regKey(x, y, z)
    r[k] = r[k] or {}; r[k].skin = sprite; r[k].place = true
    setAnchor(x, y, z, sprite)
    print("[Kacha][SV] placed " .. tostring(sprite) .. " @" .. x .. "," .. y .. "," .. z)
    return true
end

-- NOTE: no LoadGridsquare / OnInitGlobalModData hooks here on purpose.
-- Engine callbacks in the world-gen path can break server boot (RULE #6).
-- placeMachine below is only ever called on-demand from the "place" command;
-- the object is saved into the chunk + transmitted, so it persists on its own.

local function findMachine(args)
    local cell = getCell()
    if not cell then print("[Kacha][SV] findMachine: getCell() nil"); return nil end
    local sq = cell:getGridSquare(args.x, args.y, args.z)
    if sq then
        local o = Kacha.getSqKacha(sq)
        if o then return o end
    end
    -- fallback: tall-sprite anchor drift / off-by-one -> scan 1-tile radius
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                local s2 = cell:getGridSquare(args.x + dx, args.y + dy, args.z)
                if s2 then
                    local o2 = Kacha.getSqKacha(s2)
                    if o2 then print("[Kacha][SV] findMachine: found via offset " .. dx .. "," .. dy); return o2 end
                end
            end
        end
    end
    -- diagnostic: what DOES the server see at the target square?
    if sq and sq.getObjects then
        local objs = sq:getObjects()
        local names = {}
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local spr = o and o.getSprite and o:getSprite()
            names[#names + 1] = (spr and spr.getName and spr:getName()) or "?"
        end
        print("[Kacha][SV] findMachine MISS @" .. tostring(args.x) .. "," .. tostring(args.y) .. "," ..
              tostring(args.z) .. " objs=[" .. table.concat(names, ", ") .. "]")
    else
        print("[Kacha][SV] findMachine: no square @" .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z))
    end
    return nil
end

-- ---- global preset store (persisted in GlobalModData) -------------------
local function presetStore()
    local g = ModData.getOrCreate(Kacha.PRESET_KEY)
    if type(g.presets) ~= "table" then g.presets = Kacha.defaultPresets() end
    return g
end

local function onClientCommand(module, command, player, args)
    if module ~= "Kacha" then return end
    if not player then return end

    -- ---- preset sync (any player may read; only admins may save) ----
    if command == "getPresets" then
        sendServerCommand(player, "Kacha", "presets", { presets = presetStore().presets })
        return
    end
    if command == "savePresets" then
        -- staff whitelist (lowercase). NEVER blacklist "None": getAccessLevel()
        -- returns lowercase roles ("user", etc.), never "None", so a plain user
        -- would slip through a == "None" guard.
        local lvl = (player.getAccessLevel and tostring(player:getAccessLevel() or ""):lower()) or ""
        if not (lvl == "admin" or lvl == "moderator" or lvl == "gm") then return end
        local g = presetStore()
        g.presets = (type(args) == "table" and type(args.presets) == "table") and args.presets or g.presets
        sendServerCommand("Kacha", "presets", { presets = g.presets })   -- broadcast to all
        return
    end

    -- ---- admin places a machine (server-authoritative, visible to all) --
    if command == "place" then
        local lvl = (player.getAccessLevel and tostring(player:getAccessLevel() or ""):lower()) or ""
        if not (lvl == "admin" or lvl == "moderator" or lvl == "gm") then return end
        if args and args.x and args.sprite then
            Kacha.placeMachine(args.x, args.y, args.z, args.sprite)
        end
        return
    end

    -- ---- machine config registry (coord-keyed) --------------------------
    -- Admin edits push here so the server can spin WITHOUT re-finding the
    -- placed tile object (brush-placed tiles aren't reliably server-visible).
    if command == "saveCfg" then
        if not (args and args.x) then return end
        local r = Kacha.reg()
        local k = Kacha.regKey(args.x, args.y, args.z)
        local prev = r[k] or {}
        r[k] = {
            entries = args.entries or {}, salt = args.salt or {},
            tokenType = args.tokenType, tokenItem = args.tokenItem,
            costPerRoll = args.costPerRoll, skin = args.skin,
            history = prev.history or {},
        }
        return
    end

    if command ~= "spin" then return end
    if not args then return end

    -- prefer the coord-registry cfg (works even if the tile object isn't
    -- server-visible); fall back to the object's modData if present.
    local rc  = Kacha.reg()[Kacha.regKey(args.x, args.y, args.z)]
    local obj = findMachine(args)          -- may be nil; used for give/history if present
    local d
    if rc then
        d = rc
    elseif obj then
        d = Kacha.getConfig(obj)
    else
        sendServerCommand(player, "Kacha", "spinResult", { ok = false, reason = "nomachine" }); return
    end

    local entries = d.entries or {}
    local salt    = d.salt or {}
    if (#entries == 0) and (#salt == 0) then
        sendServerCommand(player, "Kacha", "spinResult", { ok = false, reason = "noitems" }); return
    end

    local count = tonumber(args.count) or 1
    if count < 1 then count = 1 elseif count > 100 then count = 100 end
    local cost = (tonumber(d.costPerRoll) or 1) * count
    local tokenItem = d.tokenItem or "Base.KachaCoin"

    if player:getInventory():getItemCount(tokenItem) < cost then
        sendServerCommand(player, "Kacha", "spinResult", { ok = false, reason = "poor" }); return
    end

    local results = {}
    local who = player:getUsername() or "player"
    local updatedHistory = false

    -- roll from the resolved cfg (registry or object) - guarantees output
    for _ = 1, count do
        local pick = Kacha.rollFromCfg(d)
        if pick then
            local nm = Kacha.displayName(pick.id)
            table.insert(results, { id = pick.id, tier = pick.tier, name = nm })

            -- บันทึกประวัติถ้าได้ของระดับแรร์
            if Kacha.RARE and Kacha.RARE[pick.tier] then
                table.insert(d.history, 1, { name = nm, tier = pick.tier, who = who, when = "Just now" })
                if #d.history > 20 then table.remove(d.history) end
                updatedHistory = true
            end
        end
    end

    if updatedHistory then Kacha.commit(obj) end

    -- ===== charge + give SERVER-SIDE, then PUSH to the client ============
    -- The server is the authority (affordability was checked above on the
    -- server's own copy). We change the server inventory, then sync each
    -- change DOWN to the owning client with sendRemoveItemFromContainer /
    -- sendAddItemToContainer (server->client is the working direction; the
    -- client->server transmit is the deprecated one). This makes items
    -- real + usable immediately AND keeps the server coin count correct
    -- (so you can't keep spinning with 0 coins).
    local inv = player:getInventory()
    local charged = 0
    for _ = 1, cost do
        local c = inv:FindAndReturn(tokenItem)
        if c then
            local cont = (c.getContainer and c:getContainer()) or inv
            if sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, c) end   -- announce first
            cont:Remove(c)
            charged = charged + 1
        else break end
    end
    -- canonical B42 MP give: instance -> AddItem(instance) -> sendAddItemToContainer
    -- (NO syncItemFields: it fires a SyncItemFields packet the client can't resolve -> NPE spam)
    local given = 0
    for _, r in ipairs(results) do
        local item = instanceItem(r.id)
        if item then
            inv:AddItem(item)
            if sendAddItemToContainer then sendAddItemToContainer(inv, item) end
            given = given + 1
        else print("[Kacha][SV] !! instanceItem nil for " .. tostring(r.id)) end
    end
    if inv.setDrawDirty then inv:setDrawDirty(true) end
    print("[Kacha][SV][give] " .. who .. " charged " .. charged .. "/" .. cost ..
          " " .. tokenItem .. " | gave " .. given .. "/" .. #results)

    sendServerCommand(player, "Kacha", "spinResult", { ok = true, results = results })

    -- broadcast rare pulls (A/S/SS/SS+) to the spinner + every online admin
    Kacha.broadcastResults(player, results)
end

-- ---- rare-pull broadcast ----------------------------------------------
-- tiers that count as "worth announcing" (ตรงกับที่ผู้ใช้อยากได้: A - SS+)
local BROADCAST_TIER = { A = true }   -- feed only A; S/SS/SS+ use the center popup
local STAFF = { admin = true, moderator = true, gm = true }
local function isStaff(p)
    if not p or not p.getAccessLevel then return false end
    local lv = tostring(p:getAccessLevel() or ""):lower()   -- whitelist + :lower()
    return STAFF[lv] == true
end

function Kacha.broadcastResults(spinner, results)
    if not spinner or type(results) ~= "table" then return end
    local rares = {}
    for _, r in ipairs(results) do
        if BROADCAST_TIER[r.tier] then rares[#rares + 1] = { name = r.name, tier = r.tier, id = r.id } end
    end
    if #rares == 0 then return end

    local who = (spinner.getUsername and spinner:getUsername()) or "player"
    local payload = { who = who, items = rares }

    sendServerCommand(spinner, "Kacha", "feed", payload)          -- คนหมุนเห็นผลตัวเอง
    local online = getOnlinePlayers()
    if not online then return end
    for i = 0, online:size() - 1 do
        local p = online:get(i)
        if p and p ~= spinner and isStaff(p) then                 -- แอดมินออนไลน์ทุกคน
            sendServerCommand(p, "Kacha", "feed", payload)
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[Kacha][BUILD] gacha-Q  (mushroom item-backed, tick-fix, feed=A only)")

Kacha.__feed(3, 11)
Kacha.__mark("srv")