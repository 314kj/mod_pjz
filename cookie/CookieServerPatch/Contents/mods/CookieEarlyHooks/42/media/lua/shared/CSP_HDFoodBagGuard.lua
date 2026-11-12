-- CookieEarlyHooks (CookieServerPatch): HDs Food Recipes (3663132395) loot filter guard.
-- Loot is filled where it is rolled (the server in multiplayer).
--
-- With one of its sandbox options "spawn foods / ingredients / tools" turned off, HDs Food
-- Recipes removes its own items from every container the game fills (OnFillContainer), calling
-- container:getItems() on the third argument. For a bag rolled inside a container the game fires
-- OnFillContainer("Container", <bag type>, <the bag's loot table>): a loot table, not a container
-- (42.22.2, ItemPickerJava). getItems() on it throws, and the console prints the error with two
-- stack traces each time (164 times in one night, 12 Nov 2026).
-- Here the handler from HDF_ProceduralDistributions.lua is called only when the third argument is
-- a real container. Bags get the same as before (nothing could be removed there anyway), every
-- other container is filtered exactly as before. The mod's files are not changed.
-- Lua loads shared files of all mods before any server file, so this file (shared, early mod)
-- wraps Events.OnFillContainer.Add before HDs adds its handler; the handler is wrapped as it is
-- added, found by its file name. Without HDs nothing happens.

local TAG = "[CookieServerPatch] hdfood-bag-guard"
local FILE = "HDF_ProceduralDistributions.lua"

local ev = Events and Events.OnFillContainer
if type(ev) ~= "table" or type(ev.Add) ~= "function" then return end

local function fromFile(fn)
    if type(fn) ~= "function" or not getFilenameOfClosure then return false end
    local ok, path = pcall(getFilenameOfClosure, fn)
    if not ok or type(path) ~= "string" then return false end
    path = string.gsub(path, "\\", "/")
    return string.sub(path, -string.len(FILE)) == FILE
end

local skipped = 0

local function guard(fn)
    return function(roomName, containerType, container, ...)
        if container == nil or not instanceof(container, "ItemContainer") then
            skipped = skipped + 1
            if skipped == 1 or skipped % 1000 == 0 then
                print(TAG .. " skipped a call without a container (" .. tostring(roomName) .. "/" .. tostring(containerType) .. "), " .. skipped .. " so far")
            end
            return
        end
        return fn(roomName, containerType, container, ...)
    end
end

local add = ev.Add
local wrapped = false
ev.Add = function(fn, ...)
    if not wrapped and fromFile(fn) then
        wrapped = true
        print(TAG .. " on")
        return add(guard(fn), ...)
    end
    return add(fn, ...)
end
