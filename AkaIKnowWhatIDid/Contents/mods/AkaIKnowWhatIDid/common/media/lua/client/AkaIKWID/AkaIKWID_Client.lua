--[[
    Client side: baseline capture, opening the diary, and the net layer.
    The client never owns the record - it keeps a cache of what the server sent
    and asks again every time the book is opened.
]]

require "AkaIKWID/AkaIKWID_Shared"
require "AkaIKWID/AkaIKWID_UI"
require "AkaIKWID/AkaIKWID_Action"
require "AkaIKWID/AkaIKWID_Admin"

local MODULE = AkaIKWID.MODULE

AkaIKWID.book = AkaIKWID.book or AkaIKWID.emptyBook()

-- ---------------------------------------------------------------- baseline

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(idx, player)
        local ok, err = pcall(function()
            if not player then return end
            AkaIKWID.ensureBaseline(player)
            -- pull the record now, so the reminder and the item name are right
            -- even for somebody who has not opened the book this session
            AkaIKWID.requestLoad(player)
        end)
        if not ok then AkaIKWID.log("baseline error: " .. tostring(err)) end
    end)
end

-- ---------------------------------------------------------------- net

local function localServer()
    return AkaIKWID.isSP() and AkaIKWID_Server or nil
end

local function setBook(book)
    if type(book) == "table" then
        book.skills     = book.skills or {}
        book.restoredBy = book.restoredBy or {}
        AkaIKWID.book   = book

        --[[ NOTE: the fresh start clears the BOOK on the server and nothing
             else. It must never touch pd.base.

             v3.1.0 did touch it - it rebuilt the baseline from getPerkBoost,
             which reports boost LEVELS and no XP. Zeroing the XP side made all
             the experience an occupation hands over at spawn look like it had
             been earned, so the diary started writing down trait skills. The
             log caught it red handed:

                 baseline captured for Corey Bass (new=true)     <- correct
                 fresh start: baseline rebuilt from traits ...   <- clobbered it

             The baseline taken at spawn is already exactly "what you were born
             with". There is nothing to improve on and everything to lose. ]]
    end
end

function AkaIKWID.requestLoad(player)
    local S = localServer()
    if S then
        setBook(S.get(AkaIKWID.username(player)))
        AkaIKWID.onBookUpdated()
        return
    end
    sendClientCommand(player, MODULE, "load", {})
end

function AkaIKWID.requestSign(player, nick)
    local S = localServer()
    if S then
        setBook(S.sign(AkaIKWID.username(player), nick, AkaIKWID.charName(player)))
        AkaIKWID.onBookUpdated(AkaIKWID.T("IGUI_AkaIKWID_Signed", "Signed. This diary is yours now."))
        return
    end
    sendClientCommand(player, MODULE, "sign", { nick = nick, charName = AkaIKWID.charName(player) })
end

function AkaIKWID.requestRecord(player)
    local pd  = AkaIKWID.ensureBaseline(player)
    local req = {
        skills   = AkaIKWID.earned(player),
        charId   = pd.charId,
        charName = AkaIKWID.charName(player),
        hours    = math.floor(AkaIKWID.safe(function() return player:getHoursSurvived() end, 0) or 0),
    }

    local S = localServer()
    if S then
        local b = S.record(AkaIKWID.username(player), req)
        setBook(b)
        AkaIKWID.afterRecord(player)
        return
    end
    AkaIKWID.pendingRecord = player
    sendClientCommand(player, MODULE, "record", req)
end

function AkaIKWID.requestRestore(player)
    local pd = AkaIKWID.ensureBaseline(player)
    AkaIKWID.pendingRestore = player

    local S = localServer()
    if S then
        AkaIKWID.onRestoreResult(S.restore(AkaIKWID.username(player), pd.charId, player))
        return
    end
    sendClientCommand(player, MODULE, "restore", { charId = pd.charId })
end

-- ---------------------------------------------------------------- results

function AkaIKWID.onBookUpdated(status)
    local w = AkaIKWID.openWindow
    if w then
        if status then w:setStatus(status, false) end
        w:onBook()
    end
end

function AkaIKWID.afterRecord(player)
    local n = AkaIKWID.bookSkillCount(AkaIKWID.book)

    -- the diary writing itself must never steal the screen mid-fight
    if AkaIKWID.autoRecording then
        AkaIKWID.autoRecording = nil
        AkaIKWID.haloPlain(player, AkaIKWID.T("IGUI_AkaIKWID_AutoWrote",
            "Your diary wrote itself up to date."))
        return
    end

    AkaIKWID.halo(player, AkaIKWID.T("IGUI_AkaIKWID_Recorded", "Recorded") .. " " .. n .. " "
        .. AkaIKWID.T("IGUI_AkaIKWID_Skills", "skills"), false)
    AkaIKWID.openDiary(player, AkaIKWID.lastItem, { kind = "record", n = n })
end

function AkaIKWID.onRestoreResult(res)
    local player = AkaIKWID.pendingRestore or getPlayer()
    AkaIKWID.pendingRestore = nil
    if res and res.book then setBook(res.book) end

    if not res or not res.ok then
        local msg = AkaIKWID.reason(res and res.reason or "IGUI_AkaIKWID_ErrDenied")
        AkaIKWID.halo(player, msg, true)
        local w = AkaIKWID.openWindow
        if w then w:setStatus(msg, true) end
        return
    end

    local pct = res.pct or AkaIKWID.restorePercent()
    local given, total, levels

    if res.applied then
        -- the server already put the XP in; all that is left here is the
        -- bookkeeping, which lives in this client's ModData
        given, total, levels = res.given or {}, res.total or 0, res.levels or 0
        AkaIKWID.foldIntoBaseline(player, given)
    else
        given, total, levels = AkaIKWID.applyXP(player, res.skills, pct)
        AkaIKWID.foldIntoBaseline(player, given)
    end
    if res.admin then AkaIKWID.log("this restore was handed out by an admin") end

    local msg
    if total <= 0 then
        msg = AkaIKWID.reason("IGUI_AkaIKWID_NothingBack")
    else
        msg = AkaIKWID.T("IGUI_AkaIKWID_Done", "You remember") .. ": "
            .. tostring(math.floor(total)) .. " EXP (" .. tostring(pct) .. "%)"
        if (levels or 0) > 0 then
            msg = msg .. " - " .. levels .. " " .. AkaIKWID.reason("IGUI_AkaIKWID_Levels")
        end
    end
    AkaIKWID.halo(player, msg, false)
    AkaIKWID.openDiary(player, AkaIKWID.lastItem,
        { kind = "restore", given = given, total = total, pct = pct, msg = msg })
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then return end
    if AkaIKWID.onAdminCommand and AkaIKWID.onAdminCommand(command, args) then return end

    if command == "book" then
        if args and args.book then setBook(args.book) end
        if args and args.recorded then
            local p = AkaIKWID.pendingRecord or getPlayer()
            AkaIKWID.pendingRecord = nil
            AkaIKWID.afterRecord(p)
        else
            AkaIKWID.onBookUpdated(args and args.signed
                and AkaIKWID.T("IGUI_AkaIKWID_Signed", "Signed. This diary is yours now.") or nil)
        end

    elseif command == "restoreResult" then
        AkaIKWID.onRestoreResult(args)
    end
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        local ok, err = pcall(onServerCommand, module, command, args)
        if not ok then AkaIKWID.log("client command error: " .. tostring(err)) end
    end)
end

-- ---------------------------------------------------------------- opening it

local function collectItems(items)
    local out = {}
    for i = 1, #items do
        local entry = items[i]
        if type(entry) == "table" and entry.items then
            for j = 1, #entry.items do out[#out + 1] = entry.items[j] end
        else
            out[#out + 1] = entry
        end
    end
    return out
end

-- The item name is cosmetic and client-side, so a diary that has been dropped,
-- looted off a corpse or moved between bags comes back reading "Diary (New)"
-- until something touches it. Sweep the player's own inventory now and then.
local nextSweep = 0
function AkaIKWID.renameAll(player)
    if not player then return end
    local nick = AkaIKWID.book and AkaIKWID.book.signed and AkaIKWID.book.nickname or nil
    local inv  = AkaIKWID.safe(function() return player:getInventory() end, nil)
    if not inv then return end

    local list = AkaIKWID.safe(function() return inv:getAllTypeRecurse(AkaIKWID.ITEM) end, nil)
                 or AkaIKWID.safe(function() return inv:getItems() end, nil)
    if not list then return end

    local n = AkaIKWID.safe(function() return list:size() end, 0) or 0
    for i = 0, n - 1 do
        local it = AkaIKWID.safe(function() return list:get(i) end, nil)
        if it and AkaIKWID.isDiary(it) then
            AkaIKWID.safe(function() AkaIKWID.stamp(it, player) end, nil)
            AkaIKWID.safe(function() AkaIKWID.applyName(it, nick) end, nil)
        end
    end
end

-- the first diary this player is actually carrying, or nil
function AkaIKWID.findDiary(player)
    if not player then return nil end
    local inv = AkaIKWID.safe(function() return player:getInventory() end, nil)
    if not inv then return nil end

    local list = AkaIKWID.safe(function() return inv:getAllTypeRecurse(AkaIKWID.ITEM) end, nil)
                 or AkaIKWID.safe(function() return inv:getItems() end, nil)
    if not list then return nil end

    local n = AkaIKWID.safe(function() return list:size() end, 0) or 0
    for i = 0, n - 1 do
        local it = AkaIKWID.safe(function() return list:get(i) end, nil)
        if it and AkaIKWID.isDiary(it) then return it end
    end
    return nil
end

--[[ Once a day: is the diary behind, and does the player want to hear about it?

     Losing three weeks of skills because nobody pressed a sticker is the worst
     thing this mod could do to somebody, so there are two nets: a reminder
     (ReminderDays) and, if the admin turns it on, the book writing itself
     (AutoRecordDays). Both stay quiet unless there is really something new. ]]
local function dailyCheck()
    local player = getPlayer()
    if not player then return end

    local book = AkaIKWID.book
    if not (book and book.signed) then return end
    if not AkaIKWID.findDiary(player) then return end   -- no book on you, no nagging

    local p = AkaIKWID.pending(player, book)
    if p.xp <= 0 then return end

    local stale = AkaIKWID.staleDays(book) or 999
    local auto  = tonumber(AkaIKWID.opt("AutoRecordDays")) or 0
    if auto > 0 and stale >= auto then
        AkaIKWID.autoRecording = true
        AkaIKWID.requestRecord(player)
        return
    end

    local remind = tonumber(AkaIKWID.opt("ReminderDays")) or 0
    if remind > 0 and stale >= remind then
        AkaIKWID.haloPlain(player, AkaIKWID.T("IGUI_AkaIKWID_Remind", "Your diary is behind")
            .. ": " .. p.n .. " " .. AkaIKWID.T("IGUI_AkaIKWID_Skills", "skills")
            .. ", " .. math.floor(p.xp) .. " EXP")
    end
end

if Events and Events.EveryDays then
    Events.EveryDays.Add(function()
        local ok, err = pcall(dailyCheck)
        if not ok then AkaIKWID.log("daily check error: " .. tostring(err)) end
    end)
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(function(player)
        if not player or player ~= getPlayer() then return end
        local now = AkaIKWID.nowMs()
        if now < nextSweep then return end
        nextSweep = now + 4000
        pcall(AkaIKWID.renameAll, player)
    end)
end

local function onFillInventoryContext(playerIdx, context, items)
    local player = getSpecificPlayer(playerIdx)
    if not player then return end

    local diary
    for _, it in ipairs(collectItems(items)) do
        if AkaIKWID.isDiary(it) then diary = it break end
    end
    if not diary then return end

    local nick = AkaIKWID.book and AkaIKWID.book.signed and AkaIKWID.book.nickname or nil
    pcall(function() AkaIKWID.applyName(diary, nick) end)

    local mine  = AkaIKWID.isMine(diary, player)
    local label = mine and AkaIKWID.T("IGUI_AkaIKWID_Open", "Open diary")
                        or AkaIKWID.reason("IGUI_AkaIKWID_ErrNotYours")

    local option = context:addOptionOnTop(label, nil, function()
        AkaIKWID.openDiary(player, diary)
    end)
    if not mine and option then option.notAvailable = true end
end

if Events and Events.OnFillInventoryObjectContextMenu then
    Events.OnFillInventoryObjectContextMenu.Add(function(playerIdx, context, items)
        local ok, err = pcall(onFillInventoryContext, playerIdx, context, items)
        if not ok then AkaIKWID.log("context menu error: " .. tostring(err)) end
    end)
end

-- double click the diary in the inventory to open it - no right click needed
local function diaryUnderCursor(pane)
    local it = AkaIKWID.safe(function() return pane:getMouseOverItem() end, nil)
    if it and AkaIKWID.isDiary(it) then return it end
    it = AkaIKWID.safe(function() return pane.mouseOverItem end, nil)
    if it and AkaIKWID.isDiary(it) then return it end

    local sel = AkaIKWID.safe(function() return pane.selected end, nil)
    if type(sel) == "table" then
        for _, v in pairs(sel) do
            local cand = v
            if type(v) == "table" then cand = v.items and v.items[1] or v.item end
            if cand and AkaIKWID.isDiary(cand) then return cand end
        end
    end
    return nil
end

local function installDoubleClick()
    if AkaIKWID._dblInstalled then return end
    if not (ISInventoryPane and ISInventoryPane.onMouseDoubleClick) then return end
    AkaIKWID._dblInstalled = true

    local vanilla = ISInventoryPane.onMouseDoubleClick
    function ISInventoryPane:onMouseDoubleClick(x, y)
        local diary = AkaIKWID.safe(function() return diaryUnderCursor(self) end, nil)
        if diary then
            local pl = getSpecificPlayer(self.player or 0) or getPlayer()
            if pl then AkaIKWID.openDiary(pl, diary) return true end
        end
        return vanilla(self, x, y)
    end
    AkaIKWID.log("double click to open installed")
end

installDoubleClick()
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function() pcall(installDoubleClick) end)
end

AkaIKWID.log("client ready v" .. AkaIKWID.VERSION)
