--[[===========================================================================
    Traka - item packs.

    A depot row normally names one item type. That falls apart for jewellery:
    Project Zomboid splits a ring into a separate item per finger per hand, an
    earring per ear, and so on. An admin who wants to buy "rings" has to add
    fourteen rows, and the board fills with fourteen cards showing the same
    picture at the same price. Nobody reads a board like that.

    A PACK is one row that matches a whole family of item types. One price, one
    quota, one clock, and one card on the board.

    WHY THE MEMBERSHIP IS DISCOVERED, NOT TYPED OUT.

    The obvious implementation is a hard-coded list of ring fullTypes. It is
    also wrong twice over: it breaks the day the game renames or adds one, and
    it silently excludes every ring that any other mod on the server adds -
    which on a server running a jewellery mod is most of them.

    So packs are built by reading the script manager at runtime and grouping by
    BODY LOCATION. Whatever is worn on a finger is a ring, whoever added it.
    The rules below are patterns against that location name, not item lists.

    The one trap in here is "ear". `Beard` contains it, and a pack that buys
    beards is a funny bug report to receive. That is why earrings match a small
    list of anchored patterns instead of a bare substring, and why every other
    rule uses a stem that cannot collide ("finger", "wrist", "necklace").

    WHEN THE BODY LOCATION IS NOT THERE AT ALL.

    v3.5.1. An admin opened the picker and found no packs in it. An empty pack
    is hidden from that list on purpose - offering a row nobody can ever sell
    into is worse than offering nothing - so "no packs" and "packs are broken"
    look identical from the outside.

    The cause is that `Item:getBodyLocation()` is not guaranteed. On a build
    where the method is missing, or answers "" for clothing whose location is
    declared somewhere else, EVERY pack comes out empty and the feature simply
    is not there.

    So there is a second pass, and it runs on ONE condition: the first pass
    matched nothing whatsoever. Not "this pack is empty" - nothing, anywhere.
    That is the only state that means the signal itself is missing rather than
    the server having no jewellery. The fallback then matches item names, with
    patterns anchored much harder than the location ones, because a name is a
    far noisier thing to read: "finger" as a bare substring would swallow every
    pair of fingerless gloves on the server, which is the beard trap wearing a
    different hat.
============================================================================]]

AkaShopPacks = AkaShopPacks or {}
local P = AkaShopPacks

--- Marker that turns a pack id into something that can sit in an entry's `ft`
--- field. Entries are keyed by `ft` all over the codebase; giving a pack a
--- reserved fullType keeps every "is this already listed" check working
--- without teaching it what a pack is. No real item can collide - "@" is not
--- legal in a module name.
P.PREFIX = "@pack:"

--- `pats`  match the BODY LOCATION, lowercased. The normal road.
--- `npats` match the ITEM NAME, lowercased, and are only ever consulted when
---         the body location told us nothing at all (see the header). They are
---         anchored on purpose: a name is read by people, so it contains words
---         like "fingerless" that a location never would.
P.RULES = {
    { id = "ring",     name = "Jewelry - Ring",             pats = { "finger" },
      npats = { "^ring_", "^ring$", "_ring_", "_ring$" } },
    { id = "earring",  name = "Jewelry - Earring",          pats = { "^ear", "earring", "_ear" },
      npats = { "^earring", "_earring", "^ear_", "_ear_" } },
    { id = "necklace", name = "Jewelry - Necklace",         pats = { "necklace" },
      npats = { "necklace", "pendant" } },
    { id = "wrist",    name = "Jewelry - Bracelet / Watch", pats = { "wrist" },
      npats = { "^bracelet", "_bracelet", "wristwatch", "^watch_", "^watch$", "wrist" } },
    { id = "nose",     name = "Jewelry - Nose",             pats = { "nose" },
      npats = { "^nose", "_nose" } },

    -- v3.5.2. The navel was the hole in the vanilla set: the game calls that
    -- slot BellyButton, which contains none of the stems above, so a belly bar
    -- fell through every rule and had to be listed one item at a time.
    { id = "navel",    name = "Jewelry - Navel",            pats = { "belly", "navel" },
      npats = { "^navel", "_navel", "^belly", "_belly", "bellybutton" } },

    -- Everything else a modded jewellery pack tends to add. Deliberately last
    -- and deliberately narrow: these are words that only ever appear on a
    -- piercing, never on ordinary clothing.
    { id = "piercing", name = "Jewelry - Piercing (other)",
      pats  = { "piercing", "eyebrow", "septum", "tongue", "^lip$", "^lips$", "_lip$" },
      npats = { "piercing", "^eyebrow", "_eyebrow", "septum", "^tongue", "_tongue" } },
}

P.ALL = { id = "jewelry", name = "Jewelry - everything" }

--============================================================== sub-packs ===
--[[ "Jewelry - Ring" is one row that buys every ring on the server, and that is
     exactly what an admin wants right up until it is not. Buying rings at 250
     each means buying the plain steel band at 250 too, and a player with a
     hundred of those has found a money printer.

     So each family is also cut into DESIGNS. Project Zomboid stores a ring as
     one item per finger per hand - Ring_Left_RingFinger_GoldRuby,
     Ring_Right_MiddleFinger_GoldRuby and so on - which means the four items an
     admin thinks of as "the gold ruby ring" are four fullTypes that differ only
     in where they are worn. Strip the position out of the name and what is left
     IS the design.

     That is the whole trick, and it is why this needs no item lists: the game
     has already told us which items are the same ring by naming them the same
     way. A modded ring named to the same convention is grouped for free; one
     named to no convention at all ends up in a design of its own, which is
     correct - it IS its own design.

     A design of one member is hidden from the picker. It would be a pack that
     means exactly one item, which the item row underneath already says. ]]

--- Words that describe WHERE a piece is worn rather than WHAT it is. Removing
--- them from a name leaves the design. "ring" is in here on purpose: it is the
--- position word in "RingFinger" far more often than it is a distinguishing
--- part of a ring's name, and dropping it merges "Ring_Left_RingFinger_Gold"
--- and "Ring_Right_MiddleFinger_Gold" into one design, which is the point.
P.POS_WORDS = {
    ring = true, finger = true, middle = true, index = true, thumb = true,
    little = true, pinky = true, left = true, right = true, l = true, r = true,
    ear = true, ears = true, eartop = true, top = true, bottom = true,
    upper = true, lower = true, wrist = true, wrists = true, neck = true,
    nose = true, navel = true, belly = true, button = true, bellybutton = true,
    front = true, back = true, both = true, piercing = true,
    ["1"] = true, ["2"] = true, ["01"] = true, ["02"] = true,
}

--- Break a fullType into the words a human would read in it.
--- Splits on separators AND on camelCase, so "Ring_Left_RingFinger_GoldRuby"
--- becomes Ring / Left / Ring / Finger / Gold / Ruby.
local function words(ft)
    local short = string.match(ft, "([^.]+)$") or ft
    local out = {}
    for chunk in string.gmatch(short, "[^_%-%s]+") do
        -- camelCase boundary: a capital that follows a lowercase or a digit
        local spaced = string.gsub(chunk, "(%l)(%u)", "%1 %2")
        spaced = string.gsub(spaced, "(%d)(%u)", "%1 %2")
        for w in string.gmatch(spaced, "%S+") do table.insert(out, w) end
    end
    return out
end

--- Words that EVERY member of a family shares.
---
--- A word carried by all of them distinguishes none of them: "Earring" in the
--- earring family is the family's own name written out again, and "Earring -
--- Earring Silver" is not a label anybody wants to read. Dropping it is not a
--- hard-coded list of family stems - it is the same idea one level up, and it
--- works for a modded family nobody anticipated.
---
--- The rule is deliberately "in ALL", not "in most". Within the wrist family
--- "Watch" is in half the members, and that half is exactly the distinction the
--- designs exist to draw, so it stays.
local function commonWords(fts)
    if #fts < 2 then return {} end
    local counts = {}
    for _, ft in ipairs(fts) do
        local seen = {}
        for _, w in ipairs(words(ft)) do
            local k = string.lower(w)
            if not seen[k] then seen[k] = true; counts[k] = (counts[k] or 0) + 1 end
        end
    end
    local out = {}
    for k, n in pairs(counts) do if n == #fts then out[k] = true end end
    return out
end

--- The design key and a human label for it. A name that is nothing but position
--- words is itself a design - "the plain one" - rather than an error.
local function designOf(ft, common)
    local kept = {}
    for _, w in ipairs(words(ft)) do
        local k = string.lower(w)
        if not P.POS_WORDS[k] and not (common and common[k]) then
            table.insert(kept, w)
        end
    end
    if #kept == 0 then
        -- Everything was stripped. Try again ignoring the family's shared
        -- words: better a redundant label than every item collapsing into one
        -- design called "plain".
        if common then return designOf(ft, nil) end
        return "plain", "plain"
    end
    return string.lower(table.concat(kept, "")), table.concat(kept, " ")
end
P.designOf = designOf

--=============================================================== building ===

local cache = nil

local function matches(loc, pats)
    for _, p in ipairs(pats) do
        if string.find(loc, p) then return true end
    end
    return false
end

--- Ask a script item one question, safely, ONCE.
---
--- Two things are being defended against and they pull in opposite directions.
--- A method that does not exist on this build must not be called four thousand
--- times, because in Kahlua each miss costs a full stack dump in console.txt.
--- But `type(it.getMethod) == "function"` was not trusted either, and using it
--- as a gate was how the whole pack feature came to be silently switched off in
--- v3.5.0.
---
--- v3.5.1 swung the other way - always try, remember the failure - and that
--- worked, at the price of ONE stack dump per missing method per boot. Which a
--- server owner then quite reasonably reported as an error, because a Java
--- stack trace in console.txt looks exactly like a crash whether it was caught
--- or not.
---
--- v3.7.2 stops guessing about `type()` and CALIBRATES it instead. Every script
--- item certainly has getFullName - the walk has just called it - so asking
--- `type(it.getFullName)` tells us whether type() can be believed about Java
--- methods on THIS build. If it can, a missing method is detected without ever
--- calling it, and console.txt stays clean. If it cannot, we fall back to the
--- v3.5.1 behaviour and eat the one dump.
---
--- The lesson worth keeping: when a reflection mechanism is unreliable, test
--- the mechanism against something known rather than arguing about it.
local typeTrusted = nil

local function calibrate(it)
    if typeTrusted == nil then
        typeTrusted = (type(it.getFullName) == "function")
    end
    return typeTrusted
end

local function prober(method)
    local alive = true
    return function(it)
        if not alive then return nil end

        -- Definitely absent, and we know it without touching it.
        if calibrate(it) and type(it[method]) ~= "function" then
            alive = false
            return nil
        end

        local v
        if not pcall(function() v = it[method](it) end) then alive = false; return nil end
        if type(v) ~= "string" or v == "" then return nil end
        return v
    end,
    function() return alive end
end

--- The item name with the module stripped: "Base.Ring_LeftRingFinger" ->
--- "ring_leftringfinger". The module is dropped because a modder's prefix is
--- noise here, and because "SomeMod.Ring" and "Base.Ring" are the same word.
local function shortName(ft)
    local s = string.match(ft, "([^.]+)$") or ft
    return string.lower(s)
end

--- Walk every item in the game once and sort it into packs.
--- Cached for the session: this is a few thousand items and the answer cannot
--- change without a restart, since scripts are loaded before any of this runs.
function P.build()
    if cache then return cache end

    local byId, order = {}, {}
    local function bucket(id, name)
        local b = byId[id]
        if not b then
            b = { id = id, name = name, fts = {}, set = {}, n = 0 }
            byId[id] = b
            table.insert(order, b)
        end
        return b
    end
    for _, r in ipairs(P.RULES) do bucket(r.id, r.name) end
    local all = bucket(P.ALL.id, P.ALL.name)

    local function put(b, ft)
        if b.set[ft] then return end
        b.set[ft] = true
        b.n = b.n + 1
        table.insert(b.fts, ft)
    end

    -- Everything worth reading about every item, gathered in ONE walk. The
    -- walk is the expensive part; a second pass over this small table is free,
    -- and it means the fallback below costs nothing on a server where the
    -- normal road works.
    local askLoc, locLives = prober("getBodyLocation")
    -- Two spellings, because which one exists depends on the build and the
    -- other one costs a single stack dump to find out.
    local askClo  = prober("getClothingItem")
    local askClo2 = prober("getClothingItemName")
    local rows, sawLoc = {}, false

    pcall(function()
        local list = getScriptManager():getAllItems()
        for i = 0, list:size() - 1 do
            local it = list:get(i)
            local ft = it and it:getFullName()
            if ft and ft ~= "" and not it:isHidden() then
                local loc = askLoc(it)
                if loc then sawLoc = true end
                table.insert(rows, { ft = ft,
                                     loc = loc and string.lower(loc) or nil,
                                     raw = loc,
                                     clo = askClo(it) or askClo2(it) })
            end
        end
    end)

    local hits = 0
    for _, row in ipairs(rows) do
        if row.loc then
            for _, r in ipairs(P.RULES) do
                if matches(row.loc, r.pats) then
                    put(byId[r.id], row.ft)
                    put(all, row.ft)
                    hits = hits + 1
                end
            end
        end
    end

    -- The fallback. Only when the first pass produced NOTHING - see the header
    -- for why that specific condition and no other.
    local via = "location"
    if hits == 0 then
        via = "name"
        for _, row in ipairs(rows) do
            -- Two candidate spellings per item: what the game calls the item,
            -- and what it calls the clothing asset. B42 jewellery carries the
            -- interesting word in the second one as often as the first.
            local cands = { shortName(row.ft) }
            if row.clo then table.insert(cands, string.lower(row.clo)) end
            for _, r in ipairs(P.RULES) do
                local hit = false
                for _, c in ipairs(cands) do
                    if matches(c, r.npats) then hit = true; break end
                end
                if hit then
                    put(byId[r.id], row.ft)
                    put(all, row.ft)
                    hits = hits + 1
                end
            end
        end
        if hits == 0 then via = "none" end
    end

    -- Cut every family into designs. Sub-packs are built AFTER the family is
    -- final, from its own membership, so a member that arrived by the name
    -- fallback is grouped exactly like one that arrived by body location.
    local subs = {}
    for _, r in ipairs(P.RULES) do
        local fam = byId[r.id]
        if fam and fam.n > 0 then
            -- "Jewelry - Ring" -> "Ring", so a sub-pack reads "Ring - Gold Ruby"
            local famShort = string.match(fam.name, "%-%s*(.+)$") or fam.name
            local common = commonWords(fam.fts)
            local byKey, keyOrder = {}, {}
            for _, ft in ipairs(fam.fts) do
                local key, label = designOf(ft, common)
                local d = byKey[key]
                if not d then
                    d = { id = r.id .. ":" .. key,
                          name = famShort .. " - " .. label,
                          fts = {}, set = {}, n = 0, parent = r.id }
                    byKey[key] = d
                    table.insert(keyOrder, d)
                end
                if not d.set[ft] then
                    d.set[ft] = true; d.n = d.n + 1
                    table.insert(d.fts, ft)
                end
            end
            for _, d in ipairs(keyOrder) do
                byId[d.id] = d              -- reachable by id even when hidden
                table.insert(subs, d)
            end
        end
    end

    for _, b in ipairs(order) do table.sort(b.fts) end
    for _, d in ipairs(subs)  do table.sort(d.fts) end
    table.sort(subs, function(a, b) return a.name < b.name end)

    -- An empty pack is worse than no pack: the admin adds it, the board shows
    -- a card, and no player can ever sell into it. Drop them from the list the
    -- picker offers, but keep them reachable by id so a save that already
    -- names one does not break.
    local list = {}
    for _, b in ipairs(order) do
        if b.n > 0 then table.insert(list, b) end
    end

    -- Families first, then designs. A design of one member is left out: it
    -- would be a pack standing for a single item, and the item's own row two
    -- lines further down already says that, more clearly.
    for _, d in ipairs(subs) do
        if d.n > 1 then table.insert(list, d) end
    end

    -- Keep the raw locations we saw. The diagnostic needs them and it must not
    -- walk the script manager a second time to get them.
    local locs = {}
    if sawLoc then
        local seen = {}
        for _, row in ipairs(rows) do
            if row.raw and not seen[row.raw] then
                seen[row.raw] = true
                table.insert(locs, row.raw)
            end
        end
        table.sort(locs)
    end

    cache = { byId = byId, list = list, designs = subs, via = via,
              askedLoc = locLives(), sawLoc = sawLoc, locs = locs,
              scanned = #rows }
    return cache
end

--- Throw the cache away. Only useful from the debug console after loading a
--- mod mid-session; nothing calls it in normal play.
function P.rebuild() cache = nil; return P.build() end

--============================================================== queries =====

function P.get(id)
    if not id then return nil end
    return P.build().byId[id]
end

--- Every pack worth offering, for the admin's picker.
function P.list() return P.build().list end

--- Is this `ft` a pack marker? Returns the pack id, or nil for a real item.
function P.idOf(ft)
    if type(ft) ~= "string" then return nil end
    local n = #P.PREFIX
    if string.sub(ft, 1, n) ~= P.PREFIX then return nil end
    return string.sub(ft, n + 1)
end

function P.key(id) return P.PREFIX .. tostring(id) end

function P.nameOf(id)
    local b = P.get(id)
    return b and b.name or ("Pack " .. tostring(id))
end

--- Does this pack accept that item? The server asks this before it agrees to
--- buy anything, which is the whole reason the client is allowed to choose
--- which of its items to hand over.
function P.contains(id, ft)
    local b = P.get(id)
    return (b and b.set[ft]) and true or false
end

function P.members(id)
    local b = P.get(id)
    return b and b.fts or {}
end

--- An icon for the card. Packs have no item of their own, so the first member
--- lends its picture - which for a ring pack is a ring, which is the point.
function P.iconFt(id)
    local b = P.get(id)
    return b and b.fts[1] or nil
end

--============================================================ diagnostics ===

--- Print what every pack actually caught, and a sample of the body locations
--- that matched nothing.
---
--- This exists because the failure mode here is SILENT. A rule that catches
--- nothing produces an empty pack, an empty pack is hidden from the picker,
--- and the admin's experience is simply "the ring pack is not there" with no
--- clue whether the feature is broken, the rule is wrong, or this server's
--- jewellery is named something nobody expected. One line in console.txt at
--- boot turns that from a conversation into a fact.
---
--- Also callable by hand from the debug console: AkaShopPacks.dump()
function P.dump(verbose)
    local c = P.build()
    print(string.format("[Traka] item packs: scanned %d item(s), matched by %s",
          c.scanned or 0, c.via or "?"))
    if c.via == "name" then
        print("[Traka]   NOTE: no item on this server answered getBodyLocation " ..
              "usefully, so packs were built from item NAMES instead. Check the " ..
              "counts below look sane before selling into them.")
    end
    local any = false
    for _, r in ipairs(P.RULES) do
        local b = c.byId[r.id]
        local n = b and b.n or 0
        if n > 0 then any = true end
        print(string.format("[Traka]   %-28s %d item(s)%s", b and b.name or r.id, n,
              (n == 0) and "   <- MATCHED NOTHING" or ""))

        -- The designs this family was cut into. Printed always, not just when
        -- verbose: how a family splits is the thing an admin actually has to
        -- decide prices against, and counting it by hand off a picker list is
        -- exactly the chore packs exist to remove.
        if n > 0 then
            local shown, singles = 0, 0
            for _, d in ipairs(c.designs or {}) do
                if d.parent == r.id then
                    if d.n > 1 then
                        shown = shown + 1
                        if verbose or shown <= 12 then
                            print(string.format("[Traka]       %-26s %d", d.name, d.n))
                        end
                    else
                        singles = singles + 1
                    end
                end
            end
            if not verbose and shown > 12 then
                print("[Traka]       ... and " .. (shown - 12) .. " more design(s)")
            end
            -- A design of one item is not offered, and saying so plainly stops
            -- an admin hunting the picker for a sub-pack that was never going
            -- to be there: the item's own row IS that sub-pack.
            if singles > 0 then
                print("[Traka]       (" .. singles .. " design(s) of a single item - " ..
                      "pick those items directly)")
            end
        end

        if verbose and b then
            for i = 1, math.min(n, 8) do print("[Traka]       " .. b.fts[i]) end
            if n > 8 then print("[Traka]       ... and " .. (n - 8) .. " more") end
        end
    end
    local all = c.byId[P.ALL.id]
    print(string.format("[Traka]   %-28s %d item(s)", P.ALL.name, all and all.n or 0))

    if not any then
        -- Nothing matched, even after the name fallback. Say which of the two
        -- worlds we are in, because the fix is different in each.
        print("[Traka] NO pack matched anything - the picker will show none.")
        local list = c.locs or {}
        if #list > 0 then
            -- Locations exist and none of them looked like jewellery. Either
            -- this server really has none, or it spells the slots in a way the
            -- rules do not expect. Show them so it can be answered by reading.
            print("[Traka] Body locations seen on this server (raw spelling):")
            for i = 1, math.min(#list, 60) do print("[Traka]     " .. list[i]) end
            if #list > 60 then print("[Traka]     ... and " .. (#list - 60) .. " more") end
        else
            print("[Traka] getBodyLocation answered for NOTHING on this build, " ..
                  "and no item NAME looked like jewellery either.")
            print("[Traka] Nothing more can be guessed from here - send this " ..
                  "line to the mod author.")
        end
    end
    return c
end

-- Runs once, on both the client and the server. Cheap - the walk is cached and
-- would have happened the first time anybody opened the item picker anyway.
--
-- Guarded so the module can also be loaded outside the game, by the test
-- harness, where there is no event bus to hook.
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function() pcall(P.dump, false) end)
end
