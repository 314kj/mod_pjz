--[[
    The admin lever.

    Right click the ground -> "AKA Diary (admin)" -> pick a player -> pick a job.
    The menu only appears for a full ADMIN, and the SERVER checks access level
    again on every command: this menu is a convenience, not the security.

    Why it exists: XP in PZ is client-authoritative, so an admin cannot simply
    write skills into somebody else's character from their own machine. Every
    job here is "server tells that player's client to do it".
]]

require "AkaIKWID/AkaIKWID_Shared"

local MODULE = AkaIKWID.MODULE

--[[ ADMIN ONLY - not moderator, not gm, not overseer.

     These jobs hand out skill levels and erase records, so the bar is the top
     rank and nothing below it. Widening this to "any access level" was the
     first version and it quietly let every moderator grant 100% of anybody's
     diary. If a server ever wants that, change it here AND in the server file:
     the server checks for itself and does not trust this one. ]]
function AkaIKWID.isStaff(player)
    if AkaIKWID.isSP() then return true end
    local lvl = AkaIKWID.safe(function() return player:getAccessLevel() end, nil)
    return type(lvl) == "string" and lvl:lower() == "admin"
end

--[[ Floating text over a head is one short line, not a report. The admin
     summary is a paragraph, so the head gets the first clause and the whole
     thing goes to the log, where it can actually be read. ]]
local function say(text)
    text = tostring(text)
    AkaIKWID.log("admin: " .. text)

    local p = getPlayer()
    if not p then return end
    local short = text
    if #short > 60 then short = short:sub(1, 57) .. "..." end
    AkaIKWID.haloPlain(p, short)
end

local function send(player, what, user, pct)
    if AkaIKWID.isSP() then
        -- single player: no round trip, act on the one record there is
        local me = AkaIKWID.username(player)
        if what == "pull" then
            AkaIKWID.adminSnapshot(player)
        elseif what == "grant" then
            local b   = AkaIKWID_Server.get(me)
            local res = AkaIKWID_Server.handOver(player, b.skills, pct or 100)
            res.book, res.admin = b, true
            AkaIKWID.onRestoreResult(res)
        elseif what == "unfreeze" then
            AkaIKWID.adminUnfreeze(player)
        elseif what == "unlock" then
            AkaIKWID_Server.clearReaders(me); say("you may read again")
        elseif what == "wipe" then
            AkaIKWID_Server.wipe(me); say("diary is blank")
        elseif what == "prune" then
            local _, n = AkaIKWID_Server.prune(me)
            say(n == 0 and "nothing to trim" or ("removed " .. n .. " unknown skill(s)"))
        elseif what == "resetall" then
            say("fresh start: " .. AkaIKWID_Server.resetAll() .. " record(s) cleared")
        elseif what == "rescan" then
            say("skill catalogue: " .. AkaIKWID.count(AkaIKWID_Server.perks(true)) .. " skills")
        elseif what == "info" then
            say(AkaIKWID_Server.summary(me))
        end
        return
    end
    sendClientCommand(player, MODULE, "admin", { what = what, user = user, pct = pct })
end

-- ---------------------------------------------------------------- the jobs

-- everything this character has right now, traits included, straight into the
-- record. This is the repair tool for a diary that ended up empty.
function AkaIKWID.adminSnapshot(player)
    player = player or getPlayer()
    if not player then return end
    local pd   = AkaIKWID.ensureBaseline(player)
    local snap = {}
    for id, rec in pairs(AkaIKWID.snapshot(player)) do
        -- an admin repair still respects IncludePassive: no smuggling Fitness in
        if AkaIKWID.recordable(id) then snap[id] = rec end
    end
    local req  = {
        skills   = snap,
        charId   = nil,   -- deliberately unsigned: an admin repair must stay readable
        charName = AkaIKWID.charName(player) .. " (admin)",
        admin    = true,
        mode     = "set",   -- a repair replaces, it does not add on top
        hours    = math.floor(AkaIKWID.safe(function() return player:getHoursSurvived() end, 0) or 0),
    }
    if AkaIKWID.isSP() then
        AkaIKWID_Server.record(AkaIKWID.username(player), req)
        say("wrote everything you have into the diary")
        return
    end
    sendClientCommand(player, MODULE, "record", req)
    AkaIKWID.haloPlain(player, "Diary repaired by an admin.")
end

-- forget the trait/occupation baseline, so skills earned before the mod was
-- installed start counting as your own work
function AkaIKWID.adminUnfreeze(player)
    player = player or getPlayer()
    if not player then return end
    local pd = AkaIKWID.playerData(player)
    pd.base = {}
    for _, e in ipairs(AkaIKWID.perkList()) do pd.base[e.id] = { xp = 0, lvl = 0 } end
    pd.baseDay = AkaIKWID.gameDay()
    AkaIKWID.safe(function() player:transmitModData() end, nil)
    AkaIKWID.haloPlain(player, "Everything you know now counts as earned.")
    AkaIKWID.log("baseline cleared by admin for " .. AkaIKWID.charName(player))
end

-- ---------------------------------------------------------------- menu

local function targets()
    local out  = {}
    local list = AkaIKWID.safe(function() return getOnlinePlayers() end, nil)
    if list then
        local n = AkaIKWID.safe(function() return list:size() end, 0) or 0
        for i = 0, n - 1 do
            local p = AkaIKWID.safe(function() return list:get(i) end, nil)
            local u = p and AkaIKWID.username(p) or nil
            if u and u ~= "" then out[#out + 1] = { user = u, name = AkaIKWID.charName(p) } end
        end
    end
    if #out == 0 then
        local me = getPlayer()
        if me then out[1] = { user = AkaIKWID.username(me), name = AkaIKWID.charName(me) } end
    end
    return out
end

local function jobsFor(parent, player, user)
    local sub = ISContextMenu:getNew(parent)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmInfo",   "What is in the diary?"), nil,
                  function() send(player, "info", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmPull",   "Write ALL their skills into it"), nil,
                  function() send(player, "pull", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmGrant",  "Give the skills back now (100%)"), nil,
                  function() send(player, "grant", user, 100) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmGrantP", "Give the skills back now (sandbox %)"), nil,
                  function() send(player, "grant", user, AkaIKWID.restorePercent()) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmUnfreeze", "Count what they already know as earned"), nil,
                  function() send(player, "unfreeze", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmUnlock", "Let them read again"), nil,
                  function() send(player, "unlock", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmPrune",  "Trim skills this server does not have"), nil,
                  function() send(player, "prune", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmRescan", "Re-scan this server's skill list"), nil,
                  function() send(player, "rescan", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmWipe",   "Erase the diary"), nil,
                  function() send(player, "wipe", user) end)
    sub:addOption(AkaIKWID.T("IGUI_AkaIKWID_AdmResetAll", "FRESH START for EVERYONE"), nil,
                  function() send(player, "resetall", user) end)
    return sub
end

local function onWorldMenu(playerIdx, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIdx)
    if not player or not AkaIKWID.isStaff(player) then return end
    if not (ISContextMenu and ISContextMenu.getNew) then return end

    local root = context:addOption(AkaIKWID.T("IGUI_AkaIKWID_Admin", "AKA Diary (admin)"), nil, nil)
    local who  = ISContextMenu:getNew(context)
    context:addSubMenu(root, who)

    for _, t in ipairs(targets()) do
        local label = t.name ~= "" and (t.name .. "  [" .. t.user .. "]") or t.user
        local opt   = who:addOption(label, nil, nil)
        who:addSubMenu(opt, jobsFor(who, player, t.user))
    end
end

if Events and Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(function(idx, context, worldobjects, test)
        local ok, err = pcall(onWorldMenu, idx, context, worldobjects, test)
        if not ok then AkaIKWID.log("admin menu error: " .. tostring(err)) end
    end)
end

-- ---------------------------------------------------------------- from server

function AkaIKWID.onAdminCommand(command, args)
    if command == "adminSnapshot" then
        AkaIKWID.adminSnapshot(getPlayer())
        return true
    elseif command == "adminUnfreeze" then
        AkaIKWID.adminUnfreeze(getPlayer())
        return true
    elseif command == "adminSaid" then
        say(args and args.text or "")
        return true
    end
    return false
end

AkaIKWID.log("admin tools ready v" .. AkaIKWID.VERSION)
