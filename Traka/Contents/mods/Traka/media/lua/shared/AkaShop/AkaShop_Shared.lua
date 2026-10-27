--[[===========================================================================
    AkaShop - Player Shops for Project Zomboid Build 42
    Shared layer: constants, sandbox access, cashier detection, permissions,
    inventory helpers. Loaded on the client, on the server and in singleplayer.
============================================================================]]

--[[ Scoping: this mod writes a known, closed list of globals, because Project
     Zomboid has no module system and every Lua file shares one state.
     Everything else in every file is `local`.

       AkaShop          this file - constants and pure helpers (all states)
       AkaShopStock     shared    - wear-aware stock rows
       AkaShopPacks     shared    - item families discovered from body slots
       AkaShopCore      server/SP - the shop database and its rules
       AkaShopBuy       server/SP - admin buy-back depots
       AkaShopOrders    server/SP - counter orders (out-of-hours trade)
       AkaShopGive      server/SP - the multiplayer hand-over (goods out)
       AkaShopTake      server    - the multiplayer hand-over (goods in)
       AkaShopSchema    server/SP - save migrations
       AkaShopTiles     server/SP - the tile keeper
       AkaShopServer    server/SP - command dispatch
       AkaShopClient    client/SP - command dispatch, context menu
       AkaShopUI        client    - theme + widget helpers
       AkaShopMap       client    - world map overlay
       AkaShopProtect   client    - move/scrap guards
       AkaShopRestore   client    - client-side tile repair
       AkaShopMenu      client    - its row in the AKA family menu (AKA.getGroup)
       AkaShopManageUI, AkaShopBuyUI, AkaShopAdminUI, AkaShopDepotUI,
       AkaShopItemPicker, AkaShopDepotPick, AkaShopOwnerPick, AkaShopNameDialog,
       AkaShopPayDialog
                        client    - the windows (ISUI classes must be global)

     Nothing outside this list is written to _G; if a new name appears at file
     scope somewhere, it is a missing `local`. Keep this list honest - a stale
     rule is worse than no rule, because it gets trusted. ]]

AkaShop = AkaShop or {}

AkaShop.VERSION = "3.7.6"
AkaShop.NET           = "AkaShop"      -- client/server command module name
AkaShop.HARD_MAX_LIST = 60
AkaShop.MAX_STOCK     = 9999
AkaShop.MAX_PRICE     = 9999999
AkaShop.MAX_SALES_LOG = 250
AkaShop.MAX_STAFF     = 20
AkaShop.MAX_CODES     = 20
AkaShop.MAX_NAME_LEN  = 32

--- The most condition-buckets one hand-over may report back to the server.
---
--- v3.7.4. Every item's state is recorded down to its AGE IN HOURS, so items
--- that look identical are almost never identical: a bag of two hundred rings
--- collapses to two hundred buckets, not one. That whole table then travels in
--- a single client command, and a bulk sale of cheap goods - where the payout
--- budget allows hundreds of items per batch - builds a packet nobody sized for.
---
--- Sixty is far more detail than any shop window can show, and anything past it
--- is folded into the last bucket keeping the worse of every value. The cost is
--- a little precision on a hoard; the alternative is an unbounded packet.
AkaShop.MAX_UNITS     = 60

-- Used when the Currency sandbox option is set to "Custom".
AkaShop.CUSTOM_CURRENCY = "Base.Money"

-- Sprite names an admin has whitelisted in game. Mirrored server -> client.
AkaShop.spriteWhitelist = AkaShop.spriteWhitelist or {}

-- The TraKA shop machine tiles that ship with this mod. These are recognised
-- out of the box, so an admin never has to allow-list them by hand.
-- media/texturepacks/Traka_machine_pack.pack supplies the sprites and
-- media/Traka_machine.tiles their properties.
--- Both families are listed together and NEITHER is tied to a role. A machine
--- tile can be a player shop or an admin depot; an admin tile can be either
--- too. What a counter becomes is decided by the menu option the admin or the
--- player picks on it, never by which picture it happens to be wearing.
AkaShop.OWN_SPRITES = {
    "Traka_machine_0",      -- blue header
    "Traka_machine_1",      -- magenta header
    "Traka_machine_2",      -- green header
    "Traka_machine_3",      -- pink header
    "Traka_machine_4",      -- dark header
    "Traka_Admin_0",        -- rustic wood
    "Traka_Admin_1",        -- pastel
    "Traka_Admin_2",        -- neon night
    "Traka_Admin_3",        -- terminal green
}

AkaShop.OWN_SPRITE_SET = {}
for i = 1, #AkaShop.OWN_SPRITES do
    AkaShop.OWN_SPRITE_SET[AkaShop.OWN_SPRITES[i]] = true
end

--- Default sprite used when a shop record has no sprite recorded yet.
AkaShop.DEFAULT_SPRITE = AkaShop.OWN_SPRITES[1]

-- Extra sprites recognised by lowercase substring match. Normally unnecessary:
-- use the admin menu "Allow this tile to be claimed as a shop" instead.
AkaShop.EXTRA_SPRITE_PATTERNS = {
    "traka_machine",
    "traka_admin",
}

--=============================================================== sandbox ====

function AkaShop.sv()
    return (SandboxVars and SandboxVars.AkaShop) or nil
end

local function svInt(field, default, lo, hi)
    local sv = AkaShop.sv()
    local v = sv and sv[field]
    if type(v) ~= "number" then return default end
    v = math.floor(v)
    if lo and v < lo then return default end
    if hi and v > hi then return default end
    return v
end

local function svBool(field, default)
    local sv = AkaShop.sv()
    local v = sv and sv[field]
    if type(v) ~= "boolean" then return default end
    return v
end

local CURRENCIES = { "Base.Money", "Base.AkaCoin" }

function AkaShop.getCurrency()
    local idx = svInt("Currency", 1, 1, 3)
    if idx == 3 then return AkaShop.CUSTOM_CURRENCY end
    return CURRENCIES[idx] or "Base.Money"
end

function AkaShop.getCurrencyName()
    local ft = AkaShop.getCurrency()
    local sm = getScriptManager()
    local si = sm and sm:FindItem(ft)
    if si then
        local n = si:getDisplayName()
        if n and n ~= "" then return n end
    end
    return ft
end

function AkaShop.getTaxPercent()        return svInt("TaxPercent", 0, 0, 90) end
function AkaShop.getMaxShopsPerPlayer() return svInt("MaxShopsPerPlayer", 2, 1, 50) end
function AkaShop.getMaxListings()       return svInt("MaxListings", 40, 1, AkaShop.HARD_MAX_LIST) end
function AkaShop.protectEnabled()       return svBool("ProtectMoveables", true) end
function AkaShop.adminCanEditAny()      return svBool("AdminCanEditAny", true) end
function AkaShop.adminAnyObject()       return svBool("AdminCanRegisterAnyObject", false) end
function AkaShop.ownerCanBuyOwn()       return svBool("OwnerCanBuyOwnShop", false) end

--- Only the TraKA machine tiles (plus the admin allow-list) may become shops.
function AkaShop.onlyOwnTiles()         return svBool("OnlyOwnTiles", true) end

--- How close you must stand to use a counter.
--- Twelve tiles was the old value and it was wrong: twelve tiles is the far
--- side of a road, which let a player shop from cover and made "who is at the
--- till" meaningless. Three puts you at the counter. Admins still bypass it,
--- because an admin inspecting a shop across the map is the whole point of the
--- teleport list.
function AkaShop.useDistance()          return svInt("UseDistance", 3, 1, 10) end

--- How long a counter order waits before the goods go back on the shelf.
--- Real hours, not game hours: an order is a promise between two people who
--- have to be online at the same time, and their availability runs on the wall
--- clock. Twelve is long enough to span a work day and short enough that a
--- shop is not permanently holding stock for somebody who quit the server.
function AkaShop.orderHours()           return svInt("OrderHours", 12, 1, 168) end

--- How much PAYOUT one request of a bulk sale is allowed to create.
---
--- v3.6.3, and the second attempt at this. The first counted ITEMS SOLD - three
--- at a time, always - which fixed the freeze and ruined everything else: a
--- player dumping thirty tin cans worth two each watched a progress bar for no
--- reason, because thirty cans is sixty coins and sixty coins was never the
--- problem. The problem is the COINS, not the cans.
---
--- So the budget is counted in what gets BUILT. Every unit of currency is a
--- real item the server has to create and announce, so the cost of a sale is
--- price x quantity, and that is what has to be bounded. Under the budget the
--- whole sale goes in one request and behaves exactly as it did before any of
--- this existed - one click, done, no pacing anybody can see. Over it, and only
--- then, the sale splits across frames, because at that size there is no third
--- option: the work is real and a frame is only so long.
---
--- 800 is roughly a few milliseconds of item building. Raise it if your server
--- runs on good hardware and you would rather have one big hitch than a short
--- ripple; lower it if anyone still reports a stutter.
function AkaShop.sellBudget()           return svInt("SellBudget", 800, 1, 100000) end

--- How many items a second a BIG sale hands over.
---
--- The budget above is a safety limit; this is a pace. They are different
--- things and both are wanted. The budget says "never build more than this on
--- one frame", which is what stops the stutter. The rate says "and even if you
--- could go faster, don't" - so that emptying a bag of two hundred rings is a
--- job the character visibly does, with a progress bar, the way reading a book
--- is, instead of a number that vanishes.
---
--- It only applies to a sale too big to finish in one hand-over. Anything that
--- fits the budget is instant, and always will be.
function AkaShop.sellRate()             return svInt("SellRate", 10, 1, 1000) end

--- The most a shop owner takes out of the till as cash in one click.
---
--- It was a hard-coded 1000 because every unit of currency withdrawn is a real
--- item the server builds and announces, all in the frame the button is
--- pressed - the same cost that made bulk selling stutter. It is a sandbox
--- option now, but the cost did not go anywhere: this is the knob that trades
--- fewer clicks against a bigger hitch on each one. Anyone who wants a large
--- sum moved does not need a larger number here - Send to bank moves any
--- amount without building a single item.
function AkaShop.withdrawMax()          return svInt("WithdrawMax", 1000, 100, 10000) end

--- Can a till be paid straight into the owner's Akacount account?
---
--- Two conditions, and the second is the one that matters. The bank holds
--- CASH - one currency, the notes Akacount issues. A till holds whatever this
--- server set Traka's currency to. Paying a till of AkaCoin into the bank as
--- if it were notes would turn coins into money at 1:1 with nobody having
--- decided that rate, so unless the two are the same item there is no link.
---
--- Read on both sides: the client uses it to decide whether to offer the
--- button, the server re-checks it before moving anything. AC is Akacount's
--- shared global, so it exists on clients too; the API itself is checked on
--- the server only, where it is actually called.
function AkaShop.bankLink()
    if type(AC) ~= "table" or AC.MOD_ID ~= "Akacount" then
        return false, "Akacount is not installed on this server."
    end
    local cash = AC.ITEM_CASH or "Base.Money"
    if AkaShop.getCurrency() ~= cash then
        return false, "This server's shops take " .. AkaShop.getCurrencyName() ..
                      ", and the bank only holds " .. cash .. "."
    end
    return true
end

--- The bank's fee for moving `units` of till into an account, in the bank's
--- own smallest unit, or nil if it cannot be worked out here. Uses Akacount's
--- own calculator so the number on the confirm box is the number charged.
function AkaShop.bankFee(units)
    if type(AC) ~= "table" or type(AC.util) ~= "table" then return nil end
    local U = AC.util
    if type(U.feeFor) ~= "function" or type(U.opt) ~= "function" then return nil end
    local sub = math.floor(tonumber(units) or 0) * (AC.SUBUNIT or 100)
    local fee = nil
    pcall(function() fee = U.feeFor(sub, U.opt("DepositFeePct")) end)
    return fee
end

--- "5.00" - the bank counts in hundredths, Traka in whole units.
function AkaShop.bankMoney(sub)
    if type(AC) == "table" and type(AC.util) == "table" and type(AC.util.fmt) == "function" then
        local s = nil
        pcall(function() s = AC.util.fmt(sub) end)
        if s then return s end
    end
    return string.format("%.2f", (tonumber(sub) or 0) / 100)
end

--- "20 -> 1 Dog Food", the one phrasing a barter deal is ever written in.
---
--- Shared rather than server-side because the card, the rail, the admin panel
--- and the server's confirmation message all say it, and a rate that reads two
--- different ways in two places is a rate players argue about. Plain ASCII: the
--- arrow has to survive whatever font the player has their UI scaled to.
function AkaShop.rateText(lot, payN, payName)
    lot  = math.max(1, math.floor(tonumber(lot) or 1))
    payN = math.max(1, math.floor(tonumber(payN) or 1))
    return lot .. " -> " .. payN .. " " .. tostring(payName or "?")
end

--============================================================ card colours ==
--- The palette an admin may paint a limited-time offer with.
---
--- A fixed palette, not a free colour picker. Every one of these is dark enough
--- that the amber price and the white item name stay legible on top - a free
--- picker invites #FFFF00, and then the card is unreadable and it is the mod
--- that looks broken. Index 1 is "no colour", which is what an ordinary
--- always-on offer uses.
AkaShop.CARD_COLOURS = {
    { 0.145, 0.157, 0.169, "Plain"  },   -- panel grey
    { 0.227, 0.141, 0.090, "Ember"  },
    { 0.086, 0.188, 0.227, "Deep"   },
    { 0.173, 0.106, 0.220, "Violet" },
    { 0.118, 0.200, 0.125, "Moss"   },
    { 0.227, 0.102, 0.102, "Blood"  },
    { 0.200, 0.149, 0.102, "Dusk"   },
}

function AkaShop.cardColour(i)
    return AkaShop.CARD_COLOURS[math.floor(tonumber(i) or 1)]
        or AkaShop.CARD_COLOURS[1]
end

--- "1h 04m" / "4m 12s" / "9s" / "ready". Lives here because the depot windows
--- redraw this every frame on the client while the rules that produce it run on
--- the server, and two copies of a formatter is two chances to disagree.
function AkaShop.durationText(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec <= 0 then return "ready" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, sec % 60) end
    return sec .. "s"
end

--================================================= trading hours (server) ===
-- The window during which a shop serves customers by itself. Outside it, the
-- shop is "counter only": the goods are still on display but nobody can buy
-- without the owner present. Off by default, so a server that does not want
-- opening hours behaves exactly as before.

function AkaShop.restrictHours()        return svBool("RestrictOnlineHours", false) end
function AkaShop.onlineFrom()           return svInt("OnlineFromHour", 0, 0, 23) end
function AkaShop.onlineTo()             return svInt("OnlineToHour", 5, 0, 23) end

--- Which clock the trading window follows.
--- REAL is the wall clock of the machine running the game (the server, in
--- multiplayer), because "open 02:00 to 05:00" normally means 2am where the
--- players actually live. In-game time is a different animal entirely: at the
--- default day length one in-game hour is 2.5 real minutes, so a three hour
--- in-game window is about seven real minutes and it repeats every real hour.
function AkaShop.hoursUseRealClock()    return svBool("HoursUseRealClock", true) end

--- Hours to add to UTC. The server's own timezone is not trusted: a box rented
--- abroad usually runs on UTC, so the offset is stated explicitly instead.
--- Thailand is +7.
function AkaShop.clockOffset()          return svInt("RealClockUTCOffset", 7, -12, 14) end

--- Current in-game hour, 0..23.
function AkaShop.gameHour()
    local h
    if pcall(function() h = getGameTime():getHour() end) and type(h) == "number" then
        return math.floor(h)
    end
    return 12
end

--- Current real-world hour in the configured timezone, 0..23.
function AkaShop.realHour()
    local t
    if not (pcall(function() t = getTimestamp() end) and type(t) == "number") then
        if pcall(function() t = getTimestampMs() end) and type(t) == "number" then
            t = math.floor(t / 1000)
        else
            return nil
        end
    end
    t = t + AkaShop.clockOffset() * 3600
    return math.floor(t / 3600) % 24
end

--- The hour the trading window is measured against.
function AkaShop.currentHour()
    if AkaShop.hoursUseRealClock() then
        local h = AkaShop.realHour()
        if h then return h end        -- no clock available: fall back rather than lock
    end
    return AkaShop.gameHour()
end

--- Is self-service buying allowed right now?
--- A window that wraps past midnight (22 -> 4) is handled: `from > to` means
--- the window spans the night, which is the common case for a night market.
function AkaShop.onlineAllowedNow()
    if not AkaShop.restrictHours() then return true end
    local h, a, b = AkaShop.currentHour(), AkaShop.onlineFrom(), AkaShop.onlineTo()
    if a == b then return true end                 -- degenerate = always on
    if a < b  then return h >= a and h < b end     -- same day
    return h >= a or h < b                          -- wraps midnight
end

function AkaShop.hoursText()
    if not AkaShop.restrictHours() then return "always open" end
    local which = AkaShop.hoursUseRealClock()
        and ("UTC" .. (AkaShop.clockOffset() >= 0 and "+" or "") .. AkaShop.clockOffset())
        or "in-game"
    return string.format("%02d:00 - %02d:00 %s",
        AkaShop.onlineFrom(), AkaShop.onlineTo(), which)
end

function AkaShop.modeLabel()
    if not AkaShop.restrictHours() then return "ONLINE" end
    return AkaShop.onlineAllowedNow() and "ONLINE" or "COUNTER ONLY"
end

--============================================== whose clock is this shop on ==
--[[ Trading hours are a rule for PLAYER shops. A counter the server itself
     runs is a piece of infrastructure - a fuel station does not shut because
     it is 3am - so an admin-owned shop serves itself around the clock and the
     sandbox window simply does not apply to it.

     The flag lives on the shop rather than being worked out from the owner's
     access level, for two reasons. The owner is usually offline, so there is
     no player object to ask. And ownership changes: hand a server store to a
     player and it should start keeping player hours, which it does, because
     the admin who hands it over decides whether the flag goes with it. ]]

--- Is this shop serving itself right now?
function AkaShop.shopSelfServeNow(shop)
    if shop and shop.alwaysOpen then return true end
    return AkaShop.onlineAllowedNow()
end

--- Can an order ever be placed here? Not at a shop that never closes.
function AkaShop.shopOrdersOn(shop)
    if shop and shop.alwaysOpen then return false end
    return AkaShop.restrictHours()
end

function AkaShop.shopHoursText(shop)
    if shop and shop.alwaysOpen then return "always open (server shop)" end
    return AkaShop.hoursText()
end

function AkaShop.shopModeLabel(shop)
    if shop and shop.alwaysOpen then return "ONLINE 24H" end
    return AkaShop.modeLabel()
end

-- shelf space: the cap that keeps the stock table bounded
function AkaShop.getStartCapacity()     return svInt("StartCapacityKg", 20, 5, 100) end
function AkaShop.getCapacityStep()      return svInt("CapacityStepKg", 10, 1, 50) end
function AkaShop.getMaxCapacity()       return svInt("MaxCapacityKg", 100, 5, 1000) end
function AkaShop.getCapacityPrice()     return svInt("CapacityPrice", 2000, 0, 999999) end

-- bounded sales history
function AkaShop.getSalesDays()         return svInt("SalesDays", 60, 1, 365) end
function AkaShop.getSalesRecent()       return svInt("SalesRecent", 30, 0, 200) end


--============================================================== utilities ===

function AkaShop.isSP()
    return (not isClient()) and (not isServer())
end

function AkaShop.isAdmin(player)
    if not player then return false end
    if AkaShop.isSP() then return true end
    local lvl
    local ok = pcall(function() lvl = player:getAccessLevel() end)
    if not ok or not lvl then return false end
    lvl = string.lower(tostring(lvl))
    return lvl == "admin" or lvl == "moderator" or lvl == "overseer"
        or lvl == "gm" or lvl == "observer"
end

function AkaShop.nameOf(player)
    if not player then return "?" end
    local u
    pcall(function() u = player:getUsername() end)
    if u and u ~= "" then return tostring(u) end
    pcall(function() u = player:getDisplayName() end)
    if u and u ~= "" then return tostring(u) end
    return "?"
end

function AkaShop.key(x, y, z)
    return string.format("%d_%d_%d", math.floor(x or 0), math.floor(y or 0), math.floor(z or 0))
end

function AkaShop.clampInt(v, lo, hi)
    v = tonumber(v)
    if not v then return lo end
    v = math.floor(v)
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

function AkaShop.trim(s)
    if type(s) ~= "string" then return "" end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function AkaShop.sanitizeName(s, fallback)
    s = AkaShop.trim(s)
    s = string.gsub(s, "%c", "")
    if #s > AkaShop.MAX_NAME_LEN then s = string.sub(s, 1, AkaShop.MAX_NAME_LEN) end
    if s == "" then return fallback or "Shop" end
    return s
end

--- Same, but an empty result stays empty: the second language is optional.
function AkaShop.sanitizeNameOpt(s)
    s = AkaShop.trim(s)
    s = string.gsub(s, "%c", "")
    if #s > AkaShop.MAX_NAME_LEN then s = string.sub(s, 1, AkaShop.MAX_NAME_LEN) end
    return s
end

--=========================================================== shop naming ====
-- Every shop carries two names: `nameTH` (Thai) and `name` (English), and BOTH
-- are always shown as "ไทย / English".
--
-- Deliberately NOT picked by game language. Project Zomboid has no official
-- Thai locale, so a language probe would resolve to English for everyone and
-- the Thai name would never appear. Showing both is also the only form that
-- reads correctly on a server with mixed players, and it means the string the
-- server composes and the string the client draws are always identical.

AkaShop.NAME_SEP = "  /  "

--- Normalise a pair of shop names. A fallback is only invented when BOTH boxes
--- are blank, so a Thai-only (or English-only) shop stays that way.
function AkaShop.pairNames(en, th, fallback)
    en = AkaShop.sanitizeNameOpt(en)
    th = AkaShop.sanitizeNameOpt(th)
    if en == "" and th == "" then
        en = AkaShop.sanitizeName(fallback, "Shop")
    end
    return { en = en, th = th }
end

local function nonEmpty(s)
    if type(s) == "string" and AkaShop.trim(s) ~= "" then return s end
    return nil
end

--- "ไทย / English", or whichever single name the shop actually has.
function AkaShop.shopName(t)
    if type(t) ~= "table" then return tostring(t or "Shop") end
    local en, th = nonEmpty(t.name), nonEmpty(t.nameTH)
    if en and th and en ~= th then return th .. AkaShop.NAME_SEP .. en end
    return th or en or "Shop"
end

--- Kept as a separate name for the places that mean "the full label" on
--- purpose (window headers, admin rows, server messages). Same output.
AkaShop.shopBoth = AkaShop.shopName

function AkaShop.normCode(s)
    s = AkaShop.trim(s or "")
    s = string.upper((string.gsub(s, "%s", "")))
    if #s > 16 then s = string.sub(s, 1, 16) end
    return s
end

function AkaShop.money(n)
    return string.format("%d", math.floor(tonumber(n) or 0))
end

--- Numeric YYYYMMDD stamp of the current in-game date.
function AkaShop.dayStamp()
    local gt = getGameTime()
    if not gt then return 0 end
    local ok, v = pcall(function()
        return (gt:getYear() * 10000) + ((gt:getMonth() + 1) * 100) + (gt:getDay() + 1)
    end)
    if ok and type(v) == "number" then return v end
    return 0
end

function AkaShop.clockString()
    local gt = getGameTime()
    if not gt then return "" end
    local ok, v = pcall(function()
        return string.format("%02d/%02d/%04d %02d:%02d",
            gt:getDay() + 1, gt:getMonth() + 1, gt:getYear(),
            gt:getHour(), math.floor(gt:getMinutes()))
    end)
    if ok and v then return v end
    return ""
end

--======================================================= cashier detection ==

--- Read a tile property, or nil.
--- Every step is checked before it is called. The old version leaned on pcall
--- alone, which still let the engine raise (and log) "Object tried to call nil"
--- for every sprite that has no properties table - 138 Java exceptions in one
--- session, all caught, all wasted.
local function propVal(obj, k)
    if not obj or type(obj.getSprite) ~= "function" then return nil end
    local sp
    if not pcall(function() sp = obj:getSprite() end) or not sp then return nil end
    if type(sp.getProperties) ~= "function" then return nil end
    local pr
    if not pcall(function() pr = sp:getProperties() end) or not pr then return nil end
    if type(pr.Val) ~= "function" then return nil end
    local v
    if not pcall(function() v = pr:Val(k) end) then return nil end
    if v and v ~= "" then return v end
    return nil
end

function AkaShop.spriteNameOf(obj)
    if not obj then return nil end
    local n
    local ok = pcall(function()
        local sp = obj:getSprite()
        if sp then n = sp:getName() end
    end)
    if ok and n and n ~= "" then return n end
    return nil
end

function AkaShop.objLabel(obj)
    local n = propVal(obj, "CustomName")
    if n then return n end
    n = propVal(obj, "GroupName")
    if n then return n end
    local v
    pcall(function() v = obj:getName() end)
    if v and v ~= "" then return tostring(v) end
    return AkaShop.spriteNameOf(obj) or "Object"
end

local function containsAny(hay, list)
    if not hay then return false end
    hay = string.lower(hay)
    for i = 1, #list do
        if string.find(hay, list[i], 1, true) then return true end
    end
    return false
end

local SPRITE_HINTS = { "cashregister", "cash_register", "cash register" }
local NAME_HINTS   = { "cash register", "cashregister", "cashier", "register", "till" }

--- Can a shop be registered on this world object?
---
--- With OnlyOwnTiles on (the default) the answer is yes for the TraKA machine
--- tiles and for anything an admin has deliberately allow-listed, and no for
--- everything else. Nothing is guessed from sprite names or tile properties, so
--- a player cannot turn a random counter they found into a shop -- and the
--- property lookups below, which are the expensive part, never run at all.
function AkaShop.isCashier(obj)
    if not obj then return false end
    local sname = AkaShop.spriteNameOf(obj)
    if not sname then return false end

    -- 1. our own tiles, then the explicit admin whitelist
    if AkaShop.OWN_SPRITE_SET[sname] then return true end
    if AkaShop.spriteWhitelist[sname] then return true end

    if AkaShop.onlyOwnTiles() then return false end

    -- 2. sprite name hints
    if containsAny(sname, SPRITE_HINTS) then return true end
    for i = 1, #AkaShop.EXTRA_SPRITE_PATTERNS do
        local p = string.lower(AkaShop.EXTRA_SPRITE_PATTERNS[i])
        if string.find(string.lower(sname), p, 1, true) then return true end
    end

    -- 3. tile CustomName / GroupName ("Cash Register" on the vanilla tiles)
    if containsAny(propVal(obj, "CustomName"), NAME_HINTS) then return true end
    if containsAny(propVal(obj, "GroupName"), NAME_HINTS) then return true end

    return false
end

local function isFloorish(spriteName)
    local s = string.lower(spriteName or "")
    return string.find(s, "^floors") ~= nil
        or string.find(s, "_floor", 1, true) ~= nil
        or string.find(s, "blends_", 1, true) ~= nil
end

--- Find a usable cashier object on a square.
--- allowAny: admin escape hatch, returns the topmost non-floor object instead.
function AkaShop.findCashier(square, allowAny)
    if not square then return nil end
    local objs
    local ok = pcall(function() objs = square:getObjects() end)
    if not ok or not objs then return nil end

    local fallback = nil
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local sname = o and AkaShop.spriteNameOf(o)
        if sname then
            if AkaShop.isCashier(o) then return o end
            if allowAny and not isFloorish(sname) then fallback = o end
        end
    end
    return allowAny and fallback or nil
end

--=================================================== inventory helpers ======

--- Create one item of `ft` INSIDE `container` and return it, or nil.
---
--- instanceItem() first, then AddItem(the instance). This is the order the B42
--- notes call for, and it also has one property the String overload does not:
--- if the item's script definition is malformed (a mod still using B41's
--- `Type = Normal` instead of `ItemType = base:normal`) instanceItem returns
--- nil and we find out here, instead of the factory throwing inside AddItem.
--- The String overload stays as a fallback for the reverse case.
local function createInto(container, ft)
    if not container or not ft then return nil end

    local item
    pcall(function() item = instanceItem(ft) end)
    if item then
        local ok = pcall(function() container:AddItem(item) end)
        if ok then AkaShop.probeItem(container, item, "instanceItem+AddItem(item)") return item end
    end

    item = nil
    pcall(function() item = container:AddItem(ft) end)
    if item then AkaShop.probeItem(container, item, "AddItem(string)") end
    return item
end
AkaShop.createInto = createInto

--=========================================================== the probe ======
-- Printed once per session, on the first item a shop hands over. It exists to
-- answer one question with facts instead of guesses: when a client creates an
-- item in multiplayer, does the server know about it?
--
-- Lua cannot list a Java class's methods, so the next best thing is to name the
-- calls that could plausibly do the registration and report which ones this
-- build actually has. Nothing here CALLS them - two earlier versions did, and
-- firing a second announcement at an item the container had already announced
-- is a good way to make the client's copy and the server's copy disagree, which
-- is exactly what an undroppable item is. This only looks.

local CANDIDATES = {
    "getID", "setID", "getWorldItem",
    "transmitCompleteItemToClients", "transmitCompleteItemToServer",
    "transmitCompleteItemToContainer", "sendObjectChange", "syncItemFields",
}
local GLOBALS = {
    "sendAddItemToContainer", "sendRemoveItemFromContainer",
    "sendItemsInContainer", "addItemsToContainer", "transferItem",
    "sendClientCommand", "instanceItem",
}

local probed = false
function AkaShop.probeItem(container, item, how)
    if probed or not item then return end
    probed = true

    local id, ft, cont, inside = "?", "?", "?", "?"
    pcall(function() ft = tostring(item:getFullType()) end)
    pcall(function() id = tostring(item:getID()) end)
    pcall(function() cont = tostring(item:getContainer() == container) end)
    pcall(function() inside = tostring(container:contains(item)) end)

    local onItem, onGlobal = {}, {}
    for _, n in ipairs(CANDIDATES) do
        if type(item[n]) == "function" then table.insert(onItem, n) end
    end
    for _, n in ipairs(GLOBALS) do
        if type(_G[n]) == "function" then table.insert(onGlobal, n) end
    end

    print("[Traka] ---- item hand-over probe (once per session) ----")
    print("[Traka]  path      : " .. tostring(how))
    print("[Traka]  item      : " .. ft .. "   id=" .. id)
    print("[Traka]  container : matches=" .. cont .. "  contains=" .. inside)
    print("[Traka]  MP        : isClient=" .. tostring(isClient()) ..
          " isServer=" .. tostring(isServer()))
    print("[Traka]  on item   : " .. (#onItem   > 0 and table.concat(onItem,   ", ") or "NONE"))
    print("[Traka]  globals   : " .. (#onGlobal > 0 and table.concat(onGlobal, ", ") or "NONE"))
    print("[Traka] -------------------------------------------------")
end

--- Older call sites still name these; they only look, they never send.
function AkaShop.noteDelivery(item) AkaShop.probeItem(nil, item, "noteDelivery") end
function AkaShop.syncItem(c, item)  AkaShop.probeItem(c, item, "syncItem") end

--- True when an item may be sold / spent: not favourited, not worn, not held.
--- The SAME rule is used to count, to display and to remove, so the number the
--- seller sees, the number the server validates and the number actually taken
--- can never disagree.
--- Is this item actually ON the character - a ring on a finger, a jacket on a
--- back - rather than merely in their bag?
---
--- `item:isEquipped()` does NOT answer this. It covers what is in the hands,
--- and a worn ring sailed straight past it: worn clothing still appears in the
--- inventory listing, so the ring on a player's finger looked like loose
--- stock, got sold, and came back on relog because the SERVER's copy of the
--- character was still wearing it. The only honest answer comes from the
--- character's own worn-items list.
--- Everything the character is WEARING, as a set keyed by the item itself.
---
--- v3.5.2. This used to be asked per item, inside isSellable, inside the walk.
--- The bill for that is easy to miss and enormous: getWornItems() plus size()
--- plus two guarded calls per slot, repeated for every item in the bag, for
--- every item type being counted. A player with a bag of jewellery standing at
--- a depot was paying it hundreds of thousands of times a second and watching
--- their frame rate fall over. Ask once, hand the answer down.
function AkaShop.wornSet(player)
    local set = {}
    if not player then return set end
    local worn
    if not pcall(function() worn = player:getWornItems() end) then return set end
    if not worn then return set end
    local n = 0
    if not pcall(function() n = worn:size() end) then return set end
    for i = 0, n - 1 do
        local slot, it
        pcall(function() slot = worn:get(i) end)
        if slot then pcall(function() it = slot:getItem() end) end
        if it then set[it] = true end
    end
    return set
end

--- Is this item on the character's body - worn, not merely carried?
---
--- `item:isEquipped()` does NOT answer this. It covers what is in the hands,
--- and a worn ring sailed straight past it: worn clothing still appears in the
--- inventory listing, so the ring on a player's finger looked like loose
--- stock, got sold, and came back on relog because the SERVER's copy of the
--- character was still wearing it. The only honest answer comes from the
--- character's own worn-items list.
---
--- Kept as a single-item convenience. Anything looping should build the set
--- once with wornSet() and pass it to isSellable instead.
function AkaShop.isWorn(player, item)
    if not player or not item then return false end
    return AkaShop.wornSet(player)[item] and true or false
end

--- `worn` is an optional precomputed set from wornSet(). Without it this falls
--- back to asking the character directly, which is correct but costs a full
--- worn-list read per call.
function AkaShop.isSellable(item, player, isBag, worn)
    if not item then return false end
    local fav, eq = false, false
    pcall(function() fav = item:isFavorite() end)
    pcall(function() eq = item:isEquipped() end)
    if fav then return false end
    if eq then return false end
    -- Worn clothing. See AkaShop.isWorn - this is the check that was missing,
    -- and jewellery is where it hurt, because a ring is the one garment people
    -- never think of as "worn".
    if worn then
        if worn[item] then return false end
    elseif AkaShop.isWorn(player, item) then
        return false
    end
    if player then
        local held = false
        pcall(function()
            held = (player:getPrimaryHandItem() == item)
                or (player:getSecondaryHandItem() == item)
        end)
        if held then return false end
    end
    return true
end

--- Walk a container (and the bags inside it, 3 deep) collecting sellable items.
--- fullType = nil collects everything. limit stops early.
---
--- `worn` may be passed in by a caller that is about to walk several times over
--- the same character; otherwise one is built here, once for the whole walk.
function AkaShop.collectItems(container, fullType, limit, player, worn)
    local out = {}
    worn = worn or AkaShop.wornSet(player)
    local function scan(c, depth)
        if not c or depth > 3 then return end
        if limit and #out >= limit then return end
        local items
        if not pcall(function() items = c:getItems() end) then return end
        if not items then return end
        for i = 0, items:size() - 1 do
            if limit and #out >= limit then return end
            local it = items:get(i)
            if it then
                local isBag = false
                pcall(function() isBag = it:IsInventoryContainer() end)
                if isBag then
                    local sub
                    pcall(function() sub = it:getInventory() end)
                    if sub then scan(sub, depth + 1) end
                end
                -- Type check FIRST. When a fullType was asked for, most items
                -- fail it, and every one that does is an isSellable call - four
                -- guarded reads - that never needed to happen.
                if (not fullType) or it:getFullType() == fullType then
                    if AkaShop.isSellable(it, player, isBag, worn) then
                        table.insert(out, it)
                    end
                end
            end
        end
    end
    scan(container, 1)
    return out
end

function AkaShop.countType(container, fullType, player)
    if not container or not fullType then return 0 end
    return #AkaShop.collectItems(container, fullType, nil, player)
end

function AkaShop.findOneType(container, fullType, player)
    local hit = AkaShop.collectItems(container, fullType, 1, player)
    return hit[1]
end

--- Returns true only if a removal path actually ran without error. The count
--- this feeds is reported to the server as "what really moved", so claiming a
--- removal that did not happen would credit stock nobody handed over.
--- Take one item off a player for good.
---
--- The multiplayer half matters as much as the local half. ItemContainer has
--- removeItemOnServer, and it is the ONLY way to tell the server an item is
--- gone. Skip it and the item comes back at the next relog - the seller keeps
--- the goods AND the money, which is a duplication bug wearing a shop apron.
--- It is called first, while item:getContainer() still answers, and it is
--- guarded because it does not exist in singleplayer builds.
function AkaShop.removeOne(player, item)
    if not item then return false end

    local c
    pcall(function() c = item:getContainer() end)
    if not c and player then pcall(function() c = player:getInventory() end) end

    if not AkaShop.isSP() and c and type(c.removeItemOnServer) == "function" then
        pcall(function() c:removeItemOnServer(item) end)
    end

    -- ISRemoveItemTool.removeItem used to be tried first here and it threw
    -- EVERY time: 1,332 stack dumps in one session of console.txt, all saying
    --   expected argument of type int, got IsoPlayer
    -- Its second parameter is a player NUMBER, not the player. pcall swallowed
    -- the result so the fallback below quietly did the work and nothing looked
    -- broken - it just cost a full Java stack trace per item removed. The call
    -- is gone rather than corrected: removeItemOnServer plus Remove is already
    -- the complete job, and anything equipped, worn or favourited was filtered
    -- out by isSellable long before we got here.
    local done = pcall(function()
        if not c then error("no container") end
        c:Remove(item)
    end)
    if done and c then pcall(function() c:setDrawDirty(true) end) end
    return done
end

--- How many of `fullType` the player could actually part with right now.
--- Counted with the same collectItems the removal uses, so the number the
--- depot window shows and the number the sale can take are the same number.
function AkaShop.countItems(player, fullType)
    if not player then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    return #AkaShop.collectItems(inv, fullType, 10000, player)
end

--- Remove up to `count` items of fullType from the player. Returns how many went.
--- `allOrNothing` refuses to remove anything unless the full count is present,
--- which is what payment must do: a half-paid purchase is worse than none.
function AkaShop.removeItems(player, fullType, count, allOrNothing)
    if not player then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    count = math.floor(count or 0)
    if count < 1 then return 0 end

    local found = AkaShop.collectItems(inv, fullType, count, player)
    if allOrNothing and #found < count then return 0 end

    local removed = 0
    for i = 1, #found do
        if AkaShop.removeOne(player, found[i]) then removed = removed + 1 end
    end
    return removed
end

--- Give `count` items of fullType to the player. Returns how many were created.
function AkaShop.giveItems(player, fullType, count)
    if not player then return 0 end
    local sm = getScriptManager()
    if not (sm and sm:FindItem(fullType)) then
        print("[Traka] unknown item type: " .. tostring(fullType))
        return 0
    end
    local inv = player:getInventory()
    local made = 0
    for _ = 1, math.floor(count or 0) do
        if createInto(inv, fullType) then made = made + 1 end
    end
    return made
end

function AkaShop.displayNameOf(fullType)
    local sm = getScriptManager()
    local si = sm and sm:FindItem(fullType)
    if si then
        local n = si:getDisplayName()
        if n and n ~= "" then return n end
    end
    return fullType
end

--============================================================ misc ==========

function AkaShop.halo(player, text, r, g, b)
    if not player then return end
    pcall(function()
        player:setHaloNote(text, r or 255, g or 220, b or 120, 200)
    end)
end

function AkaShop.say(text)
    if isServer() then
        print("[Traka] " .. tostring(text))
    else
        pcall(function()
            getPlayer():Say(tostring(text))
        end)
    end
end

--- The boot banner, and the mod's origin tag.
---
--- Every line this mod ever prints is prefixed "[Traka]", and this first one
--- says whose Traka it is. A server runs thirty mods and console.txt is where
--- they all shout at once; without an owner on the banner, working out which
--- mod produced a stray line is guesswork. This is also the authorship marker
--- the licence refers to - it is part of the Work, not decoration.
AkaShop.AUTHOR = "AKA (lookchinnoi)"
AkaShop.BANNER = "Traka v" .. AkaShop.VERSION .. " - " .. AkaShop.AUTHOR ..
                 " - built for the HaftFull server"

print("[Traka] " .. AkaShop.BANNER)


--=================================================== state-aware transfers ==
-- The plain removeItems/giveItems only ever knew a count. These carry the
-- item's real condition across the wire so a chipped axe stays a chipped axe.

--- Remove up to `count` of `ft` and report what was actually taken, folded
--- into state rows. Built on collectItems/removeOne so it honours exactly the
--- same "what counts as sellable" rules as every other path (starred items,
--- the bag on your back, what is in your hands).
--- Returns moved, states.
--- `exact` refuses to remove anything at all unless the full count is present.
---
--- Needed by barter rows at a depot, where the trade is priced per LOT: a
--- player who hands over nineteen of the twenty has destroyed nineteen items in
--- exchange for nothing, and a depot cannot give them back. Without a lot the
--- old forgiving behaviour is right - handing over fewer simply pays less.
function AkaShop.removeItemsWithState(player, ft, count, exact)
    if not player then return 0, {} end
    local inv = player:getInventory()
    if not inv then return 0, {} end
    count = math.floor(count or 0)
    if count < 1 then return 0, {} end

    local found = AkaShop.collectItems(inv, ft, count, player)
    if exact and #found < count then return 0, {} end
    local buckets, order, moved = {}, {}, 0

    for i = 1, #found do
        local it = found[i]
        local st = AkaShopStock.stateOf(it)      -- read BEFORE removing it
        local k  = AkaShopStock.keyOf(st)
        if AkaShop.removeOne(player, it) then
            moved = moved + 1
            local b = buckets[k]
            if b then
                b.n = b.n + 1
            elseif #order >= AkaShop.MAX_UNITS and order[#order] then
                -- The cap. Everything past it folds into the last bucket,
                -- keeping the WORSE of every value, so a shop is never credited
                -- with better goods than were actually handed over.
                st.n = 1
                AkaShopStock.mergeInto(order[#order], st)
            else
                st.n = 1
                buckets[k] = st
                table.insert(order, st)
            end
        end
    end
    return moved, order
end

--- Create items from stored state rows. Returns how many actually appeared.
function AkaShop.giveItemsWithState(player, ft, states)
    local inv = player and player:getInventory()
    if not inv then return 0 end
    local sm = getScriptManager()
    if not (sm and sm:FindItem(ft)) then return 0 end

    local made = 0
    for _, st in ipairs(states or {}) do
        for _ = 1, math.floor(st.n or 0) do
            local item = createInto(inv, ft)
            if item then
                -- state goes on after the container owns the item, so the
                -- finished article is what gets announced, not a blank one
                AkaShopStock.applyState(item, st)
                made = made + 1
            end
        end
    end
    return made
end
