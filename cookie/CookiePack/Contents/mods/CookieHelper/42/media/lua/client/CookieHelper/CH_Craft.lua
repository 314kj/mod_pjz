-- Cookie Helper : craft-from-zone engine
-- Same flow as vanilla crafting, plus walking:
--   plan with zone containers -> walk to each box -> take what the recipe picked -> (wear mask)
--   -> walk to the workstation / table if the recipe needs one -> craft -> put tools back -> next.
-- Every craft re-plans from the real world state, so moved/used items never break a queue.
-- Link: when an ingredient is missing but can be made from what is in the zone, those crafts are
-- planned first (depth LinkDepth, never tools, never a loop).
if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "CookieHelper/CH_Scan"
require "CookieHelper/CH_UI"
require "CookieHelper/CH_Inputs"

CHelp.Craft = CHelp.Craft or {}
local Craft = CHelp.Craft
local Scan = CHelp.Scan
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

-- ------------------------------------------------------------------ console trace of craft jobs
-- One line per step of a craft (plan, loads, pile, craft, stash, stop) so a report with console.txt
-- shows exactly where a run stopped. Craft.active = the job running right now.
Craft.active = nil
function Craft.trace(job, msg)
    if not job then return end
    pcall(function()
        local p = job.p
        CHelp.log(string.format("craft %s %d/%d: %s @%d,%d,%d", job.recipe and job.recipe:getName() or "?",
            math.min(job.total or 0, (job.total or 0) - (job.left or 0) + 1), job.total or 0, tostring(msg),
            floor(p:getX()), floor(p:getY()), floor(p:getZ())))
    end)
end

-- the game wipes the whole action queue when an action is refused (a transfer the server turns
-- down, a walk with no path, a step that added nothing). Note which action it was.
if ISTimedActionQueue and ISTimedActionQueue.resetQueue and not CHelp._craftResetHook then
    CHelp._craftResetHook = true
    local origReset = ISTimedActionQueue.resetQueue
    ISTimedActionQueue.resetQueue = function(self, ...)
        local job = Craft.active
        if job and not job.dead and self and self.character == job.p then
            pcall(function()
                local cur = self.queue and self.queue[1]
                local what = cur and tostring(cur.Type or "?") or "none"
                if cur and cur.item and cur.item.getFullType then what = what .. " " .. cur.item:getFullType() end
                job.lastReset = what
                Craft.trace(job, "action queue reset at " .. what)
            end)
        end
        return origReset(self, ...)
    end
end

-- waits (at most limit ms) until cond() is true. In MP the server makes the craft and sends the
-- result a moment later: the next plan must see the real bag, not the one from before the craft.
if ISBaseTimedAction and not CHelp.SyncWait then
    CHelp.SyncWait = ISBaseTimedAction:derive("CHelpSyncWait")
    local SW = CHelp.SyncWait
    function SW:isValid() return true end
    function SW:waitToStart() return false end
    function SW:start() self.t0 = CHelp.nowMs() end
    function SW:update()
        local ok, done = pcall(self.cond)
        if (ok and done) or CHelp.nowMs() - (self.t0 or 0) > self.limit then self:forceComplete() end
    end
    function SW:stop() ISBaseTimedAction.stop(self) end
    function SW:perform() ISBaseTimedAction.perform(self) end
    function SW:new(p, cond, limit)
        local o = ISBaseTimedAction.new(self, p)
        o.cond, o.limit = cond, limit or 2000
        o.stopOnWalk, o.stopOnRun, o.stopOnAim = false, false, false
        o.maxTime = -1
        return o
    end
end

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

-- everything a plan may use: the bag, the floor right around the character (what a craft just
-- put down), the zone boxes and a pile left by an interrupted run (the craft goes back for it)
function Craft.countAll(p, entries)
    local all = {}
    local inv = p and p:getInventory()
    if inv then all[#all + 1] = { c = inv, label = t("YourBag") } end
    pcall(function()
        local pc = ISInventoryPaneContextMenu.getContainers(p)
        for i = 0, pc:size() - 1 do
            local c = pc:get(i)
            if c:getType() == "floor" then all[#all + 1] = { c = c, label = t("FloorHere") } end
        end
    end)
    for _, e in ipairs(entries or {}) do all[#all + 1] = e end
    all.floor = entries and entries.floor or nil
    local counts = Scan.count(all)
    local pl = Craft.pile
    if pl and pl.fts and not Craft.nearSq(p, getCell():getGridSquare(pl.x, pl.y, pl.z), 1.6) then
        local pileMap = {}
        for ft, n in pairs(pl.fts) do
            pileMap[ft] = { ft = ft, n = n, name = Scan.itemName(ft), tex = Scan.itemTex(ft), cat = "", boxes = { t("PileLabel") }, boxSeen = {} }
        end
        counts = Scan.merge(counts, pileMap)
    end
    return counts
end

-- every logic the mod builds runs in the same mode as the game's crafting window: "manual inputs"
-- on, filled automatically by setContainers/setRecipe. ISHandcraftAction only builds its input
-- table in that mode (with it off, 42.21 passes false to convertToPZNetTable and the craft dies).
function Craft.makeLogic(p, bench, obj)
    local logic = HandcraftLogic.new(p, bench, obj)
    pcall(function() logic:setManualSelectInputs(true) end)
    return logic
end

-- setRecipe also stores the vanilla crafting window's "last recipe": keep the player's own choice
-- the player's item choices (CH_Inputs) are applied right after, so every check and craft uses them
function Craft.setRecipe(logic, r)
    local okL, last = pcall(function() return logic:getLastSelectedRecipe() end)
    logic:setRecipe(r)
    if okL and last and last ~= r then pcall(function() logic:setLastSelectedRecipe(last) end) end
    CHelp.Inputs.apply(logic, r)
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

-- the recipe needs light and it is too dark where the character stands
function Craft.tooDark(r, p)
    local ok, v = pcall(function() return (not r:canBeDoneInDark()) and p:tooDarkToRead() end)
    return ok and v == true
end

-- every input except the blowtorch is there and a torch can be refilled from a propane tank
local function refillCovers(lg, r, p)
    if not usesBlowTorch(r) then return false end
    local rr = refillRecipe()
    if not rr then return false end
    local okA, rest = pcall(function()
        local ins = r:getInputs()
        for i = 0, ins:size() - 1 do
            local input = ins:get(i)
            local torch = false
            for _, ft in ipairs(Craft.inputItems(input)) do if ft == "Base.BlowTorch" then torch = true end end
            if not torch and not lg:isInputSatisfied(input) then return false end
        end
        return true
    end)
    if not (okA and rest) then return false end
    local rl = Craft.makeLogic(p, nil, nil)
    local okC, cont = pcall(function() return lg:getContainers() end)
    if not (okC and cont) then return false end
    rl:setContainers(cont)
    Craft.setRecipe(rl, rr)
    local okR, canR = pcall(function() return rl:canPerformCurrentRecipe() end)
    return okR and canR == true
end
Craft.refillCovers = refillCovers

-- the blowtorch input of r is not satisfied (not enough gas)
function Craft.torchShort(lg, r)
    local ok, short = pcall(function()
        local ins = r:getInputs()
        for i = 0, ins:size() - 1 do
            local input = ins:get(i)
            for _, ft in ipairs(Craft.inputItems(input)) do
                if ft == "Base.BlowTorch" and not lg:isInputSatisfied(input) then return true end
            end
        end
        return false
    end)
    return ok and short == true
end

-- is r something this character may make, and where
-- st = { known, learned, skills, needsBench, station, can, max, refill, dark, noTable }
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
        st.dark = Craft.tooDark(r, p)
        if (not st.needsBench) and Craft.isSurface(r) and stations and #(stations.surfaces or {}) == 0 then
            local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
            st.noTable = not (okF and f)
        end
        st.can = lg:canPerformCurrentRecipe()
        if not st.can and (st.needsBench or Craft.isSurface(r) or st.dark) then
            -- only too far from the bench / table (we walk there) or dark here: the inputs decide
            st.can = lg:areAllInputItemsSatisfied() and st.known
        end
        if st.can then st.max = math.max(1, lg:getPossibleCraftCount(false)) end
        if not st.can and st.known and refillCovers(lg, r, p) then
            st.can, st.refill, st.max = true, true, 1
        end
        if st.noTable then st.can = false end
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
Craft.inputAmount = amount

-- how many of this item one craft needs. "item 2 [Base.Log;3:Base.LargeBranch;6:Base.Plank]" gives
-- each item its own amount (2 / 3 / 6) and the game then reports 1 for the input as a whole.
-- getAmount(name) is 1.0 for items that are not listed by name (tag inputs): use the input's amount.
local function amountFor(input, ft)
    local base = amount(input)
    if not ft then return base end
    local ok, a = pcall(function() return input:getAmount(ft) end)
    if ok and type(a) == "number" and a > 0 and math.abs(a - 1) > 0.001 then
        return math.max(1, math.ceil(a - 0.001))
    end
    return base
end
Craft.inputAmountFor = amountFor

-- IsExclusive: every item of one craft must be the same kind
local function isExclusive(input)
    local ok, v = pcall(function() return input:isExclusive() end)
    return ok and v == true
end
Craft.inputExclusive = isExclusive

-- crafts' worth of an input: n(ft) items of each kind, each kind with its own amount
local function unitsOf(input, fts, nOf)
    local excl = isExclusive(input)
    local units = 0
    for _, ft in ipairs(fts) do
        local n = nOf(ft)
        if n > 0 then
            local a = amountFor(input, ft)
            if excl then units = units + floor(n / a) else units = units + n / a end
        end
    end
    return units
end
Craft.inputUnits = unitsOf

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
Craft.inputCountMode = countMode

function Craft.requirements(r, qty, counts, logic)
    local rows = {}
    if logic then pcall(function() Craft.setRecipe(logic, r) end) end
    local ins = r:getInputs()
    for i = 0, ins:size() - 1 do
        local input = ins:get(i)
        if isItemInput(input) then
            local allFts = inputItems(input)
            local fts = CHelp.Inputs.allowed(r, i, allFts)
            local tool = isTool(input)
            local cm = countMode(input)
            local need = tool and 1 or (amount(input) * qty)
            local have, boxes, firstHave = 0, {}, nil
            -- kinds with their own amounts (logs 2 / branches 3 / planks 6): show the first kind
            -- that covers a craft, with its own amount
            local mixed = false
            for _, ft in ipairs(fts) do if amountFor(input, ft) ~= amountFor(input, fts[1]) then mixed = true break end end
            local showFt = nil
            for _, ft in ipairs(fts) do
                local e = counts[ft]
                if e then
                    have = have + e.n
                    firstHave = firstHave or ft
                    if not showFt and e.n >= amountFor(input, ft) then showFt = ft end
                    for _, b in ipairs(e.boxes) do if #boxes < 3 then boxes[#boxes + 1] = b end end
                end
            end
            local units = unitsOf(input, fts, function(ft) return counts[ft] and counts[ft].n or 0 end)
            if not tool then
                local f = showFt or firstHave or fts[1]
                if mixed then
                    need = amountFor(input, f) * qty
                    have = counts[f] and counts[f].n or 0
                    firstHave = f
                else
                    need = amountFor(input, f) * qty
                end
            end
            local ok1 = true
            if logic then
                local okS, sat = pcall(function() return logic:isInputSatisfied(input) end)
                if okS then ok1 = sat end
            end
            local ft0 = (not tool and showFt) or firstHave or fts[1]
            local row = {
                input = input, fts = fts, ft = ft0, name = ft0 and Scan.itemName(ft0) or "?", tex = ft0 and Scan.itemTex(ft0) or nil,
                tool = tool, uses = not cm, need = need, have = have, boxes = boxes,
                idx = i, allFts = allFts, custom = CHelp.Inputs.isCustom(r, i, allFts),
            }
            if cm then row.ok = units >= qty - 0.0001 else row.ok = ok1 end
            if tool then row.ok = have >= 1 end
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- ------------------------------------------------------------------ why a recipe cannot be done
local function fmtKg(w) return string.format("%.1f", w or 0) end
Craft.fmtKg = fmtKg

function Craft.stationTags(r)
    local parts = {}
    pcall(function()
        local tags = r:getTags()
        for i = 0, tags:size() - 1 do
            local tg = tostring(tags:get(i))
            parts[#parts + 1] = getTextOrNull("IGUI_CH_Station_" .. tg) or tg
        end
    end)
    return table.concat(parts, "/")
end

-- short plain lines, most important first. opts = { logic (recipe + containers set), counts, qty,
-- station, noTable, dark }
function Craft.whyNot(r, p, opts)
    opts = opts or {}
    local out = {}
    local function add(s) if s and s ~= "" then out[#out + 1] = s end end
    pcall(function()
        if r:needToBeLearn() and not r:hasPlayerLearned(p) then add(t("Why_NotLearned")) end
    end)
    pcall(function()
        for i = 0, r:getRequiredSkillCount() - 1 do
            local rs = r:getRequiredSkill(i)
            local have = p:getPerkLevel(rs:getPerk())
            if have < rs:getLevel() then add(t("Why_Skill", rs:getPerk():getName(), rs:getLevel(), have)) end
        end
    end)
    local okB, needsBench = pcall(function() return r:requiresSpecificWorkstation() end)
    if okB and needsBench and not opts.station then add(t("Why_NoStation", Craft.stationTags(r))) end
    if opts.noTable then add(t("Why_NoTable")) end
    if opts.dark then add(t("Why_Dark")) end
    local counts = opts.counts
    if not counts and opts.logic then
        pcall(function()
            local cs = opts.logic:getContainers()
            local list = {}
            for i = 0, cs:size() - 1 do list[#list + 1] = { c = cs:get(i) } end
            counts = Scan.count(list)
        end)
    end
    local okR, rows = pcall(Craft.requirements, r, opts.qty or 1, counts or {}, opts.logic)
    if okR and rows then
        for _, rq in ipairs(rows) do
            if not rq.ok and not rq.refill then
                if rq.uses then add(t("Why_Uses", rq.name))
                elseif rq.tool then add(t("Why_Tool", rq.name))
                else add(t("Why_Short", rq.name, math.max(1, rq.need - rq.have), rq.have, rq.need)) end
            end
        end
    end
    if #out == 0 and opts.logic then
        -- the counts look fine but the game still says no: name the inputs it does not accept
        pcall(function()
            local ins = r:getInputs()
            for i = 0, ins:size() - 1 do
                local input = ins:get(i)
                if not opts.logic:isInputSatisfied(input) then
                    local fts = isItemInput(input) and CHelp.Inputs.allowed(r, i, inputItems(input)) or {}
                    local nm = fts[1] and Scan.itemName(fts[1]) or tostring(i + 1)
                    add(t("Why_Input", nm))
                    CHelp.log("why " .. r:getName() .. ": input " .. (i + 1) .. " (" .. table.concat(fts, ",") .. ") not satisfied, needs " ..
                        tostring(fts[1] and amountFor(input, fts[1]) or amount(input)))
                end
            end
        end)
    end
    if #out == 0 then add(t("Why_GameSaysNo")) end
    return out
end

function Craft.whyText(list, maxN)
    if not list or #list == 0 then return nil end
    local n = math.min(#list, maxN or 3)
    local parts = {}
    for i = 1, n do parts[i] = list[i] end
    local s = table.concat(parts, ", ")
    if #list > n then s = s .. " " .. t("Why_More", #list - n) end
    return s
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
            local fts = CHelp.Inputs.allowed(r, i, inputItems(input))
            local tool = isTool(input)
            local have = 0
            for _, ft in ipairs(fts) do have = have + (ctx.avail[ft] or 0) end
            local units = tool and have or unitsOf(input, fts, function(ft) return ctx.avail[ft] or 0 end)
            if units >= qty - 0.0001 or (tool and have >= 1) then
                if not tool then
                    -- reserve crafts' worth, kind by kind (each kind with its own amount)
                    local excl = isExclusive(input)
                    local leftC = qty
                    for _, ft in ipairs(fts) do
                        local a = ctx.avail[ft] or 0
                        local amt = amountFor(input, ft)
                        local canC = excl and floor(a / amt) or (a / amt)
                        local takeC = math.min(canC, leftC)
                        if takeC > 0 then
                            ctx.avail[ft] = a - math.min(a, math.ceil(takeC * amt - 0.0001))
                            leftC = leftC - takeC
                        end
                        if leftC <= 0.0001 then break end
                    end
                end
            else
                -- shortfall named by the kind closest to enough (each kind with its own amount)
                local short = tool and 1 or math.max(1, math.ceil((qty - units) * amountFor(input, fts[1]) - 0.0001))
                local shortFt = fts[1]
                if not tool and #fts > 1 then
                    for _, ft in ipairs(fts) do
                        local sft = math.ceil(qty * amountFor(input, ft) - 0.0001) - (ctx.avail[ft] or 0)
                        if sft > 0 and sft < short then short, shortFt = sft, ft end
                    end
                end
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
                        name = shortFt and Scan.itemName(shortFt) or "?" }
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

local function standable(sq)
    if not sq then return false end
    local ok, res = pcall(function()
        if not sq:TreatAsSolidFloor() then return false end
        if sq:isSolid() or sq:isSolidTrans() then return false end
        return true
    end)
    return ok and res == true
end

-- the character is (about) on / next to sq
function Craft.nearSq(p, sq, dist)
    if not sq then return false end
    dist = dist or 1.6
    if floor(p:getZ()) ~= sq:getZ() then return false end
    return math.abs(sq:getX() + 0.5 - p:getX()) <= dist and math.abs(sq:getY() + 0.5 - p:getY()) <= dist
end

-- a free tile touching sq with no wall in between. The game's finder first (it also skips tiles
-- by windows and low fences); when it finds none, any standable neighbour that reaches sq. The
-- nearest one wins - the walk itself finds the way round through other rooms.
function Craft.adjacentStand(p, sq)
    if not sq then return nil end
    local okA, adj = pcall(function() return AdjacentFreeTileFinder.Find(sq, p) end)
    if okA and adj then return adj end
    local best, bd = nil, nil
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nb = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                if standable(nb) then
                    local okR, reach = pcall(function() return nb:canReachTo(sq) end)
                    if okR and reach then
                        local ddx, ddy = nb:getX() + 0.5 - p:getX(), nb:getY() + 0.5 - p:getY()
                        local d = ddx * ddx + ddy * ddy
                        if not bd or d < bd then best, bd = nb, d end
                    end
                end
            end
        end
    end
    return best
end

-- adjacent free tile for a box, or false when it cannot be reached
local function standFor(p, c)
    local sq, noWalk = boxSquare(c)
    if noWalk then return nil end
    if not sq then return false end
    local adj = Craft.adjacentStand(p, sq)
    if not adj then return false end
    return adj
end
Craft.standFor = standFor

-- weight the character can still pick up before the heavy-load moodle
function Craft.carryRoom(p)
    local ok, v = pcall(function() return p:getMaxWeight() - p:getInventoryWeight() end)
    if not ok or not v then return 1000 end
    return math.max(0.5, v)
end

-- weight that still fits in the main inventory at all
function Craft.freeCapacity(p)
    local inv = p:getInventory()
    local ok, v = pcall(function() return inv:getEffectiveCapacity(p) - inv:getCapacityWeight() end)
    if ok and type(v) == "number" then return v end
    return 1000
end

function Craft.overloaded(p)
    local ok, v = pcall(function() return p:getInventoryWeight() > p:getMaxWeight() end)
    return ok and v == true
end

-- ------------------------------------------------------------------ the job
-- job = { p, recipe, left, entriesFn, stationsFn, returns, refilled, onDone, onFail, onProgress }
-- items are tracked by ID: in MP the server moves them and the client gets new objects.
-- opts.keepTools: borrowed tools stay in the bag (opts.returns collects them) - the queue gives
-- them back once it runs dry, so a loop does not walk every tool back and forth.

-- loads that were put down for a craft that then got interrupted: { x, y, z, ids }
Craft.pile = nil

local function outTypes(r)
    local set = {}
    pcall(function()
        local outs = r:getOutputs()
        for i = 0, outs:size() - 1 do
            local items = outs:get(i):getPossibleResultItems()
            for j = 0, items:size() - 1 do set[items:get(j):getFullName()] = true end
        end
    end)
    return set
end

function Craft.start(p, recipe, qty, entriesFn, opts)
    if not p or not recipe then return end
    if ISTimedActionQueue.isPlayerDoingAction(p) and not (opts and opts.force) then
        UI.toast(t("Msg_Busy"), false)
        if opts and opts.onFail then opts.onFail("Msg_Busy") end
        return
    end
    opts = opts or {}
    local start = {}
    pcall(function()
        local items = p:getInventory():getItems()
        for i = 0, items:size() - 1 do start[items:get(i):getID()] = true end
    end)
    local job = { p = p, recipe = recipe, left = math.max(1, floor(qty or 1)), total = math.max(1, floor(qty or 1)),
        entriesFn = entriesFn, stationsFn = opts.stationsFn, returns = opts.returns or {}, refilled = false,
        keepTools = opts.keepTools == true, startIds = start, outTypes = outTypes(recipe),
        onDone = opts.onDone, onFail = opts.onFail, onProgress = opts.onProgress, quiet = opts.quiet,
        stopCheck = opts.stopCheck, onStopped = opts.onStopped }
    Craft.active = job
    Craft.trace(job, "start x" .. job.total)
    Craft.step(job)
    return job
end

-- detail: what exactly is missing / in the way (shown after the message, kept in the queue card)
local function fail(job, key, detail)
    if job.dead then return end
    Craft.releaseBench(job.p, job.benchObj)
    job.benchObj = nil
    if detail == "" then detail = nil end
    Craft.trace(job, "STOP " .. tostring(key) .. (detail and (" | " .. detail) or "") .. (job.lastReset and (" | last queue reset at " .. job.lastReset) or ""))
    local msg = t(key, Craft.label(job.recipe))
    if detail then msg = msg .. " · " .. detail end
    if not job.quiet then UI.toast(msg, false) end
    Craft.returnTools(job)
    if Craft.active == job then Craft.active = nil end
    if job.onFail then
        local cb = job.onFail
        job.onFail = nil
        pcall(cb, key, detail)
    end
end
Craft.fail = fail

local function stationsOf(job)
    if not job.stationsFn then return nil end
    local ok, s = pcall(job.stationsFn)
    return ok and s or nil
end

-- queue taking the pile's items (still on the floor around us) into the bag, as far as they fit.
-- The pile is only forgotten once Craft.prunePile (queued after) sees nothing of it left here.
local function queuePileTake(p, ids)
    pcall(function() getPlayerLoot(p:getPlayerNum()):refreshBackpacks() end)
    local floorC = ISInventoryPage.GetFloorContainer(p:getPlayerNum())
    local inv = p:getInventory()
    local free = Craft.freeCapacity(p)
    local added = false
    for _, id in ipairs(ids or {}) do
        local it = floorC:getItemWithID(id)
        if it and it:getUnequippedWeight() <= free then
            free = free - it:getUnequippedWeight()
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, floorC, inv))
            added = true
        end
    end
    return added
end

-- keep only what of the pile still lies here (an interrupted pick-up keeps the rest remembered)
function Craft.prunePile(p)
    local pl = Craft.pile
    if not pl then return end
    if not Craft.nearSq(p, getCell():getGridSquare(pl.x, pl.y, pl.z), 1.6) then return end
    pcall(function()
        getPlayerLoot(p:getPlayerNum()):refreshBackpacks()
        local floorC = ISInventoryPage.GetFloorContainer(p:getPlayerNum())
        local ids, fts = {}, {}
        for _, id in ipairs(pl.ids or {}) do
            local it = floorC:getItemWithID(id)
            if it then
                ids[#ids + 1] = id
                fts[it:getFullType()] = (fts[it:getFullType()] or 0) + 1
            end
        end
        if #ids == 0 then Craft.pile = nil else pl.ids, pl.fts = ids, fts end
    end)
end

-- go back to an interrupted pile and pick it up before planning again
function Craft.pickPile(p, job)
    if job.dead then return end
    local ok, err = pcall(function()
        if Craft.pile then queuePileTake(p, Craft.pile.ids) end
        ISTimedActionQueue.queueActions(p, Craft.pileThenStep, job)
    end)
    if not ok then
        CHelp.log("pick pile failed: " .. tostring(err))
        fail(job, "Msg_CantCraft", t("Why_Error"))
    end
end

function Craft.pileThenStep(p, job)
    if job.dead then return end
    Craft.prunePile(p)
    Craft.queuedStep(p, job)
end

function Craft.queuedStep(p, job)
    if job.dead then return end
    local ok, err = pcall(Craft.step, job)
    if not ok then
        CHelp.log("craft step failed: " .. tostring(err))
        fail(job, "Msg_CantCraft", t("Why_Error"))
    end
end

function Craft.step(job)
    local p = job.p
    if job.dead or job.left <= 0 then return end
    -- an earlier, interrupted run left loads on the floor: fetch them first
    if Craft.pile and not job.pileTried then
        job.pileTried = true
        local pl = Craft.pile
        local sq = getCell():getGridSquare(pl.x, pl.y, pl.z)
        -- a pile from some other workshop far away is not this job's business (it stays remembered)
        local far = sq and (pl.z ~= floor(p:getZ()) or math.abs(pl.x - p:getX()) > 40 or math.abs(pl.y - p:getY()) > 40)
        if sq and not far then
            if not Craft.nearSq(p, sq, 0.6) then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, sq)) end
            ISTimedActionQueue.queueActions(p, Craft.pickPile, job)
            return
        end
        if not sq then Craft.pile = nil end
    end
    local entries = job.entriesFn and job.entriesFn() or {}
    local cont = Craft.planContainers(p, entries)
    local stations = stationsOf(job)
    local station = nil
    local okB, needsBench = pcall(function() return job.recipe:requiresSpecificWorkstation() end)
    if okB and needsBench then
        station = Scan.benchFor(stations, job.recipe)
        if not station then return fail(job, "Msg_NoStation", t("Why_NoStation", Craft.stationTags(job.recipe))) end
    end
    job.station = station
    if not station and Craft.isSurface(job.recipe) and not Scan.surfaceNear(stations, p:getX(), p:getY()) then
        -- no table in the zone: only go on if there is one right here (checked before taking anything)
        local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
        if not (okF and f) then return fail(job, "Msg_NoSurface") end
    end
    local logic = Craft.newLogic(p, cont, job.recipe, station)
    local dark = Craft.tooDark(job.recipe, p)
    local okCan, can = pcall(function()
        return logic:canPerformCurrentRecipe() or ((station ~= nil or Craft.isSurface(job.recipe) or dark) and logic:areAllInputItemsSatisfied())
    end)
    if not (okCan and can) and Craft.gatherFloor(job, logic, entries) then return end
    if not (okCan and can) then
        -- refill only when the torch is the one thing missing and a propane tank can fill it
        if not job.refilled and refillCovers(logic, job.recipe, p) then
            job.refilled = true
            local rr = refillRecipe()
            local rl = Craft.newLogic(p, cont, rr)
            UI.toast(t("Msg_Refill"), true)
            Craft.fetchAndCraft(job, rl, rr, true)
            return
        end
        if job.refilled and Craft.torchShort(logic, job.recipe) then return fail(job, "Msg_TorchEmpty") end
        if dark then return fail(job, "Msg_TooDark") end
        local why = Craft.whyNot(job.recipe, p, { logic = logic, station = station, counts = Craft.countAll(p, entries) })
        if #why == 0 then
            -- the zone count has it, the boxes in reach do not: it lies somewhere nobody can get to
            why = Craft.whyNot(job.recipe, p, { logic = logic, station = station })
        end
        return fail(job, "Msg_CantCraft", Craft.whyText(why))
    end
    Craft.trace(job, "plan ok" .. (station and (" at " .. tostring(station.name)) or ""))
    Craft.fetchAndCraft(job, logic, job.recipe, false)
end

-- ------------------------------------------------------------------ things lying on the zone floor
-- The craft logic only sees boxes (and the floor right around the character). What the recipe still
-- needs and only lies on the floor somewhere in the zone is picked up first, then the step plans again.
local function floorStand(p, sq)
    local okR, reach = pcall(function() return p:getCurrentSquare():canReachTo(sq) end)
    if Craft.nearSq(p, sq, 1.2) and (p:getCurrentSquare() == sq or (okR and reach)) then return nil end
    if standable(sq) then return sq end
    return Craft.adjacentStand(p, sq) or false
end

function Craft.gatherFloor(job, logic, entries)
    local fl = entries and entries.floor
    if not fl or #fl == 0 or (job.floorTries or 0) >= 3 then return false end
    local p, r = job.p, job.recipe
    -- what is short, by input
    local inReach = {}
    pcall(function()
        local cs = logic:getContainers()
        local list = {}
        for i = 0, cs:size() - 1 do list[#list + 1] = { c = cs:get(i) } end
        inReach = Scan.count(list)
    end)
    local onFloor = {}
    for _, f in ipairs(fl) do
        for _, it in ipairs(f.items) do
            local ft = it:getFullType()
            onFloor[ft] = (onFloor[ft] or 0) + 1
        end
    end
    local wants = {}
    local okW = pcall(function()
        local ins = r:getInputs()
        for i = 0, ins:size() - 1 do
            local input = ins:get(i)
            if isItemInput(input) and not logic:isInputSatisfied(input) then
                local fts = CHelp.Inputs.allowed(r, i, inputItems(input))
                local tool = isTool(input)
                local w = nil
                if countMode(input) then
                    -- the first kind (in order) that the floor completes, with that kind's own amount
                    for _, ft in ipairs(fts) do
                        local need = tool and 1 or amountFor(input, ft)
                        local have = inReach[ft] and inReach[ft].n or 0
                        if have + (onFloor[ft] or 0) >= need then
                            w = { set = { [ft] = true }, n = math.max(1, need - have) }
                            break
                        end
                    end
                end
                if not w then
                    local set = {}
                    for _, ft in ipairs(fts) do set[ft] = true end
                    w = { set = set, n = countMode(input) and math.max(1, amountFor(input, fts[1])) or 1 }
                end
                wants[#wants + 1] = w
            end
        end
    end)
    if not okW or #wants == 0 then return false end
    -- nearest floor spots first; everything that is short must be there
    local px, py = p:getX(), p:getY()
    local spots = {}
    for _, f in ipairs(fl) do
        if f.sq and f.sq:getZ() == floor(p:getZ()) then
            local dx, dy = f.sq:getX() + 0.5 - px, f.sq:getY() + 0.5 - py
            spots[#spots + 1] = { f = f, d = dx * dx + dy * dy }
        end
    end
    table.sort(spots, function(a, b) return a.d < b.d end)
    local left = {}
    for i, w in ipairs(wants) do left[i] = w.n end
    local free = Craft.freeCapacity(p)
    local picks = {}
    for _, sp in ipairs(spots) do
        local ids = {}
        for _, it in ipairs(sp.f.items) do
            local ft = it:getFullType()
            for i, w in ipairs(wants) do
                if left[i] > 0 and w.set[ft] then
                    left[i] = left[i] - 1
                    local wt = it:getUnequippedWeight()
                    if wt <= free then
                        free = free - wt
                        ids[#ids + 1] = it:getID()
                    end
                    break
                end
            end
        end
        if #ids > 0 then picks[#picks + 1] = { sq = sp.f.sq, ids = ids } end
    end
    for i = 1, #wants do if left[i] > 0 then return false end end
    if #picks == 0 then return false end
    job.floorTries = (job.floorTries or 0) + 1
    Craft.trace(job, "picking up from the zone floor at " .. #picks .. " spot(s)")
    if not job.quiet then UI.toast(t("Msg_FloorPick"), true) end
    Craft.queueFloorPick(p, { job = job, picks = picks, i = 1 })
    return true
end

-- walk to the next floor spot; the step there takes its items and queues the next spot
function Craft.queueFloorPick(p, arg)
    local job = arg.job
    while arg.picks[arg.i] do
        local pk = arg.picks[arg.i]
        local stand = floorStand(p, pk.sq)
        if stand ~= false then
            if stand then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, stand)) end
            ISTimedActionQueue.queueActions(p, Craft.takeFloorPick, arg)
            return
        end
        arg.i = arg.i + 1
    end
    ISTimedActionQueue.queueActions(p, Craft.queuedStep, job)
end

function Craft.takeFloorPick(p, arg)
    if arg.job.dead then return end
    local ok, err = pcall(function()
        queuePileTake(p, arg.picks[arg.i].ids)
        arg.i = arg.i + 1
        Craft.queueFloorPick(p, arg)
    end)
    if not ok then
        CHelp.log("floor pick failed: " .. tostring(err))
        fail(arg.job, "Msg_CantCraft", t("Why_Error"))
    end
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
        if g.stand == false then return fail(job, "Msg_CantReach", t("Why_Reach", Scan.boxName(g.c))) end
    end

    for _, r in ipairs(newReturns) do job.returns[#job.returns + 1] = r end

    -- nearest-first walk through the boxes (things on the floor around us first)
    local px, py = p:getX(), p:getY()
    local route = {}
    while #order > 0 do
        local bi, bd = 1, nil
        for i, g in ipairs(order) do
            local sq = g.stand
            local d = sq and ((sq:getX() - px) * (sq:getX() - px) + (sq:getY() - py) * (sq:getY() - py)) or -1
            if not bd or d < bd then bi, bd = i, d end
        end
        local g = table.remove(order, bi)
        route[#route + 1] = g
        if g.stand then px, py = g.stand:getX(), g.stand:getY() end
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

    -- split into loads. Materials first; tools and things to wear last, so they end up in the bag
    -- (tools go back to their box later) and only materials are put down at the spot.
    local isKeep = {}
    for i = 0, keep:size() - 1 do isKeep[keep:get(i)] = true end
    for _, g in ipairs(route) do
        for _, it in ipairs(g.items) do
            if seen[it:getID()] then isKeep[it] = true end
        end
    end
    -- things on the floor around us come first (the floor list changes once we walk off)
    local ordered = {}
    for _, g in ipairs(route) do
        if not g.stand then
            for _, it in ipairs(g.items) do ordered[#ordered + 1] = { it = it, g = g, here = true } end
        end
    end
    for pass = 1, 2 do
        for _, g in ipairs(route) do
            if g.stand then
                for _, it in ipairs(g.items) do
                    if (pass == 1) ~= (isKeep[it] == true) then ordered[#ordered + 1] = { it = it, g = g } end
                end
            end
        end
    end
    -- a load is what the character carries without getting slow (encumbrance limit) and what still
    -- fits in the bag. One item that is heavier than that still goes alone in its own load.
    local free = Craft.freeCapacity(p)
    local room = math.min(Craft.carryRoom(p) * (job.loadScale or 1), free)
    local trips, cur, curW = {}, {}, 0
    for _, e in ipairs(ordered) do
        local w = e.it:getUnequippedWeight()
        if w > free then
            -- the bag is full: put what this job made away first, then plan again
            if not job.madeRoom and Craft.stashOutputs(job, Craft.queuedStep, job) then
                job.madeRoom = true
                return
            end
            return fail(job, "Msg_TooHeavy", t("Why_Heavy", Scan.itemName(e.it:getFullType(), e.it), fmtKg(w), fmtKg(math.max(0, free))))
        end
        if #cur > 0 and curW + w > room and not (e.here and #trips == 0) then
            trips[#trips + 1] = cur
            cur, curW = {}, 0
        end
        cur[#cur + 1] = e
        curW = curW + w
    end
    if #cur > 0 then trips[#trips + 1] = cur end
    job.spot = nil
    if #trips > 1 then
        local dropW = 0
        for ti = 1, #trips - 1 do for _, e in ipairs(trips[ti]) do dropW = dropW + e.it:getUnequippedWeight() end end
        job.spot = Craft.dropSpot(job, recipe, isRefill, dropW)
        if not job.spot then return fail(job, "Msg_TooHeavy") end
        if not job.quiet then UI.toast(t("Msg_Trips", #trips), true) end
    end
    Craft.trace(job, string.format("fetch: %d box(es), %d load(s), load %s kg, bag free %s kg%s", #route, #trips, fmtKg(room), fmtKg(free),
        job.spot and string.format(", pile at %d,%d", job.spot:getX(), job.spot:getY()) or ""))

    local ctx = { job = job, recipe = recipe, refill = isRefill, wear = wearIds,
        station = (not isRefill) and job.station or nil, spot = job.spot, trips = trips, trip = 1, dropped = {} }
    Craft.queueTrip(p, ctx)
end

-- a workstation only accepts crafts from the player marked as using it (the game's bench window
-- sets that when it opens). Taken right before the craft, given back after it.
-- returns ok, took: took = we set it (so we give it back); the player's own open bench window
-- already holds it and keeps it
function Craft.claimBench(p, obj)
    if not obj then return true, false end
    local took = false
    local ok, res = pcall(function()
        local u = obj:getUsingPlayer()
        if u and u ~= p then return false end
        if u ~= p then
            obj:setUsingPlayer(p)
            took = true
        end
        return true
    end)
    if not ok then return true, false end
    return res == true, took
end

function Craft.releaseBench(p, obj)
    if not obj then return end
    pcall(function() if obj:getUsingPlayer() == p then obj:setUsingPlayer(nil) end end)
end

-- where loads are put down when everything does not fit at once: next to the workstation or zone
-- table the recipe uses, else where the character stands now
-- weight that can still be put down from sq (the game drops on the square, else the 3x3 around it
-- that is not behind a wall / window; 50 per square)
function Craft.floorRoom(sq)
    local room = 0
    if not sq then return 0 end
    pcall(function()
        local cell = getCell()
        for dx = -1, 1 do
            for dy = -1, 1 do
                local o = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                if o and o:TreatAsSolidFloor() and not o:isSolid() and not o:isSolidTrans()
                    and (o == sq or (not sq:isBlockedTo(o) and not sq:isWindowTo(o))) then
                    room = room + math.max(0, 50 - o:getTotalWeightOfItemsOnFloor())
                end
            end
        end
    end)
    return room
end

-- where loads are put down when everything does not fit at once: next to the workstation or zone
-- table the recipe uses (a spot with floor room for need kg), else where the character stands now
function Craft.dropSpot(job, recipe, isRefill, need)
    local p = job.p
    local obj = nil
    if (not isRefill) and job.station then
        obj = job.station.obj
    elseif Craft.isSurface(recipe) then
        local s = Scan.surfaceNear(stationsOf(job), p:getX(), p:getY())
        obj = s and s.obj or nil
    end
    need = (need or 0) * 1.1
    if obj then
        local okS, sq = pcall(function() return obj:getSquare() end)
        if okS and sq then
            local adj = Craft.adjacentStand(p, sq)
            if adj and Craft.floorRoom(adj) >= need then return adj end
            -- that spot's floor is full: any free tile within 2 of the workstation that has room
            local best, bd = nil, nil
            local cell = getCell()
            for dx = -2, 2 do
                for dy = -2, 2 do
                    local c = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                    if c and c ~= sq and standable(c) and Craft.floorRoom(c) >= need then
                        local okR, reach = pcall(function() return c:canReachTo(sq) or (adj and c:canReachTo(adj)) end)
                        local d = dx * dx + dy * dy
                        if (okR and reach) or d <= 2 then
                            if not bd or d < bd then best, bd = c, d end
                        end
                    end
                end
            end
            if best then return best end
            if adj then return adj end
        end
    end
    return p:getCurrentSquare()
end

-- one load: walk the boxes of this trip and take its items; then either put the load down at the
-- spot and come back for the next one, or (last load) go craft
function Craft.queueTrip(p, ctx)
    local inv = p:getInventory()
    local trip = ctx.trips[ctx.trip] or {}
    local last = "none"
    for _, e in ipairs(trip) do
        local g = e.g
        if g.stand and g.stand ~= last then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, g.stand)) end
        last = g.stand
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, e.it, g.c, inv))
    end
    if ctx.trip < #ctx.trips then
        local ids = {}
        for _, e in ipairs(trip) do ids[#ids + 1] = e.it:getID() end
        ISTimedActionQueue.add(ISWalkToTimedAction:new(p, ctx.spot))
        ISTimedActionQueue.queueActions(p, Craft.dropLoad, { ctx = ctx, ids = ids })
    else
        ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
    end
end

-- runs at the spot: put this load on the floor (found again by ID), then fetch the next load
function Craft.dropLoad(p, arg)
    local ctx = arg.ctx
    if ctx.job.dead then return end
    local ok, err = pcall(function()
        local inv = p:getInventory()
        local floorC = ISInventoryPage.GetFloorContainer(p:getPlayerNum())
        for _, id in ipairs(arg.ids) do
            local it = inv:getItemWithIDRecursiv(id)
            if it and it:getContainer() and not p:isEquippedClothing(it) then
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), floorC))
                ctx.dropped[#ctx.dropped + 1] = id
                ctx.droppedFts = ctx.droppedFts or {}
                ctx.droppedFts[it:getFullType()] = (ctx.droppedFts[it:getFullType()] or 0) + 1
            end
        end
        -- remembered so an interrupted run can come back for it
        Craft.pile = { x = ctx.spot:getX(), y = ctx.spot:getY(), z = ctx.spot:getZ(), ids = ctx.dropped, fts = ctx.droppedFts }
        Craft.trace(ctx.job, "load " .. ctx.trip .. "/" .. #ctx.trips .. " put down (" .. #ctx.dropped .. " on the pile)")
        ctx.trip = ctx.trip + 1
        Craft.queueTrip(p, ctx)
    end)
    if not ok then
        CHelp.log("drop load failed: " .. tostring(err))
        fail(ctx.job, "Msg_CantCraft", t("Why_Error"))
    end
end

-- in reach of the workstation the way the game checks it
local function inBenchRange(p, ctx)
    local obj = ctx.station and ctx.station.obj
    if not obj then return true end
    local ok, v = pcall(function()
        local lg = Craft.makeLogic(p, ctx.station.bench, obj)
        return lg:isCharacterInRangeOfWorkbench()
    end)
    if ok and type(v) == "boolean" then return v end
    return Craft.nearSq(p, obj:getSquare(), 1.6)
end

local function surfaceFor(p, ctx)
    local s = Scan.surfaceNear(stationsOf(ctx.job), p:getX(), p:getY())
    local surf = s and s.obj or nil
    if not surf then
        local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
        if okF then surf = f end
    end
    return surf
end

-- the craft runs in three short steps, each queued after the last one's walking / carrying:
--   place : stand where the craft happens (on the pile, else next to the workstation / table)
--   pick  : take the pile back into the bag (like the game's crafting window does) + wear things
--   craft : the craft itself
-- Walks are queued directly (never the game's walkAdj, which clears actions added in the same step).
local function deferredCraftInner(p, ctx)
    local job = ctx.job
    local inv = p:getInventory()
    local surface = (not ctx.station) and Craft.isSurface(ctx.recipe)
    if not ctx.placed then
        ctx.placed = true
        local target = nil
        if ctx.spot then
            if not Craft.nearSq(p, ctx.spot, 0.6) then target = ctx.spot end
        elseif ctx.station then
            if not inBenchRange(p, ctx) then
                target = Craft.adjacentStand(p, ctx.station.obj:getSquare())
                if not target then return fail(job, "Msg_CantReach", t("Why_ReachStation", tostring(ctx.station.name))) end
            end
        elseif surface then
            ctx.surf = surfaceFor(p, ctx)
            if not ctx.surf then return fail(job, "Msg_NoSurface") end
            if not Craft.nearSq(p, ctx.surf:getSquare(), 1.6) then
                target = Craft.adjacentStand(p, ctx.surf:getSquare())
                if not target then return fail(job, "Msg_CantReach", t("Why_ReachTable")) end
            end
        end
        if target then
            ISTimedActionQueue.add(ISWalkToTimedAction:new(p, target))
            ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
            return
        end
    end
    if not ctx.picked then
        ctx.picked = true
        if #(ctx.dropped or {}) > 0 and queuePileTake(p, ctx.dropped) then
            ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
            return
        end
    end
    if not ctx.wore then
        ctx.wore = true
        Craft.prunePile(p)
        local added = false
        for _, id in ipairs(ctx.wear or {}) do
            local it = inv:getItemWithIDRecursiv(id)
            if it and not p:isEquippedClothing(it) then
                if it:getContainer() ~= inv then
                    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), inv))
                end
                ISTimedActionQueue.add(ISWearClothing:new(p, it))
                added = true
            end
        end
        if added then
            ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
            return
        end
    end
    -- craft: the pile spot is next to the workstation; when it was not (no free tile there) walk now
    if ctx.station and not ctx.walked and not inBenchRange(p, ctx) then
        ctx.walked = true
        local target = Craft.adjacentStand(p, ctx.station.obj:getSquare())
        if not target then return fail(job, "Msg_CantReach", t("Why_ReachStation", tostring(ctx.station.name))) end
        ISTimedActionQueue.add(ISWalkToTimedAction:new(p, target))
        ISTimedActionQueue.queueActions(p, Craft.deferredCraft, ctx)
        return
    end
    local logic = Craft.makeLogic(p, ctx.station and ctx.station.bench or nil, ctx.station and ctx.station.obj or nil)
    if surface then
        local surf = ctx.surf or surfaceFor(p, ctx)
        if not surf then return fail(job, "Msg_NoSurface") end
        logic:setIsoObject(surf)
    end
    if Craft.tooDark(ctx.recipe, p) then return fail(job, "Msg_TooDark") end
    pcall(function() getPlayerLoot(p:getPlayerNum()):refreshBackpacks() end)
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    Craft.setRecipe(logic, ctx.recipe)
    local okCan, can = pcall(function()
        if surface then return logic:areAllInputItemsSatisfied() end
        return logic:canPerformCurrentRecipe()
    end)
    if not (okCan and can) then
        return Craft.replanOrFail(job, logic, ctx, "craft check failed")
    end
    if ctx.station then
        local okB, took = Craft.claimBench(p, ctx.station.obj)
        if not okB then
            local who = "?"
            pcall(function() who = ctx.station.obj:getUsingPlayer():getUsername() end)
            return fail(job, "Msg_BenchBusy", t("Why_BenchBusy", who))
        end
        job.benchObj = took and ctx.station.obj or nil
    end
    local synced = Craft.craftSynced(p, logic, job)
    -- the game's craft button does this right before starting (keeps the picked item types)
    pcall(function() logic:updateManualInputAllowedItemTypes() end)
    local actions = ISEntityUI.HandcraftStartMultiple(p, logic, false, 1, false)
    if not actions or #actions == 0 then
        return Craft.replanOrFail(job, logic, ctx, "the game did not start the craft")
    end
    for _, a in ipairs(actions) do ISTimedActionQueue.add(a) end
    -- MP: the server makes the craft; wait for its result before planning the next one
    if CHelp.SyncWait then ISTimedActionQueue.add(CHelp.SyncWait:new(p, synced, 2500)) end
    Craft.trace(job, "crafting")
    ISTimedActionQueue.queueActions(p, Craft.afterCraft, ctx)
end

-- something changed between planning and the craft (items moved, the server was a step behind):
-- plan again from what is really there, twice at most, then say what is missing
function Craft.replanOrFail(job, logic, ctx, what)
    if (job.replans or 0) < 2 then
        job.replans = (job.replans or 0) + 1
        Craft.trace(job, tostring(what) .. " at the craft spot, plan again (" .. job.replans .. "/2)")
        Craft.releaseBench(job.p, job.benchObj)
        job.benchObj = nil
        job.pileTried = false
        Craft.step(job)
        return
    end
    local why = Craft.whyNot(job.recipe, job.p, { logic = logic, station = ctx.station, dark = Craft.tooDark(ctx.recipe, job.p) })
    return fail(job, "Msg_CantCraft", Craft.whyText(why) or t("Why_NotInReach"))
end

-- true once the bag shows the craft's result (an output arrived or the used-up inputs are gone)
function Craft.craftSynced(p, logic, job)
    local inv = p:getInventory()
    local ids = {}
    pcall(function()
        local data = logic:getRecipeData()
        local all, keep = data:getAllInputItems(), data:getAllPutBackInputItems()
        for i = 0, all:size() - 1 do
            local it = all:get(i)
            if not keep:contains(it) and inv:getItemWithIDRecursiv(it:getID()) then ids[#ids + 1] = it:getID() end
        end
    end)
    local function outCount()
        local n = 0
        pcall(function()
            local items = inv:getItems()
            for i = 0, items:size() - 1 do if job.outTypes[items:get(i):getFullType()] then n = n + 1 end end
        end)
        return n
    end
    local before = outCount()
    return function()
        if outCount() > before then return true end
        if #ids == 0 then return false end
        for _, id in ipairs(ids) do if inv:getItemWithIDRecursiv(id) then return false end end
        return true
    end
end

function Craft.deferredCraft(p, ctx)
    if ctx.job.dead then return end
    local ok, err = pcall(deferredCraftInner, p, ctx)
    if not ok then
        CHelp.log("deferred craft failed: " .. tostring(err))
        fail(ctx.job, "Msg_CantCraft", t("Why_Error"))
    end
end

function Craft.afterCraft(p, ctx)
    local job = ctx.job
    if job.dead then return end
    Craft.releaseBench(p, job.benchObj)
    job.benchObj = nil
    local ok, err = pcall(function()
        if ctx.refill then
            Craft.step(job)          -- torch is full again, try the real recipe
            return
        end
        job.left = job.left - 1
        job.refilled = false
        job.retries = 0
        job.replans = 0
        job.floorTries = 0
        job.madeRoom = false
        job.pileTried = false
        Craft.trace(job, "made one, " .. job.left .. " to go")
        Craft.prunePile(p)
        if job.onProgress then pcall(job.onProgress, job.total - job.left, job.total) end
        -- carrying too much: put what was made away before going on
        if Craft.overloaded(p) and Craft.stashOutputs(job, Craft.afterStash, job) then return end
        Craft.afterStash(p, job)
    end)
    if not ok then
        CHelp.log("after craft failed: " .. tostring(err))
        fail(job, "Msg_CantCraft", t("Why_Error"))
    end
end

function Craft.afterStash(p, job)
    if job.dead then return end
    local ok, err = pcall(function()
        if job.left > 0 then
            if job.stopCheck and job.stopCheck() then
                Craft.trace(job, "paused by the queue")
                if Craft.active == job then Craft.active = nil end
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
            if Craft.active == job then Craft.active = nil end
            if not job.quiet then UI.toast(t("Msg_CraftDone", Craft.label(job.recipe)), true) end
            if job.onDone then
                local cb = job.onDone
                job.onDone = nil
                pcall(cb)
            end
        end
    end)
    if not ok then
        CHelp.log("after stash failed: " .. tostring(err))
        fail(job, "Msg_CantCraft", t("Why_Error"))
    end
end

-- what this job made that is still in the bag (never things the player had before it started)
function Craft.madeItems(job)
    local out, w = {}, 0
    local p = job.p
    pcall(function()
        local items = p:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if job.outTypes[it:getFullType()] and not job.startIds[it:getID()]
                and not p:isEquippedClothing(it) and not it:isEquipped() and not it:isFavorite() then
                out[#out + 1] = it
                w = w + it:getUnequippedWeight()
            end
        end
    end)
    return out, w
end

-- put what the job made into the nearest zone box with room, else on the floor here.
-- Returns true when something was queued (fn(p, arg) runs after it).
function Craft.stashOutputs(job, fn, arg)
    local p = job.p
    local made, total = Craft.madeItems(job)
    if #made == 0 then return false end
    local inv = p:getInventory()
    local best, bd = nil, nil
    local entries = job.entriesFn and job.entriesFn() or {}
    for _, e in ipairs(entries) do
        local okT, ty = pcall(function() return e.c and e.c:getType() end)
        local sameFloor = e.sq and e.sq:getZ() == floor(p:getZ())
        if not e.veh and e.c and sameFloor and not (okT and ty == "floor") then
            local okR, room = pcall(function()
                if not e.c:hasRoomFor(p, total) then return false end
                for _, it in ipairs(made) do
                    if not e.c:isItemAllowed(it) then return false end
                end
                return true
            end)
            if okR and room then
                local stand = standFor(p, e.c)
                if stand then
                    local dx, dy = stand:getX() - p:getX(), stand:getY() - p:getY()
                    local d = dx * dx + dy * dy
                    if not bd or d < bd then best, bd = { c = e.c, stand = stand }, d end
                end
            end
        end
    end
    if best then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(p, best.stand))
        for _, it in ipairs(made) do
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), best.c))
        end
        Craft.trace(job, "bag heavy: " .. #made .. " made item(s) into " .. tostring(Scan.boxName(best.c)))
        if not job.toldStash then
            job.toldStash = true
            UI.toast(t("Msg_StashBox", Scan.boxName(best.c)), true)
        end
    else
        -- only as much as the floor around can take (a refused drop would stop the whole run)
        local room = Craft.floorRoom(p:getCurrentSquare()) * 0.9
        local floorC = ISInventoryPage.GetFloorContainer(p:getPlayerNum())
        local n = 0
        for _, it in ipairs(made) do
            local w = it:getUnequippedWeight()
            if w <= room then
                room = room - w
                n = n + 1
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, it:getContainer(), floorC))
            end
        end
        if n == 0 then
            Craft.trace(job, "bag heavy, no box with room and the floor here is full: keep carrying")
            return false
        end
        Craft.trace(job, "bag heavy: " .. n .. " made item(s) put on the floor here")
        if not job.toldStash then
            job.toldStash = true
            UI.toast(t("Msg_StashFloor"), true)
        end
    end
    ISTimedActionQueue.queueActions(p, fn, arg)
    return true
end

-- walk to the boxes holding these items (nearest first), take them, then fn(p, arg) runs from
-- the action queue. Returns false, msgKey when a box cannot be reached (nothing is queued then).
function Craft.isBusy(p)
    return (CHelp.Queue and CHelp.Queue.running ~= nil) or ISTimedActionQueue.isPlayerDoingAction(p)
end

-- skipBusy: the caller checked already (and may have queued getting out of a car)
function Craft.fetchThen(p, items, fn, arg, skipBusy)
    if not skipBusy and Craft.isBusy(p) then return false, "Msg_Busy" end
    local inv = p:getInventory()
    local groups, order = {}, {}
    for _, it in ipairs(items or {}) do
        local c = it:getContainer()
        if c and c ~= inv and not c:isInCharacterInventory(p) then
            local g = groups[c]
            if not g then
                g = { c = c, items = {} }
                groups[c] = g
                order[#order + 1] = g
            end
            g.items[#g.items + 1] = it
        end
    end
    for _, g in ipairs(order) do
        g.stand = standFor(p, g.c)
        if g.stand == false then return false, "Msg_CantReach" end
    end
    local px, py = p:getX(), p:getY()
    while #order > 0 do
        local bi, bd = 1, nil
        for i, g in ipairs(order) do
            local sq = g.stand
            local d = sq and ((sq:getX() - px) * (sq:getX() - px) + (sq:getY() - py) * (sq:getY() - py)) or -1
            if not bd or d < bd then bi, bd = i, d end
        end
        local g = table.remove(order, bi)
        if g.stand then
            ISTimedActionQueue.add(ISWalkToTimedAction:new(p, g.stand))
            px, py = g.stand:getX(), g.stand:getY()
        end
        for _, it in ipairs(g.items) do
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, it, g.c, inv))
        end
    end
    ISTimedActionQueue.queueActions(p, fn, arg)
    return true
end

-- tools that were borrowed from boxes go back where they came from
function Craft.returnToolList(p, list)
    if not CHelp.sv("ReturnToolsAfterCraft") then return end
    local inv = p:getInventory()
    local byBox, order, seen = {}, {}, {}
    for _, r in ipairs(list or {}) do
        local it = (not seen[r.id]) and inv:getItemWithIDRecursiv(r.id) or nil
        if it and it:getContainer() ~= r.c then
            seen[r.id] = true
            local g = byBox[r.c]
            if not g then g = { c = r.c, items = {} } byBox[r.c] = g order[#order + 1] = g end
            g.items[#g.items + 1] = it
        end
    end
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

function Craft.returnTools(job)
    if job.keepTools then return end      -- the queue gives them back once it is done
    local list = job.returns
    job.returns = {}
    Craft.returnToolList(job.p, list)
end
