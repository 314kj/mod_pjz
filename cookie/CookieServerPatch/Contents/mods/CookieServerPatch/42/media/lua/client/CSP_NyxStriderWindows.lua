-- CookieServerPatch: Nyx Strider (3814087266) - cheaper glass check.
-- The mod's client file NyxStrider_Windows.lua swaps the Strider's glass models (whole /
-- light cracks / heavy cracks / gone) every 30 ticks. To find Striders it reads every
-- square within 30 of each local player (61 x 61 = 3,721 squares, two game calls each),
-- all the time, even with no Strider anywhere near.
-- This file replaces only that search (NyxStrider.Windows.scan): it walks the list of
-- loaded vehicles (a few dozen) and hands each Strider within the same 30 squares to the
-- mod's own NyxStrider.Windows.update, so the glass looks exactly as before.
-- If the vehicle list cannot be read, the mod's own search is used again (logged once).
-- Client only. ASCII only. Does nothing without the mod. To undo: remove this file.

if isServer() and not isClient() then return end

local TAG = "[CookieServerPatch] nyx-windows"

CSP_NyxWindows = CSP_NyxWindows or {}
local M = CSP_NyxWindows

local function isStrider(v)
    local name = v:getScriptName()
    return name ~= nil and string.find(name, "NyxStrider", 1, true) ~= nil
end

local function nearLocalPlayer(v, r)
    local vx, vy = v:getX(), v:getY()
    for n = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(n)
        if p and math.abs(p:getX() - vx) <= r and math.abs(p:getY() - vy) <= r then
            return true
        end
    end
    return false
end

-- Striders within r of a local player, from the cell's vehicle list
function M.find(r)
    local found = {}
    local cell = getCell()
    if not cell then return found end
    local vs = cell:getVehicles()
    if not vs then return found end
    local it = vs:iterator()
    while it:hasNext() do
        local v = it:next()
        if v and isStrider(v) and nearLocalPlayer(v, r) then found[#found + 1] = v end
    end
    return found
end

function M.patch()
    if M.done then return end
    local W = NyxStrider and NyxStrider.Windows
    if type(W) ~= "table" or type(W.scan) ~= "function" or type(W.update) ~= "function" then return end
    M.done = true
    M.orig = W.scan
    W.scan = function()
        if M.failed then return M.orig() end
        local ok, list = pcall(M.find, W.RADIUS or 30)
        if not ok then
            M.failed = true
            print(TAG .. ": vehicle list not readable (" .. tostring(list) .. "), the mod's own search is used")
            return M.orig()
        end
        for i = 1, #list do W.update(list[i]) end
    end
    print(TAG .. " on")
end

Events.OnGameStart.Add(M.patch)
