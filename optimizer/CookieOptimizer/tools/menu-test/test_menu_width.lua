-- Test for CookieSlicer_Menu.lua outside the game (plain Lua 5.1+).
-- Loads the game's own ISContextMenu.lua with small stand-ins for the Java side, then
-- builds menus with and without Cookie Slicer and compares widths and text measurements.
--
--   lua test_menu_width.lua <ProjectZomboid folder> <CookieSlicer_Menu.lua>
-- Copyright (c) AKA / Cookie Cheetah. All rights reserved.

local gameDir, slicerFile = arg[1], arg[2]
assert(gameDir and slicerFile, "usage: lua test_menu_width.lua <ProjectZomboid folder> <CookieSlicer_Menu.lua>")
local vanillaFile = gameDir .. "/media/lua/client/ISUI/ISContextMenu.lua"

local failed = 0
local function check(cond, name)
    print((cond and "PASS " or "FAIL ") .. name)
    if not cond then failed = failed + 1 end
end

-- ---------------------------------------------------------------- stand-ins
local calls, clock
local textManager = {}
function textManager:MeasureStringX(font, text)
    calls = calls + 1
    if type(text) ~= "string" then error("MeasureStringX: text is " .. type(text)) end
    return #text * font.px
end
function textManager:getFontHeight(font) return font.px * 2 end

local function setup()
    calls, clock = 0, 1000
    ISPanel = { derive = function(self, name)
        local t = {}
        t.__index = t
        return setmetatable(t, { __index = self })
    end }
    UIFont = { Small = { px = 5 }, Medium = { px = 7 }, Large = { px = 9 } }
    require = function() end
    getTextManager = function() return textManager end
    getTimestampMs = function() return clock end
    getCore = function() return {
        isTutorial = function() return false end,
        getScreenHeight = function() return 1080 end,
    } end
    table.wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end end
    Events = { OnResolutionChange = { Add = function() end } }
    CookieSlicerMenu = nil
    dofile(vanillaFile)
end

local function newMenu(font)
    local m = setmetatable({
        options = {}, numOptions = 1, optionPool = {}, font = font or UIFont.Medium,
        itemHgt = 26, padTopBottom = 4, scrollIndicatorHgt = 14,
    }, ISContextMenu)
    function m:setWidth(w) self.width = w end
    function m:setHeight(h) self.height = h end
    function m:setScrollHeight() end
    return m
end

local names = {}
for i = 1, 120 do names[i] = "Option " .. string.rep("x", (i * 37) % 23) .. i end

-- build one menu; returns the width after every add and the measurement count
local function build(n, menu)
    menu = menu or newMenu()
    local widths = {}
    calls = 0
    for i = 1, n do
        menu:addOption(names[i])
        widths[i] = menu.width
    end
    return widths, calls, menu
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- ---------------------------------------------------------------- 1. same widths, fewer calls
setup()
local plainW, plainCalls = build(120)
setup()
dofile(slicerFile)
local fastW, fastCalls = build(120)
check(same(plainW, fastW), "120 options: width after every add is the same as the game's")
print(("     text measurements: game " .. plainCalls .. ", Cookie Slicer " .. fastCalls))
-- the first 30 adds also run the game's way (check), then one measurement per new text
check(fastCalls < plainCalls / 5, "120 options: at least 5x fewer text measurements")
check(CookieSlicerMenu.on == true, "still on after a normal menu")

-- ---------------------------------------------------------------- 2. another mod wrapped calcWidth first
-- (like Smarter Storage: adds room for its buttons and measures text of its own)
local function wrapLikeStorage()
    local inner = ISContextMenu.calcWidth
    ISContextMenu.calcWidth = function(self)
        local w = inner(self)
        if self.storage then w = w + getTextManager():MeasureStringX(self.font, "[Take all]") + getTextManager():getFontHeight(self.font) end
        return w
    end
end
setup(); wrapLikeStorage()
local m1 = newMenu(); m1.storage = true
local before1 = build(60, m1)
setup(); wrapLikeStorage(); dofile(slicerFile)
local m2 = newMenu(); m2.storage = true
local after1 = build(60, m2)
check(same(before1, after1), "mod wrapped calcWidth BEFORE Cookie Slicer: same widths (its extra kept)")
check(CookieSlicerMenu.on == true, "mod wrapped before: still on (getFontHeight passed through)")

-- ---------------------------------------------------------------- 3. another mod wraps AFTER Cookie Slicer
setup(); wrapLikeStorage()
local m3 = newMenu(); m3.storage = true
local before2 = build(60, m3)
setup(); dofile(slicerFile); wrapLikeStorage()
local m4 = newMenu(); m4.storage = true
local after2 = build(60, m4)
check(same(before2, after2), "mod wrapped calcWidth AFTER Cookie Slicer: same widths")

-- ---------------------------------------------------------------- 4. menu reused, other font, removals
setup()
local ref = newMenu(UIFont.Large)
local refW = {}
build(40, ref); ref:removeLastOption(); refW[1] = ref.width
ref:insertOptionBefore(names[3], "Inserted long option name here"); refW[2] = ref.width
ref:clear(); ref:addOption("a"); refW[3] = ref.width
setup(); dofile(slicerFile)
local m5 = newMenu(UIFont.Large)
local w5 = {}
build(40, m5); m5:removeLastOption(); w5[1] = m5.width
m5:insertOptionBefore(names[3], "Inserted long option name here"); w5[2] = m5.width
m5:clear(); m5:addOption("a"); w5[3] = m5.width
check(same(refW, w5), "remove / insert / clear on a Large-font menu: same widths")

-- same text in two fonts must not share a remembered width
setup(); dofile(slicerFile)
local small, large = newMenu(UIFont.Small), newMenu(UIFont.Large)
small:addOption("Same text"); large:addOption("Same text")
setup()
local small2, large2 = newMenu(UIFont.Small), newMenu(UIFont.Large)
small2:addOption("Same text"); large2:addOption("Same text")
check(small.width == small2.width and large.width == large2.width, "same text, two fonts: two different widths kept apart")

-- ---------------------------------------------------------------- 5. memory is dropped after 0.5 s
setup(); dofile(slicerFile)
build(10)
clock = clock + 600
calls = 0
newMenu():addOption(names[1])
check(calls >= 1, "after 0.5 s the remembered texts are gone (measured again)")

-- ---------------------------------------------------------------- 6. a difference switches it off
setup(); dofile(slicerFile)
local realMeasure = textManager.MeasureStringX
local n = 0
-- a measurer that answers differently the second time it sees a text (the check catches it)
textManager.MeasureStringX = function(self, font, text) n = n + 1; return realMeasure(self, font, text) + n end
local m6 = newMenu()
-- (long texts: the game never makes a menu narrower than 100, short ones would hide the difference)
m6:addOption("Option number one, long enough"); m6:addOption("Option number two, long enough")
textManager.MeasureStringX = realMeasure
check(CookieSlicerMenu.on == false, "result differs from the game's: switches itself off")
local m7 = newMenu()
local offW = build(20, m7)
setup()
local plainOff = build(20)
check(same(offW, plainOff), "after switching off: game's own widths")

-- ---------------------------------------------------------------- 7. an error inside switches it off, menu still works
setup(); dofile(slicerFile)
local m8 = newMenu()
m8:addOption("fine")
local okAdd = pcall(function() m8:addOption(nil) end)
-- the game's own code errors on a nil text too; Cookie Slicer must not leave the stand-in behind
check(getTextManager() == textManager, "after an error the real text manager is back")
check(CookieSlicerMenu.on == false, "error inside calcWidth: switches itself off")
print("     (the nil option itself " .. (okAdd and "was added" or "errors as in the game") .. ")")

print(failed == 0 and "ALL PASS" or (failed .. " FAILED"))
os.exit(failed == 0 and 0 or 1)
