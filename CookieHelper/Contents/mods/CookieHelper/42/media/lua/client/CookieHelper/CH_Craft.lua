-- Cookie Helper : craft-from-zone engine
-- Same flow as vanilla "craft from context menu", plus walking:
--   plan with zone containers -> walk to each box -> take what the recipe picked -> (wear mask)
--   -> craft with what is now in the backpack -> put tools back -> next one.
-- Every step re-plans from the real world state, so moved/used items never break the queue.
if isServer() then return end

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "CookieHelper/CH_Scan"
require "CookieHelper/CH_UI"

CHelp.Craft = CHelp.Craft or {}
local Craft = CHelp.Craft
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

-- ------------------------------------------------------------------ recipe catalogue (built once, lazily)
local allRecipes = nil
local byOutput = nil
local refill = false

function Craft.recipes()
    if allRecipes then return allRecipes end
    allRecipes = {}
    local list = ScriptManager.instance:getAllCraftRecipes()
    for i = 0, list:size() - 1 do
        local r = list:get(i)
        local okB, isBuild = pcall(function() return r:isBuildableRecipe() end)
        if not (okB and isBuild) then allRecipes[#allRecipes + 1] = r end
    end
    return allRecipes
end

function Craft.outputsIndex()
    if byOutput then return byOutput end
    byOutput = {}
    for _, r in ipairs(Craft.recipes()) do
        local outs = r:getOutputs()
        for i = 0, outs:size() - 1 do
            local ok, items = pcall(function() return outs:get(i):getPossibleResultItems() end)
            if ok and items then
                for j = 0, items:size() - 1 do
                    local ft = items:get(j):getFullName()
                    local l = byOutput[ft]
                    if not l then l = {} byOutput[ft] = l end
                    l[#l + 1] = r
                end
            end
        end
    end
    return byOutput
end

function Craft.recipesFor(fullType)
    return Craft.outputsIndex()[fullType] or {}
end

function Craft.byName(name)
    for _, r in ipairs(Craft.recipes()) do
        if r:getName() == name then return r end
    end
    return nil
end

function Craft.label(r)
    local ok, n = pcall(function() return r:getTranslationName() end)
    if ok and n and n ~= "" then return n end
    return r:getName()
end

local searchKeys = nil   -- lower-cased "label|name" per recipe, built once
function Craft.search(text, limit)
    text = string.lower(text or "")
    local out = {}
    if string.len(text) < 2 then return out end
    local list = Craft.recipes()
    if not searchKeys then
        searchKeys = {}
        for i, r in ipairs(list) do
            searchKeys[i] = string.lower(Craft.label(r) .. "|" .. r:getName())
        end
    end
    for i, r in ipairs(list) do
        if string.find(searchKeys[i], text, 1, true) then
            out[#out + 1] = r
            if #out >= (limit or 40) then break end
        end
    end
    return out
end

local torchCache = {}
local function usesBlowTorch(r)
    local key = r:getName()
    if torchCache[key] ~= nil then return torchCache[key] end
    local res = false
    local ins = r:getInputs()
    for i = 0, ins:size() - 1 do
        local ok, items = pcall(function() return ins:get(i):getPossibleInputItems() end)
        if ok and items then
            for j = 0, items:size() - 1 do
                if items:get(j):getFullName() == "Base.BlowTorch" then res = true end
            end
        end
    end
    torchCache[key] = res
    return res
end

local function refillRecipe()
    if refill == false then refill = Craft.byName("RefillBlowTorch") end
    return refill
end

-- ------------------------------------------------------------------ logic helpers
function Craft.planContainers(p, entries)
    local list = ArrayList.new()
    local seen = {}
    local pc = ISInventoryPaneContextMenu.getContainers(p)
    for i = 0, pc:size() - 1 do
        local c = pc:get(i)
        if not seen[c] then seen[c] = true list:add(c) end
    end
    for _, e in ipairs(entries or {}) do
        -- vehicle trunks are counted but never auto-looted (doors / seats make that unreliable)
        if not e.veh and not seen[e.c] then
            seen[e.c] = true
            list:add(e.c)
        end
    end
    return list
end

function Craft.newLogic(p, containers, recipe)
    local logic = HandcraftLogic.new(p, nil, nil)
    logic:setContainers(containers)
    if recipe then logic:setRecipe(recipe) end
    return logic
end

-- status of one recipe against the containers already set on logic (logic is reused)
function Craft.statusOne(logic, r)
    local st = { known = true, can = false, max = 0, bench = false }
    local ok = pcall(function()
        st.known = logic:isRecipeAvailableForCharacter(r)
        st.bench = r:requiresSpecificWorkstation()
        logic:setRecipe(r)
        st.can = logic:canPerformCurrentRecipe()
        if st.can then st.max = logic:getPossibleCraftCount(false) end
    end)
    if not ok then st.can = false end
    return st
end

local function isWeldingMask(it)
    return string.find(it:getFullType(), "WeldingMask", 1, true) ~= nil
end

-- where to stand for a box: nil,true = no walk needed (floor / carried), sq = walk next to it
local function boxSquare(c)
    local okT, ty = pcall(function() return c:getType() end)
    if okT and ty == "floor" then return nil, true end
    local sq = c:getSquare()
    if not sq then
        local outer = c:getOutermostContainer()
        if outer and outer ~= c then sq = outer:getSquare() end
    end
    return sq, false
end

-- adjacent free tile for a box, or false when it cannot be reached
local function standFor(p, c)
    local sq, noWalk = boxSquare(c)
    if noWalk then return nil end
    if not sq then return false end
    local adj = AdjacentFreeTileFinder.Find(sq, p)
    if not adj then return false end
    return adj
end

-- ------------------------------------------------------------------ the job
-- job = { p, recipe, left, entriesFn, returns = { {id, c} }, refilled }
-- items are tracked by ID: in MP the server moves them and the client gets new objects.
function Craft.start(p, recipe, qty, entriesFn)
    if not p or not recipe then return end
    if ISTimedActionQueue.isPlayerDoingAction(p) then
        UI.toast(t("Msg_Busy"), false)
        return
    end
    local job = { p = p, recipe = recipe, left = math.max(1, floor(qty or 1)), entriesFn = entriesFn, returns = {}, refilled = false }
    Craft.step(job)
end

local function fail(job, key)
    UI.toast(t(key, Craft.label(job.recipe)), false)
    Craft.returnTools(job)
end

function Craft.step(job)
    local p = job.p
    if job.left <= 0 then return end
    local entries = job.entriesFn and job.entriesFn() or {}
    local cont = Craft.planContainers(p, entries)
    local logic = Craft.newLogic(p, cont, job.recipe)
    local okCan, can = pcall(function() return logic:canPerformCurrentRecipe() end)
    if not (okCan and can) then
        if not job.refilled and usesBlowTorch(job.recipe) then
            job.refilled = true
            local rr = refillRecipe()
            if rr then
                local rl = Craft.newLogic(p, cont, rr)
                local okR, canR = pcall(function() return rl:canPerformCurrentRecipe() end)
                if okR and canR then
                    UI.toast(t("Msg_Refill"), true)
                    Craft.fetchAndCraft(job, rl, rr, true)
                    return
                end
            end
        end
        return fail(job, "Msg_CantCraft")
    end
    Craft.fetchAndCraft(job, logic, job.recipe, false)
end

function Craft.fetchAndCraft(job, logic, recipe, isRefill)
    local p = job.p
    local inv = p:getInventory()
    local data = logic:getRecipeData()
    local items = data:getAllInputItems()
    local keep = data:getAllPutBackInputItems()

    local groups, order, newReturns = {}, {}, {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local c = it:getContainer()
        if c and c ~= inv and not c:isInCharacterInventory(p) then
            local g = groups[c]
            if not g then
                g = { c = c, items = {} }
                groups[c] = g
                order[#order + 1] = g
            end
            g.items[#g.items + 1] = it
            if keep:contains(it) then newReturns[#newReturns + 1] = { id = it:getID(), c = c } end
        end
    end

    -- every box must be reachable before anything is queued (a failed walk/transfer resets the queue)
    for _, g in ipairs(order) do
        g.stand = standFor(p, g.c)
        if g.stand == false then return fail(job, "Msg_CantReach") end
    end

    -- everything has to fit in the backpack at once, otherwise the queue would stall half way
    local need = 0
    for _, g in ipairs(order) do
        for _, it in ipairs(g.items) do need = need + it:getUnequippedWeight() end
    end
    if need > 0 and not inv:hasRoomFor(p, need) then
        return fail(job, "Msg_TooHeavy")
    end
    for _, r in ipairs(newReturns) do job.returns[#job.returns + 1] = r end

    -- nearest-first walk through the boxes
    local px, py = p:getX(), p:getY()
    local route = {}
    while #order > 0 do
        local bi, bd = 1, nil
        for i, g in ipairs(order) do
            local sq = g.stand
            local d = sq and ((sq:getX() - px) * (sq:getX() - px) + (sq:getY() - py) * (sq:getY() - py)) or 0
            if not bd or d < bd then bi, bd = i, d end
        end
        local g = table.remove(order, bi)
        route[#route + 1] = g
        if g.stand then px, py = g.stand:getX(), g.stand:getY() end
    end

    for _, g in ipairs(route) do
        if g.stand then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, g.stand)) end
        for _, it in ipairs(g.items) do
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, g.c, inv))
        end
    end

    -- items to wear (IsWorn inputs + welding mask) are found again by ID once they are in the bag
    local wearIds, seen = {}, {}
    local function addWear(it)
        local id = it:getID()
        if not seen[id] and not p:isEquippedClothing(it) then
            seen[id] = true
            wearIds[#wearIds + 1] = id
        end
    end
    local okW, worn = pcall(function() return data:getAllInputItemsWithFlag("IsWorn") end)
    if okW and worn then for i = 0, worn:size() - 1 do addWear(worn:get(i)) end end
    if CHelp.sv("AutoWearWeldingMask") then
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if isWeldingMask(it) then addWear(it) end
        end
    end

    ISTimedActionQueue.queueActions(p, Craft.deferredCraft, { job = job, recipe = recipe, refill = isRefill, wear = wearIds })
end

-- runs when the queue reaches it: everything should be in the backpack now
local function deferredCraftInner(p, ctx)
    local inv = p:getInventory()
    for _, id in ipairs(ctx.wear or {}) do
        local it = inv:getItemWithIDRecursiv(id)
        if it and not p:isEquippedClothing(it) then
            if it:getContainer() ~= inv then
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), inv))
            end
            ISTimedActionQueue.add(ISWearClothing:new(p, it))
        end
    end
    local logic = HandcraftLogic.new(p, nil, nil)
    pcall(function() logic:setIsoObject(ISEntityUI.FindCraftSurface(p, 2)) end)
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    logic:setRecipe(ctx.recipe)
    local okCan, can = pcall(function() return logic:canPerformCurrentRecipe() end)
    if not (okCan and can) then
        return fail(ctx.job, "Msg_CantCraft")
    end
    local actions = ISEntityUI.HandcraftStartMultiple(p, logic, false, 1, false)
    if not actions or #actions == 0 then
        return fail(ctx.job, "Msg_CantCraft")
    end
    for _, a in ipairs(actions) do ISTimedActionQueue.add(a) end
    ISTimedActionQueue.queueActions(p, Craft.afterCraft, ctx)
end

function Craft.deferredCraft(p, ctx)
    local ok, err = pcall(deferredCraftInner, p, ctx)
    if not ok then
        CHelp.log("deferred craft failed: " .. tostring(err))
        fail(ctx.job, "Msg_CantCraft")
    end
end

function Craft.afterCraft(p, ctx)
    local job = ctx.job
    local ok, err = pcall(function()
        if ctx.refill then
            Craft.step(job)          -- torch is full again, try the real recipe
            return
        end
        job.left = job.left - 1
        job.refilled = false
        if job.left > 0 then
            Craft.step(job)
        else
            Craft.returnTools(job)
            UI.toast(t("Msg_CraftDone", Craft.label(job.recipe)), true)
        end
    end)
    if not ok then
        CHelp.log("after craft failed: " .. tostring(err))
        Craft.returnTools(job)
    end
end

-- tools that were borrowed from boxes go back where they came from
function Craft.returnTools(job)
    if not CHelp.sv("ReturnToolsAfterCraft") then job.returns = {} return end
    local p = job.p
    local inv = p:getInventory()
    local byBox, order, seen = {}, {}, {}
    for _, r in ipairs(job.returns) do
        local it = (not seen[r.id]) and inv:getItemWithIDRecursiv(r.id) or nil
        if it and it:getContainer() ~= r.c then
            seen[r.id] = true
            local g = byBox[r.c]
            if not g then g = { c = r.c, items = {} } byBox[r.c] = g order[#order + 1] = g end
            g.items[#g.items + 1] = it
        end
    end
    job.returns = {}
    for _, g in ipairs(order) do
        local stand = standFor(p, g.c)
        if stand ~= false then
            if stand then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, stand)) end
            for _, it in ipairs(g.items) do
                local a = ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), g.c)
                if a.setAllowMissingItems then a:setAllowMissingItems(true) end
                ISTimedActionQueue.add(a)
            end
        end
    end
end
