-- CookieServerPatch: FTZ Carts & Trolleys - carts are donation only (see server/CSP_FTZCartsCleanup.lua).
-- Client side. A player holding a cart that did not come from Cookie Express lets go of it,
-- with the same drop request FTZ uses for climbing/sitting (the game's heavy-item drop, done
-- by the server). The server file then removes the cart from the ground and leaves what was
-- inside on that square. Carts with item mod data "ckx_o" (Cookie Express) are kept.
-- ASCII only. To undo: remove this file and server/CSP_FTZCartsCleanup.lua.

if not isClient() then return end

local CLEAN_MAKESHIFT = false
local KEEP_KEY = "ckx_o"
local CHECK_MS = 2000

local TYPES = {
    ["Base.FTZ_ShoppingCart"] = true,
    ["Base.FTZ_PlatformTrolley"] = true,
    ["Base.FTZ_LaundryCart"] = true,
    ["Base.FTZ_GardenCart"] = true,
    ["Base.FTZ_JanitorCart"] = true,
    ["Base.FTZ_HandTruck"] = true,
    ["Base.FTZ_Wheelbarrow"] = true,
    ["Base.FTZ_MechanicCart"] = true,
}
if CLEAN_MAKESHIFT then TYPES["Base.FTZ_MakeshiftCart"] = true end

local function isTarget(item)
    if not item or not TYPES[item:getFullType()] then return false end
    if item:hasModData() and item:getModData()[KEEP_KEY] ~= nil then return false end
    return true
end

local nextCheck = 0
local lastDrop = {}

local function onTick()
    local now = getTimestampMs()
    if now < nextCheck then return end
    nextCheck = now + CHECK_MS
    for n = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(n)
        if p and not p:isDead() then
            if isTarget(p:getPrimaryHandItem()) or isTarget(p:getSecondaryHandItem()) then
                if not lastDrop[n] or now - lastDrop[n] > 3000 then
                    lastDrop[n] = now
                    sendClientCommand(p, "player", "onDropHeavyItem", { id = p:getOnlineID() })
                    print("[CookieServerPatch] ftz-drop: cart let go (donation only)")
                end
            end
        end
    end
end

Events.OnTick.Add(onTick)
print("[CookieServerPatch] ftz-drop on")
