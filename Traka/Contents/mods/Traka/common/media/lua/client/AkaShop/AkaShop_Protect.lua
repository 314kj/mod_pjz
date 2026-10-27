--[[===========================================================================
    AkaShop - "only an admin may move or break it".

    Not even the owner: a registered counter is a fixed piece of world furniture
    that the shop record is keyed to by coordinate. If the owner could pick it
    up, the record would be left pointing at an empty tile with their stock and
    till still inside it.

    There is no single chokepoint in B42 for picking up / scrapping / destroying
    a world object, so this file wraps every vanilla entry point it can find and
    also strips the offending context-menu entries. Anything it cannot find is
    simply skipped, so a future patch renaming a class degrades gracefully
    instead of erroring.
============================================================================]]

AkaShopProtect = AkaShopProtect or {}

--=============================================================== the check ==

--- Returns the shop entry when `character` must NOT touch the object on
--- `square`, or nil when they are free to. Only admins are ever free to.
function AkaShopProtect.blocked(character, square)
    if not AkaShop.protectEnabled() then return nil end
    if not square then return nil end

    local x, y, z
    local ok = pcall(function()
        x, y, z = square:getX(), square:getY(), square:getZ()
    end)
    if not ok or not x then return nil end

    local entry = AkaShopClient.index[AkaShop.key(x, y, z)]
    if not entry then return nil end

    local pl = character or AkaShopClient.me()
    if AkaShop.isAdmin(pl) then return nil end
    return entry
end

local lastWarn = nil
function AkaShopProtect.warn(entry)
    local t = nil
    pcall(function() t = getTimestampMs() end)
    if t and lastWarn and (t - lastWarn) < 2000 then return end
    lastWarn = t
    AkaShopClient.notify("\"" .. AkaShop.shopName(entry) ..
        "\" is a registered shop - only an admin can move or remove it.", true)
end

--========================================================= square sniffing ==

local function asSquare(v)
    if type(v) ~= "userdata" then return nil end
    local sq = nil
    pcall(function()
        if instanceof(v, "IsoGridSquare") then
            sq = v
        elseif instanceof(v, "IsoObject") then
            sq = v:getSquare()
        end
    end)
    return sq
end

local function findSquare(self, a1, a2, a3, a4)
    if type(self) == "table" then
        if self.square then
            local sq = asSquare(self.square)
            if sq then return sq end
        end
        if self.object then
            local sq = asSquare(self.object)
            if sq then return sq end
        end
        if self.moveableObject then
            local sq = asSquare(self.moveableObject)
            if sq then return sq end
        end
    end
    return asSquare(a1) or asSquare(a2) or asSquare(a3) or asSquare(a4)
end

local function asPlayer(v)
    if type(v) ~= "userdata" then return nil end
    local isPlayer = false
    pcall(function() isPlayer = instanceof(v, "IsoPlayer") end)
    return isPlayer and v or nil
end

local function charOf(self, a1, a2)
    if type(self) == "table" and self.character then return self.character end
    -- deliberately not ipairs{a1,a2}: a nil a1 would stop the iteration at once
    return asPlayer(a1) or asPlayer(a2) or AkaShopClient.me()
end

--============================================================= the wrappers =

local wrapped = {}

--- Wrap a method so it returns `falseValue` when the target tile is protected.
local function guard(className, methodName, falseValue)
    local cls = _G[className]
    if type(cls) ~= "table" or type(cls[methodName]) ~= "function" then return false end
    local orig = cls[methodName]
    cls[methodName] = function(self, a1, a2, a3, a4)
        local sq = findSquare(self, a1, a2, a3, a4)
        if sq then
            -- placing a NEW object on a shop tile is harmless; only moving,
            -- rotating, scrapping and destroying are blocked.
            local mode = (type(self) == "table") and self.mode or nil
            if mode ~= "place" then
                local entry = AkaShopProtect.blocked(charOf(self, a1, a2), sq)
                if entry then
                    AkaShopProtect.warn(entry)
                    return falseValue
                end
            end
        end
        return orig(self, a1, a2, a3, a4)
    end
    table.insert(wrapped, className .. ":" .. methodName)
    return true
end

local function installGuards()
    -- Only pure predicates are wrapped. A timed action whose isValid() turns
    -- false is stopped by the engine before perform() ever runs, so there is no
    -- need (and it would be unsafe) to short-circuit perform/start directly.
    guard("ISMoveablesAction",     "isValid", false)
    guard("ISMoveableCursor",      "isValid", false)
    guard("ISMoveableSpriteProps", "canPickUpMoveable", false)
    guard("ISMoveableSpriteProps", "canScrapObject",    false)

    -- destruction / disassembly
    guard("ISDestroyStuffAction",  "isValid", false)
    guard("ISScrapObjectAction",   "isValid", false)
    guard("ISRemoveItemFurniture", "isValid", false)

    if #wrapped > 0 then
        print("[Traka] protection installed on: " .. table.concat(wrapped, ", "))
    else
        print("[Traka] WARNING - no moveable classes found to protect")
    end
end

--============================================== context menu option removal =

local REMOVE_KEYS = {
    "ContextMenu_Pickup", "ContextMenu_PickUp", "ContextMenu_Disassemble",
    "ContextMenu_Rotate", "ContextMenu_Scrap", "ContextMenu_Destroy",
    "ContextMenu_PlaceInto", "ContextMenu_Grab",
}

local function stripOptions(playerNum, context, worldobjects, test)
    if test then return end
    local pl = getSpecificPlayer(playerNum)
    if not pl then return end

    local sq = nil
    for i = 1, #worldobjects do
        local o = worldobjects[i]
        if o and o.getSquare then
            sq = o:getSquare()
            if sq then break end
        end
    end

    local entry = AkaShopProtect.blocked(pl, sq)
    if not entry then return end

    for i = 1, #REMOVE_KEYS do
        pcall(function()
            local label = getText(REMOVE_KEYS[i])
            if label and label ~= "" then context:removeOptionByName(label) end
        end)
    end

    local o = context:addOptionOnTop(
        "Registered shop (" .. tostring(entry.owner) .. ") - admin only", nil, nil)
    o.notAvailable = true
end

--==================================================================== boot ==

Events.OnGameStart.Add(installGuards)
Events.OnFillWorldObjectContextMenu.Add(stripOptions)
