-- Cookie Mastery - Mechanic Lv 10 reward (file name sorts after CMM_Shared on purpose): 5 Legendary Forge Seals (CookieServerPatch item CSP.LTWForgeSeal)
-- Given once per life (a death starts a new life), the first time the player is online and alive with the mechanic branch at Lv 10.
-- Kept in its own file so the main server file stays untouched. Skipped (logged once) if the item is missing.
require "CMM_Shared"

CMM.SEAL_TYPE = "CSP.LTWForgeSeal"
CMM.SEAL_COUNT = 5

-- the mechanic Lv 10 node is live (the seals); the vehicle repair part of it is still coming
CMM.LIVE.mech = CMM.LIVE.mech or {}
CMM.LIVE.mech[10] = true

if isClient() and not isServer() then return end

CMMSeal = CMMSeal or {}
local warned = false
local lastMs = 0

local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return CM.now() * 1000
end

local function players()
    local out = {}
    if CM.isSP() then
        local p = getSpecificPlayer(0)
        if p then out[#out + 1] = p end
        return out
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

local function alive(p)
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

-- server-side items only (a client-side add/remove can trip the anti-cheat)
local function give(p, n)
    local inv = p:getInventory()
    if not inv then return 0 end
    local got = 0
    for _ = 1, n do
        local ok, item = pcall(instanceItem, CMM.SEAL_TYPE)
        if ok and item then
            inv:AddItem(item)
            if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
            got = got + 1
        end
    end
    return got
end

function CMMSeal.tick()
    if not CMMS or not CMMS.state or not CMM.sv("Enabled") then return end
    local S = CMMS.state()
    if not S or not S.p then return end
    local sm = getScriptManager()
    if not (sm and sm:FindItem(CMM.SEAL_TYPE)) then
        if not warned then
            warned = true
            CMM.log("mech seal: item " .. CMM.SEAL_TYPE .. " not found (is CookieServerPatch on?)")
        end
        return
    end
    -- S.seal[key] = the life that already got its seals (kept outside S.p so an admin reset does not re-arm it)
    S.seal = S.seal or {}
    for _, p in ipairs(players()) do
        local k = CMMS.keyOf(p)
        local r = k and S.p[k]
        local life = r and (r.life or 1)
        if r and r.br == "mech" and S.seal[k] ~= life and alive(p) then
            local lv = CMM.level(r.pts)
            if lv >= 10 then
                local got = give(p, CMM.SEAL_COUNT)
                if got > 0 then
                    S.seal[k] = life
                    if CMMS.toast then CMMS.toast(k, "seal", { got }) end
                    if CMMS.logLine then CMMS.logLine(tostring(r.name or k) .. " got " .. got .. " legendary forge seals (mechanic Lv 10)") end
                end
            end
        end
    end
end

Events.OnTick.Add(function()
    local t = nowMs()
    if t - lastMs < 5000 then return end
    lastMs = t
    local ok, err = pcall(CMMSeal.tick)
    if not ok and not CMMSeal.err then
        CMMSeal.err = true
        CMM.log("mech seal error: " .. tostring(err))
    end
end)
CMM.log("mech seal on: Lv 10 mechanic gets " .. CMM.SEAL_COUNT .. " x " .. CMM.SEAL_TYPE)
return CMMSeal
