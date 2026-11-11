-- Cookie Throttle (part of Cookie - Server Patches, in the CookieEarlyHooks mod), players' games only.
-- Work a mod does every frame that gives the same result a few times a second.
--
-- Lifestyle: Hobbies - CLSInv.UpdateInvScripts. Its OnTick (LSPerTick.lua) calls it every frame,
-- and it walks every item in the inventory and loot windows to put back the stats saved on
-- invention items. Measured 10 Nov 2026 with the Cookie Profiler: 2.4% of the game's main
-- thread. Now it runs at most every 250 ms, and 100 ms after a container or the inventory/loot
-- window changes. Equipping an invention still updates it at once (Lifestyle's own
-- OnEquipPrimary handler, not changed). Nothing is saved or sent differently.
--
-- Log: "[CookieServerPatch] throttle: Lifestyle inventions ...". To undo: remove this file.

if isServer() then return end

local TAG = "[CookieServerPatch] throttle"
local EVERY_MS = 250
local AFTER_CHANGE_MS = 100

local lifestyle = { installed = false, last = nil, dirty = true, runs = 0, skips = 0 }

local function markDirty()
    lifestyle.dirty = true
end

local function installLifestyle()
    lifestyle.last, lifestyle.dirty = nil, true
    if lifestyle.installed then return end
    local C = CLSInv
    local orig = C and C.UpdateInvScripts
    if type(orig) ~= "function" then return end
    lifestyle.installed = true
    C.UpdateInvScripts = function(character, ...)
        local now = getTimestampMs()
        local last = lifestyle.last
        local due = last == nil or now < last or now - last >= EVERY_MS
            or (lifestyle.dirty and now - last >= AFTER_CHANGE_MS)
        if not due then
            lifestyle.skips = lifestyle.skips + 1
            return
        end
        lifestyle.last, lifestyle.dirty = now, false
        lifestyle.runs = lifestyle.runs + 1
        return orig(character, ...)
    end
    if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(markDirty) end
    if Events.OnRefreshInventoryWindowContainers then Events.OnRefreshInventoryWindowContainers.Add(markDirty) end
    print(TAG .. ": Lifestyle inventions every " .. EVERY_MS .. " ms (" .. AFTER_CHANGE_MS
        .. " ms after a container change) instead of every frame")
end

CookieThrottle = { lifestyle = lifestyle }

Events.OnGameStart.Add(installLifestyle)
