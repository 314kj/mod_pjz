-- CookieServerPatch: change a vehicle's skin without debug mode.
--
-- How to use:
--   * outside: right-click the car body -> "Change skin (n/N)" -> Next /
--     Previous / pick one from the list (names come from the skin textures, so
--     the Cookie Car Skins packs show e.g. "Miku", "HelloKitty").
--   * inside: V (vehicle radial menu) -> "Next skin" / "Previous skin".
--     Right-click while seated also shows the menu when the game opens one.
-- Only cars whose script has 2 or more skins get the option (most trailers
-- and burnt wrecks have one skin, so they show nothing).
--
-- Who may change a skin (the server decides; the menu shows the same answer):
--   * ADMIN_ONLY = true (default): admins only (role with ManipulateVehicle
--     or admin powers), any car, any range. Other players do not see the
--     option at all, and the server refuses the command if sent by hand.
--   * ADMIN_ONLY = false: admins as above, and everyone else in the car or
--     within MAX_DIST tiles of it, when
--       - car claimed with Another Vehicle Claim System: whoever AVCS lets
--         use the car (owner; faction / safehouse members when AVCS allows)
--       - unclaimed car: allowed while ALLOW_UNCLAIMED is true
-- Free. The skin is saved with the car and sent to every player by the game's
-- own vehicle update (the same path as the debug skin tool:
-- setSkinIndex + transmitSkinIndex).
--
-- Log: "[CookieServerPatch] vehicle-skin on (...)" when the file loads, and on
-- the server one line per change:
--   "[CookieServerPatch] vehicle-skin: <user> <script> id=<n> skin <a> -> <b>"
-- ASCII only. No next() (Kahlua). No percent sign in translation strings.

local TAG = "[CookieServerPatch] vehicle-skin"
local MODULE = "CSPVehicleSkin"

-- settings ------------------------------------------------------------------
local ADMIN_ONLY = true      -- true: only admins can change skins (8 Nov: Pie)
local ALLOW_UNCLAIMED = true -- (ADMIN_ONLY = false only) false: unclaimed cars only by admins
local MAX_DIST = 8           -- tiles from the car's centre (long trucks / trailers)
local COOLDOWN_MS = 1000     -- per player, checked on the server
local PAGE = 20              -- skins per sub menu in the list
------------------------------------------------------------------------------

local CSPVehicleSkin = {}

local function isSP()
    return not isClient() and not isServer()
end

local function skinCount(v)
    local n = 0
    pcall(function() n = v:getSkinCount() end)
    return tonumber(n) or 0
end

local function skinIndex(v)
    local i = -1
    pcall(function() i = v:getSkinIndex() end)
    return tonumber(i) or -1
end

local function vehicleId(v)
    local id = nil
    pcall(function() id = v:getId() end)
    return id
end

local function scriptName(v)
    local s = "?"
    pcall(function() s = v:getScript():getFullName() end)
    return tostring(s)
end

local function isAdmin(p)
    if isSP() then return true end
    local ok, yes = pcall(function()
        local role = p:getRole()
        if not role then return false end
        if Capability and Capability.ManipulateVehicle and role:hasCapability(Capability.ManipulateVehicle) then
            return true
        end
        return role:hasAdminPower() == true
    end)
    return ok and yes == true
end

local function isNear(p, v)
    local ok, yes = pcall(function()
        local pv = p:getVehicle()
        if pv and pv:getId() == v:getId() then return true end
        local dx = p:getX() - v:getX()
        local dy = p:getY() - v:getY()
        local dz = math.abs(p:getZ() - v:getZ())
        return dz < 1.5 and (dx * dx + dy * dy) <= MAX_DIST * MAX_DIST
    end)
    return ok and yes == true
end

-- Another Vehicle Claim System: AVCS.checkPermission returns
--   true = not claimed, false = vehicle AVCS does not handle,
--   table = claimed, .permissions says if this player may use it.
local function claimAllows(p, v)
    local A = AVCS
    if type(A) ~= "table" or type(A.checkPermission) ~= "function" then
        if ALLOW_UNCLAIMED then return true end
        return false, "Unclaimed"
    end
    local ok, res = pcall(A.checkPermission, p, v)
    if not ok then return false, "NoPerm" end
    if res == true or res == false then
        if ALLOW_UNCLAIMED then return true end
        return false, "Unclaimed"
    end
    if type(res) == "table" and res.permissions == true then return true end
    return false, "NoPerm"
end

-- returns true, or false + the reason key (IGUI_CSP_VSkin_<key>)
function CSPVehicleSkin.canChange(p, v)
    if not p or not v then return false, "NoCar" end
    if skinCount(v) < 2 then return false, "OneSkin" end
    if isAdmin(p) then return true end
    if ADMIN_ONLY then return false, "AdminOnly" end
    if not isNear(p, v) then return false, "TooFar" end
    return claimAllows(p, v)
end

-- server (or single player): really change the skin. Returns a result key.
local function apply(p, v, idx)
    local n = skinCount(v)
    if type(idx) ~= "number" or idx ~= math.floor(idx) or idx < 0 or idx >= n then
        return "Failed"
    end
    local ok, key = CSPVehicleSkin.canChange(p, v)
    if not ok then return key end
    local old = skinIndex(v)
    if old == idx then return "Same" end
    local done = pcall(function()
        v:setSkinIndex(idx)
        if isServer() then
            v:transmitSkinIndex()
        else
            v:updateSkin()
        end
    end)
    if not done or skinIndex(v) ~= idx then return "Failed" end
    local user = "?"
    pcall(function() user = p:getUsername() end)
    print(TAG .. ": " .. tostring(user) .. " " .. scriptName(v) .. " id=" .. tostring(vehicleId(v))
        .. " skin " .. tostring(old + 1) .. " -> " .. tostring(idx + 1) .. " of " .. tostring(n))
    return "Done"
end

------------------------------------------------------------------------------
-- server
------------------------------------------------------------------------------
if isServer() then
    local lastAt = {}
    Events.OnClientCommand.Add(function(module, command, p, args)
        if module ~= MODULE or command ~= "set" then return end
        if not p or type(args) ~= "table" then return end
        local user = "?"
        pcall(function() user = p:getUsername() end)
        local now = getTimestampMs()
        local key
        if lastAt[user] and now - lastAt[user] < COOLDOWN_MS then
            key = "Wait"
        else
            lastAt[user] = now
            local v = nil
            local id = tonumber(args.vehicle)
            if id then pcall(function() v = getVehicleById(id) end) end
            if v then
                key = apply(p, v, tonumber(args.index))
            else
                key = "NoCar"
            end
        end
        sendServerCommand(p, MODULE, "result", { key = key, vehicle = args.vehicle, index = args.index })
    end)
end

------------------------------------------------------------------------------
-- players
------------------------------------------------------------------------------
if not isServer() then
    local function say(p, key)
        local text = getText("IGUI_CSP_VSkin_" .. tostring(key))
        if key == "Done" then
            pcall(HaloTextHelper.addGoodText, p, text)
        else
            pcall(HaloTextHelper.addBadText, p, text)
        end
    end

    local function request(p, v, idx)
        if not p or not v then return end
        local ok, key = CSPVehicleSkin.canChange(p, v)
        if not ok then
            say(p, key)
            return
        end
        if isSP() then
            say(p, apply(p, v, idx))
            return
        end
        sendClientCommand(p, MODULE, "set", { vehicle = vehicleId(v), index = idx })
    end
    CSPVehicleSkin.request = request

    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE or command ~= "result" then return end
        local p = getPlayer()
        if not p then return end
        local key = (args and args.key) or "Failed"
        if key == "Done" then
            -- show it at once; the game's vehicle update brings the same skin
            pcall(function()
                local v = getVehicleById(tonumber(args.vehicle))
                local i = tonumber(args.index)
                if v and i then
                    v:setSkinIndex(i)
                    v:updateSkin()
                end
            end)
        end
        say(p, key)
    end)

    -- skin names ------------------------------------------------------------
    local function baseName(tex)
        if type(tex) ~= "string" or tex == "" or tex == "BOGUS" then return nil end
        local s = string.gsub(tex, "\\", "/")
        s = string.match(s, "([^/]+)$") or s
        s = string.gsub(s, "%.[Pp][Nn][Gg]$", "")
        return s
    end

    -- drop the start every name shares ("Containers_Miku" -> "Miku")
    local function trimShared(names, n)
        for i = 1, n do
            if not names[i] then return end
        end
        local pre = names[1]
        for i = 2, n do
            local s = names[i]
            local k, m = 0, math.min(#pre, #s)
            while k < m and string.sub(pre, k + 1, k + 1) == string.sub(s, k + 1, k + 1) do
                k = k + 1
            end
            pre = string.sub(pre, 1, k)
            if pre == "" then return end
        end
        local cut = 0
        for j = #pre, 1, -1 do
            local c = string.sub(pre, j, j)
            if c == "_" or c == "-" or c == " " then
                cut = j
                break
            end
        end
        if cut == 0 then return end
        for i = 1, n do
            if string.sub(names[i], cut + 1) == "" then return end
        end
        for i = 1, n do
            names[i] = string.sub(names[i], cut + 1)
        end
    end

    -- The script's skin list is not readable from Lua outside debug mode, so
    -- ask the car itself: point it at each skin, read the texture name, and
    -- put it back. Only on this player's copy of the car, nothing is sent and
    -- the model is not redrawn.
    local function skinNames(v, n)
        local names = {}
        local cur = skinIndex(v)
        if cur < 0 or cur >= n then return names end
        pcall(function()
            for i = 0, n - 1 do
                v:setSkinIndex(i)
                names[i + 1] = baseName(v:getSkin())
            end
        end)
        pcall(function() v:setSkinIndex(cur) end)
        trimShared(names, n)
        return names
    end

    local function label(names, i)
        local s = tostring(i + 1)
        local name = names[i + 1]
        if name and name ~= "" then
            if #name > 36 then name = string.sub(name, 1, 34) .. ".." end
            s = s .. ". " .. name
        end
        return s
    end

    local function fillList(p, menu, v)
        local n = skinCount(v)
        local cur = skinIndex(v)
        local names = skinNames(v, n)
        local nxt, prv = 0, n - 1
        if cur >= 0 then
            nxt = (cur + 1) % n
            prv = (cur - 1 + n) % n
        end
        menu:addOption(getText("IGUI_CSP_VSkin_Next") .. ": " .. label(names, nxt), p, request, v, nxt)
        menu:addOption(getText("IGUI_CSP_VSkin_Prev") .. ": " .. label(names, prv), p, request, v, prv)
        local function addRange(m, a, b)
            for i = a, b do
                local text = label(names, i)
                if i == cur then text = text .. "  " .. getText("IGUI_CSP_VSkin_Now") end
                local o = m:addOption(text, p, request, v, i)
                if i == cur and o then o.notAvailable = true end
            end
        end
        if n <= PAGE then
            addRange(menu, 0, n - 1)
            return
        end
        local a = 0
        while a < n do
            local b = math.min(a + PAGE, n) - 1
            local o = menu:addOption(getText("IGUI_CSP_VSkin_List") .. " " .. (a + 1) .. "-" .. (b + 1))
            local sub = ISContextMenu:getNew(menu)
            menu:addSubMenu(o, sub)
            addRange(sub, a, b)
            a = b + 1
        end
    end

    -- right-click menu ----------------------------------------------------------
    local function addContext(player, context, v)
        local p = getSpecificPlayer(player)
        if not p or not v or not context then return end
        local n = skinCount(v)
        if n < 2 then return end
        local ok, key = CSPVehicleSkin.canChange(p, v)
        if not ok and key == "AdminOnly" then return end -- players do not see it
        local cur = skinIndex(v)
        local title = getText("IGUI_CSP_VSkin") .. " (" .. tostring(cur + 1) .. "/" .. tostring(n) .. ")"
        local opt = context:addOption(title, nil, nil)
        if not opt then return end
        if not ok then
            opt.notAvailable = true
            if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
                local tip = ISWorldObjectContextMenu.addToolTip()
                tip:setName(getText("IGUI_CSP_VSkin"))
                tip.description = getText("IGUI_CSP_VSkin_" .. tostring(key))
                opt.toolTip = tip
            end
            return
        end
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(opt, sub)
        fillList(p, sub, v)
    end

    -- radial menu (V) inside the car ----------------------------------------
    local icon = nil
    local function radialIcon()
        if icon then return icon end
        local sm = getScriptManager()
        for _, ft in ipairs({ "Base.PaintRed", "Base.PaintBlue", "Base.PaintWhite" }) do
            pcall(function()
                local s = sm:getItem(ft)
                if s and not icon then icon = getTexture("Item_" .. tostring(s:getIcon())) end
            end)
            if icon then return icon end
        end
        icon = getTexture("media/ui/vehicles/vehicle_repair.png")
        return icon
    end

    local function addSlices(p)
        if not p then return end
        local v = p:getVehicle()
        if not v then return end
        local n = skinCount(v)
        if n < 2 then return end
        if not CSPVehicleSkin.canChange(p, v) then return end
        local menu = getPlayerRadialMenu(p:getPlayerNum())
        if not menu or not menu:isReallyVisible() then return end
        for _, s in ipairs(menu.slices or {}) do
            if s.command and s.command[1] == request then return end
        end
        local cur = skinIndex(v)
        local nxt, prv = 0, n - 1
        if cur >= 0 then
            nxt = (cur + 1) % n
            prv = (cur - 1 + n) % n
        end
        local tex = radialIcon()
        menu:addSlice(getText("IGUI_CSP_VSkin_Next") .. " (" .. (nxt + 1) .. "/" .. n .. ")", tex, request, p, v, nxt)
        menu:addSlice(getText("IGUI_CSP_VSkin_Prev") .. " (" .. (prv + 1) .. "/" .. n .. ")", tex, request, p, v, prv)
    end

    local hooked = { context = false, radial = false }
    local function hook()
        if type(ISVehicleMenu) ~= "table" then return end
        if not hooked.context and type(ISVehicleMenu.FillMenuOutsideVehicle) == "function" then
            local orig = ISVehicleMenu.FillMenuOutsideVehicle
            ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
                local r = orig(player, context, vehicle, test)
                if not test then
                    local ok, err = pcall(addContext, player, context, vehicle)
                    if not ok then print(TAG .. ": menu error " .. tostring(err)) end
                end
                return r
            end
            hooked.context = true
        end
        if not hooked.radial and type(ISVehicleMenu.showRadialMenu) == "function" then
            local orig = ISVehicleMenu.showRadialMenu
            ISVehicleMenu.showRadialMenu = function(playerObj, ...)
                local r = orig(playerObj, ...)
                local ok, err = pcall(addSlices, playerObj)
                if not ok then print(TAG .. ": radial error " .. tostring(err)) end
                return r
            end
            hooked.radial = true
        end
    end

    -- seated in a car: the outside menu is not built, add ours if the game
    -- opens a world menu at all
    Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
        if test then return end
        local p = getSpecificPlayer(player)
        local v = p and p:getVehicle()
        if not v then return end
        local ok, err = pcall(addContext, player, context, v)
        if not ok then print(TAG .. ": menu error " .. tostring(err)) end
    end)

    Events.OnGameBoot.Add(hook)
    Events.OnGameStart.Add(function()
        hook()
        print(TAG .. " menus: right-click " .. tostring(hooked.context) .. ", radial " .. tostring(hooked.radial))
    end)
end

print(TAG .. " on (" .. (isServer() and "server" or (isClient() and "client" or "single player"))
    .. ", AVCS " .. ((type(AVCS) == "table" and type(AVCS.checkPermission) == "function") and "yes" or "no")
    .. (ADMIN_ONLY and ", admins only"
        or (", unclaimed cars " .. (ALLOW_UNCLAIMED and "allowed" or "admins only")
            .. ", range " .. MAX_DIST .. " tiles"))
    .. ")")

return CSPVehicleSkin
