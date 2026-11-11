--[[ ===================================================================
     AkaMenu - one right-click parent for every AKA mod.

     THE PROBLEM THIS SOLVES

     Each mod registers its own OnFillWorldObjectContextMenu handler, and
     each one politely puts its tools under a parent called "AKA Mod". None
     of them can see the others, so a player with four AKA mods installed
     right-clicks a tile and gets four rows all called "AKA Mod", stacked on
     top of each other, and has to open each one to find out which is which.
     Politeness practised separately turns into clutter.

     HOW IT WORKS

     A mod does not build its parent any more. It REGISTERS a builder:

         AkaMenu.add(context, "Traka", function(menu)
             menu:addOption("Shop Manager...", nil, openManager)
         end)

     Every registration made during one right-click is collected, and the
     menu is built once at the end of that fill, when the number of mods
     that spoke up is finally known:

         one mod  ->  AKA Mod > Shop Manager...          (no extra click)
         several  ->  AKA Mod > Traka    > Shop Manager...
                              > Akacount > ...

     That is the whole reason the build is deferred. Building eagerly would
     force the "which mod" level to exist even when only one mod is
     installed, and that extra click would be paid by every player forever
     to solve a problem only some of them have.

     WHAT BELONGS IN HERE

     Server-wide tools that are reachable from any tile. NOT verbs that act
     on the tile that was clicked - "Sell to Joy's Shop" must stay a
     top-level row, because burying the thing a counter exists to do is how
     the clutter started.

     SHIPPING IT IN ANOTHER MOD

     Copy this file to media/lua/client/AkaMenu.lua in that mod too. If two
     mods ship it at the same path the game loads one of them; if they ship
     it at different paths the version guard below makes the second copy a
     no-op. Either way there is exactly one AkaMenu, and mods that have not
     been updated yet simply keep their own separate parent - nothing
     breaks, the menu is just not tidy yet.

     IF THE DEFERRED BUILD EVER FAILS

     The build runs from a handler registered during OnGameStart, so it is
     added after every mod's file-scope handler and therefore runs last. If
     some future build changes that and the flush stops running, the next
     right-click notices the leftovers, gives up on deferring permanently,
     and falls back to building immediately with one submenu per mod. A
     click deeper than it needs to be beats an admin menu that vanished.
     ================================================================== ]]

if AkaMenu and (AkaMenu.VERSION or 0) >= 1 then return end

AkaMenu = AkaMenu or {}
AkaMenu.VERSION = 1
AkaMenu.LABEL   = "AKA Mod"

local pending  = {}
local deferOK  = true

-- Frame, not clock. Every handler for one right-click is dispatched inside
-- a single tick, so "same frame" is exactly "same menu" - no timing window
-- to tune and nothing to get wrong on a stuttering server.
local frame     = 0
local lastFrame = -1

-- Degraded-mode state, only ever touched once deferOK has gone false.
local degMenu = nil

pcall(function()
    Events.OnTick.Add(function() frame = frame + 1 end)
end)

--- Run a mod's builder without letting it take the menu down with it.
local function safebuild(fn, menu)
    -- Closure rather than pcall(fn, menu): Kahlua's pcall is not Lua 5.1's,
    -- and every other guarded call in this codebase is written this way.
    local ok = pcall(function() fn(menu) end)
    if not ok then
        local o = menu:addOption("(this section failed to build)", nil, nil)
        o.notAvailable = true
    end
end

local function newSub(parent, label)
    local sub = ISContextMenu:getNew(parent)
    local opt = parent:addOption(label, nil, nil)
    parent:addSubMenu(opt, sub)
    return sub
end

--- True the first time it is called in a given right-click.
local function beginFill(context)
    if frame == lastFrame then return false end
    lastFrame = frame
    if #pending > 0 then
        -- Registrations from the previous fill were never built. The flush
        -- handler is not running; stop relying on it.
        deferOK = false
        pending = {}
    end
    degMenu = nil
    return true
end

--- Register a section. `fn` is called with the menu to fill, either at the
--- end of this fill or - in degraded mode - immediately.
---
--- Only call this when the section will actually contain something. An
--- empty submenu is a row that opens onto nothing.
function AkaMenu.add(context, modName, fn)
    if not context or type(fn) ~= "function" then return false end
    modName = tostring(modName or "AKA")

    beginFill(context)

    if deferOK then
        table.insert(pending, { name = modName, fn = fn, seq = #pending + 1 })
        return true
    end

    if not degMenu then
        local root = context:addOptionOnTop(AkaMenu.LABEL, nil, nil)
        degMenu = ISContextMenu:getNew(context)
        context:addSubMenu(root, degMenu)
    end
    safebuild(fn, newSub(degMenu, modName))
    return true
end

--- Alphabetical, with the registration order breaking ties, so the list a
--- player learns does not reshuffle itself when mod load order changes.
local function byName(a, b)
    local x, y = string.lower(a.name), string.lower(b.name)
    if x ~= y then return x < y end
    return a.seq < b.seq
end

local function flush(playerNum, context, worldobjects, test)
    if test then return end
    local n = #pending
    if n == 0 then return end
    local list = pending
    pending = {}
    if not context then return end

    local root = context:addOptionOnTop(AkaMenu.LABEL, nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)

    if n == 1 then
        -- One mod: its options ARE the AKA Mod menu. This is the case that
        -- pays for the deferral.
        safebuild(list[1].fn, menu)
        return
    end

    table.sort(list, byName)
    for i = 1, n do
        safebuild(list[i].fn, newSub(menu, list[i].name))
    end
end

AkaMenu.flush = flush   -- exposed for the test harness

-- Registered here rather than at file scope on purpose: handlers run in the
-- order they were added, mods add theirs while their files load, and this
-- one has to run after all of them.
Events.OnGameStart.Add(function()
    Events.OnFillWorldObjectContextMenu.Add(flush)
end)
