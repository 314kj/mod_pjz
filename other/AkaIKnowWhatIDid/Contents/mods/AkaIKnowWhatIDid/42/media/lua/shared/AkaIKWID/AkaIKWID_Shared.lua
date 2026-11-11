--[[
    AKA - I Know What I Did  (AkaIKnowWhatIDid)

    v2 data model - READ THIS BEFORE CHANGING ANYTHING
    --------------------------------------------------
    The diary's contents do NOT live on the item any more. B42 has no working
    InventoryItem:transmitModData(), so anything written on the item client-side
    was lost the moment the item went through the server: dropping it, putting it
    in a bag, or dying handed the player back a blank "new" diary.

    So: the book is a KEY, not a database. Everything is stored server-side,
    keyed by USERNAME (ModData "AkaIKWID_Books"). Any diary you hold opens YOUR
    record. That also gives "one written diary per player" for free - there is
    only ever one record per account, no matter how many blank books you craft.

    The item still carries a tiny cosmetic cache (the nickname, for the item
    name); if that is lost it is refilled from the server the next time the book
    is opened.

    Design rule: every engine call that might not exist on a given build is
    wrapped. A missing method must degrade to "feature off", never to "server
    does not boot" (PZ-B42-vehicle-spawn-RULE, rule 6).
]]

AkaIKWID = AkaIKWID or {}

AkaIKWID.MOD_ID  = "AkaIKnowWhatIDid"
AkaIKWID.VERSION = "3.1.3"
AkaIKWID.ITEM    = "Base.AkaDiary"
AkaIKWID.MODULE  = "AkaIKWID"

-- ---------------------------------------------------------------- utilities

function AkaIKWID.log(msg)
    print("[AkaIKWID] " .. tostring(msg))
end

function AkaIKWID.isSP()
    return (not isClient()) and (not isServer())
end

-- Every user-facing string also lives here in plain English. The translate
-- files are NOT reliable on a Thai client (getText returned the raw key in
-- testing), so nothing may depend on them: T() falls back to this table.
AkaIKWID.STR = {
    IGUI_AkaIKWID_ErrUnsigned   = "This diary is not signed yet.",
    IGUI_AkaIKWID_ErrEmpty      = "Nothing is written in this diary yet.",
    IGUI_AkaIKWID_ErrSameLife   = "Nice try. Go and die first.",
    IGUI_AkaIKWID_ErrAlready    = "You have already read this back.",
    IGUI_AkaIKWID_ErrDenied     = "The server refused this.",
    IGUI_AkaIKWID_ErrBadRequest = "Something is wrong with this diary.",
    IGUI_AkaIKWID_Levels        = "levels back",
    IGUI_AkaIKWID_NothingBack   = "Nothing came back - the diary was empty.",
    IGUI_AkaIKWID_Pending       = "not written down yet",
    IGUI_AkaIKWID_Remind        = "Your diary is behind",
    IGUI_AkaIKWID_AutoWrote     = "Your diary wrote itself up to date.",
    IGUI_AkaIKWID_Ready         = "ready",
    IGUI_AkaIKWID_Confirm       = "sure? click again",
    IGUI_AkaIKWID_Close         = "close  (ESC)",
    IGUI_AkaIKWID_Admin         = "AKA Diary (admin)",
    IGUI_AkaIKWID_AdmInfo       = "What is in the diary?",
    IGUI_AkaIKWID_AdmPull       = "Write ALL their skills into it",
    IGUI_AkaIKWID_AdmGrant      = "Give the skills back now (100%)",
    IGUI_AkaIKWID_AdmGrantP     = "Give the skills back now (sandbox %)",
    IGUI_AkaIKWID_AdmUnfreeze   = "Count what they already know as earned",
    IGUI_AkaIKWID_AdmUnlock     = "Let them read again",
    IGUI_AkaIKWID_AdmPrune      = "Trim skills this server does not have",
    IGUI_AkaIKWID_AdmRescan     = "Re-scan this server's skill list",
    IGUI_AkaIKWID_AdmResetAll   = "FRESH START for EVERYONE",
    IGUI_AkaIKWID_AdmWipe       = "Erase the diary",
    IGUI_AkaIKWID_ErrNotYours   = "This diary belongs to someone else.",
}

function AkaIKWID.reason(key)
    return AkaIKWID.T(key, AkaIKWID.STR[key] or key)
end

function AkaIKWID.T(key, fallback)
    local ok, s = pcall(getText, key)
    if (not ok) or s == nil or s == key then return fallback or key end
    return s
end

-- Kahlua returns nil when indexing a Java method that does not exist, so a
-- membership test is possible - and necessary: a pcall that fails still dumps
-- a full stack trace into console.txt every single time.
function AkaIKWID.has(obj, name)
    if obj == nil then return false end
    local ok, res = pcall(function() return obj[name] ~= nil end)
    return ok and res == true
end

local function safe(fn, default)
    local ok, res = pcall(fn)
    if ok and res ~= nil then return res end
    return default
end
AkaIKWID.safe = safe

function AkaIKWID.now()
    return safe(function() return getTimestamp() end, 0)
end

function AkaIKWID.nowMs()
    local ms = safe(function() return getTimestampMs() end, nil)
    if type(ms) == "number" then return ms end
    return (safe(function() return getTimestamp() end, 0) or 0) * 1000
end

function AkaIKWID.gameDay()
    return safe(function() return getGameTime():getNightsSurvived() end, 0)
end

function AkaIKWID.username(player)
    if not player then return "" end
    local u = safe(function() return player:getUsername() end, nil)
    if u == nil or u == "" then u = safe(function() return player:getDisplayName() end, "") end
    return tostring(u or "")
end

function AkaIKWID.charName(player)
    if not player then return "" end
    local n = safe(function()
        local d = player:getDescriptor()
        return ((d:getForename() or "") .. " " .. (d:getSurname() or "")):gsub("^%s+", ""):gsub("%s+$", "")
    end, "")
    if n == nil or n == "" then n = AkaIKWID.username(player) end
    return tostring(n or "")
end

-- forename / surname split, for the three tape labels on the cover
function AkaIKWID.nameParts(player)
    if not player then return "", "" end
    local f = safe(function() return player:getDescriptor():getForename() end, "") or ""
    local s = safe(function() return player:getDescriptor():getSurname() end, "") or ""
    if f == "" and s == "" then f = AkaIKWID.username(player) end
    return tostring(f), tostring(s)
end

--[[ Floating text, without betting on an overload that may not exist.

     B42 has no addText(IsoPlayer, String, ColorRGB):

         java.lang.RuntimeException: No implementation found for function:
         addText(IsoPlayer, String, HaloTextHelper$ColorRGB)

     and a call that misses its overload dumps a stack trace even from inside a
     pcall, so "wrap it and hope" is not a fix - the log fills up anyway. The
     only safe move is to try each call form ONCE, remember the one that worked,
     and never touch the losers again. One trace per bad form per session, then
     silence for ever. ]]
local haloMode   -- nil = not tried yet · 1..3 = the form that works · false = none

local function haloProbe(player, text)
    if pcall(function()
        HaloTextHelper.addTextWithArrow(player, text, true, HaloTextHelper.getColorGreen())
    end) then return 1 end
    if pcall(function() HaloTextHelper.addText(player, text) end) then return 2 end
    if pcall(function() player:Say(text) end) then return 3 end
    return false
end

function AkaIKWID.showText(player, text, bad)
    if not player or text == nil then return end
    text = tostring(text)

    if haloMode == nil then
        haloMode = haloProbe(player, text)
        AkaIKWID.log("halo text uses form " .. tostring(haloMode))
        return                      -- the probe already showed it
    end

    if haloMode == 1 then
        pcall(function()
            local col = bad and HaloTextHelper.getColorRed() or HaloTextHelper.getColorGreen()
            HaloTextHelper.addTextWithArrow(player, text, not bad, col)
        end)
    elseif haloMode == 2 then
        pcall(function() HaloTextHelper.addText(player, text) end)
    elseif haloMode == 3 then
        pcall(function() player:Say(text) end)
    end
end

function AkaIKWID.halo(player, text, bad)
    AkaIKWID.showText(player, text, bad)
end

function AkaIKWID.haloPlain(player, text)
    AkaIKWID.showText(player, text, false)
end

-- ---------------------------------------------------------------- sandbox

AkaIKWID.DEFAULTS = {
    RestorePercent         = 50,
    OncePerCharacter       = true,
    IncludePassive         = false,
    RestoredCountsAsEarned = false,
    BaselineExisting       = true,
    WriteSeconds           = 60,
    ReminderDays           = 3,   -- nag when the diary is this many days behind (0 = never)
    AutoRecordDays         = 0,   -- write it up to date by itself (0 = off, manual only)
}

function AkaIKWID.opt(key)
    local sv = SandboxVars and SandboxVars.AkaIKWID
    local v = sv and sv[key]
    if v == nil then return AkaIKWID.DEFAULTS[key] end
    return v
end

function AkaIKWID.restorePercent()
    local v = AkaIKWID.opt("RestorePercent")
    if type(v) ~= "number" then v = AkaIKWID.DEFAULTS.RestorePercent end
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return v
end

-- ---------------------------------------------------------------- perks

function AkaIKWID.perkList()
    if AkaIKWID._perks then return AkaIKWID._perks end
    local out = {}
    local list = safe(function() return PerkFactory.PerkList end, nil)
    if not list then return out end
    local n = safe(function() return list:size() end, 0)
    for i = 0, n - 1 do
        local perk = safe(function() return list:get(i) end, nil)
        if perk then
            local isLeaf = safe(function() return perk:getParent() ~= Perks.None end, true)
            local id     = safe(function() return tostring(perk:getId()) end, nil)
            if isLeaf and id and id ~= "" and id ~= "None" then
                out[#out + 1] = {
                    id      = id,
                    perk    = perk,
                    passive = safe(function() return perk:isPassiv() end, false) and true or false,
                    name    = safe(function() return PerkFactory.getPerkName(perk) end, id),
                }
            end
        end
    end
    --[[ Only keep the cache once it actually found something. Modded skills
         (Lifestyle's Cleaning, Music, ...) register into PerkFactory during
         script load, so a call that happens too early would otherwise freeze a
         short or empty list for the rest of the session and quietly drop them. ]]
    if #out > 0 then AkaIKWID._perks = out end
    return out
end

function AkaIKWID.perkById(id)
    for _, e in ipairs(AkaIKWID.perkList()) do
        if e.id == id then return e end
    end
    return nil
end

-- ---------------------------------------------------------------- baseline

function AkaIKWID.playerData(player)
    local md = player:getModData()
    md.AkaIKWID = md.AkaIKWID or {}
    return md.AkaIKWID
end

function AkaIKWID.snapshot(player)
    local out = {}
    for _, e in ipairs(AkaIKWID.perkList()) do
        out[e.id] = {
            xp  = safe(function() return player:getXp():getXP(e.perk) end, 0) or 0,
            lvl = safe(function() return player:getPerkLevel(e.perk) end, 0) or 0,
        }
    end
    return out
end

--[[ The baseline is everything the character was GIVEN at birth (occupation +
     traits). Anything above it was earned by playing, and only that is written. ]]
function AkaIKWID.ensureBaseline(player)
    local d = AkaIKWID.playerData(player)

    if not d.charId then
        d.charId = AkaIKWID.username(player) .. "#" .. tostring(AkaIKWID.now())
                   .. "-" .. tostring(safe(function() return ZombRand(1000000) end, 0))
                   .. "-" .. tostring(safe(function() return ZombRand(1000000) end, 0))
                   .. "-" .. tostring(AkaIKWID.charName(player))
    end

    if not d.base then
        local hours = safe(function() return player:getHoursSurvived() end, 0) or 0
        local isNew = (hours <= 1)

        --[[ Arrived late (the baseline went missing, or the mod was just
             installed). getPerkBoost was tried here in v3.1.0 and it is the
             wrong tool: it gives boost LEVELS with no XP, so using it as the
             baseline hands the occupation's XP to the diary as if the player
             had earned it. Back to the rule that was right for nine versions -
             the admin decides with BaselineExisting. ]]
        d.base = AkaIKWID.snapshot(player)
        d.baseNew = isNew
        if (not isNew) and (AkaIKWID.opt("BaselineExisting") == false) then
            local zero = {}
            for _, e in ipairs(AkaIKWID.perkList()) do zero[e.id] = { xp = 0, lvl = 0 } end
            d.base = zero
        end
        d.baseDay = AkaIKWID.gameDay()
        safe(function() player:transmitModData() end, nil)
        AkaIKWID.log("baseline captured for " .. AkaIKWID.charName(player)
                     .. " (new=" .. tostring(d.baseNew) .. ")")
    end

    return d
end

--[[ May this skill go in the diary at all?

     Strength and Fitness are the passive pair. They are not learned the way a
     craft is - they drift with what your body does - and handing them back made
     a fresh character feel like somebody else's. With IncludePassive off they
     are now skipped ENTIRELY: not recorded, not shown on the page, not restored.
     Off used to mean "recorded but never given back", which just left two rows
     on the page that could never do anything. ]]
function AkaIKWID.recordable(id)
    if AkaIKWID.opt("IncludePassive") == true then return true end
    local e = AkaIKWID.perkById(id)
    if e and e.passive then return false end
    return true
end

function AkaIKWID.earned(player)
    local d   = AkaIKWID.ensureBaseline(player)
    local now = AkaIKWID.snapshot(player)
    local out = {}
    for id, cur in pairs(now) do
      if AkaIKWID.recordable(id) then
        local b    = d.base[id] or { xp = 0, lvl = 0 }
        local dxp  = (cur.xp or 0) - (b.xp or 0)
        local dlvl = (cur.lvl or 0) - (b.lvl or 0)
        if dxp > 0.01 or dlvl > 0 then
            out[id] = { xp = dxp > 0 and dxp or 0, lvl = dlvl > 0 and dlvl or 0 }
        end
      end
    end
    return out
end

-- ---------------------------------------------------------------- the item

function AkaIKWID.isDiary(item)
    if not item then return false end
    return safe(function() return item:getFullType() end, "") == AkaIKWID.ITEM
end

function AkaIKWID.itemData(item)
    local md = item:getModData()
    md.AkaIKWID = md.AkaIKWID or {}
    return md.AkaIKWID
end

-- Best effort ownership mark. It lives in the item's ModData, which does not
-- survive a trip through the server in MP, so it is a courtesy lock: it stops
-- someone opening a book they picked up locally. It can never leak a record -
-- a diary always shows the reader's OWN account data, never the owner's.
function AkaIKWID.stamp(item, player)
    if not (item and player) then return end
    local d = AkaIKWID.itemData(item)
    if d.owner == nil or d.owner == "" then d.owner = AkaIKWID.username(player) end
end

function AkaIKWID.isMine(item, player)
    if not (item and player) then return true end
    local d = AkaIKWID.itemData(item)
    if d.owner == nil or d.owner == "" then return true end
    return d.owner == AkaIKWID.username(player)
end

-- cosmetic only: the real name lives on the server
function AkaIKWID.applyName(item, nickname)
    if not item then return end
    local title
    if nickname and nickname ~= "" then
        title = "Diary - " .. tostring(nickname)
        AkaIKWID.itemData(item).nickname = nickname
    else
        title = AkaIKWID.T("IGUI_AkaIKWID_NewDiary", "Diary (New)")
    end
    safe(function() item:setName(title) end, nil)
end

-- ---------------------------------------------------------------- the record

function AkaIKWID.emptyBook()
    return { signed = false, skills = {}, restoredBy = {} }
end

function AkaIKWID.bookSkillCount(book)
    if type(book) ~= "table" or type(book.skills) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(book.skills) do n = n + 1 end
    return n
end

--[[ What this life has learned that the diary does not know about yet.

     The single most expensive mistake a player can make with this mod is to
     play for three weeks and never press "record". This is what the page and
     the reminder are built on: {n = skills, xp = experience} that would be
     added if the book were written right now. ]]
function AkaIKWID.pending(player, book)
    local out = { n = 0, xp = 0 }
    if not player then return out end

    local have           = (type(book) == "table" and book.skills) or {}
    local includePassive = (AkaIKWID.opt("IncludePassive") == true)

    for id, rec in pairs(AkaIKWID.earned(player)) do
        local e = AkaIKWID.perkById(id)
        if e and (includePassive or not e.passive) then
            local written = (have[id] and have[id].xp) or 0
            local diff    = (rec.xp or 0) - written
            if diff > 0 then
                out.n  = out.n + 1
                out.xp = out.xp + diff
            end
        end
    end
    return out
end

-- how many days ago the diary was last written; nil = never written
function AkaIKWID.staleDays(book)
    if type(book) ~= "table" or book.recDay == nil then return nil end
    local d = AkaIKWID.gameDay() - (book.recDay or 0)
    if d < 0 then d = 0 end
    return d
end

-- what reading this book back would actually pay out, at the current percent
function AkaIKWID.payout(book, pct)
    if type(book) ~= "table" or type(book.skills) ~= "table" then return 0 end
    pct = pct or AkaIKWID.restorePercent()
    local includePassive = (AkaIKWID.opt("IncludePassive") == true)
    local total = 0
    for id, rec in pairs(book.skills) do
        local e = AkaIKWID.perkById(id)
        if e and (includePassive or not e.passive) then
            total = total + math.floor(((rec.xp or 0) * pct) / 100)
        end
    end
    return total
end

--[[ THE BOOK ADDS WHAT YOU ACTUALLY PLAYED. It never goes down.

     `prev` is what this same character had already written. The book gains the
     difference, so pressing record twice in a row adds nothing, and pressing it
     after an afternoon of carpentry adds exactly that afternoon.

         book 900, you had written 0,   you now show 200  -> book 1100
         book 1100, you had written 200, you now show 200 -> book 1100
         a new life starts with prev = {} and its own birth grant subtracted

     The XP the diary GAVE you is already excluded before it gets here (it goes
     into your baseline), so this cannot launder the same XP round and round -
     the book only ever grows by hours somebody actually put in. ]]
function AkaIKWID.addSkills(book, gained, prev)
    local out = {}
    for id, rec in pairs(book or {}) do
        if type(rec) == "table" then out[id] = { xp = rec.xp or 0, lvl = rec.lvl or 0 } end
    end
    for id, rec in pairs(gained or {}) do
        if type(rec) == "table" then
            local had  = (prev and prev[id]) or { xp = 0, lvl = 0 }
            local dxp  = (rec.xp  or 0) - (had.xp  or 0)
            local dlvl = (rec.lvl or 0) - (had.lvl or 0)
            if dxp > 0 or dlvl > 0 then
                local cur = out[id] or { xp = 0, lvl = 0 }
                if dxp  > 0 then cur.xp  = (cur.xp  or 0) + dxp  end
                if dlvl > 0 then cur.lvl = (cur.lvl or 0) + dlvl end
                if cur.lvl > 10 then cur.lvl = 10 end
                out[id] = cur
            end
        end
    end
    return out
end

--[[ Two lives folded into one record, keeping whichever value is larger.

     A diary is a HIGH WATER MARK, not a snapshot of the life that wrote last.
     Writing used to replace the whole list, so a fresh character who picked up
     the pen erased the life before it - and then had nothing to read back.

         book Carpentry 100, you bring  90 -> stays   100
         book Carpentry 100, you bring 150 -> becomes 150
         a skill the book never had         -> added

     Always returns a fresh table so nothing downstream shares a reference with
     the record that is already stored. ]]
function AkaIKWID.mergeSkills(oldSkills, newSkills)
    local out = {}
    for id, rec in pairs(oldSkills or {}) do
        if type(rec) == "table" then out[id] = { xp = rec.xp or 0, lvl = rec.lvl or 0 } end
    end
    for id, rec in pairs(newSkills or {}) do
        if type(rec) == "table" then
            local cur = out[id]
            if not cur then
                out[id] = { xp = rec.xp or 0, lvl = rec.lvl or 0 }
            else
                if (rec.xp  or 0) > (cur.xp  or 0) then cur.xp  = rec.xp  end
                if (rec.lvl or 0) > (cur.lvl or 0) then cur.lvl = rec.lvl end
            end
        end
    end
    return out
end

--[[ THE SKILL CATALOGUE - what this particular server actually has.

     Every server runs a different mod list. Lifestyle adds Cleaning and Music,
     another adds a dozen more, and the next wipe may drop them again. A diary
     written on a server that had Cleaning is meaningless on one that does not.

     So the server writes down its own skill list once, next to the diaries, and
     everything that reads a record checks against it first: an entry for a skill
     this server has never heard of is skipped, counted, and reported - never
     silently handed out and never quietly deleted either, because the mod may
     simply be switched off for a week.

     catalogue = { [perkId] = { name = "Cleaning", passive = false } } ]]
function AkaIKWID.catalogue()
    local out = {}
    for _, e in ipairs(AkaIKWID.perkList()) do
        out[e.id] = { name = e.name or e.id, passive = e.passive and true or false }
    end
    return out
end

function AkaIKWID.count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- split a record into what this server can honour and what it cannot
-- returns kept, dropped (dropped is a list of ids, for the message)
function AkaIKWID.filterToKnown(skills, known)
    local kept, dropped = {}, {}
    for id, rec in pairs(skills or {}) do
        if type(known) ~= "table" or AkaIKWID.count(known) == 0 or known[id] then
            kept[id] = rec
        else
            dropped[#dropped + 1] = id
        end
    end
    table.sort(dropped)
    return kept, dropped
end

-- why this character may not read the record; server checks the same thing
function AkaIKWID.whyNotRestore(book, charId)
    if type(book) ~= "table" or not book.signed then return "IGUI_AkaIKWID_ErrUnsigned" end
    if AkaIKWID.bookSkillCount(book) == 0 then return "IGUI_AkaIKWID_ErrEmpty" end
    if book.recCharId and book.recCharId == charId then return "IGUI_AkaIKWID_ErrSameLife" end
    if AkaIKWID.opt("OncePerCharacter") ~= false then
        local used = book.restoredBy or {}
        if used[charId] then return "IGUI_AkaIKWID_ErrAlready" end
    end
    return nil
end

--[[ Handing the XP over.

     THIS RUNS ON THE SERVER in multiplayer. The old build did it on the client
     because "PZ keeps XP on the owning client" - which is true for XP the
     character earns, but not for XP handed out. A working B42 reward mod
     (HF Town Rank) grants straight from a server-side client-command handler:

         local perk = Perks.FromString(id)
         player:getXp():AddXP(perk, amount, false, false, true)

     That is the call copied here, five arguments and all. It is the form that
     survives the round trip: the server owns the character object it is writing
     to, so the level-up and the sync happen the way the game expects.

     Bookkeeping (folding the gift into the baseline) is NOT done here - the
     player's ModData belongs to their own client, so it happens there. ]]
function AkaIKWID.perkFrom(id, entry)
    -- Perks.FromString is the direct route and exists on B42; perkList is the
    -- fallback for anything it does not know
    local p = safe(function() return Perks.FromString(id) end, nil)
    if p ~= nil then return p end
    if entry and entry.perk then return entry.perk end
    local e = AkaIKWID.perkById(id)
    return e and e.perk or nil
end

local function addXP(player, perk, amount)
    -- the five-argument form first: it is what the working reward mod uses
    local ok = pcall(function() player:getXp():AddXP(perk, amount, false, false, true) end)
    if ok then return end
    pcall(function() player:getXp():AddXP(perk, amount) end)
end

function AkaIKWID.applyXP(player, skills, pct)
    if not player then return {}, 0, 0 end
    local includePassive = (AkaIKWID.opt("IncludePassive") == true)
    local given, total, levels = {}, 0, 0

    for id, rec in pairs(skills or {}) do
        local e    = AkaIKWID.perkById(id)
        local perk = AkaIKWID.perkFrom(id, e)
        if perk and (includePassive or not (e and e.passive)) then
            local before   = safe(function() return player:getXp():getXP(perk) end, 0) or 0
            local beforeLv = safe(function() return player:getPerkLevel(perk) end, 0) or 0

            local amount = math.floor(((rec.xp or 0) * pct) / 100)
            if amount > 0 then
                addXP(player, perk, amount)
                given[id] = amount
                total = total + amount
            end

            --[[ NO LevelPerk. NOT EVER. This is what put players in debt.

                 LevelPerk raises the level WITHOUT handing over the experience
                 that level is supposed to cost. Do it after an AddXP and the two
                 numbers disagree: the perk sits at level 4 while the counter
                 still holds level-3 experience, so the bar in the skills panel
                 reads NEGATIVE and the player has to earn the shortfall back
                 before they can make any progress at all. They were given a
                 level and a debt in the same breath.

                 It was added when the two-argument AddXP appeared not to level
                 anybody up. The real problem was the call form; the five
                 argument version copied from a working B42 mod levels up by
                 itself, the way the game does it for a skill book. Hand over the
                 experience and let the engine decide what that is worth. ]]

            local afterXp = safe(function() return player:getXp():getXP(perk) end, before) or before
            local afterLv = safe(function() return player:getPerkLevel(perk) end, beforeLv) or beforeLv
            if amount > 0 or afterLv ~= beforeLv then
                levels = levels + (afterLv - beforeLv)
                AkaIKWID.log(("restore %s: xp %d -> %d (+%d asked), lv %d -> %d")
                    :format(tostring((e and e.name) or id), before, afterXp, amount, beforeLv, afterLv))
            end
        end
    end

    AkaIKWID.log("restored " .. tostring(total) .. " xp / " .. tostring(levels)
                 .. " levels at " .. tostring(pct) .. "%")
    return given, total, levels
end

--[[ XP you REMEMBERED is not XP you earned. Folding the gift into the baseline
     is what stops it being written back into the diary and passed around for
     ever. Runs on the receiving client, because that is who owns the ModData. ]]
function AkaIKWID.foldIntoBaseline(player, given)
    if not player or type(given) ~= "table" then return end
    local pd = AkaIKWID.ensureBaseline(player)

    if AkaIKWID.opt("RestoredCountsAsEarned") ~= true and type(pd.base) == "table" then
        for id, amount in pairs(given) do
            local b    = pd.base[id] or { xp = 0, lvl = 0 }
            local perk = AkaIKWID.perkFrom(id)
            b.xp = (b.xp or 0) + (tonumber(amount) or 0)
            if perk then b.lvl = safe(function() return player:getPerkLevel(perk) end, b.lvl) or b.lvl end
            pd.base[id] = b
        end
    end
    pd.restoredOnce = true
    safe(function() player:transmitModData() end, nil)
end

-- {name = "Carpentry", xp = 300} sorted biggest first
function AkaIKWID.rowsFromGiven(given)
    local rows = {}
    for id, amount in pairs(given or {}) do
        local e = AkaIKWID.perkById(id)
        rows[#rows + 1] = { name = (e and e.name) or id, xp = math.floor(amount or 0) }
    end
    table.sort(rows, function(a, b) return a.xp > b.xp end)
    return rows
end

-- {name, lvl, xp} sorted by levels then xp - what the diary holds
function AkaIKWID.rowsFromSkills(skills)
    local rows = {}
    for id, rec in pairs(skills or {}) do
      if AkaIKWID.recordable(id) then
        local e = AkaIKWID.perkById(id)
        rows[#rows + 1] = {
            -- a skill whose mod is not on this server any more: say so on the
            -- page rather than printing a bare internal id at the player
            name = (e and e.name) or (tostring(id) .. " (?)"),
            lvl  = rec.lvl or 0,
            xp   = math.floor(rec.xp or 0),
        }
      end
    end
    table.sort(rows, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl > b.lvl end
        return a.xp > b.xp
    end)
    return rows
end

AkaIKWID.log("shared loaded v" .. AkaIKWID.VERSION)
