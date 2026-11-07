-- Cookie Helper : which items a recipe may use, per input (the player's own choice)
-- An input that accepts several items (any charcoal, any hammer, nails or screws ...) can be set
-- to: only some of them (tick boxes) and in which order to use them. The craft takes the first
-- ticked one that is in reach and moves on to the next when it runs out.
-- Stored on this computer only: Zomboid/Lua/CookieHelper_inputs.txt
if isServer() then return end

require "CookieHelper/CH_Shared"

CHelp.Inputs = CHelp.Inputs or {}
local In = CHelp.Inputs
local FILE = "CookieHelper_inputs.txt"

-- prefs[recipeName][inputIndex] = { order = { ft, ... }, off = { [ft] = true } }
In.prefs = In.prefs or {}
In.gen = In.gen or 0          -- bumps on every change, so cached plans/status redo themselves

local function split(s, sep)
    local out = {}
    local from = 1
    while true do
        local i = string.find(s, sep, from, true)
        if not i then
            out[#out + 1] = string.sub(s, from)
            break
        end
        out[#out + 1] = string.sub(s, from, i - 1)
        from = i + 1
    end
    return out
end

function In.load()
    In.prefs = {}
    local ok = pcall(function()
        local r = getFileReader(FILE, false)
        if not r then return end
        while true do
            local line = r:readLine()
            if not line then break end
            -- recipe|index|ft,ft,ft|offFt,offFt
            local f = split(line, "|")
            local rn, idx = f[1], tonumber(f[2])
            if rn and rn ~= "" and idx then
                local e = { order = {}, off = {} }
                if f[3] and f[3] ~= "" then e.order = split(f[3], ",") end
                if f[4] and f[4] ~= "" then for _, ft in ipairs(split(f[4], ",")) do e.off[ft] = true end end
                In.prefs[rn] = In.prefs[rn] or {}
                In.prefs[rn][idx] = e
            end
        end
        r:close()
    end)
    if not ok then In.prefs = {} end
end

function In.save()
    pcall(function()
        local w = getFileWriter(FILE, true, false)
        if not w then return end
        for rn, list in pairs(In.prefs) do
            for idx, e in pairs(list) do
                local off = {}
                for ft, v in pairs(e.off or {}) do if v then off[#off + 1] = ft end end
                w:write(rn .. "|" .. tostring(idx) .. "|" .. table.concat(e.order or {}, ",") .. "|" .. table.concat(off, ",") .. "\n")
            end
        end
        w:close()
    end)
end

function In.get(r, idx)
    local list = r and In.prefs[r:getName()]
    return list and list[idx] or nil
end

-- the player set this input (once saved, the order is followed even if it is the game's own)
function In.isCustom(r, idx, fts)
    return In.get(r, idx) ~= nil
end

-- fts in the player's order, unticked ones left out (never empty: all off = the game's list)
function In.allowed(r, idx, fts)
    local e = In.get(r, idx)
    if not e then return fts end
    local out, seen = {}, {}
    local valid = {}
    for _, ft in ipairs(fts) do valid[ft] = true end
    for _, ft in ipairs(e.order or {}) do
        if valid[ft] and not seen[ft] and not e.off[ft] then
            seen[ft] = true
            out[#out + 1] = ft
        end
    end
    for _, ft in ipairs(fts) do
        if not seen[ft] and not e.off[ft] then
            seen[ft] = true
            out[#out + 1] = ft
        end
    end
    if #out == 0 then return fts end
    return out
end

-- full ordered list (ticked and unticked) for the picker window
function In.ordered(r, idx, fts)
    local e = In.get(r, idx)
    local out, seen, valid = {}, {}, {}
    for _, ft in ipairs(fts) do valid[ft] = true end
    for _, ft in ipairs(e and e.order or {}) do
        if valid[ft] and not seen[ft] then seen[ft] = true out[#out + 1] = ft end
    end
    for _, ft in ipairs(fts) do
        if not seen[ft] then seen[ft] = true out[#out + 1] = ft end
    end
    return out
end

function In.isOn(r, idx, ft)
    local e = In.get(r, idx)
    return not (e and e.off[ft])
end

function In.set(r, idx, order, off)
    local rn = r:getName()
    In.prefs[rn] = In.prefs[rn] or {}
    In.prefs[rn][idx] = { order = order or {}, off = off or {} }
    In.gen = In.gen + 1
    In.save()
end

function In.reset(r, idx)
    local list = In.prefs[r:getName()]
    if list then list[idx] = nil end
    In.gen = In.gen + 1
    In.save()
end

local function usesOf(it)
    local ok, n = pcall(function() return it:getCurrentUses() end)
    if ok and type(n) == "number" and n > 0 then return n end
    return 1
end

-- point the logic at the player's choice: for every customised input, hand it exactly the
-- items to use (first choice first, then the next ones). Call after setRecipe.
function In.apply(logic, r, p)
    if not logic or not r or not In.prefs[r:getName()] then return end
    pcall(function()
        local Craft = CHelp.Craft
        local ins = r:getInputs()
        local viable = nil
        for i = 0, ins:size() - 1 do
            local input = ins:get(i)
            local fts = Craft.inputItems(input)
            if #fts > 1 and In.isCustom(r, i, fts) then
                if not viable then viable = logic:getAllViableInputInventoryItems() end
                local rank = {}
                for k, ft in ipairs(In.allowed(r, i, fts)) do rank[ft] = k end
                local cand = {}
                for j = 0, viable:size() - 1 do
                    local it = viable:get(j)
                    local rk = rank[it:getFullType()]
                    if rk then cand[#cand + 1] = { it = it, rk = rk, j = j } end
                end
                table.sort(cand, function(a, b)
                    if a.rk ~= b.rk then return a.rk < b.rk end
                    return a.j < b.j
                end)
                local need = Craft.inputAmount(input)
                local partial = not Craft.inputCountMode(input)
                local list = ArrayList.new()
                local got = 0
                for _, c in ipairs(cand) do
                    if got >= need then break end
                    list:add(c.it)
                    got = got + (partial and usesOf(c.it) or 1)
                end
                logic:setManualInputsFor(input, list)
            end
        end
    end)
end

Events.OnGameStart.Add(function() In.load() end)
