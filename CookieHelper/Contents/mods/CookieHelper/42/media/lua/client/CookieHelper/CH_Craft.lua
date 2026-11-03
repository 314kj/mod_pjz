-- Cookie Helper : craft-from-zone engine
-- Same flow as vanilla crafting, plus walking:
--   plan with zone containers -> walk to each box -> take what the recipe picked -> (wear mask)
--   -> walk to the workstation / table if the recipe needs one -> craft -> put tools back -> next.
-- Every craft re-plans from the real world state, so moved/used items never break a queue.
-- Link: when an ingredient is missing but can be made from what is in the zone, those crafts are
-- planned first (depth LinkDepth, never tools, never a loop).
if isServer() then return end

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "CookieHelper/CH_Scan"
require "CookieHelper/CH_UI"

CHelp.Craft = CHelp.Craft or {}
local Craft = CHelp.Craft
local Scan = CHelp.Scan
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

function Craft.icon(r)
    local ok, tex = pcall(function() return r:getIconTexture() end)
    if ok and tex then return tex end
    return nil
end

function Craft.category(r)
    local ok, c = pcall(function() return r:getCategory() end)
    if ok and c and c ~= "" then return getTextOrNull("IGUI_CraftCategory_" .. c) or c end
    return ""
end

-- how many of fullType one craft of r makes
function Craft.outPer(r, fullType)
    local outs = r:getOutputs()
    for i = 0, outs:size() - 1 do
        local o = outs:get(i)
        local ok, items = pcall(function() return o:getPossibleResultItems() end)
        if ok and items then
            for j = 0, items:size() - 1 do
                if not fullType or items:get(j):getFullName() == fullType then
                    local okA, a = pcall(function() return o:getIntAmount() end)
                    return math.max(1, (okA and a) or 1)
                end
            end
        end
    end
    return 1
end

-- first output item of r (for the icon / name of what it makes)
function Craft.mainOutput(r)
    local outs = r:getOutputs()
    for i = 0, outs:size() - 1 do
        local ok, items = pcall(function() return outs:get(i):getPossibleResultItems() end)
        if ok and items and items:size() > 0 then return items:get(0):getFullName() end
    end
    return nil
end

local searchKeys = nil
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

-- counts of everything the player could use: own inventory + zone boxes
function Craft.countWithBag(p, zoneMap)
    local inv = p and p:getInventory()
    if not inv then return zoneMap end
    local bag = Scan.count({ { c = inv, label = t("YourBag") } })
    return Scan.merge(zoneMap, bag)
end

function Craft.countAll(p, entries)
    local all = {}
    local inv = p and p:getInventory()
    if inv then all[#all + 1] = { c = inv, label = t("YourBag") } end
    for _, e in ipairs(entries or {}) do all[#all + 1] = e end
    return Scan.count(all)
end

-- every logic the mod builds picks inputs automatically: the vanilla "manual inputs" toggle is
-- copied into new logics and would make every recipe look empty
function Craft.makeLogic(p, bench, obj)
    local logic = HandcraftLogic.new(p, bench, obj)
    pcall(function() logic:setManualSelectInputs(false) end)
    return logic
end

-- setRecipe also stores the vanilla crafting window's "last recipe": keep the player's own choice
function Craft.setRecipe(logic, r)
    local okL, last = pcall(function() return logic:getLastSelectedRecipe() end)
    logic:setRecipe(r)
    if okL and last and last ~= r then pcall(function() logic:setLastSelectedRecipe(last) end) end
end

function Craft.isSurface(r)
    local ok, v = pcall(function() return r:isAnySurfaceCraft() end)
    return ok and v == true
end

function Craft.newLogic(p, containers, recipe, station)
    local logic = Craft.makeLogic(p, station and station.bench or nil, station and station.obj or nil)
    logic:setContainers(containers)
    if recipe then Craft.setRecipe(logic, recipe) end
    return logic
end

-- is r something this character may make, and where
-- st = { known, learned, skills, needsBench, station, can, max }
function Craft.statusOne(logic, r, p, stations, benchLogic)
    local st = { known = true, learned = true, skills = true, can = false, max = 0 }
    local ok = pcall(function()
        st.learned = (not r:needToBeLearn()) or r:hasPlayerLearned(p)
        st.skills = r:characterHasRequiredSkills(p)
        st.known = st.learned and st.skills
        st.needsBench = r:requiresSpecificWorkstation()
        local lg = logic
        if st.needsBench then
            st.station = Scan.benchFor(stations, r)
            if not st.station then return end
            lg = benchLogic and benchLogic(st.station) or nil
            if not lg then return end
        end
        Craft.setRecipe(lg, r)
        st.can = lg:canPerformCurrentRecipe()
        if not st.can and (st.needsBench or Craft.isSurface(r)) then
            -- only too far from the bench / table: we walk there, so the inputs decide
            st.can = lg:areAllInputItemsSatisfied() and st.known
        end
        if st.can then st.max = math.max(1, lg:getPossibleCraftCount(false)) end
    end)
    if not ok then st.can = false end
    if not st.known then st.can = false st.max = 0 end
    return st
end

-- ------------------------------------------------------------------ requirements of one recipe
-- returns rows { name, ft, tex, tool, need, have, ok, uses, boxes } for qty crafts
local function isItemInput(input)
    local ok, rt = pcall(function() return tostring(input:getResourceType()) end)
    return (not ok) or rt == "Item"
end

local function inputItems(input)
    local out = {}
    local ok, items = pcall(function() return input:getPossibleInputItems() end)
    if ok and items then
        for i = 0, items:size() - 1 do out[#out + 1] = items:get(i):getFullName() end
    end
    return out
end
Craft.inputItems = inputItems

local function isTool(input)
    local ok, v = pcall(function() return input:isKeep() or input:isTool() end)
    return ok and v == true
end

local function amount(input)
    local ok, v = pcall(function() return input:getIntAmount() end)
    return math.max(1, (ok and v) or 1)
end

local function countMode(input)
    local ok, v = pcall(function() return input:isItemCount() end)
    if ok and v then return true end
    -- uses-based inputs (gas, thread, glue) are judged by the game's own check
    local fts = inputItems(input)
    local si = fts[1] and getScriptManager():getItem(fts[1])
    if si then
        local okD, partial = pcall(function() return input:isUsesPartialItem(si) end)
        if okD and partial then return false end
    end
    return true
end

function Craft.requirements(r, qty, counts, logic)
    local rows = {}
    if logic then pcall(function() Craft.setRecipe(logic, r) end) end
    local ins = r:getInputs()
    for i = 0, ins:size() - 1 do
        local input = ins:get(i)
        if isItemInput(input) then
            local fts = inputItems(input)
            local tool = isTool(input)
            local cm = countMode(input)
            local need = tool and 1 or (amount(input) * qty)
            local have, boxes, firstHave = 0, {}, nil
            for _, ft in ipairs(fts) do
                local e = counts[ft]
                if e then
                    have = have + e.n
                    firstHave = firstHave or ft
                    for _, b in ipairs(e.boxes) do if #boxes < 3 then boxes[#boxes + 1] = b end end
                end
            end
            local ok1 = true
            if logic then
                local okS, sat = pcall(function() return logic:isInputSatisfied(input) end)
                if okS then ok1 = sat end
            end
            local ft0 = firstHave or fts[1]
            local row = {
                input = input, fts = fts, ft = ft0, name = ft0 and Scan.itemName(ft0) or "?", tex = ft0 and Scan.itemTex(ft0) or nil,
                tool = tool, uses = not cm, need = need, have = have, boxes = boxes,
            }
            if cm then row.ok = have >= need else row.ok = ok1 end
            if tool then row.ok = have >= 1 end
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- ------------------------------------------------------------------ Link planning
-- avail: ft -> n (mutated while reserving). Returns { ok, steps = { {recipe, qty} }, missing = { row } }
local function copyCounts(counts)
    local a = {}
    for ft, e in pairs(counts) do a[ft] = e.n end
    return a
end

local function recipeUsable(r, p, stations)
    local ok, res = pcall(function()
        if r:needToBeLearn() and not r:hasPlayerLearned(p) then return false end
        if not r:characterHasRequiredSkills(p) then return false end
        if r:requiresSpecificWorkstation() and not Scan.benchFor(stations, r) then return false end
        return true
    end)
    return ok and res == true
end

local function consumesAny(r, fts)
    if not fts then return false end
    local set = {}
    for _, ft in ipairs(fts) do set[ft] = true end
    local ins = r:getInputs()
    for i = 0, ins:size() - 1 do
        for _, ft in ipairs(inputItems(ins:get(i))) do
            if set[ft] then return true end
        end
    end
    return false
end

local function planInner(ctx, r, qty, depth, path)
    local steps, missing = {}, {}
    local ins = r:getInputs()
    local myOut = {}
    local outs = r:getOutputs()
    for i = 0, outs:size() - 1 do
        local okO, items = pcall(function() return outs:get(i):getPossibleResultItems() end)
        if okO and items then for j = 0, items:size() - 1 do myOut[#myOut + 1] = items:get(j):getFullName() end end
    end
    for i = 0, ins:size() - 1 do
        local input = ins:get(i)
        if isItemInput(input) and countMode(input) then
            local fts = inputItems(input)
            local tool = isTool(input)
            local need = tool and 1 or (amount(input) * qty)
            local have = 0
            for _, ft in ipairs(fts) do have = have + (ctx.avail[ft] or 0) end
            if have >= need then
                if not tool then
                    local left = need
                    for _, ft in ipairs(fts) do
                        local a = ctx.avail[ft] or 0
                        local take = math.min(a, left)
                        ctx.avail[ft] = a - take
                        left = left - take
                        if left <= 0 then break end
                    end
                end
            else
                local short = need - have
                if not tool then for _, ft in ipairs(fts) do ctx.avail[ft] = 0 end end
                local made = false
                if ctx.link and not tool and depth < ctx.maxDepth then
                    for _, ft in ipairs(fts) do
                        for _, cr in ipairs(Craft.recipesFor(ft)) do
                            if not path[cr] and not consumesAny(cr, myOut) and recipeUsable(cr, ctx.p, ctx.stations) then
                                local per = Craft.outPer(cr, ft)
                                local crafts = math.ceil(short / per)
                                local saved = {}
                                for k, v in pairs(ctx.avail) do saved[k] = v end
                                path[cr] = true
                                local sub = planInner(ctx, cr, crafts, depth + 1, path)
                                path[cr] = nil
                                if sub.ok then
                                    for _, s in ipairs(sub.steps) do steps[#steps + 1] = s end
                                    local extra = crafts * per - short
                                    if extra > 0 then ctx.avail[ft] = (ctx.avail[ft] or 0) + extra end
                                    made = true
                                    break
                                else
                                    ctx.avail = saved
                                end
                            end
                        end
                        if made then break end
                    end
                end
                if not made then
                    missing[#missing + 1] = { input = input, fts = fts, short = short, tool = tool,
                        name = fts[1] and Scan.itemName(fts[1]) or "?" }
                end
            end
        end
    end
    steps[#steps + 1] = { recipe = r, qty = qty }
    return { ok = #missing == 0, steps = steps, missing = missing }
end

-- ctx = { p, counts, stations, link }
function Craft.plan(ctx, r, qty)
    local c = { p = ctx.p, avail = copyCounts(ctx.counts or {}), stations = ctx.stations, link = ctx.link == true,
        maxDepth = CHelp.svInt("LinkDepth", 0, 4) }
    local path = {}
    path[r] = true
    return planInner(c, r, math.max(1, qty), 0, path)
end

-- the biggest qty (<= upTo) the plan can do
function Craft.maxPlan(ctx, r, upTo)
    local lo, hi = 0, math.max(0, upTo)
    while lo < hi do
        local mid = floor((lo + hi + 1) / 2)
        if Craft.plan(ctx, r, mid).ok then lo = mid else hi = mid - 1 end
    end
    return lo
end

-- ------------------------------------------------------------------ walking helpers
local function isWeldingMask(it)
    return string.find(it:getFullType(), "WeldingMask", 1, true) ~= nil
end

-- square of a world container (getSquare, else the source grid, else the object holding it)
function Craft.containerSquare(c)
    if not c then return nil end
    local ok, sq = pcall(function() return c:getSquare() end)
    if ok and sq then return sq end
    ok, sq = pcall(function() return c:getSourceGrid() end)
    if ok and sq then return sq end
    ok, sq = pcall(function() local par = c:getParent() return par and par:getSquare() end)
    if ok and sq then return sq end
    return nil
end

-- where to stand for a box: nil,true = no walk needed (floor / carried), sq = walk next to it
local function boxSquare(c)
    local okT, ty = pcall(function() return c:getType() end)
    if okT and ty == "floor" then return nil, true end
    local sq = Craft.containerSquare(c)
    if not sq then
        local okO, outer = pcall(function() return c:getOutermostContainer() end)
        if okO and outer and outer ~= c then sq = Craft.containerSquare(outer) end
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
Craft.standFor = standFor

-- ------------------------------------------------------------------ the job
-- job = { p, recipe, left, entriesFn, stationsFn, returns, refilled, onDone, onFail, onProgress }
-- items are tracked by ID: in MP the server moves them and the client gets new objects.
function Craft.start(p, recipe, qty, entriesFn, opts)
    if not p or not recipe then return end
    if ISTimedActionQueue.isPlayerDoingAction(p) and not (opts and opts.force) then
        UI.toast(t("Msg_Busy"), false)
        if opts and opts.onFail then opts.onFail("Msg_Busy") end
        return
    end
    opts = opts or {}
    local job = { p = p, recipe = recipe, left = math.max(1, floor(qty or 1)), total = math.max(1, floor(qty or 1)),
        entriesFn = entriesFn, stationsFn = opts.stationsFn, returns = {}, refilled = false,
        onDone = opts.onDone, onFail = opts.onFail, onProgress = opts.onProgress, quiet = opts.quiet,
        stopCheck = opts.stopCheck, onStopped = opts.onStopped }
    Craft.step(job)
    return job
end

local function fail(job, key)
    if job.dead then return end
    if not job.quiet then UI.toast(t(key, Craft.label(job.recipe)), false) end
    Craft.returnTools(job)
    if job.onFail then
        local cb = job.onFail
        job.onFail = nil
        pcall(cb, key)
    end
end

local function stationsOf(job)
    if not job.stationsFn then return nil end
    local ok, s = pcall(job.stationsFn)
    return ok and s or nil
end

function Craft.step(job)
    local p = job.p
    if job.dead or job.left <= 0 then return end
    local entries = job.entriesFn and job.entriesFn() or {}
    local cont = Craft.planContainers(p, entries)
    local stations = stationsOf(job)
    local station = nil
    local okB, needsBench = pcall(function() return job.recipe:requiresSpecificWorkstation() end)
    if okB and needsBench then
        station = Scan.benchFor(stations, job.recipe)
        if not station then return fail(job, "Msg_NoStation") end
    end
    job.station = station
    if not station and Craft.isSurface(job.recipe) and not Scan.surfaceNear(stations, p:getX(), p:getY()) then
        -- no table in the zone: only go on if there is one right here (checked before taking anything)
        local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
        if not (okF and f) then return fail(job, "Msg_NoSurface") end
    end
    local logic = Craft.newLogic(p, cont, job.recipe, station)
    local okCan, can = pcall(function()
        return logic:canPerformCurrentRecipe() or ((station ~= nil or Craft.isSurface(job.recipe)) and logic:areAllInputItemsSatisfied())
    end)
    if not (okCan and can) then
        if not job.refilled and usesBlowTorch(job.recipe) then
            job.refilled = true
            local rr = refillRecipe()
            if rr then
                local rl = Craft.newLogic(p, cont, rr)
                local okR, canR = pcall(function() return rl:canPerformCurrentRecipe() end)
                if okR and canR then
                    if not job.quiet then UI.toast(t("Msg_Refill"), true) end
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

    ISTimedActionQueue.queueActions(p, Craft.deferredCraft, { job = job, recipe = recipe, refill = isRefill, wear = wearIds,
        station = (not isRefill) and job.station or nil })
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
    -- a bench recipe: walk next to it first, the craft is queued after the walk
    if ctx.station and not ctx.walked then
        ctx.walked = true
        local okW = pcall(function() ISEntityUI.WalkToEntity(p, ctx.station.obj, 1) end)
        if okW then
            ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
            return
        end
    end
    local logic = Craft.makeLogic(p, ctx.station and ctx.station.bench or nil, ctx.station and ctx.station.obj or nil)
    local surface = (not ctx.station) and Craft.isSurface(ctx.recipe)
    if surface then
        -- surface recipes: the nearest table in the zone, else whatever is next to us.
        -- HandcraftStartMultiple walks to it; the game only allows the craft within 3 tiles of it.
        local st = stationsOf(ctx.job)
        local s = Scan.surfaceNear(st, p:getX(), p:getY())
        local surf = s and s.obj or nil
        if not surf then
            local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
            if okF then surf = f end
        end
        if not surf then return fail(ctx.job, "Msg_NoSurface") end
        logic:setIsoObject(surf)
    end
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    Craft.setRecipe(logic, ctx.recipe)
    local okCan, can = pcall(function()
        if surface then return logic:areAllInputItemsSatisfied() end
        return logic:canPerformCurrentRecipe() or (ctx.station ~= nil and logic:areAllInputItemsSatisfied())
    end)
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
    if ctx.job.dead then return end
    local ok, err = pcall(deferredCraftInner, p, ctx)
    if not ok then
        CHelp.log("deferred craft failed: " .. tostring(err))
        fail(ctx.job, "Msg_CantCraft")
    end
end

function Craft.afterCraft(p, ctx)
    local job = ctx.job
    if job.dead then return end
    local ok, err = pcall(function()
        if ctx.refill then
            Craft.step(job)          -- torch is full again, try the real recipe
            return
        end
        job.left = job.left - 1
        job.refilled = false
        if job.onProgress then pcall(job.onProgress, job.total - job.left, job.total) end
        if job.left > 0 then
            if job.stopCheck and job.stopCheck() then
                Craft.returnTools(job)
                if job.onStopped then
                    local cb = job.onStopped
                    job.onStopped = nil
                    pcall(cb, job.total - job.left)
                end
                return
            end
            Craft.step(job)
        else
            Craft.returnTools(job)
            if not job.quiet then UI.toast(t("Msg_CraftDone", Craft.label(job.recipe)), true) end
            if job.onDone then
                local cb = job.onDone
                job.onDone = nil
                pcall(cb)
            end
        end
    end)
    if not ok then
        CHelp.log("after craft failed: " .. tostring(err))
        fail(job, "Msg_CantCraft")
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
