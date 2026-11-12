-- Cookie Mission - task missions on the client: glowing targets, right-click option, walk there,
-- minigame window, then a short work action (hands busy, progress bar) before the server counts it
require "CM_Client"
require "CM_UI_Games"
require "TimedActions/ISBaseTimedAction"

CMTasks = CMTasks or {}
local T = CMC.txt

-- outline colour of the glowing furniture per mission type
CMTasks.COL = {
    wire = { 1.00, 0.82, 0.20 }, safe = { 0.78, 0.55, 1.00 }, pipe = { 0.30, 0.80, 1.00 },
    board = { 1.00, 0.60, 0.25 }, trap = { 1.00, 0.30, 0.35 },
    rush = { 0.45, 1.00, 0.45 }, dance = { 1.00, 0.45, 0.85 },
}
local BUSY_COL = { 0.55, 0.55, 0.60 }

-- work action look per type: animation, LootPosition, tool shown in the hands, sound
CMTasks.WORK = {
    wire  = { anim = "Loot", pos = "Mid", tool = "Base.Screwdriver", sound = "GeneratorRepair" },
    safe  = { anim = "Loot", pos = "Low", tool = "Base.Screwdriver", sound = "RepairWithWrench" },
    pipe  = { anim = "Loot", pos = "Low", tool = "Base.PipeWrench", sound = "RepairWithWrench" },
    board = { anim = "Build", tool = "Base.Hammer", tool2 = "Base.Plank" },
    trap  = { anim = "Loot", pos = "Mid", tool = "Base.Screwdriver" },
    rush  = { anim = "Loot", pos = "Mid", tool = "Base.Wrench", sound = "GeneratorRepair" },
    dance = { anim = "Loot", pos = "Mid" },
}

CMTasks.pend = nil      -- { i, tok, kind, tier, run, won }
CMTasks.wait = nil      -- { i, at } waiting for the server to answer "tstart"

local function ms() return CMC.ms() end

function CMTasks.taskRun()
    local run = CMC.run()
    if run and run.phase == "live" and CM.isTask(run.type) then return run end
    return nil
end

function CMTasks.byIdx(run, i)
    for _, t in ipairs((run and run.tasks) or {}) do
        if t.i == i then return t end
    end
    return nil
end

-- ===================================================================== finding the target object on this client
local function square(t)
    local c = getCell and getCell()
    return c and c:getGridSquare(t.x, t.y, t.z) or nil
end

function CMTasks.findObj(t)
    local sq = square(t)
    if not sq then return nil, nil end
    local objs = CM.call(sq, "getObjects")
    local n = objs and (CM.call(objs, "size") or 0) or 0
    local byKind = nil
    for i = 0, n - 1 do
        local o = objs:get(i)
        if t.s and t.s ~= "" and CM.spriteName(o) == t.s then return o, sq end
        if not byKind and t.c and t.c ~= "obj" and t.c ~= "cont" and CM.objKind(o) == t.c then byKind = o end
    end
    return byKind, sq
end

-- ===================================================================== highlight
local lit = {}          -- task key -> { o = object, key }
local lastResolve = 0

local function tkey(t) return tostring(t.x) .. "," .. tostring(t.y) .. "," .. tostring(t.z) end

local function pnum()
    local p = CMC.player()
    local n = p and CM.call(p, "getPlayerNum")
    return n or 0
end

local function setLit(o, on, col, a)
    if not o then return end
    local pn = pnum()
    local okH = pcall(function() o:setHighlighted(pn, on, false) end)
    if not okH then pcall(function() o:setHighlighted(on) end) end
    if on then
        local ci = nil
        pcall(function() ci = ColorInfo.new(col[1], col[2], col[3], a or 1) end)
        if ci then
            local okC = pcall(function() o:setHighlightColor(pn, ci) end)
            if not okC then pcall(function() o:setHighlightColor(ci) end) end
            pcall(function() o:setOutlineHighlight(pn, true) end)
            pcall(function() o:setOutlineHighlightCol(pn, ci) end)
        end
    else
        pcall(function() o:setOutlineHighlight(pn, false) end)
    end
end
CMTasks.setLit = setLit

function CMTasks.unlightAll()
    for k, e in pairs(lit) do
        setLit(e.o, false)
        lit[k] = nil
    end
end

local function highlightTick(run)
    local t = ms()
    local want = {}
    for _, tk in ipairs(run.tasks or {}) do want[tkey(tk)] = tk end
    -- targets that are done (or gone) stop glowing
    for k, e in pairs(lit) do
        if not want[k] then setLit(e.o, false); lit[k] = nil end
    end
    local resolve = t - lastResolve >= 1000
    if resolve then lastResolve = t end
    local pulse = 0.65 + 0.35 * math.abs(math.sin(t / 380))
    local col0 = CMTasks.COL[run.type] or CMTasks.COL.wire
    for k, tk in pairs(want) do
        local e = lit[k]
        if resolve or not e then
            local o = CMTasks.findObj(tk)
            if e and e.o ~= o then setLit(e.o, false) end
            if o then
                e = { o = o }
                lit[k] = e
            else
                lit[k] = nil
                e = nil
            end
        end
        if e then
            local col = col0
            if tk.b then col = BUSY_COL end
            setLit(e.o, true, { col[1] * pulse, col[2] * pulse, col[3] * pulse }, 1)
        end
    end
end

-- ===================================================================== distance helpers
function CMTasks.dist(p, t)
    local dx, dy = p:getX() - (t.x + 0.5), p:getY() - (t.y + 0.5)
    return math.sqrt(dx * dx + dy * dy)
end

function CMTasks.nearest(run)
    local p = CMC.player()
    if not p or not run or not run.tasks then return nil end
    local pz = math.floor(p:getZ())
    local best, bestD = nil, 999999
    for _, t in ipairs(run.tasks) do
        local d = CMTasks.dist(p, t) + math.abs(t.z - pz) * 12
        if d < bestD then best, bestD = t, d end
    end
    return best, bestD
end

function CMTasks.inReach(t)
    local p = CMC.player()
    if not p or not t then return false end
    return CMTasks.dist(p, t) <= 2.3 and math.abs(math.floor(p:getZ()) - t.z) == 0
end

-- ===================================================================== timed actions
-- 1) a zero-time step queued after the walk: when the player arrives it asks the server for the minigame
CMTaskStep = ISBaseTimedAction:derive("CMTaskStep")

function CMTaskStep:isValid() return CMTasks.taskRun() ~= nil end
function CMTaskStep:update() end
function CMTaskStep:start() end
function CMTaskStep:stop() ISBaseTimedAction.stop(self) end
function CMTaskStep:perform()
    local ok, err = pcall(CMTasks.arrived, self.i)
    if not ok then CM.log("task step error: " .. tostring(err)) end
    ISBaseTimedAction.perform(self)
end
function CMTaskStep:new(character, i)
    local o = ISBaseTimedAction.new(self, character)
    o.i = i
    o.maxTime = 1
    o.useProgressBar = false
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end

-- 2) after a won minigame: hands busy for a few seconds, then the server is told
CMTaskWork = ISBaseTimedAction:derive("CMTaskWork")

function CMTaskWork:isValid()
    local pd = CMTasks.pend
    return CMTasks.taskRun() ~= nil and pd ~= nil and pd.i == self.i and pd.won == true
end

function CMTaskWork:face()
    if self.obj then
        pcall(function() self.character:faceThisObject(self.obj) end)
    elseif self.tx then
        pcall(function() self.character:faceLocation(self.tx, self.ty) end)
    end
end

function CMTaskWork:waitToStart()
    self:face()
    local ok, turning = pcall(function() return self.character:shouldBeTurning() end)
    return ok and turning == true
end

function CMTaskWork:update()
    self:face()
    pcall(function() self.character:setMetabolicTarget(Metabolics.LightWork) end)
end

function CMTaskWork:start()
    local w = CMTasks.WORK[self.kind] or CMTasks.WORK.wire
    pcall(function() self:setActionAnim(w.anim) end)
    if w.pos then pcall(function() self.character:SetVariable("LootPosition", w.pos) end) end
    if w.tool then pcall(function() self:setOverrideHandModelsString(w.tool, w.tool2) end) end
    if w.sound then
        local ok, snd = pcall(function() return self.character:playSound(w.sound) end)
        if ok then self.sound = snd end
    end
end

function CMTaskWork:stopSound()
    if self.sound then
        pcall(function() self.character:stopOrTriggerSound(self.sound) end)
        self.sound = nil
    end
end

function CMTaskWork:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function CMTaskWork:perform()
    self:stopSound()
    local ok, err = pcall(CMTasks.workDone, self.i)
    if not ok then CM.log("task work error: " .. tostring(err)) end
    ISBaseTimedAction.perform(self)
end

function CMTaskWork:new(character, i, kind, obj, tx, ty)
    local o = ISBaseTimedAction.new(self, character)
    o.i = i
    o.kind = kind
    o.obj = obj
    o.tx, o.ty = tx, ty
    local sec = CM.gameVal(kind, "work") or 4
    o.maxTime = math.floor(sec * 48)
    o.forceProgressBar = true
    o.caloriesModifier = 2
    local okI, inst = pcall(function() return character:isTimedActionInstant() end)
    if okI and inst then o.maxTime = 1 end
    return o
end

-- ===================================================================== flow
local function toast(key, a)
    CMC.toast(T("IGUI_CM_T_" .. key, a), "bad", 5)
end

-- start (or resume) the task at index i: walk next to it, then ask the server
function CMTasks.go(i)
    local run = CMTasks.taskRun()
    local t = CMTasks.byIdx(run, i)
    local p = CMC.player()
    if not run or not t or not p then return end
    if CMGame.cur then CMGame.cur:bringToTop(); return end
    local obj, sq = CMTasks.findObj(t)
    sq = (obj and CM.call(obj, "getSquare")) or sq
    if not sq then toast("tfar"); return end
    local walked = false
    if luautils and luautils.walkAdj then
        local ok, r = pcall(luautils.walkAdj, p, sq, false)
        walked = ok and r == true
    end
    if not walked then
        if CMTasks.inReach(t) then
            pcall(function() ISTimedActionQueue.clear(p) end)
        else
            toast("tnoreach")
            return
        end
    end
    ISTimedActionQueue.add(CMTaskStep:new(p, i))
end

function CMTasks.queueWork(i)
    local pd = CMTasks.pend
    local run = CMTasks.taskRun()
    local t = CMTasks.byIdx(run, i)
    local p = CMC.player()
    if not pd or not t or not p then return end
    local obj = CMTasks.findObj(t)
    ISTimedActionQueue.add(CMTaskWork:new(p, i, pd.kind, obj, t.x + 0.5, t.y + 0.5))
end

-- arrived next to the target
function CMTasks.arrived(i)
    local run = CMTasks.taskRun()
    if not run then return end
    local pd = CMTasks.pend
    if pd and pd.i == i and pd.won and pd.run == run.id then
        CMTasks.queueWork(i)
        return
    end
    if CMTasks.wait and ms() - CMTasks.wait.at < 4000 then return end
    CMTasks.wait = { i = i, at = ms() }
    CMC.send("tstart", { run = run.id, i = i })
end

-- the server locked the target for us: play
function CMTasks.onGo(args)
    CMTasks.wait = nil
    local run = CMTasks.taskRun()
    if not run or args.run ~= run.id then return end
    local i = CM.int(args.i, 0)
    local t = CMTasks.byIdx(run, i) or { x = args.x, y = args.y, z = args.z, i = i }
    local tok, rid = args.tok, run.id
    CMTasks.pend = { i = i, tok = tok, kind = args.type, tier = CM.int(args.tier, 1, 1, 3), run = rid, won = false }
    CMGame.open(args.type, CMTasks.pend.tier, { x = t.x, y = t.y, z = t.z, i = i }, function(won, why)
        CMTasks.gameOver(i, won, why, tok, rid)
    end)
end

-- the token of the game itself is used, so a lost or given-up game always frees the target on the server
function CMTasks.gameOver(i, won, why, tok, rid)
    local pd = CMTasks.pend
    if won then
        if pd and pd.i == i and pd.tok == tok then
            pd.won = true
            CMTasks.queueWork(i)
        end
        return
    end
    CMC.send("tfail", { run = rid, i = i, tok = tok, why = why })
    if pd and pd.i == i then CMTasks.pend = nil end
end

function CMTasks.workDone(i)
    local pd = CMTasks.pend
    if not pd or pd.i ~= i or not pd.won then return end
    CMC.send("tdone", { run = pd.run, i = i, tok = pd.tok })
end

-- ===================================================================== server answers
local function onServerCommand(module, command, args)
    if module ~= CM.MOD then return end
    args = args or {}
    if command == "tgo" then
        CMTasks.onGo(args)
    elseif command == "tno" then
        CMTasks.wait = nil
        local pd = CMTasks.pend
        if pd and pd.i == CM.int(args.i, 0) then CMTasks.pend = nil end
    elseif command == "tok" then
        local pd = CMTasks.pend
        if pd and pd.i == CM.int(args.i, 0) then CMTasks.pend = nil end
    end
end
Events.OnServerCommand.Add(onServerCommand)
CMTasks.onServerCommand = onServerCommand

-- ===================================================================== right click on a glowing object
local function onFillWorld(playerNum, context, worldobjects, test)
    if test then return end
    local run = CMTasks.taskRun()
    if not run or not run.tasks or #run.tasks == 0 then return end
    local hit = nil
    for _, o in ipairs(worldobjects or {}) do
        local sq = CM.call(o, "getSquare")
        if sq then
            local x, y, z = CM.call(sq, "getX"), CM.call(sq, "getY"), CM.call(sq, "getZ")
            for _, t in ipairs(run.tasks) do
                if t.x == x and t.y == y and t.z == z then hit = t end
            end
        end
        if hit then break end
    end
    if not hit then return end
    local pd = CMTasks.pend
    local label = T("IGUI_CM_Task_go_" .. tostring(run.type))
    if pd and pd.i == hit.i and pd.won then label = T("IGUI_CM_Task_resume") end
    if hit.b then label = label .. " (" .. T("IGUI_CM_Task_busy", hit.b) .. ")" end
    local fn = function() CMTasks.go(hit.i) end
    local ok = pcall(function() context:addOptionOnTop(label, nil, fn) end)
    if not ok then pcall(function() context:addOption(label, nil, fn) end) end
end
if Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
        local ok, err = pcall(onFillWorld, playerNum, context, worldobjects, test)
        if not ok then CM.log("task context error: " .. tostring(err)) end
    end)
end

-- ===================================================================== HUD lines (called from the tracker)
function CMTasks.drawHud(win, x, y, w, run)
    local S = CMUI.S
    local C = CMUI.C
    local lh = CMUI.fh(UIFont.Small) + S(4)
    local p = CMC.player()
    if not p then return y end
    if not run.tasks or #run.tasks == 0 then
        CMUI.text(win, T("IGUI_CM_Task_placing"), x, y, C.dim)
        return y + lh
    end
    local pd = CMTasks.pend
    local t = nil
    if pd and pd.won then t = CMTasks.byIdx(run, pd.i) end
    t = t or CMTasks.nearest(run)
    if not t then return y end
    local col = CMTasks.COL[run.type] or C.gold
    if CMTasks.inReach(t) then
        if t.b and not t.mine then
            CMUI.text(win, CMUI.fit(T("IGUI_CM_Task_busy", t.b), UIFont.Small, w), x, y, C.dim)
            y = y + lh
        else
            local label = T("IGUI_CM_Task_go_" .. tostring(run.type))
            if pd and pd.i == t.i and pd.won then label = T("IGUI_CM_Task_resume") end
            local busy = CMGame.cur ~= nil
            CMUI.btn(win, x, y, w, S(26), label, function() CMTasks.go(t.i) end, "primary", { disabled = busy })
            y = y + S(26) + S(6)
        end
    else
        local d = CMTasks.dist(p, t)
        local s = T("IGUI_CM_Task_next", T("IGUI_CM_Dir_" .. CMHud.dirOf(t.x + 0.5 - p:getX(), t.y + 0.5 - p:getY())), math.floor(d))
        local pz = math.floor(p:getZ())
        if t.z ~= pz then s = s .. T("IGUI_CM_Task_floor", t.z + 1) end
        CMUI.text(win, CMUI.fit(s, UIFont.Small, w), x, y, col)
        y = y + lh
        CMUI.text(win, CMUI.fit(T("IGUI_CM_Task_hint"), UIFont.Small, w), x, y, C.faint)
        y = y + lh
    end
    return y
end

-- ===================================================================== tick
local lastTick = 0
local function onTick()
    local run = CMTasks.taskRun()
    if not run then
        CMTasks.unlightAll()
        if CMGame.cur then CMGame.cur:drop() end
        CMTasks.pend = nil
        CMTasks.wait = nil
        return
    end
    local pd = CMTasks.pend
    if pd and pd.run ~= run.id then CMTasks.pend = nil end
    local t = ms()
    if t - lastTick < 90 then return end
    lastTick = t
    highlightTick(run)
end
Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CM.log("task tick error: " .. tostring(err)) end
end)

return CMTasks
