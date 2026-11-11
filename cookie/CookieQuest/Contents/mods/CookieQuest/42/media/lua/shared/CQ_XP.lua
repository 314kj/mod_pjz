-- Cookie Quest - XP multiplier hook (shared: runs on server, MP client and SP)
--
-- Where XP is granted differs by game mode, so the hook decides at runtime:
--   SP / host     : bonus applied right away in this process
--   MP server     : bonus applied with addXpNoMultiplier() (syncs to the client),
--                   then the client is told "srvxp" so it never applies its own copy
--   MP client     : bonus is queued for 2 s and only applied if the server never
--                   claimed XP handling (fallback for builds where XP is client side)
-- Provider: CQ.XP.provider(player, perkId) -> multiplier (set by server / client code)

require "CQ_Shared"

CQ.XP = CQ.XP or {}
local X = CQ.XP
X.busy = false
X.srvFlag = X.srvFlag or false
X.queue = X.queue or {}
X.notes = X.notes or {}
X.QUEUE_MS = 2000

function X.perkId(perk)
    if perk == nil then return "" end
    local ok, id = pcall(function() return perk:getId() end)
    if ok and id ~= nil then return tostring(id) end
    return tostring(perk)
end

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return CQ.now() * 1000
end

function X.note(player, pid, base, bonus, mult, side)
    table.insert(X.notes, 1, { pid = pid, base = base, bonus = bonus, mult = mult, side = side, ms = nowMs() })
    while #X.notes > 6 do table.remove(X.notes) end
    if X.onNote then pcall(X.onNote, player, X.notes[1]) end
end

-- actually add `amount` (may be negative for penalties)
function X.apply(player, perk, amount)
    X.busy = true
    local ok = false
    if (isServer() or CQ.isSP()) and type(addXpNoMultiplier) == "function" then
        ok = pcall(addXpNoMultiplier, player, perk, amount)
    end
    if not ok then
        ok = pcall(function() player:getXp():AddXP(perk, amount, false, false, false) end)
    end
    X.busy = false
    return ok
end

function X.onAddXP(character, perk, amount)
    if X.busy then return end
    if character == nil or perk == nil then return end
    amount = tonumber(amount)
    if amount == nil or amount <= 0 then return end
    if not instanceof(character, "IsoPlayer") then return end
    local provider = X.provider
    if type(provider) ~= "function" then return end
    local pid = X.perkId(perk)
    local okm, mult = pcall(provider, character, pid)
    if not okm or type(mult) ~= "number" then return end
    if math.abs(mult - 1) < 0.001 then return end
    local bonus = amount * (mult - 1)
    if isServer() then
        if X.apply(character, perk, bonus) then
            X.note(character, pid, amount, bonus, mult, "srv")
            if X.onServerApplied then pcall(X.onServerApplied, character) end
        end
    elseif isClient() then
        if X.srvFlag then return end
        local okl, isLocal = pcall(function() return character:isLocalPlayer() end)
        if okl and not isLocal then return end
        X.queue[#X.queue + 1] = { p = character, perk = perk, pid = pid, base = amount, bonus = bonus, mult = mult, at = nowMs() }
    else
        if X.apply(character, perk, bonus) then
            X.note(character, pid, amount, bonus, mult, "sp")
        end
    end
end

-- MP client: flush queued bonuses (called from OnTick)
function X.flush()
    if #X.queue == 0 then return end
    if X.srvFlag then X.queue = {}; return end
    local t = nowMs()
    local keep = {}
    for i = 1, #X.queue do
        local q = X.queue[i]
        if t - q.at >= X.QUEUE_MS then
            if X.apply(q.p, q.perk, q.bonus) then
                X.note(q.p, q.pid, q.base, q.bonus, q.mult, "cli")
            end
        else
            keep[#keep + 1] = q
        end
    end
    X.queue = keep
end

function X.setServerHandled()
    X.srvFlag = true
    X.queue = {}
end

if not X._registered then
    X._registered = true
    if Events.AddXP then
        Events.AddXP.Add(function(character, perk, amount)
            local ok, err = pcall(X.onAddXP, character, perk, amount)
            if not ok then CQ.log("AddXP hook error: " .. tostring(err)) end
        end)
    else
        CQ.log("AddXP event not available - EXP buffs disabled")
    end
    if isClient() and not isServer() then
        Events.OnTick.Add(function() X.flush() end)
    end
end

return X
