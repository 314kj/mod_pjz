-- Cookie Helper : right-click menu for a part in the garage window
-- On top: "repair / install with things from the zone" - the character fetches what is missing
-- from the zone boxes first. If the zone does not have it but the rest of the safehouse does, it
-- asks before searching the whole house. Below: the game's own mechanics menu for that part
-- (repair, install, uninstall, windows, tires...), exactly as the mechanics window shows it.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Craft"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehiclePartMenu"
require "Vehicles/TimedActions/ISPathFindAction"

CHelp.VehFix = CHelp.VehFix or {}
local F = CHelp.VehFix
local UI = CHelp.UI
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local t = CHelp.t
local floor = math.floor

local function fixerType(fixing, name)
    if not name then return nil end
    if string.find(name, ".", 1, true) then return name end
    local okM, mod = pcall(function() return fixing:getModule():getName() end)
    return ((okM and mod) or "Base") .. "." .. name
end

local function usesOf(it)
    local ok, n = pcall(function() return it:getCurrentUses() end)
    if ok and type(n) == "number" and n > 0 then return n end
    return 1
end

local function notBroken(it)
    local ok, b = pcall(function() return it:isBroken() end)
    return not (ok and b)
end

-- items of full type ft in the boxes of entries (vehicle trunks skipped), fullest first
local function findItems(entries, ft, pred)
    local out, seen = {}, {}
    for _, e in ipairs(entries or {}) do
        if not e.veh and e.c then
            local ok, list = pcall(function() return e.c:getAllTypeRecurse(ft) end)
            if ok and list then
                for i = 0, list:size() - 1 do
                    local it = list:get(i)
                    if not seen[it] and (not pred or pred(it)) then
                        seen[it] = true
                        out[#out + 1] = it
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return usesOf(a) > usesOf(b) end)
    return out
end
F.findItems = findItems

-- enough items from list to reach `need` uses on top of `have`
local function pickUses(list, need, have)
    local picks, got = {}, have
    for _, it in ipairs(list) do
        if got >= need then break end
        picks[#picks + 1] = it
        got = got + usesOf(it)
    end
    return picks, got >= need
end

local function addTop(ctx, label, target, fn, a, b, c)
    local ok, opt = pcall(function() return ctx:addOptionOnTop(label, target, fn, a, b, c) end)
    if ok and opt then return opt end
    return ctx:addOption(label, target, fn, a, b, c)
end

local function tip(opt, title, text)
    local tt = ISToolTip:new()
    tt:initialise()
    tt:setVisible(false)
    if title then tt:setName(title) end
    tt.description = text
    opt.toolTip = tt
end

-- ------------------------------------------------------------------ repair
-- one fixer: what is in the bag, what the zone / the house would add
local function planFix(p, item, fixing, fixer, zoneE, houseE)
    local res = { skillsOk = true, needs = {}, zonePicks = {}, housePicks = {} }
    pcall(function()
        local skills = fixer:getFixerSkills()
        if skills then
            for j = 0, skills:size() - 1 do
                local sk = skills:get(j)
                if p:getPerkLevel(Perks.FromString(sk:getSkillName())) < sk:getSkillLevel() then res.skillsOk = false end
            end
        end
    end)
    local okU, haveU = pcall(function() return fixing:countUses(p, fixer, item) end)
    res.needs[#res.needs + 1] = { ft = fixerType(fixing, fixer:getFixerName()), need = fixer:getNumberOfUse(), have = (okU and haveU) or 0 }
    local g = fixing:getGlobalItem()
    if g then
        local okG, haveG = pcall(function() return fixing:countUses(p, g, nil) end)
        res.needs[#res.needs + 1] = { ft = fixerType(fixing, g:getFixerName()), need = g:getNumberOfUse(), have = (okG and haveG) or 0, global = true }
    end
    res.okInv, res.okZone, res.okHouse = true, true, true
    for _, n in ipairs(res.needs) do
        if n.have < n.need then
            res.okInv = false
            local zp, zok = pickUses(findItems(zoneE, n.ft, notBroken), n.need, n.have)
            for _, it in ipairs(zp) do res.zonePicks[#res.zonePicks + 1] = it end
            if not zok then res.okZone = false end
            if houseE then
                local hp, hok = pickUses(findItems(houseE, n.ft, notBroken), n.need, n.have)
                for _, it in ipairs(hp) do res.housePicks[#res.housePicks + 1] = it end
                if not hok then res.okHouse = false end
            else
                res.okHouse = false
            end
        end
    end
    return res
end

-- walk to the part, then the game's own repair (it checks the items again)
local function runFix(p, arg)
    local part = arg.part
    if not part:getInventoryItem() then return end
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, part:getVehicle(), part:getArea()))
    ISTimedActionQueue.queueActions(p, function(p2)
        local it = part:getInventoryItem()
        if not it then return end
        local okR, items = pcall(function()
            local fixing = FixingManager.getFixes(it):get(arg.fi)
            return fixing:getRequiredItems(p2, fixing:getFixers():get(arg.xi), it)
        end)
        if not (okR and items) then
            UI.toast(t("Msg_FixShort"), false)
            return
        end
        ISInventoryPaneContextMenu.onFix(it, p2:getPlayerNum(), arg.fi, arg.xi, part)
    end)
end

local function leaveCar(p)
    if p:getVehicle() then pcall(function() ISVehicleMenu.onExit(p) end) end
end

local function startFix(p, part, fi, xi, picks)
    if Craft.isBusy(p) then UI.toast(t("Msg_Busy"), false) return end
    leaveCar(p)
    local ok, why = Craft.fetchThen(p, picks, runFix, { part = part, fi = fi, xi = xi }, true)
    if not ok then UI.toast(t(why or "Msg_CantReach", ""), false) end
end

local function addRepair(ctx, p, part, zoneE, houseFn)
    local item = part:getInventoryItem()
    if not item then return false end
    local okS, mech = pcall(function() return part:getScriptPart():isRepairMechanic() end)
    if not (okS and mech) then return false end
    local fixes = FixingManager.getFixes(item)
    if not fixes or fixes:isEmpty() then return false end
    local houseE = houseFn and houseFn() or nil
    local root = addTop(ctx, t("FixFromZone"), nil, nil)
    root.iconTexture = CHelp.Th.tex("px_hammer")
    local sub = ISContextMenu:getNew(ctx)
    ctx:addSubMenu(root, sub)
    for fi = 0, fixes:size() - 1 do
        local fixing = fixes:get(fi)
        local fixers = fixing:getFixers()
        for xi = 0, fixers:size() - 1 do
            local fixer = fixers:get(xi)
            local pl = planFix(p, item, fixing, fixer, zoneE, houseE)
            local main = pl.needs[1]
            local label = fixer:getNumberOfUse() .. " " .. Scan.itemName(main.ft)
            local opt
            if not pl.skillsOk then
                opt = sub:addOption(label .. "  ·  " .. t("FixNoSkill"), nil, nil)
                opt.notAvailable = true
            elseif pl.okInv then
                opt = sub:addOption(label .. "  ·  " .. t("FromBag"), p, function(pp) startFix(pp, part, fi, xi, {}) end)
            elseif pl.okZone then
                opt = sub:addOption(label .. "  ·  " .. t("FromZone"), p, function(pp) startFix(pp, part, fi, xi, pl.zonePicks) end)
            elseif pl.okHouse then
                opt = sub:addOption(label .. "  ·  " .. t("FromHouse"), p, function(pp)
                    UI.confirm(t("HouseAskTitle"), t("HouseAskFix", Scan.itemName(main.ft)), t("HouseYes"), false, nil,
                        function() startFix(pp, part, fi, xi, pl.housePicks) end)
                end)
            else
                opt = sub:addOption(label .. "  ·  " .. t("NotAnywhere"), nil, nil)
                opt.notAvailable = true
            end
            opt.iconTexture = Scan.itemTex(main.ft)
            -- tooltip: what it needs, how much it fixes, the odds
            local lines = {}
            for _, n in ipairs(pl.needs) do
                local col = n.have >= n.need and " <GHC> " or " <BHC> "
                lines[#lines + 1] = col .. Scan.itemName(n.ft) .. " " .. floor(n.have) .. "/" .. n.need .. " <RGB:1,1,1> "
            end
            local okP, pct = pcall(function() return FixingManager.getCondRepaired(item, p, fixing, fixer) end)
            local okF, failP = pcall(function() return FixingManager.getChanceOfFail(item, p, fixing, fixer) end)
            if okP and pct then lines[#lines + 1] = t("FixGain", math.ceil(pct)) end
            if okF and failP then lines[#lines + 1] = t("FixChance", math.ceil(100 - failP)) end
            tip(opt, label, table.concat(lines, " <LINE> "))
        end
    end
    return true
end

-- ------------------------------------------------------------------ install a missing part
-- the part item plus the tools the install needs, from the zone (or the house)
local function toolPicks(p, part, entries)
    local picks, short = {}, false
    pcall(function()
        local tbl = part:getTable("install")
        if not tbl or not tbl.items then return end
        for _, itemTable in ipairs(VehicleUtils.getItemScripts(tbl.items)) do
            local need = tonumber(itemTable.item.count) or 1
            local have = 0
            for _, thing in ipairs(itemTable.scripts) do
                local ft = thing.script:getFullName()
                local okN, n = pcall(function() return p:getInventory():getCountTypeRecurse(ft) end)
                have = have + ((okN and n) or 0)
            end
            for _, thing in ipairs(itemTable.scripts) do
                if have >= need then break end
                for _, it in ipairs(findItems(entries, thing.script:getFullName(), notBroken)) do
                    if have >= need then break end
                    picks[#picks + 1] = it
                    have = have + 1
                end
            end
            if have < need then short = true end
        end
    end)
    return picks, short
end

local function runInstall(p, arg)
    local it = p:getInventory():getItemWithIDRecursiv(arg.id)
    if not it then
        UI.toast(t("Msg_FixShort"), false)
        return
    end
    ISVehiclePartMenu.onInstallPart(p, arg.part, it)
end

local function startInstall(p, part, it, entries)
    if Craft.isBusy(p) then UI.toast(t("Msg_Busy"), false) return end
    leaveCar(p)
    local picks = { it }
    local tools = toolPicks(p, part, entries)
    for _, x in ipairs(tools) do picks[#picks + 1] = x end
    local ok, why = Craft.fetchThen(p, picks, runInstall, { part = part, id = it:getID() }, true)
    if not ok then UI.toast(t(why or "Msg_CantReach", ""), false) end
end

local function addInstall(ctx, p, part, zoneE, houseFn)
    if part:getInventoryItem() then return false end
    local types = part:getItemType()
    if not types or types:isEmpty() or not part:getTable("install") then return false end
    local inZone, inHouse = {}, {}
    for i = 0, types:size() - 1 do
        local ft = types:get(i)
        if not string.find(ft, ".", 1, true) then ft = "Base." .. ft end
        for _, it in ipairs(findItems(zoneE, ft, notBroken)) do inZone[#inZone + 1] = it end
    end
    local houseE = nil
    if #inZone == 0 and houseFn then
        houseE = houseFn()
        for i = 0, types:size() - 1 do
            local ft = types:get(i)
            if not string.find(ft, ".", 1, true) then ft = "Base." .. ft end
            for _, it in ipairs(findItems(houseE, ft, notBroken)) do inHouse[#inHouse + 1] = it end
        end
    end
    local root = addTop(ctx, t("InstallFromZone"), nil, nil)
    root.iconTexture = CHelp.Th.tex("px_crate")
    if #inZone == 0 and #inHouse == 0 then
        root.notAvailable = true
        tip(root, nil, t("InstallNone"))
        return true
    end
    local sub = ISContextMenu:getNew(ctx)
    ctx:addSubMenu(root, sub)
    local list, fromHouse = inZone, false
    if #inZone == 0 then list, fromHouse = inHouse, true end
    for i, it in ipairs(list) do
        if i > 12 then break end
        local okC, cond = pcall(function() return it:getCondition() end)
        local label = it:getDisplayName() .. ((okC and type(cond) == "number") and (" (" .. cond .. "%)") or "")
            .. "  ·  " .. (fromHouse and t("FromHouse") or t("FromZone"))
        local opt = sub:addOption(label, p, function(pp)
            if fromHouse then
                UI.confirm(t("HouseAskTitle"), t("HouseAskFix", it:getDisplayName()), t("HouseYes"), false, nil,
                    function() startInstall(pp, part, it, houseE) end)
            else
                startInstall(pp, part, it, zoneE)
            end
        end)
        opt.itemForTexture = it
        local okC, can = pcall(function() return part:getVehicle():canInstallPart(p, part) end)
        if okC and not can then tip(opt, nil, t("InstallCheck")) end
    end
    return true
end

-- ------------------------------------------------------------------ the menu
-- opts = { zoneFn = fn() -> entries, houseFn = fn() -> entries|nil, onCraft = fn(ft)|nil }
function F.partMenu(p, part, x, y, opts)
    opts = opts or {}
    local pn = p:getPlayerNum()
    local ctx = nil
    -- the game's own part menu, built as if the mechanics window asked for it
    pcall(function()
        local proxy = setmetatable({ chr = p, playerNum = pn, vehicle = part:getVehicle(),
            getAbsoluteX = function() return 0 end, getAbsoluteY = function() return 0 end }, { __index = ISVehicleMechanics })
        ISVehicleMechanics.doPartContextMenu(proxy, part, x, y)
        ctx = proxy.context
    end)
    if not ctx then ctx = ISContextMenu.get(pn, x, y) end
    -- the game's own Repair entry expects you standing at the car (its window closes otherwise);
    -- ours below walks there and covers the same fixes, so drop the game's one
    if part:getId() ~= "lightbar" and part:getInventoryItem() then
        pcall(function() ctx:removeOptionByName(getText("ContextMenu_Repair")) end)
    end
    local zoneE = opts.zoneFn and opts.zoneFn() or {}
    local any = false
    if opts.onCraft then
        local ft = nil
        local item = part:getInventoryItem()
        if item then ft = item:getFullType()
        else
            local types = part:getItemType()
            if types and not types:isEmpty() then
                ft = types:get(0)
                if not string.find(ft, ".", 1, true) then ft = "Base." .. ft end
            end
        end
        if ft and #Craft.recipesFor(ft) > 0 then
            local o = addTop(ctx, t("CraftThisPart"), ft, opts.onCraft)
            o.iconTexture = CHelp.Th.tex("px_anvil")
            any = true
        end
    end
    local okI, inst = pcall(addInstall, ctx, p, part, zoneE, opts.houseFn)
    if not okI then CHelp.log("install menu failed: " .. tostring(inst)) end
    local okR, rep = pcall(addRepair, ctx, p, part, zoneE, opts.houseFn)
    if not okR then CHelp.log("repair menu failed: " .. tostring(rep)) end
    any = any or (okI and inst) or (okR and rep)
    local n = ctx.numOptions or (#(ctx.options or {}) + 1)
    ctx:setVisible(any or n > 1)
    return ctx
end
