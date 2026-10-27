-- Cookie Server Patches: PhunMart never sells items from the mods below.
--
-- Every item those mods define goes onto PhunMart's item blacklist on the server,
-- so no machine puts it on its shelves. The list is built from the game's own
-- item scripts (each knows which mod added it), so new items from these mods
-- are covered without editing this file.
-- PhunMart_Blacklist.json is left alone: these items are added in memory only,
-- and stripped again whenever an admin saves the blacklist from PhunMart's UI.
--
-- Shops that already stocked these items keep them until they restock.
-- To clear them at once: PhunMart admin → Tools → "Restock every machine".
-- Logged at server start as "[CookieServerPatch] PhunMart: ...".

local HIDE_MODS = { "Rabbit", "nangongyiyi", "BundleUp", "BundleUpUI", "BundleUpVFX", "BundleUpGoM" }

if isClient() then return end -- the server builds the shelves

local TAG = "[CookieServerPatch] PhunMart"
local hidden, counts

local function modKey(raw)
    if raw == nil then return nil end
    local s = tostring(raw)
    s = s:match("([^\\/]+)$") or s -- "\BundleUp" / "3746632343\BundleUp" -> BundleUp
    return string.lower(s)
end

local function buildHidden()
    hidden, counts = {}, {}
    local wanted = {}
    for _, m in ipairs(HIDE_MODS) do wanted[string.lower(m)] = m end
    local sm = getScriptManager and getScriptManager()
    if not sm then return end
    local ok, items = pcall(function() return sm:getAllItems() end)
    if not ok or not items then return end
    local byModule = {} -- fallback when this build has no item:getModID(): match the script module name
    local modIdWorks = false
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local okF, full = pcall(function() return item:getFullName() end)
        local okM, mid = pcall(function() return item:getModID() end)
        if okM then modIdWorks = true end
        local name = okM and wanted[modKey(mid) or ""] or nil
        if okF and full then
            if name then
                hidden[tostring(full)] = true
                counts[name] = (counts[name] or 0) + 1
            elseif not okM then
                local module = tostring(full):match("^([^%.]+)%.")
                local mname = module and wanted[string.lower(module)]
                if mname then byModule[#byModule + 1] = { tostring(full), mname } end
            end
        end
    end
    if not modIdWorks then
        for _, e in ipairs(byModule) do
            hidden[e[1]] = true
            counts[e[2]] = (counts[e[2]] or 0) + 1
        end
        print(TAG .. ": item:getModID() not available, matched by module name instead")
    end
end

local function install()
    local Core = PhunMart
    if type(Core) ~= "table" or type(Core.getBlacklist) ~= "function" then return false end
    if Core.cspHideMods then return true end
    local origGet, origSet = Core.getBlacklist, Core.setBlacklist

    Core.getBlacklist = function(refresh)
        local list = origGet(refresh)
        if type(list) ~= "table" then return list end
        if not hidden then buildHidden() end
        list.items = list.items or {}
        list.items.exclude = list.items.exclude or {}
        for full in pairs(hidden) do list.items.exclude[full] = true end
        return list
    end

    if type(origSet) == "function" then
        Core.setBlacklist = function(data)
            local ex = type(data) == "table" and type(data.items) == "table" and data.items.exclude
            if not (hidden and type(ex) == "table") then return origSet(data) end
            local keep = {}
            for k, v in pairs(ex) do
                if not hidden[k] then keep[k] = v end
            end
            local items = {}
            for k, v in pairs(data.items) do items[k] = v end
            items.exclude = keep
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.items = items
            return origSet(copy)
        end
    end

    Core.cspHideMods = true
    return true
end

local function report()
    if not install() then
        print(TAG .. " not loaded - nothing to patch")
        return
    end
    if not hidden then buildHidden() end
    local parts, total = {}, 0
    for _, m in ipairs(HIDE_MODS) do
        local n = counts and counts[m] or 0
        total = total + n
        if n > 0 then parts[#parts + 1] = m .. " " .. n end
    end
    print(TAG .. ": hiding " .. total .. " items from shops (" .. (#parts > 0 and table.concat(parts, ", ") or "none found") .. ")")
end

Events.OnGameBoot.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(report) end
