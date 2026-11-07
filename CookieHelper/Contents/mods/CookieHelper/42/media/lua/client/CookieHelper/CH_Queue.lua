-- Cookie Helper : craft queue (engine + window)
-- Jobs run one after another. Each job is re-planned from the real stock right before it starts
-- (Link crafts first, then the job itself). If something is missing: skip to the next job or stop
-- the queue, as the player chose. Pause stops after the craft in progress.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Craft"

CHelp.Queue = CHelp.Queue or {}
local Q = CHelp.Queue
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local t = CHelp.t
local floor = math.floor

Q.jobs = Q.jobs or {}
Q.seq = Q.seq or 0
Q.paused = Q.paused or false
Q.policy = Q.policy or "skip"
Q.loop = Q.loop or false      -- run the whole list again when it is done (until something runs out)
Q.round = Q.round or 1
Q.returns = Q.returns or {}   -- tools borrowed by the jobs, given back when the queue runs dry

local function changed() C.emit("queue") end

-- borrowed tools go back to their boxes once nothing else is left to do
local function giveToolsBack()
    if #Q.returns == 0 then return end
    local p = C.player()
    local list = Q.returns
    Q.returns = {}
    if p then pcall(Craft.returnToolList, p, list) end
end

-- nothing left to wait for or run (even while paused): the tools can go back now
local function toolsBackIfEmpty()
    if Q.running then return end
    for _, j in ipairs(Q.jobs) do
        if j.status == "wait" or j.status == "run" then return end
    end
    giveToolsBack()
end

-- house = the safehouse: take things from every box in the house, not only the zone.
-- The craft itself still happens in the zone (its workstations and tables).
local function zoneFns(zone, house)
    local function entries()
        if house then
            -- the zone's own boxes first (the craft logic takes items in list order), then the rest
            -- of the house; vehicles in the zone still count (never looted)
            local zoneE, veh = Scan.containers(zone, zone.z, true)
            local out, seen = {}, {}
            for _, e in ipairs(zoneE) do
                if not e.veh then
                    out[#out + 1] = e
                    seen[e.c] = true
                end
            end
            for _, e in ipairs(Scan.house(house)) do
                if not seen[e.c] then out[#out + 1] = e end
            end
            for _, v in ipairs(veh or {}) do
                for i = 0, v:getPartCount() - 1 do
                    local part = v:getPartByIndex(i)
                    local c = part and part:getItemContainer()
                    if c then out[#out + 1] = { c = c, sq = v:getSquare(), veh = v, part = part } end
                end
            end
            return out
        end
        return Scan.containers(zone, zone.z, true)
    end
    local function stations() return Scan.stations(zone, zone.z) end
    return entries, stations
end
Q.zoneFns = zoneFns

local function inZone(zone)
    local p = C.player()
    if not p or floor(p:getZ()) ~= zone.z then return false end
    return CHelp.zoneHas(zone, floor(p:getX()), floor(p:getY()), 2)
end

function Q.count()
    local n = 0
    for _, j in ipairs(Q.jobs) do if j.status ~= "done" then n = n + 1 end end
    return n
end

-- spec = { recipe, qty, link, zone, zoneName, house = SafeHouse|nil }
function Q.add(spec)
    local p = C.player()
    if not p or not spec.recipe or not spec.zone then return end
    Q.seq = Q.seq + 1
    local entries, stations = zoneFns(spec.zone, spec.house)
    local counts = Craft.countAll(p, entries())
    local plan = Craft.plan({ p = p, counts = counts, stations = stations(), link = spec.link }, spec.recipe, spec.qty)
    local job = { id = Q.seq, recipe = spec.recipe, qty = math.max(1, spec.qty or 1), qty0 = math.max(1, spec.qty or 1), link = spec.link == true,
        zone = spec.zone, zoneName = spec.zoneName or spec.zone.name or "", status = "wait", steps = plan.steps, stepIdx = 0,
        done = 0, why = nil, stepDone = 0, house = spec.house }
    Q.jobs[#Q.jobs + 1] = job
    UI.toast(t("Msg_Queued", Craft.label(spec.recipe), job.qty), true)
    changed()
    Q.kick()
    return job
end

function Q.remove(id)
    for i, j in ipairs(Q.jobs) do
        if j.id == id then
            if j.status == "run" then
                j.cancel = true
                -- nothing left in the action queue: the chain is gone, drop the job now
                local p = C.player()
                if p and not ISTimedActionQueue.isPlayerDoingAction(p) then Q.interrupt(j, true) end
                return
            end
            table.remove(Q.jobs, i)
            changed()
            if not Q.running then Q.kick() end
            toolsBackIfEmpty()
            return
        end
    end
end

function Q.move(id, d)
    for i, j in ipairs(Q.jobs) do
        if j.id == id then
            local k = i + d
            if k >= 1 and k <= #Q.jobs then
                Q.jobs[i], Q.jobs[k] = Q.jobs[k], Q.jobs[i]
                changed()
            end
            return
        end
    end
end

function Q.clearDone()
    local keep = {}
    for _, j in ipairs(Q.jobs) do if j.status ~= "done" then keep[#keep + 1] = j end end
    Q.jobs = keep
    changed()
    toolsBackIfEmpty()
end

function Q.setPaused(v)
    Q.paused = v
    changed()
    if not v then Q.kick() end
end

function Q.setPolicy(v)
    Q.policy = v
    changed()
end

function Q.setLoop(v)
    Q.loop = v == true
    if Q.loop then Q.round = 1 end
    changed()
    if Q.loop then Q.kick() end
end



local function finish(job, status, why)
    job.status = status
    job.why = why
    if Q.running == job then Q.running = nil end
    changed()
end

function Q.kick()
    if Q.running or Q.paused then return end
    for _, j in ipairs(Q.jobs) do
        if j.status == "wait" then
            Q.runJob(j)
            return
        end
    end
    -- loop: every job is done -> the next round starts with the same list
    if Q.loop then
        local again = false
        for _, j in ipairs(Q.jobs) do
            if j.status == "done" then
                j.status, j.qty, j.done, j.why, j.stepIdx, j.stepDone = "wait", j.qty0 or j.qty, 0, nil, 0, 0
                again = true
            end
        end
        if again then
            Q.round = Q.round + 1
            changed()
            for _, j in ipairs(Q.jobs) do
                if j.status == "wait" then
                    Q.runJob(j)
                    return
                end
            end
        end
    end
    giveToolsBack()
end

local function warn(job, why)
    finish(job, "warn", why)
    if Q.loop then
        -- a loop never spins on something it cannot make: stop and say why
        Q.paused = true
        UI.toast(t("Msg_LoopStopped", why or ""), false)
        changed()
        giveToolsBack()
        return
    end
    if Q.policy == "stop" then
        Q.paused = true
        giveToolsBack()
        UI.toast(t("Msg_QueueStopped", Craft.label(job.recipe)), false)
        changed()
    else
        Q.kick()
    end
end

function Q.runJob(job)
    local p = C.player()
    if not p then return end
    if not inZone(job.zone) then return warn(job, t("Q_StandInZone", job.zoneName)) end
    local entries, stations = zoneFns(job.zone, job.house)
    local counts = Craft.countAll(p, entries())
    local plan = Craft.plan({ p = p, counts = counts, stations = stations(), link = job.link }, job.recipe, job.qty)
    job.steps = plan.steps
    if not plan.ok then
        local names = {}
        for _, m in ipairs(plan.missing) do names[#names + 1] = m.name .. " " .. m.short end
        return warn(job, t("Q_Missing", table.concat(names, ", ")))
    end
    job.status = "run"
    job.stepIdx = 1
    job.stepDone = 0
    Q.running = job
    changed()
    Q.nextStep(job, entries, stations)
end

function Q.nextStep(job, entries, stations)
    if job.cancel then
        job.cancel = nil
        finish(job, "wait")
        for i, j in ipairs(Q.jobs) do if j == job then table.remove(Q.jobs, i) break end end
        changed()
        return Q.kick()
    end
    local step = job.steps[job.stepIdx]
    if not step then
        finish(job, "done")
        UI.toast(t("Msg_CraftDone", Craft.label(job.recipe)), true)
        return Q.kick()
    end
    job.stepDone = 0
    changed()
    local isMain = job.stepIdx == #job.steps
    local okS, cj = pcall(Craft.start, C.player(), step.recipe, step.qty, entries, {
        force = true, quiet = true, stationsFn = stations, keepTools = true, returns = Q.returns,
        stopCheck = function() return Q.paused or job.cancel == true end,
        onProgress = function(n)
            job.stepDone = n
            if isMain then job.done = n end
            changed()
        end,
        onDone = function()
            job.stepIdx = job.stepIdx + 1
            Q.nextStep(job, entries, stations)
        end,
        onStopped = function(n)
            if isMain then job.qty = math.max(1, job.qty - n) end
            if job.cancel then
                job.cancel = nil
                for i, j in ipairs(Q.jobs) do if j == job then table.remove(Q.jobs, i) break end end
                Q.running = nil
                changed()
                return Q.kick()
            end
            finish(job, "wait")
        end,
        onFail = function(key)
            warn(job, t(key, Craft.label(step.recipe)))
        end,
    })
    if not okS then
        CHelp.log("queue step failed: " .. tostring(cj))
        return warn(job, t("Msg_CantCraft", Craft.label(step.recipe)))
    end
    if Q.running == job then job.craft = cj end
end

-- the craft chain lives in the action queue; walking away, a hit or a blocked path clears that
-- queue and none of its callbacks run. Then the job waits (paused) instead of blocking forever.
function Q.interrupt(job, quiet)
    if job.craft then
        job.craft.dead = true
        Craft.releaseBench(job.craft.p, job.craft.benchObj)
        pcall(Craft.returnTools, job.craft)
        job.craft = nil
    end
    if Q.running == job then Q.running = nil end
    if job.cancel then
        job.cancel = nil
        for i, j in ipairs(Q.jobs) do if j == job then table.remove(Q.jobs, i) break end end
        changed()
        return Q.kick()
    end
    local isMain = job.stepIdx == #(job.steps or {})
    if isMain and (job.stepDone or 0) > 0 then job.qty = math.max(0, job.qty - job.stepDone) end
    if job.qty <= 0 then
        finish(job, "done")
        return Q.kick()
    end
    job.status = "wait"
    Q.paused = true
    if not quiet then UI.toast(t("Msg_QueueInterrupted"), false) end
    changed()
end

-- a stalled craft (a transfer refused, a path blocked) gets one more go with half-size loads,
-- picked up from wherever things are now. The player walking off or zombies around = pause.
local function canRetry(job, p)
    local cj = job.craft
    if not cj or cj.dead or cj.retried or job.cancel or Q.paused then return false end
    if p:getVehicle() or p:isDead() then return false end
    local okM, moving = pcall(function() return p:isPlayerMoving() end)
    if okM and moving == true then return false end
    local okZ, z = pcall(function() return p:getStats():getNumChasingZombies() end)
    if okZ and type(z) == "number" and z > 0 then return false end
    return true
end

function Q.retry(job)
    local cj = job.craft
    cj.retried = true
    cj.refilled = false
    Craft.releaseBench(cj.p, cj.benchObj)
    cj.benchObj = nil
    cj.loadScale = 0.5
    UI.toast(t("Msg_Retry"), true)
    local ok, err = pcall(Craft.step, cj)
    if not ok then
        CHelp.log("queue retry failed: " .. tostring(err))
        Q.interrupt(job)
    end
end

-- moving the character is how a player cancels: if it stood still the whole time the craft was
-- stuck on its own, otherwise the player stopped it and the queue only pauses
local idleSince, idleX, idleY, idleZ = nil, 0, 0, 0
Events.OnTick.Add(function()
    local job = Q.running
    if not job then idleSince = nil return end
    local p = C.player()
    if not p then return end
    if ISTimedActionQueue.isPlayerDoingAction(p) then
        idleSince, job.walkedOff = nil, nil
        return
    end
    local ms = CHelp.nowMs()
    if not idleSince then
        idleSince, idleX, idleY, idleZ = ms, p:getX(), p:getY(), p:getZ()
        return
    end
    if math.abs(p:getX() - idleX) > 0.3 or math.abs(p:getY() - idleY) > 0.3 or p:getZ() ~= idleZ then
        job.walkedOff = true
    end
    if ms - idleSince > 2500 then
        idleSince = nil
        local walked = job.walkedOff
        job.walkedOff = nil
        if not walked and canRetry(job, p) then Q.retry(job) else Q.interrupt(job) end
    end
end)

-- ------------------------------------------------------------------ window
local W = UI.Window:derive("CHelpQueue")
local ROW_BASE = 52

function W:createChildren()
    UI.Window.createChildren(self)
    local hr = self:headRight()
    self.clearBtn = UI.button(self, hr - 120, floor((UI.HEAD_H - UI.BTN_H) / 2), 120, t("ClearDone"), self, W.onClear, "ghost")
    self.pauseBtn = UI.button(self, hr - 120 - 8 - 150, floor((UI.HEAD_H - UI.BTN_H) / 2), 150, "", self, W.onPause, "sec")
    self.headTextRight = self.pauseBtn:getX() - 10
    local y = UI.HEAD_H + 4 + 86
    local fh = UI.BTN_H + UI.HS + 34
    self.list = UI.makeList(self, UI.PAD, y, self.width - UI.PAD * 2, self.height - y - fh, ROW_BASE, self, W.drawJob)
    self.list.noSelect = true
    self.list.rowGap = 8
    self.list.onMouseDown = function(l, mx, my)
        local row = l:rowAt(mx, my)
        local it = l.items[row]
        if it and it.item.hits then
            for _, hb in ipairs(it.item.hits) do
                if mx >= hb.x and mx < hb.x + hb.w then
                    if hb.kind == "up" then Q.move(it.item.job.id, -1)
                    elseif hb.kind == "down" then Q.move(it.item.job.id, 1)
                    else Q.remove(it.item.job.id) end
                    return true
                end
            end
        end
        return true
    end
    self.policy = UI.tabs(self, UI.PAD + T.tw(t("IfMissing")) + 12, self.height - fh + 10,
        { { id = "skip", label = t("PolicySkip") }, { id = "stop", label = t("PolicyStop") } }, Q.policy, self, W.onPolicy)
    local lw = 64 + T.tw(t("LoopLabel")) + 16
    self.loopBtn = UI.button(self, self.width - UI.PAD - lw, self.policy:getY(), lw, "", self, W.onLoop, "sec", self.policy.height)
    self.loopBtn.drawFn = function(b, bw, bh, hov)
        T.rrect(b, 0, 0, bw, bh, UI.RC, Q.loop and K.accD or (hov and K.surf3 or K.surf2))
        UI.drawSwitch(b, 10, floor((bh - 22) / 2), Q.loop)
        T.text(b, t("LoopLabel"), 60, floor((bh - UI.HS) / 2), Q.loop and K.acc or K.text2)
    end
    self.loopBtn.tooltip = t("LoopTip")
    C.on("queue", self, W.fill)
    self:fill()
end

function W:onClose()
    C.off(self)
    if Q.instance == self then Q.instance = nil end
end

function W:fill()
    self.list:clear()
    for i, j in ipairs(Q.jobs) do
        local item = self.list:addItem(Craft.label(j.recipe), { job = j, n = i })
        local lines = (#j.steps > 1 or j.why) and (#j.steps + (j.why and 1 or 0)) or 0
        item.height = ROW_BASE + lines * (UI.HS + 4) + (lines > 0 and 6 or 0) + 8
    end
    self.pauseBtn:setTitle(Q.paused and t("Resume") or t("Pause"))
    self.pauseBtn:setIcon(Q.paused and "play" or "pause")
    self.pauseBtn:setKind(Q.paused and "pri" or "sec")
    self.policy.sel = Q.policy
    self.subtitle = t("QueueSub", Q.count())
end

local ST = {
    wait = { fg = K.text2, bg = K.surf2 },
    run  = { fg = K.acc, bg = K.accD },
    done = { fg = K.acc, bg = K.accD },
    warn = { fg = K.bad, bg = K.badD },
}

function W.drawJob(self, list, d, x, y, w, h)
    local j = d.job
    if j.status == "run" then T.rring(list, x, y, w, h, UI.RC, Q.paused and K.warn or K.acc, K.surf, 2)
    elseif j.status == "warn" then T.rring(list, x, y, w, h, UI.RC, K.bad, K.surf, 2) end
    local a = j.status == "done" and 0.55 or 1
    local s = 40
    local sy = y + 6
    local out = Craft.mainOutput(j.recipe)
    T.slot(list, x + 10, sy, s, Craft.icon(j.recipe) or (out and Scan.itemTex(out)), nil)
    T.circle(list, x + 4, sy - 4, UI.HS + 2, K.surf3)
    T.textC(list, tostring(d.n), x + 4 + (UI.HS + 2) / 2, sy - 3, K.text)
    local tx = x + 10 + s + 12
    local name = Craft.label(j.recipe) .. "  ×" .. tostring(j.qty)
    T.text(list, T.fit(name, w - 330), tx, sy + 2, K.text, T.FS, a)
    local px = tx + math.min(w - 330, T.tw(name)) + 10
    if j.link then px = px + T.pill(list, px, sy + 1, "Link", K.acc, K.accD, T.FS, { ic = "link" }) + 6 end
    if j.house then px = px + T.pill(list, px, sy + 1, t("WholeHouseTag"), K.warn, K.warnD) + 6 end
    local stl = j.status == "run" and (Q.paused and t("St_Paused") or t("St_Running")) or t("St_" .. j.status)
    local st = ST[j.status] or ST.wait
    if j.status == "run" and Q.paused then st = { fg = K.warn, bg = K.warnD } end
    T.pill(list, px, sy + 1, stl, st.fg, st.bg)
    -- progress line
    if j.status == "run" then
        local step = j.steps[j.stepIdx]
        local txt = step and t("Q_Step", j.stepIdx, #j.steps, Craft.label(step.recipe), j.stepDone, step.qty) or ""
        T.text(list, T.fit(txt, w - 220), tx, sy + UI.HS + 6, K.text3)
    elseif j.status == "done" then
        T.text(list, t("Q_DoneN", j.qty), tx, sy + UI.HS + 6, K.text3, T.FS, a)
    end
    -- buttons: up / down / remove
    d.hits = {}
    local bs = 30
    local bx = x + w - 10 - bs * 3 - 12
    local mx = list:getMouseX()
    local my = list:getMouseY()
    local overRow = my >= y and my < y + h
    for i, kind in ipairs({ "up", "down", "close" }) do
        local cx = bx + (i - 1) * (bs + 6)
        local hov = overRow and mx >= cx and mx < cx + bs
        local bg = kind == "close" and (hov and T.rgb("5A2C33") or K.badD) or (hov and K.surf3 or K.surf2)
        T.rrect(list, cx, sy + 4, bs, bs, 8, bg)
        T.icon(list, kind, cx + 7, sy + 11, bs - 14, kind == "close" and K.bad or K.text2)
        d.hits[#d.hits + 1] = { x = cx, w = bs, kind = kind }
    end
    -- steps
    if #j.steps > 1 or j.why then
        local ly = sy + s + 8
        for i, stp in ipairs(j.steps) do
            local mark, col, tc = "dot", K.text3, K.text
            if j.status == "done" or (j.status == "run" and i < j.stepIdx) then mark, col, tc = "check", K.acc, K.text3
            elseif j.status == "run" and i == j.stepIdx then mark, col = "chev", K.acc end
            T.icon(list, mark, tx, ly + 2, UI.HS - 2, col)
            local label = t("Q_StepLine", Craft.label(stp.recipe), stp.qty)
            T.text(list, T.fit(label, w - (tx - x) - 30), tx + UI.HS + 4, ly, tc, T.FS, a)
            ly = ly + UI.HS + 4
        end
        if j.why then
            T.icon(list, "warn", tx, ly + 2, UI.HS - 2, K.bad)
            T.text(list, T.fit(j.why, w - (tx - x) - 30), tx + UI.HS + 4, ly, K.bad)
        end
    end
end

function W:drawBody()
    -- now-running card
    local x, y, w = UI.PAD, UI.HEAD_H + 4, self.width - UI.PAD * 2
    local hh = 74
    T.rrect(self, x, y, w, hh, 14, K.surf)
    local run = Q.running
    local txt, col, frac = t("QueueIdle"), K.text3, 0
    if run then
        local step = run.steps[run.stepIdx]
        txt = (Q.paused and t("Q_PausedAt") or t("Q_Now")) .. "  " .. Craft.label(run.recipe) .. "  " .. tostring(run.done) .. "/" .. tostring(run.qty)
        if Q.loop then txt = txt .. "  ·  " .. t("LoopRound", Q.round) end
        col = Q.paused and K.warn or K.acc
        local total, doneN = 0, 0
        for i, s in ipairs(run.steps) do
            total = total + s.qty
            if i < run.stepIdx then doneN = doneN + s.qty elseif i == run.stepIdx then doneN = doneN + (run.stepDone or 0) end
        end
        frac = total > 0 and doneN / total or 0
        if step then T.textR(self, t("Q_StepOf", run.stepIdx, #run.steps), x + w - 16, y + 12, K.text3) end
    elseif Q.paused then
        txt, col = t("QueuePaused"), K.warn
    end
    T.text(self, T.fit(txt, w - 140), x + 16, y + 12, col)
    T.rrect(self, x + 16, y + 20 + UI.HS, w - 32, 8, 4, K.bar)
    if frac > 0 then T.rrect(self, x + 16, y + 20 + UI.HS, math.max(8, (w - 32) * frac), 8, 4, K.acc) end
    T.text(self, T.fit(t("QueueHint"), w - 32), x + 16, y + 34 + UI.HS, K.text3)
    -- footer
    local fy = self.policy:getY()
    T.text(self, t("IfMissing"), UI.PAD, fy + floor((self.policy.height - UI.HS) / 2), K.text3)
    T.text(self, T.fit(t("QueueFoot"), self.width - UI.PAD * 2), UI.PAD, fy + self.policy.height + 8, K.text3)
    if #Q.jobs == 0 then
        T.textC(self, t("QueueEmpty"), self.width / 2, self.list:getY() + 30, K.text3)
    end
end

function W:onPause() Q.setPaused(not Q.paused) end
function W:onClear() Q.clearDone() end
function W:onPolicy(id) Q.setPolicy(id) end
function W:onLoop() Q.setLoop(not Q.loop) end

function Q.open()
    if Q.instance then Q.instance:bringToTop() return Q.instance end
    local w, h = 620, 640
    local x, y = UI.center(w, h)
    local win = W:new(x + 200, y, w, h, t("QueueTitle"))
    win.headIcon = "cookie_64"
    win:show()
    Q.instance = win
    return win
end
