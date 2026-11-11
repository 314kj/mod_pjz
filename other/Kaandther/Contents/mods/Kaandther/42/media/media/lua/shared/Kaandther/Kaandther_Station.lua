--[[ ============================================================
     kaandther  -  STATION  (shared; events fire on correct side)
     ------------------------------------------------------------
     REWORK 0.13:
       - NO register / enable step. Place it -> usable immediately, forever.
       - single sprite pair (aka_table_plus_0 anchor + _1 deco). No _2/_3.
       - registry (positions) synced to ALL clients (tables are visible anyway).
       - BOTH server AND each client re-place the visual tile from the registry
         when a square streams in, so it never "disappears" after teleport.
       - detection is by SPRITE presence (+registry), NOT tile modData, so a
         re-placed tile is always interactive even if modData didn't sync.
       - admin: place / rename / registry / log / remove.  Remove keeps config.
     ============================================================ ]]
if isClient() then
    pcall(function() require "ISUI/ISContextMenu" end)
    pcall(function() require "ISUI/ISTextBox" end)
end

Kaandther = Kaandther or {}
local K = Kaandther
Kaandther.Station = Kaandther.Station or {}

local ANCHOR_SPRITE = "aka_table_plus_1"   -- the "2nd" bench tile Pie wants; single-tile station
local SPRITE_PREFIX = "aka_table_plus_"

local STAFF = { admin = true, moderator = true, gm = true }
local function isStaff(player)
    local lvl = player and player.getAccessLevel and player:getAccessLevel()
    return lvl ~= nil and STAFF[tostring(lvl):lower()] == true
end

local function keyOf(sq) return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ() end
local function parseKey(k)
    local x, y, z = tostring(k):match("(-?%d+),(-?%d+),(-?%d+)")
    return tonumber(x), tonumber(y), tonumber(z)
end
local function isAuthority() return isServer() or K.isSP() end

local function squareHasSprite(sq, sprite)
    if not sq then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i); local s = o.getSprite and o:getSprite()
        if s and s.getName and s:getName() == sprite then return true end
    end
    return false
end
local function squareHasStationSprite(sq)
    if not sq then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i); local s = o.getSprite and o:getSprite()
        local n = s and s.getName and s:getName()
        if n and n:sub(1, #SPRITE_PREFIX) == SPRITE_PREFIX then return true end
    end
    return false
end

-- ===== registry ==============================================
local function reg() return ModData.getOrCreate("kaandther_Stations") end

-- distance gate: player within `range` tiles of the station (occupies (x,y) & (x,y+1))
function Kaandther.Station.nearKey(player, key, range)
    if not player or not key then return true end
    local x, y, z = parseKey(key); if not x then return true end
    range = range or 2
    local ok = false
    pcall(function()
        if math.floor(player:getZ()) ~= z then return end
        local px, py = player:getX(), player:getY()
        local dx = math.abs(px - (x + 0.5))
        local dy = math.abs(py - (y + 0.5))
        ok = (dx <= range and dy <= range)
    end)
    return ok
end

-- station "usable" == it exists in the registry (nil key = console/test path)
function Kaandther.Station.isEnabledKey(key)
    if not key then return true end
    return reg()[key] ~= nil
end

-- find a station under the right-clicked squares -> returns obj, sq, key
local function findStation(worldobjects)
    for _, o in ipairs(worldobjects) do
        local sq = o.getSquare and o:getSquare()
        if sq and squareHasSprite(sq, ANCHOR_SPRITE) then
            return o, sq, keyOf(sq)
        end
    end
    return nil
end

-- ===== file-backed persistence (ModData alone doesn't survive restart) =====
local REGFILE = "kaandther_stations.txt"
function Kaandther.Station.saveRegFile()
    if not isAuthority() then return end
    pcall(function()
        local w = getFileWriter(REGFILE, true, false)
        if not w then return end
        for _, rec in pairs(reg()) do
            if type(rec) == "table" and rec.x then
                local nm = tostring(rec.name or ""):gsub("[\r\n|]", "")
                w:write(rec.x .. "|" .. rec.y .. "|" .. rec.z .. "|1|" .. nm .. "\n")
            end
        end
        w:close()
    end)
end
local function loadRegFile()
    if not isAuthority() then return end
    pcall(function()
        local r = getFileReader(REGFILE, false)
        if not r then return end
        local R = reg()
        local line = r:readLine()
        while line do
            if line ~= "" then
                local a, rest = {}, line
                for i = 1, 4 do local p = rest:find("|", 1, true)
                    if p then a[i] = rest:sub(1, p-1); rest = rest:sub(p+1) else a[i] = rest; rest = "" end end
                local x, y, z = tonumber(a[1]), tonumber(a[2]), tonumber(a[3])
                if x and y and z then
                    local key = x .. "," .. y .. "," .. z
                    R[key] = R[key] or { x=x, y=y, z=z, name=(rest ~= "" and rest or ""), owner="", log={} }
                end
            end
            line = r:readLine()
        end
        r:close()
    end)
end

-- ===== tile placement / restore =============================
-- place the pair of tiles for a record if the squares are loaded and missing them.
-- `transmit` = true on the authority side (push to fresh clients); false = local visual only.
local function placeTile(sq, sprite, anchor, transmit)
    if not sq then return false end
    local ok, err = pcall(function()
        local obj = IsoObject.new(getCell(), sq, sprite)
        sq:AddTileObject(obj)
        if anchor then
            local md = obj:getModData()
            md.kaandtherStation = true
            K.Origin.stamp(md)
        end
        if transmit and sq.transmitAddObjectToSquare then
            local okT = pcall(function() sq:transmitAddObjectToSquare(obj, sq:getObjects():indexOf(obj)) end)
            if not okT then pcall(function() sq:transmitAddObjectToSquare(obj) end) end
        end
    end)
    if not ok then print("[kaandther] placeTile error: " .. tostring(err)) end
    return ok
end

local function restoreRecord(rec, transmit)
    if type(rec) ~= "table" or not rec.x then return 0 end
    local cell = getCell(); if not cell then return 0 end
    local placed = 0
    local sq0 = cell:getGridSquare(rec.x, rec.y, rec.z)
    if sq0 and not squareHasSprite(sq0, ANCHOR_SPRITE) then if placeTile(sq0, ANCHOR_SPRITE, true, transmit) then placed = placed + 1 end end
    return placed
end
local function restoreAll(reason)
    local transmit = isAuthority()
    local total = 0
    for _, rec in pairs(reg()) do total = total + restoreRecord(rec, transmit) end
    if total > 0 then print(("[kaandther] restored %d station tiles (%s,%s)"):format(total, tostring(reason), K.side())) end
end

-- immediate restore as each square streams in (runs on BOTH server and client)
if Events.LoadGridsquare then
    Events.LoadGridsquare.Add(function(sq)
        if not sq then return end
        local transmit = isAuthority()
        pcall(function()
            local x, y, z = sq:getX(), sq:getY(), sq:getZ()
            for _, rec in pairs(reg()) do
                if type(rec) == "table" and rec.x and rec.z == z then
                    if x == rec.x and y == rec.y and not squareHasSprite(sq, ANCHOR_SPRITE) then
                        placeTile(sq, ANCHOR_SPRITE, true, transmit)
                    end
                end
            end
        end)
    end)
end
-- periodic safety sweep (~8s) on both sides
local sweepT = 0
Events.OnTick.Add(function()
    sweepT = sweepT + 1; if sweepT < 480 then return end sweepT = 0
    pcall(function() restoreAll("sweep") end)
end)

local function persistBoot()
    if isAuthority() then
        loadRegFile()
        local n = 0; for _, rec in pairs(reg()) do if type(rec) == "table" and rec.x then n = n + 1 end end
        print(("[kaandther][SV] station registry has %d stations at boot"):format(n))
        ModData.transmit("kaandther_Stations")
    else
        pcall(function() ModData.request("kaandther_Stations") end)
    end
    restoreAll("boot")
end
Events.OnGameStart.Add(persistBoot)
if Events.OnServerStarted then Events.OnServerStarted.Add(persistBoot) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(function()
    if isClient() then pcall(function() ModData.request("kaandther_Stations") end) end
end) end
-- client: whenever the synced registry arrives, restore visuals
if Events.OnReceiveGlobalModData then
    Events.OnReceiveGlobalModData.Add(function(name)
        if name == "kaandther_Stations" then pcall(function() restoreAll("modsync") end) end
    end)
end

-- ===== CLIENT: admin brush placement =========================
local function spriteHalo(pl)
    local hasSprite = IsoSpriteManager and IsoSpriteManager.instance
                      and IsoSpriteManager.instance:getSprite(ANCHOR_SPRITE) ~= nil
    if not hasSprite then pl:setHaloNote("Kaandther: sprite NOT loaded -> " .. ANCHOR_SPRITE, 250, 120, 120, 400) end
    return hasSprite
end
local function brushPlace(pl)
    if not spriteHalo(pl) then return end
    if not ISBrushToolTileCursor then pl:setHaloNote("Kaandther: tile cursor unavailable", 250, 120, 120, 300); return end
    local cursor = ISBrushToolTileCursor:new(ANCHOR_SPRITE, ANCHOR_SPRITE, pl)
    getCell():setDrag(cursor, pl:getPlayerNum())
    pl:setHaloNote("Kaandther: left-click ground to place the station", 150, 220, 250, 300)
end

-- ===== CLIENT: context menu ==================================
-- Shared top-level menu for ALL AKA mods. Every AKA mod must create THIS exact
-- string and match tolerantly, so they all collapse into one "AKA MOD" menu.
local AKA_ROOT = "AKA MOD"
-- normalize a menu name: lowercase + strip spaces -> merges "AKA MOD","AKA Mods","aka  mod"...
local function isAkaRoot(name)
    local k = tostring(name or ""):lower():gsub("%s+", "")
    return k == "akamod" or k == "akamods"
end
-- get-or-create the shared "AKA MOD" top-level (merges with Kacha/Akacamp/etc.),
-- then a single fresh "Kaandther" submenu under it. All admin options live here.
local function akaKaandtherSub(context)
    local akaOpt
    for i = 1, #context.options do
        if isAkaRoot(context.options[i].name) then akaOpt = context.options[i]; break end
    end
    local akaSub = akaOpt and akaOpt.subOption and context:getSubMenu(akaOpt.subOption)
    if not akaSub then
        akaOpt = context:addOption(AKA_ROOT, nil, nil)
        akaSub = ISContextMenu:getNew(context)
        context:addSubMenu(akaOpt, akaSub)
    end
    local kOpt = akaSub:addOption("Kaandther", nil, nil)
    local kSub = ISContextMenu:getNew(akaSub)
    akaSub:addSubMenu(kOpt, kSub)
    return kSub
end

local function onMenu(playerNum, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(function()
        local pl = getSpecificPlayer(playerNum)
        if not pl then return end
        local staff = isStaff(pl)
        local obj, sq, key = findStation(worldobjects)
        local registered = obj and Kaandther.Station.isEnabledKey(key)

        -- PLAYER: 3 options, only on a station that admin has REGISTERED (active)
        if obj and registered then
            context:addOption("Enhance Weapon", nil, function() Kaandther.UI.open(pl, key) end)
            context:addOption("Check My Weapon", nil, function() Kaandther.UI.openWeaponCheck(pl) end)
            context:addOption("View Weapon Tiers", nil, function() Kaandther.UI.openBrowser(pl) end)
        end

        if not staff then return end

        -- ADMIN: everything under AKA MOD > Kaandther (one place)
        local kSub = akaKaandtherSub(context)
        if obj and registered then
            kSub:addOption("Rename Location", nil, function()
                local modal = ISTextBox:new(getCore():getScreenWidth()/2 - 150, getCore():getScreenHeight()/2 - 75,
                    300, 150, "Station name:", "", nil, function(target, button)
                        if button.internal == "OK" then
                            sendClientCommand(pl, "kaandther", "rename", { key = key, name = button.parent.entry:getText() })
                        end
                    end)
                modal:initialise(); modal:addToUIManager()
            end)
            kSub:addOption("Station Registry", nil, function() sendClientCommand(pl, "kaandther", "registry", {}) end)
            kSub:addOption("View Log (recent)", nil, function() sendClientCommand(pl, "kaandther", "log", { key = key }) end)
            kSub:addOption("Remove Station (keeps settings)", nil, function() sendClientCommand(pl, "kaandther", "remove", { key = key }) end)
        elseif obj and not registered then
            -- tile is placed but NOT active yet -> admin registers it here
            kSub:addOption("Register Station", nil, function()
                sendClientCommand(pl, "kaandther", "claim", { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
                pl:setHaloNote("Kaandther: station registered", 150, 220, 150, 300)
            end)
            kSub:addOption("Remove Tile", nil, function() sendClientCommand(pl, "kaandther", "remove", { key = key }) end)
        else
            kSub:addOption("Place Tile (brush)", nil, function() brushPlace(pl) end)
        end
        -- general admin tools (always available to staff)
        kSub:addOption("Admin Panel", nil, function() Kaandther.UI.openAdmin(pl) end)
        kSub:addOption("Upgrade (test)", nil, function() Kaandther.UI.open(pl, nil) end)
        kSub:addOption("Weapon Tiers", nil, function() Kaandther.UI.openBrowser(pl) end)
        kSub:addOption("Dump Config", nil, function() Kaandther.Admin.dump() end)
    end)
    if not ok then print("[kaandther] station menu error: " .. tostring(err)) end
end
Events.OnFillWorldObjectContextMenu.Add(onMenu)

-- ===== SERVER: handlers ======================================
local function serverPlace(player, a)
    local cell = getCell()
    local sq0 = cell:getGridSquare(a.x, a.y, a.z)
    if sq0 and not squareHasSprite(sq0, ANCHOR_SPRITE) then placeTile(sq0, ANCHOR_SPRITE, true, true)
    elseif sq0 then -- reuse brush-painted tile: stamp it as the anchor
        local objs = sq0:getObjects()
        for i = 0, objs:size() - 1 do local o = objs:get(i); local s = o.getSprite and o:getSprite()
            if s and s:getName() == ANCHOR_SPRITE then local md = o:getModData(); md.kaandtherStation = true; K.Origin.stamp(md) end end
    end

    local key = a.x .. "," .. a.y .. "," .. a.z
    local R = reg()
    R[key] = R[key] or { x = a.x, y = a.y, z = a.z, name = "",
                         owner = (player and player:getUsername()) or "brush", log = {} }
    ModData.transmit("kaandther_Stations")
    Kaandther.Station.saveRegFile()
    print("[kaandther][SV] placed station @" .. key)
end

local function serverRemove(player, a)
    local x, y, z = parseKey(a.key); if not x then return end
    local cell = getCell()
    local function clearTile(sx, sy)
        local sq = cell and cell:getGridSquare(sx, sy, z); if not sq then return end
        local objs = sq:getObjects()
        for i = objs:size() - 1, 0, -1 do
            local o = objs:get(i); local s = o.getSprite and o:getSprite()
            local n = s and s.getName and s:getName()
            if n and n:sub(1, #SPRITE_PREFIX) == SPRITE_PREFIX then
                pcall(function() sq:transmitRemoveItemFromSquare(o); sq:RemoveTileObject(o) end)
            end
        end
    end
    clearTile(x, y)
    reg()[a.key] = nil
    ModData.transmit("kaandther_Stations")
    Kaandther.Station.saveRegFile()
    print("[kaandther][SV] removed station @" .. tostring(a.key) .. " (config untouched)")
end

local function serverRename(player, a)
    local rec = reg()[a.key]
    if rec then rec.name = tostring(a.name or "") end
    ModData.transmit("kaandther_Stations")
    Kaandther.Station.saveRegFile()
    print(("[kaandther][SV] %s renamed -> %q"):format(tostring(a.key), tostring(a.name)))
end

-- result-code -> Thai (for log readability)
local RES_TH = { SUCCESS="สำเร็จ", DOWNGRADE="ตกเทียร์", PROTECT="เห็ดกันไว้ได้", MISS="พลาด", MAX="เต็มแล้ว" }
local function thaiRes(r) return RES_TH[r] or tostring(r) end

local function serverRegistry(player)
    local R = reg(); local lines = { "[kaandther] === ทะเบียนโต๊ะทั้งหมด ===" }
    local n = 0
    for k, v in pairs(R) do n = n + 1
        table.insert(lines, ("  พิกัด %s | ชื่อ: %s | ผู้วาง: %s | บันทึก %d รายการ"):format(k, tostring(v.name or "-"), tostring(v.owner or "-"), v.log and #v.log or 0))
    end
    if n == 0 then table.insert(lines, "  (ยังไม่มีโต๊ะที่ลงทะเบียน)") end
    sendServerCommand(player, "kaandther", "info", { lines = lines })
end

-- ===== log retention + stats (unchanged) =====================
local LOG_DAYS = 7
local function pruneLog(rec)
    if not rec or not rec.log then return end
    local today = (getGameTime and getGameTime():getNightsSurvived()) or 0
    local keep = {}
    for _, e in ipairs(rec.log) do
        if e.day == nil or (today - e.day) <= LOG_DAYS then keep[#keep + 1] = e end
    end
    rec.log = keep
    while #rec.log > 200 do table.remove(rec.log, 1) end
end
local function serverLog(player, a)
    local rec = reg()[a.key]
    if rec then pruneLog(rec) end
    local lines = { ("[kaandther] === บันทึกโต๊ะ %s (%s) ==="):format(tostring(a.key), rec and rec.name or "-") }
    if rec and rec.log and #rec.log > 0 then
        for i = math.max(1, #rec.log - 20), #rec.log do
            local e = rec.log[i]
            table.insert(lines, ("  วันที่ %s | ผู้เล่น %s | อาวุธ %s | +%s->+%s | ผล: %s"):format(
                tostring(e.day), tostring(e.u), tostring(e.item), tostring(e.from), tostring(e.to), thaiRes(e.res)))
        end
    else table.insert(lines, "  (ยังไม่มีบันทึก)") end
    sendServerCommand(player, "kaandther", "info", { lines = lines })
end

function Kaandther.Station.appendLog(key, entry)
    if not key then return end
    local rec = reg()[key]; if not rec then return end
    rec.log = rec.log or {}
    entry.day = (getGameTime and getGameTime():getNightsSurvived()) or 0
    table.insert(rec.log, entry)
    pruneLog(rec)
    ModData.transmit("kaandther_Stations")
end

function Kaandther.Station.computeStats()
    local R = reg()
    local userAtt, userSucc, userProt, itemAtt, userItem = {}, {}, {}, {}, {}
    local total = 0
    for _, rec in pairs(R) do
        pruneLog(rec)
        for _, e in ipairs(rec.log or {}) do
            total = total + 1
            local u, it = tostring(e.u or "?"), tostring(e.item or "?")
            userAtt[u]  = (userAtt[u]  or 0) + 1
            itemAtt[it] = (itemAtt[it] or 0) + 1
            userItem[u] = userItem[u] or {}
            userItem[u][it] = (userItem[u][it] or 0) + 1
            if e.res == "SUCCESS" then userSucc[u] = (userSucc[u] or 0) + 1 end
            if e.res == "PROTECT" then userProt[u] = (userProt[u] or 0) + 1 end
        end
    end
    local function topKey(t) local bk, bv for k, v in pairs(t) do if not bv or v > bv then bk, bv = k, v end end return bk, bv end
    local lines = { ("[kaandther] === สถิติ 7 วันล่าสุด (รวม %d ครั้ง) ==="):format(total) }
    if total == 0 then lines[#lines+1] = "  (ยังไม่มีข้อมูล)"; return lines end
    local u1, v1 = topKey(userAtt)
    lines[#lines+1] = ("  ตีบ่อยสุด: %s (%d ครั้ง)"):format(tostring(u1), v1 or 0)
    if u1 then local it = topKey(userItem[u1] or {}); lines[#lines+1] = ("    ส่วนใหญ่ตี: %s"):format(tostring(it)) end
    local i1, iv = topKey(itemAtt)
    lines[#lines+1] = ("  อาวุธที่ถูกตีมากสุด: %s (%d)"):format(tostring(i1), iv or 0)
    local p1, pv = topKey(userProt)
    lines[#lines+1] = ("  ใช้เห็ดกันมากสุด: %s (%d)"):format(tostring(p1 or "-"), pv or 0)
    local bestU, bestR, worstU, worstR
    for u, att in pairs(userAtt) do
        if att >= 5 then
            local r = (userSucc[u] or 0) / att
            if not bestR  or r > bestR  then bestU, bestR  = u, r end
            if not worstR or r < worstR then worstU, worstR = u, r end
        end
    end
    if bestU  then lines[#lines+1] = ("  ดวงดีสุด: %s (%d%% จาก %d ครั้ง)"):format(bestU, math.floor(bestR*100), userAtt[bestU]) end
    if worstU then lines[#lines+1] = ("  ดวงซวยสุด: %s (%d%% จาก %d ครั้ง)"):format(worstU, math.floor(worstR*100), userAtt[worstU]) end
    lines[#lines+1] = "  --- แยกรายคน ---"
    for u, att in pairs(userAtt) do
        lines[#lines+1] = ("   %s: ตี %d | สำเร็จ %d | กัน %d"):format(u, att, userSucc[u] or 0, userProt[u] or 0)
    end
    return lines
end
local function serverStats(player)
    sendServerCommand(player, "kaandther", "info", { lines = Kaandther.Station.computeStats() })
end

local function onStationCmd(module, command, player, args)
    if module ~= "kaandther" then return end
    if not isStaff(player) and (command == "place" or command == "rename" or command == "registry"
        or command == "log" or command == "remove" or command == "stats" or command == "claim") then
        return
    end
    if     command == "remove"   then serverRemove(player, args)
    elseif command == "place"    then serverPlace(player, args)
    elseif command == "claim"    then serverPlace(player, args)
    elseif command == "rename"   then serverRename(player, args)
    elseif command == "registry" then serverRegistry(player)
    elseif command == "log"      then serverLog(player, args)
    elseif command == "stats"    then serverStats(player)
    end
end
Events.OnClientCommand.Add(onStationCmd)

local function onStationServerCmd(module, command, args)
    if module ~= "kaandther" then return end
    if command == "info" and args.lines then for _, l in ipairs(args.lines) do print(l) end end
end
Events.OnServerCommand.Add(onStationServerCmd)

-- ===== brush paint just makes a tile; admin registers it via right-click =====
-- (no auto-register on paint: paint the _1 tile, then AKA MOD > Kaandther > Register Station)
