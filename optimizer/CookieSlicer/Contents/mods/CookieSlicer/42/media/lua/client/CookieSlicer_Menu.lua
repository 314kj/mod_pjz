-- Cookie Slicer (client): right-click menu opens faster with a long mod list.
--
-- The game's ISContextMenu:addOption ends with self:setWidth(self:calcWidth()), and
-- calcWidth measures the text of EVERY option already in the menu (one Java call
-- each). A menu of n options costs about n*n/2 text measurements while it is built;
-- with our mod list a right click on a busy square adds 40-100 options (plus their
-- sub-menus), so the menu shows up late and quick right clicks get lost.
--
-- Here calcWidth runs as before (the game's own code, plus any mod that wrapped it
-- before this file loaded; mods that wrap it later sit outside and measure with the
-- real one), but while it runs the text measurer remembers each text it has already
-- measured for that font. Each option's text is measured once, the rest are table
-- lookups. The width comes out the same number.
--   - nothing else of the menu changes: options, order, sub-menus, drawing
--   - memory: the remembered texts are thrown away at the first width worked out
--     more than 0.5 s after the one before (and when the screen size changes)
--   - check: the first 30 widths are also worked out the game's way; one difference
--     (or any error) and this file switches itself off for the session
-- Copyright (c) AKA / Cookie Cheetah. All rights reserved.

require "ISUI/ISContextMenu"

local TAG = "[CookieSlicer] menu"
local CHECKS = 30       -- widths compared with the game's own result
local KEEP_MS = 500     -- remembered texts live this long after the last use

if not ISContextMenu or type(ISContextMenu.calcWidth) ~= "function"
    or type(getTimestampMs) ~= "function" or type(getTextManager) ~= "function" then
    print(TAG .. ": ISContextMenu.calcWidth / getTimestampMs / getTextManager not found, off")
    return
end

local M = { on = true, checksLeft = CHECKS, hits = 0, measured = 0 }
CookieSlicerMenu = M

local nextCalc = ISContextMenu.calcWidth
local memo, lastUse = {}, 0
local active = false

-- stands in for the TextManager while calcWidth runs: MeasureStringX from memory,
-- every other method goes to the real one
local real
local proxy = {}
function proxy:MeasureStringX(font, text)
    if font == nil or type(text) ~= "string" then
        return real:MeasureStringX(font, text)
    end
    local byFont = memo[font]
    if not byFont then
        byFont = {}
        memo[font] = byFont
    end
    local w = byFont[text]
    if w == nil then
        w = real:MeasureStringX(font, text)
        byFont[text] = w
        M.measured = M.measured + 1
    else
        M.hits = M.hits + 1
    end
    return w
end
setmetatable(proxy, { __index = function(_, k)
    return function(_, ...) return real[k](real, ...) end
end })
local function getProxy() return proxy end

local function off(why)
    M.on = false
    memo = {}
    print(TAG .. ": off for this session (" .. tostring(why) .. ")")
end

ISContextMenu.calcWidth = function(self)
    if not M.on or active then
        return nextCalc(self)
    end
    -- whatever getTextManager is right now (another mod may have wrapped it) goes back after
    local prev = getTextManager
    active = true
    local ok, w = pcall(function()
        local now = getTimestampMs()
        if now - lastUse > KEEP_MS then memo = {} end
        lastUse = now
        real = prev()
        getTextManager = getProxy
        return nextCalc(self)
    end)
    getTextManager = prev
    active = false

    if not ok then
        off("error: " .. tostring(w))
        return nextCalc(self)
    end
    if M.checksLeft > 0 then
        M.checksLeft = M.checksLeft - 1
        local plain = nextCalc(self)
        if plain ~= w then
            off("width " .. tostring(w) .. " but the game says " .. tostring(plain))
            return plain
        end
    end
    return w
end

Events.OnResolutionChange.Add(function() memo = {} end)
