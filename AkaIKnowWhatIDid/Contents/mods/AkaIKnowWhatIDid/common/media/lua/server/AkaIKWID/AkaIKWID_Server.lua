--[[
    Server side - the diary's actual storage.

    ModData "AkaIKWID_Books" = { v = 2,
                                books = { [username] = book },
                                perks = { [perkId] = {name, passive} },  -- what THIS server has
                                perksDay = <game day the list was last grown> }
    book = { signed, nickname, charName, signedDay,
             skills = {[perkId] = {xp, lvl}},
             recCharId, recChar, recDay, recHours,
             restoredBy = {[charId] = day} }

    One record per account. The item is only the key that opens it, so moving,
    dropping or dying with the book cannot wipe anything.
]]

require "AkaIKWID/AkaIKWID_Shared"

AkaIKWID_Server = AkaIKWID_Server or {}

local MODULE = AkaIKWID.MODULE

local DATA_VERSION = 3

--[[ v2 -> v3: everybody starts again.

     The records written before v3 were built under rules that have since been
     found wrong - baselines that froze people's work, and a merge that kept the
     highest single life instead of adding up what was played. Carrying those
     numbers forward would mean carrying the mistakes forward. So the skills,
     the read-back locks and the "who wrote last" stamps are cleared once.

     The signature and the nickname are KEPT: the player does not have to craft
     or sign anything again, their book just opens empty, exactly as it did the
     first time.

     It clears the BOOK and NOTHING ELSE. v3.1.0 also had clients rebuild their
     baseline on reset and that was a mistake - it made trait and occupation XP
     look earned, so the diary started writing down skills nobody had played
     for. A character's baseline is captured at spawn and is never touched by
     anything here. ]]
local function migrate(d)
    if (d.v or 2) >= DATA_VERSION then return end
    local n = 0
    for _, b in pairs(d.books or {}) do
        b.skills     = {}
        b.restoredBy = {}
        b.lastCharId, b.lastEarned = nil, nil
        b.recCharId, b.recChar, b.recDay, b.recHours = nil, nil, nil, nil
        n = n + 1
    end
    d.v       = DATA_VERSION
    d.resetAt = AkaIKWID.now()
    AkaIKWID.log("v3 fresh start: cleared " .. n .. " record(s), signatures kept")
end

local function db()
    local d = ModData.getOrCreate("AkaIKWID_Books")
    d.v     = d.v or 2
    d.books = d.books or {}
    d.perks = d.perks or {}
    migrate(d)
    return d
end

local function save()
    if ModData.transmit then pcall(function() ModData.transmit("AkaIKWID_Books") end) end
end

--[[ The server's own skill list, written down beside the diaries.

     Built lazily, not at load: on a dedicated server the perk list is only
     complete once every mod's scripts have registered, and a list captured too
     early would be short and then cached as gospel. The first client command of
     the session is comfortably after that.

     It only ever grows on its own. A skill that disappears (mod switched off)
     stays in the catalogue so a week-long absence does not throw away anybody's
     record - trimming is a deliberate admin act, not a side effect of a reboot. ]]
function AkaIKWID_Server.perks(force)
    local d    = db()
    local live = AkaIKWID.catalogue()
    local nLive, nHave = AkaIKWID.count(live), AkaIKWID.count(d.perks)

    if nLive > 0 and (force or nLive > nHave) then
        local added = 0
        for id, rec in pairs(live) do
            if not d.perks[id] then added = added + 1 end
            d.perks[id] = rec
        end
        d.perksDay = AkaIKWID.gameDay()
        save()
        if added > 0 then
            AkaIKWID.log("skill catalogue: " .. AkaIKWID.count(d.perks)
                         .. " skills known (" .. added .. " new)")
        end
    end
    return d.perks
end

-- everything in this record that this server cannot honour right now
function AkaIKWID_Server.orphans(username)
    local b = AkaIKWID_Server.get(username)
    local _, dropped = AkaIKWID.filterToKnown(b.skills, AkaIKWID.catalogue())
    return dropped
end

-- drop them for good. Admin only, and only when they mean it.
function AkaIKWID_Server.prune(username)
    local b = AkaIKWID_Server.get(username)
    local kept, dropped = AkaIKWID.filterToKnown(b.skills, AkaIKWID.catalogue())
    if #dropped == 0 then return b, 0 end
    b.skills = kept
    save()
    AkaIKWID.log("admin pruned " .. #dropped .. " unknown skills from " .. tostring(username)
                 .. ": " .. table.concat(dropped, ", "))
    return b, #dropped
end


function AkaIKWID_Server.get(username)
    if type(username) ~= "string" or username == "" then return AkaIKWID.emptyBook() end
    local d = db()
    d.books[username] = d.books[username] or AkaIKWID.emptyBook()
    local b = d.books[username]
    b.skills     = b.skills or {}
    b.restoredBy = b.restoredBy or {}
    b.resetAt    = d.resetAt          -- travels with the book so clients see it
    return b
end

function AkaIKWID_Server.sign(username, nick, charName)
    local b = AkaIKWID_Server.get(username)
    b.signed    = true
    b.nickname  = tostring(nick or "")
    b.charName  = tostring(charName or b.charName or "")
    b.signedDay = AkaIKWID.gameDay()
    save()
    AkaIKWID.log("signed: " .. tostring(username) .. " as " .. tostring(b.nickname))
    return b
end

function AkaIKWID_Server.record(username, data)
    local b = AkaIKWID_Server.get(username)
    if not b.signed then
        -- an admin repair may land on a book nobody has signed yet; sign it for
        -- them rather than refusing, otherwise the repair tool is useless on
        -- exactly the accounts that need it most
        if type(data) == "table" and data.admin then
            b.signed   = true
            b.nickname = tostring(b.nickname or data.charName or username)
            b.charName = tostring(data.charName or b.charName or "")
            b.signedDay = AkaIKWID.gameDay()
        else
            return b, "IGUI_AkaIKWID_ErrUnsigned"
        end
    end
    if type(data) ~= "table" or type(data.skills) ~= "table" then
        return b, "IGUI_AkaIKWID_ErrBadRequest"
    end

    --[[ Two ways in.

         mode "set" is the admin repair: the record becomes exactly what was
         sent, merged high-water so nothing already there is lost.

         Normal writing is ADDITIVE: the book keeps everything it has and gains
         only what this character has done since the last time it wrote. That is
         what makes "write it down once and it stays, and grows" true, and why a
         short new life can never shrink a long one. ]]
    if data.mode == "set" then
        b.skills = AkaIKWID.mergeSkills(b.skills, data.skills)
    else
        local prev = (b.lastCharId ~= nil and b.lastCharId == data.charId) and b.lastEarned or nil
        b.skills = AkaIKWID.addSkills(b.skills, data.skills, prev)

        -- remember what this character had already handed in, so the next press
        -- adds only the difference instead of the whole total again
        local mark = {}
        for id, rec in pairs(data.skills) do mark[id] = { xp = rec.xp or 0, lvl = rec.lvl or 0 } end
        b.lastCharId = data.charId
        b.lastEarned = mark
    end

    -- and drop anything that is not allowed in the book at all (Strength and
    -- Fitness with IncludePassive off). This also cleans out rows written by an
    -- older version, so a diary tidies itself the next time it is written in.
    for id in pairs(b.skills) do
        if not AkaIKWID.recordable(id) then b.skills[id] = nil end
    end
    b.recCharId = data.charId
    b.recChar   = data.charName
    b.recDay    = AkaIKWID.gameDay()
    b.recHours  = math.floor(tonumber(data.hours) or 0)
    save()
    AkaIKWID.log("recorded " .. tostring(AkaIKWID.bookSkillCount(b)) .. " skills for " .. tostring(username))
    return b
end

--[[ {ok, pct, given, total, levels, reason}

     The XP is handed over HERE, on the server, on the player object the server
     owns - the same thing a working B42 reward mod does. Granting from the
     receiving client was the old design and it is why skills "did not come
     back": the client's AddXP did not survive as the game expected.

     The client still folds the gift into its own baseline afterwards, because
     ModData belongs to the client. ]]
function AkaIKWID_Server.restore(username, charId, player)
    local b = AkaIKWID_Server.get(username)
    if type(charId) ~= "string" or charId == "" then
        return { ok = false, reason = "IGUI_AkaIKWID_ErrBadRequest" }
    end

    local why = AkaIKWID.whyNotRestore(b, charId)
    if why then
        -- say WHY in the log. "it just would not let me" is not a bug report,
        -- and these four reasons look identical from the outside.
        AkaIKWID.log("restore refused for " .. tostring(username) .. ": " .. tostring(why)
                     .. " (book has " .. AkaIKWID.bookSkillCount(b) .. " skills, written by "
                     .. tostring(b.recChar or "-") .. ")")
        return { ok = false, reason = why }
    end

    b.restoredBy[charId] = AkaIKWID.gameDay()
    save()

    local pct = AkaIKWID.restorePercent()
    AkaIKWID.log("restore granted " .. tostring(username) .. " char=" .. tostring(charId)
                 .. " pct=" .. tostring(pct))

    -- honour only what this server actually has; the rest stays in the record
    local kept, dropped = AkaIKWID.filterToKnown(b.skills, AkaIKWID_Server.perks())
    if #dropped > 0 then
        AkaIKWID.log("skipped " .. #dropped .. " skill(s) this server does not have: "
                     .. table.concat(dropped, ", "))
    end

    local res = AkaIKWID_Server.handOver(player, kept, pct)
    res.skipped = #dropped
    return res
end

-- the actual gift, wherever it is called from (normal restore or admin)
function AkaIKWID_Server.handOver(player, skills, pct)
    if not player then
        return { ok = false, reason = "IGUI_AkaIKWID_ErrDenied" }
    end
    local given, total, levels = AkaIKWID.applyXP(player, skills, pct)
    return { ok = true, pct = pct, given = given, total = total, levels = levels, applied = true }
end

-- ---------------------------------------------------------------- admin

-- ADMIN ONLY, and the access level is read from the PLAYER OBJECT THE SERVER
-- HAS, never from anything the client sent. A client asking nicely is not
-- authorisation - a modified client can put the menu back, it just gets told no.
function AkaIKWID_Server.isStaff(player)
    if AkaIKWID.isSP() then return true end
    local lvl = AkaIKWID.safe(function() return player:getAccessLevel() end, nil)
    return type(lvl) == "string" and lvl:lower() == "admin"
end

local function onlinePlayerNamed(username)
    local list = AkaIKWID.safe(function() return getOnlinePlayers() end, nil)
    if not list then return nil end
    local n = AkaIKWID.safe(function() return list:size() end, 0) or 0
    for i = 0, n - 1 do
        local p = AkaIKWID.safe(function() return list:get(i) end, nil)
        if p and AkaIKWID.username(p) == username then return p end
    end
    return nil
end

function AkaIKWID_Server.clearReaders(username)
    local b = AkaIKWID_Server.get(username)
    b.restoredBy = {}
    b.recCharId  = nil
    save()
    AkaIKWID.log("admin unlocked " .. tostring(username))
    return b
end

function AkaIKWID_Server.wipe(username)
    local b = AkaIKWID_Server.get(username)
    b.skills, b.restoredBy = {}, {}
    b.recCharId, b.recChar, b.recDay, b.recHours = nil, nil, nil, nil
    save()
    AkaIKWID.log("admin wiped " .. tostring(username))
    return b
end

-- do the fresh start again, on purpose
function AkaIKWID_Server.resetAll()
    local d = db()
    d.v = 2
    migrate(d)
    save()
    return AkaIKWID.count(d.books)
end

function AkaIKWID_Server.summary(username)
    local b   = AkaIKWID_Server.get(username)
    local orp = AkaIKWID_Server.orphans(username)
    local txt = string.format("%s: %s skills, %d EXP, written by %s on day %s",
        tostring(username), tostring(AkaIKWID.bookSkillCount(b)),
        math.floor(AkaIKWID.payout(b, 100)), tostring(b.recChar or "-"), tostring(b.recDay or "-"))
    txt = txt .. string.format(" | server knows %d skills", AkaIKWID.count(AkaIKWID_Server.perks()))
    if #orp > 0 then
        txt = txt .. string.format(" | %d not on this server: %s", #orp, table.concat(orp, ", "))
    end
    return txt
end

-- ---------------------------------------------------------------- net

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    args = args or {}
    local user = AkaIKWID.username(player)

    -- by now every mod has registered its skills, so this is a safe moment to
    -- write down what this server has. It is a no-op once the list stops growing.
    AkaIKWID.safe(function() AkaIKWID_Server.perks() end, nil)

    if command == "load" then
        sendServerCommand(player, MODULE, "book", { book = AkaIKWID_Server.get(user) })

    elseif command == "sign" then
        local b = AkaIKWID_Server.sign(user, args.nick, args.charName)
        sendServerCommand(player, MODULE, "book", { book = b, signed = true })

    elseif command == "record" then
        local b, err = AkaIKWID_Server.record(user, args)
        sendServerCommand(player, MODULE, "book", { book = b, recorded = (err == nil), reason = err })

    elseif command == "restore" then
        local res = AkaIKWID_Server.restore(user, args.charId, player)
        res.book = AkaIKWID_Server.get(user)
        sendServerCommand(player, MODULE, "restoreResult", res)

    elseif command == "admin" then
        if not AkaIKWID_Server.isStaff(player) then
            AkaIKWID.log("admin refused for " .. tostring(user))
            sendServerCommand(player, MODULE, "adminSaid", { text = "not an admin" })
            return
        end

        local who    = tostring(args.user or user)
        local what   = tostring(args.what or "")
        local target = onlinePlayerNamed(who)

        if what == "pull" then
            -- the server cannot read anybody's XP: ask that client for a full
            -- snapshot and let the normal record path merge it in
            if target then
                sendServerCommand(target, MODULE, "adminSnapshot", {})
                sendServerCommand(player, MODULE, "adminSaid", { text = "asked " .. who .. " for a snapshot" })
            else
                sendServerCommand(player, MODULE, "adminSaid", { text = who .. " is offline" })
            end

        elseif what == "grant" then
            local b   = AkaIKWID_Server.get(who)
            local pct = tonumber(args.pct) or 100
            if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
            if target then
                local res = AkaIKWID_Server.handOver(target, b.skills, pct)
                res.book, res.admin = b, true
                sendServerCommand(target, MODULE, "restoreResult", res)
                sendServerCommand(player, MODULE, "adminSaid",
                    { text = "gave " .. who .. " " .. pct .. "% = "
                             .. tostring(math.floor(res.total or 0)) .. " EXP" })
            else
                sendServerCommand(player, MODULE, "adminSaid", { text = who .. " is offline" })
            end

        elseif what == "unfreeze" then
            if target then
                sendServerCommand(target, MODULE, "adminUnfreeze", {})
                sendServerCommand(player, MODULE, "adminSaid", { text = who .. ": everything counts as earned now" })
            else
                sendServerCommand(player, MODULE, "adminSaid", { text = who .. " is offline" })
            end

        elseif what == "unlock" then
            AkaIKWID_Server.clearReaders(who)
            sendServerCommand(player, MODULE, "adminSaid", { text = who .. " may read again" })

        elseif what == "wipe" then
            AkaIKWID_Server.wipe(who)
            sendServerCommand(player, MODULE, "adminSaid", { text = who .. "'s diary is blank" })

        elseif what == "prune" then
            local _, n = AkaIKWID_Server.prune(who)
            sendServerCommand(player, MODULE, "adminSaid",
                { text = n == 0 and (who .. ": nothing to trim")
                                or (who .. ": removed " .. n .. " skill(s) this server does not have") })

        elseif what == "resetall" then
            local n = AkaIKWID_Server.resetAll()
            sendServerCommand(player, MODULE, "adminSaid",
                { text = "fresh start: " .. n .. " record(s) cleared, everyone counts again from now" })

        elseif what == "rescan" then
            local n = AkaIKWID.count(AkaIKWID_Server.perks(true))
            sendServerCommand(player, MODULE, "adminSaid",
                { text = "skill catalogue rebuilt: " .. n .. " skills" })

        elseif what == "info" then
            sendServerCommand(player, MODULE, "adminSaid", { text = AkaIKWID_Server.summary(who) })
        end
    end
end

if Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(function(module, command, player, args)
        local ok, err = pcall(onClientCommand, module, command, player, args)
        if not ok then AkaIKWID.log("server command error: " .. tostring(err)) end
    end)
end

AkaIKWID.log("server ready v" .. AkaIKWID.VERSION)
