--[[ Akacamp client: item right-click actions + warp + server replies ]]
require "Akacamp_Util"

local function teleport(player, x, y, z)
    player:setX(x);     player:setY(y);     player:setZ(z)
    player:setLastX(x); player:setLastY(y); player:setLastZ(z)
end

-- add an interior light at the tent (client-side, once per location per session)
local _lit = {}
local function addTentLight(x, y, z)
    local key = x..","..y..","..z
    if _lit[key] then return end
    _lit[key] = true
    pcall(function()
        local ls = IsoLightSource.new(x, y, z, 0.95, 0.90, 0.72, 8)
        getCell():addLamppost(ls)
    end)
end

-- right-click items
local function onItemContext(player, context, items)
    local pl = getSpecificPlayer(player)
    if not pl then return end
    local list = ISInventoryPane.getActualItems(items)
    for _, it in ipairs(list) do
        if not instanceof(it, "InventoryItem") then return end
        local ft = it:getFullType()
        local d = it:getModData()
        if Akacamp.SIZE_OF_KIT[it:getType()] then
            local size = Akacamp.SIZE_OF_KIT[it:getType()]
            context:addOption("Unpack Tent Kit ("..size..")", nil, function()
                sendClientCommand(pl, "Akacamp", "unpack", { size = size })
            end)
        elseif ft == "Akacamp.TentKey" then
            context:addOption("Register Key", nil, function()
                sendClientCommand(pl, "Akacamp", "register", { kitId = d.kitId, size = d.size })
            end)
        elseif ft == "Akacamp.TentCanvas" then
            context:addOption("Craft Tent Roll", nil, function()
                sendClientCommand(pl, "Akacamp", "craft_roll", { kitId = d.kitId, size = d.size })
            end)
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onItemContext)

-- right-click ground: warp out (only if currently inside a tent)
local function onWorldContext(player, context, worldobjects, test)
    if test then return end
    local pl = getSpecificPlayer(player)
    if not pl then return end

    -- right-click a placed tent -> Enter Tent (must be standing within range;
    -- server claims/finds an interior slot of this size, pays toll, warps in)
    for _, wo in ipairs(worldobjects) do
        if Akacamp.isTentObject and Akacamp.isTentObject(wo) then
            local size = Akacamp.tentSizeOf and Akacamp.tentSizeOf(wo)
            local sq = wo:getSquare()
            local tx = sq and sq:getX(); local ty = sq and sq:getY(); local tz = sq and sq:getZ()
            local near = true
            if tx and ty then
                local dx = pl:getX() - (tx + 0.5); local dy = pl:getY() - (ty + 0.5)
                near = (dx*dx + dy*dy) <= (2.5*2.5)
            end
            local label = near and "Enter Tent" or "Enter Tent (too far)"
            local opt = context:addOption(label, nil, function()
                if not near then return end
                sendClientCommand(pl, "Akacamp", "enter_tent", { size = size, x = tx, y = ty, z = tz })
            end)
            if not near then opt.notAvailable = true end
            break
        end
    end

    local ret = pl:getModData().akacampReturn
    if ret then
        context:addOption("Leave Tent (Warp out)", nil, function()
            teleport(pl, ret.x, ret.y, ret.z)
            pl:getModData().akacampReturn = nil
        end)
    end
end
Events.OnFillWorldObjectContextMenu.Add(onWorldContext)

-- server replies
local function onServerCmd(module, command, args)
    if module ~= "Akacamp" then return end
    args = args or {}
    local pl = getPlayer()
    if command == "msg" then
        if pl and args.text then pl:Say(args.text) end
    elseif command == "registerResult" then
        if pl then
            if args.ok then pl:Say(args.already and "Key already registered" or ("Registered ("..tostring(args.size)..")"))
            elseif args.reason == "no_free" then pl:Say("No free slot for "..tostring(args.size).." (ask admin)")
            else pl:Say("Register failed") end
        end
    elseif command == "warpTo" then
        if pl then
            if args.store then
                pl:getModData().akacampReturn = { x=pl:getX(), y=pl:getY(), z=pl:getZ() }
            end
            teleport(pl, args.x, args.y, args.z)
            addTentLight(args.x, args.y, args.z)
            pl:Say("Entered tent")
        end
    elseif command == "registry" then
        if AkacampAdmin and AkacampAdmin.onRegistry then AkacampAdmin.onRegistry(args) end
    elseif command == "config" then
        if AkacampAdmin and AkacampAdmin.onConfig then AkacampAdmin.onConfig(args) end
    end
end
Events.OnServerCommand.Add(onServerCmd)
print("[AKA][CL] Akacamp context loaded")
