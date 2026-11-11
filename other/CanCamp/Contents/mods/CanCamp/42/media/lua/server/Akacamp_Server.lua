--[[ Akacamp server: registry, builder, claim, warp, admin. Per-size recipe+toll.
     Broadcasts registry on every change so open admin panels stay live. ]]
require "Akacamp_Util"
local MODKEY = "AkacampData"

local function data()
    local md = ModData.getOrCreate(MODKEY)
    md.slots  = md.slots  or {}
    md.nextId = md.nextId or 1
    md.config = md.config or {}
    md.config.recipe = md.config.recipe or {}
    md.config.toll   = md.config.toll   or {}
    for _, sz in ipairs(Akacamp.SIZES) do
        md.config.recipe[sz] = md.config.recipe[sz] or {}
        md.config.toll[sz]   = md.config.toll[sz]   or {}
    end
    return md
end
local function save() ModData.transmit(MODKEY) end
local function broadcastRegistry()
    local md = data()
    sendServerCommand("Akacamp", "registry", { slots = md.slots, nextId = md.nextId })
end
local function sendConfig(player)
    local md = data()
    sendServerCommand(player, "Akacamp", "config", { recipe = md.config.recipe, toll = md.config.toll })
end

----------------------------------------------------------------------
-- BUILDER (proven)
----------------------------------------------------------------------
local function placeOne(cell, ox, oy, oz, e, stat)
    local dx, dy, dz, kind, sprite
    if type(e[3]) == "number" then dx,dy,dz,kind,sprite = e[1],e[2],e[3],e[4],e[5]
    else dx,dy,dz,kind,sprite = e[1],e[2],0,e[3],e[4] end
    local sq = cell:getOrCreateGridSquare(ox + dx, oy + dy, oz + dz)
    if not sq then stat.nosq = stat.nosq + 1; return end
    if kind == "floor" then
        pcall(function() sq:addFloor(sprite) end); stat.floor = stat.floor + 1
    else
        pcall(function()
            local obj = IsoObject.new(cell, sq, sprite)
            sq:AddTileObject(obj)
            if obj.transmitCompleteItemToClients then obj:transmitCompleteItemToClients() end
        end); stat.obj = stat.obj + 1
    end
    stat.sqset[sq] = true
end
local function buildTent(ox, oy, oz, size)
    local tpl = AkacampTpl and AkacampTpl[size]; if not tpl then return false end
    local cell = getCell(); local stat = { floor=0, obj=0, nosq=0, sqset={} }
    for _, e in ipairs(tpl) do placeOne(cell, ox, oy, oz, e, stat) end
    for sq in pairs(stat.sqset) do pcall(function() sq:RecalcAllWithNeighbours(true) end) end
    print("[AKA][SV] built "..size.." @ "..ox..","..oy.." floor="..stat.floor.." obj="..stat.obj.." nosq="..stat.nosq)
    return stat.nosq == 0
end
local function spawnOffset(size)
    local tpl = AkacampTpl[size]; if not tpl then return 1,1 end
    local fx,fy,n = 0,0,0
    for _,e in ipairs(tpl) do
        local z = (type(e[3])=="number") and e[3] or 0
        local k = (type(e[3])=="number") and e[4] or e[3]
        if z==0 and k=="floor" then fx=fx+e[1]; fy=fy+e[2]; n=n+1 end
    end
    if n==0 then return 1,1 end
    return math.floor(fx/n+0.5), math.floor(fy/n+0.5)
end

----------------------------------------------------------------------
-- item helpers (B42: instanceItem, never AddItem(string))
----------------------------------------------------------------------
local function giveItem(player, fulltype, opts)
    opts = opts or {}
    local sm = getScriptManager()
    if not (sm and sm:FindItem(fulltype)) then print("[AKA][SV] !! unknown item "..tostring(fulltype)); return nil end
    local inv = player:getInventory()
    local it = instanceItem(fulltype); if not it then return nil end
    if opts.mod then local d = it:getModData(); for k,v in pairs(opts.mod) do d[k]=v end end
    if opts.name then pcall(function() it:setName(opts.name) end) end
    if opts.color then local c = opts.color
        pcall(function() it:setColorRed(c[1]); it:setColorGreen(c[2]); it:setColorBlue(c[3]) end) end
    inv:AddItem(it)
    if sendAddItemToContainer then pcall(function() sendAddItemToContainer(inv, it) end) end
    return it
end
local function hasIngredients(inv, list)
    for _, ing in ipairs(list) do
        if inv:getNumberOfItem(ing.item) < (ing.count or 1) then return false, ing.item end
    end
    return true
end
local function consumeIngredients(inv, list)
    for _, ing in ipairs(list) do
        for _ = 1, (ing.count or 1) do
            local it = inv:getFirstTypeRecurse(ing.item)
            if it then inv:Remove(it); if sendRemoveItemFromContainer then pcall(function() sendRemoveItemFromContainer(inv, it) end) end end
        end
    end
end
local function ingList(list)
    local s = {} ; for _, g in ipairs(list or {}) do s[#s+1] = g.item.." x"..tostring(g.count or 1) end
    return table.concat(s, ", ")
end

----------------------------------------------------------------------
-- ADMIN ops
----------------------------------------------------------------------
local function adminPump(player, size)
    if not Akacamp.isStaff(player) then return end
    if not size or not (AkacampTpl and AkacampTpl[size]) then return end
    local sq = player:getCurrentSquare(); if not sq then return end
    local ox,oy,oz = sq:getX(), sq:getY(), sq:getZ()
    buildTent(ox, oy, oz, size)
    local md = data(); local id = md.nextId; md.nextId = id + 1
    local sx,sy = spawnOffset(size)
    md.slots[tostring(id)] = { id=id, size=size, x=ox, y=oy, z=oz, spawnX=ox+sx, spawnY=oy+sy, spawnZ=oz, owner=nil, kitId=nil }
    save(); print("[AKA][SV] pumped slot "..id.." "..size); broadcastRegistry()
end
local function adminRemove(player, slotId)
    if not Akacamp.isStaff(player) then return end
    if slotId == nil then return end
    local md = data(); local s = md.slots[tostring(slotId)]
    if s then s.owner = nil; s.kitId = nil; save(); print("[AKA][SV] cleared registration slot "..tostring(slotId)) end
    broadcastRegistry()
end
local function adminDelete(player, slotId)
    if not Akacamp.isStaff(player) then return end
    if slotId == nil then return end
    local md = data(); md.slots[tostring(slotId)] = nil; save()
    print("[AKA][SV] deleted slot "..tostring(slotId)); broadcastRegistry()
end
local function adminGiveKit(player, size)
    if not Akacamp.isStaff(player) then return end
    local ft = Akacamp.KIT_OF[size]; if not ft then return end
    giveItem(player, ft, nil); print("[AKA][SV] gave kit "..size)
end
local function adminSetRecipe(player, size, recipe)
    if not Akacamp.isStaff(player) or not size then return end
    local md = data(); md.config.recipe[size] = recipe or {}; save(); sendConfig(player)
    print("[AKA][SV] recipe["..size.."] set")
end
local function adminSetToll(player, size, toll)
    if not Akacamp.isStaff(player) or not size then return end
    local md = data(); md.config.toll[size] = toll or {}; save(); sendConfig(player)
    print("[AKA][SV] toll["..size.."] set")
end

----------------------------------------------------------------------
-- PLAYER ops
----------------------------------------------------------------------
local function findKit(player, size)
    local items = player:getInventory():getItems()
    for i=0, items:size()-1 do
        local it = items:get(i)
        if it:getFullType() == Akacamp.KIT_OF[size] then return it end
    end
end
local function playerUnpack(player, size)
    local kit = findKit(player, size); if not kit then return end
    local inv = player:getInventory()
    inv:Remove(kit); if sendRemoveItemFromContainer then pcall(function() sendRemoveItemFromContainer(inv, kit) end) end
    local kitId = Akacamp.newKitId()
    giveItem(player, "Akacamp.TentKey",    { mod={kitId=kitId, size=size}, name="Tent Key ("..size..")" })
    giveItem(player, "Akacamp.TentCanvas", { mod={kitId=kitId, size=size}, name="Tent Canvas ("..size..")" })
    print("[AKA][SV] "..player:getUsername().." unpacked "..size)
    sendServerCommand(player, "Akacamp", "msg", { text = "Unpacked: Tent Key + Canvas. Register the key, then craft the Canvas into a Tent Roll." })
end
local function playerRegister(player, kitId, size)
    if not kitId or not size then return end
    local md = data()
    for _,s in pairs(md.slots) do
        if s.kitId == kitId and s.owner == player:getUsername() then
            sendServerCommand(player,"Akacamp","registerResult",{ok=true, already=true, size=size}); return
        end
    end
    local pick
    for _,s in pairs(md.slots) do if s.size == size and not s.owner then pick = s; break end end
    if not pick then sendServerCommand(player,"Akacamp","registerResult",{ok=false, reason="no_free", size=size}); return end
    pick.owner = player:getUsername(); pick.kitId = kitId; save()
    print("[AKA][SV] "..player:getUsername().." registered slot "..pick.id.." "..size)
    sendServerCommand(player,"Akacamp","registerResult",{ok=true, slotId=pick.id, size=size})
    broadcastRegistry()
    broadcastRegistry()                                  -- live refresh for admins
end
-- craft the Canvas into a Tent Roll (the rolled-tent moveable you place)
local function playerCraftRoll(player, kitId, size)
    local md = data(); local recipe = md.config.recipe[size] or {}
    local inv = player:getInventory()
    local ok, missing = hasIngredients(inv, recipe)
    if not ok then sendServerCommand(player,"Akacamp","msg",{text="Need: "..ingList(recipe)}); return end
    consumeIngredients(inv, recipe)
    local items = inv:getItems()
    for i=0, items:size()-1 do
        local it = items:get(i)
        if it:getFullType()=="Akacamp.TentCanvas" and it:getModData().kitId==kitId then
            inv:Remove(it); if sendRemoveItemFromContainer then pcall(function() sendRemoveItemFromContainer(inv,it) end) end; break
        end
    end
    local ft = Akacamp.MOVEABLE_OF[size]
    if ft then giveItem(player, ft, nil) end        -- the rolled tent (place it, then right-click -> Enter)
    sendServerCommand(player,"Akacamp","msg",{text="Crafted a Tent Roll - place it, then right-click the tent to enter"})
    print("[AKA][SV] tent roll crafted "..size)
end
local function playerWarpIn(player, kitId)
    local md = data(); local slot
    for _,s in pairs(md.slots) do if s.kitId == kitId and s.owner == player:getUsername() then slot = s; break end end
    if not slot then sendServerCommand(player,"Akacamp","msg",{text="Not your tent / not registered"}); return end
    local toll = md.config.toll[slot.size] or {}
    local inv = player:getInventory()
    if #toll > 0 then
        local ok = hasIngredients(inv, toll)
        if not ok then sendServerCommand(player,"Akacamp","msg",{text="Entry toll: "..ingList(toll)}); return end
        consumeIngredients(inv, toll)
        print("[AKA][SV] "..player:getUsername().." paid toll "..slot.size)
    end
    sendServerCommand(player,"Akacamp","warpTo",{x=slot.spawnX, y=slot.spawnY, z=slot.spawnZ, store=true})
end

-- enter the tent the player just placed: claim/find an interior slot of the
-- tent's size for this player, pay the toll, and warp them in.
local function playerEnterTent(player, size, tx, ty, tz)
    if not size then return end
    -- range check: must be standing near the tent (within 2 tiles)
    if tx and ty then
        local px, py = player:getX(), player:getY()
        local dx, dy = px - (tx + 0.5), py - (ty + 0.5)
        if (dx*dx + dy*dy) > (2.5*2.5) then
            sendServerCommand(player,"Akacamp","msg",{text="Too far - stand next to the tent to enter"}); return
        end
    end
    local md = data(); local slot
    for _,s in pairs(md.slots) do
        if s.owner == player:getUsername() and s.size == size then slot = s; break end
    end
    if not slot then
        for _,s in pairs(md.slots) do
            if s.size == size and not s.owner then s.owner = player:getUsername(); slot = s; break end
        end
    end
    if not slot then
        sendServerCommand(player,"Akacamp","msg",{text="No "..tostring(size).." tent interior available (ask admin to pump one)"}); return
    end
    local toll = md.config.toll[size] or {}
    local inv = player:getInventory()
    if #toll > 0 then
        local ok = hasIngredients(inv, toll)
        if not ok then sendServerCommand(player,"Akacamp","msg",{text="Entry toll: "..ingList(toll)}); return end
        consumeIngredients(inv, toll)
    end
    save(); broadcastRegistry()
    sendServerCommand(player,"Akacamp","warpTo",{x=slot.spawnX, y=slot.spawnY, z=slot.spawnZ, store=true})
    print("[AKA][SV] "..player:getUsername().." entered "..size.." slot "..tostring(slot.id))
end

----------------------------------------------------------------------
local function adminWarp(player, slotId)
    if not Akacamp.isStaff(player) then return end
    local md = data(); local s = md.slots[tostring(slotId)]
    if not s then return end
    sendServerCommand(player,"Akacamp","warpTo",{x=s.spawnX, y=s.spawnY, z=s.spawnZ, store=true})
    print("[AKA][SV] admin "..player:getUsername().." warped to slot "..tostring(slotId))
end

local function onCmd(module, command, player, args)
    if module ~= "Akacamp" or not player then return end
    args = args or {}
    if     command == "admin_pump"      then adminPump(player, args.size)
    elseif command == "admin_remove"    then adminRemove(player, args.slotId)
    elseif command == "admin_delete"    then adminDelete(player, args.slotId)
    elseif command == "admin_warp"      then adminWarp(player, args.slotId)
    elseif command == "admin_giveKit"   then adminGiveKit(player, args.size)
    elseif command == "admin_setRecipe" then adminSetRecipe(player, args.size, args.recipe)
    elseif command == "admin_setToll"   then adminSetToll(player, args.size, args.toll)
    elseif command == "admin_registry"  then if Akacamp.isStaff(player) then sendServerCommand(player,"Akacamp","registry",{slots=data().slots,nextId=data().nextId}) end
    elseif command == "get_config"      then sendConfig(player)
    elseif command == "unpack"          then playerUnpack(player, args.size)
    elseif command == "register"        then playerRegister(player, args.kitId, args.size)
    elseif command == "make_zip"        then playerCraftRoll(player, args.kitId, args.size)
    elseif command == "craft_roll"      then playerCraftRoll(player, args.kitId, args.size)
    elseif command == "warp_in"         then playerWarpIn(player, args.kitId)
    elseif command == "enter_tent"      then playerEnterTent(player, args.size, args.x, args.y, args.z)
    end
end
Events.OnClientCommand.Add(onCmd)
print("[AKA][SV] Akacamp server v2 loaded")
