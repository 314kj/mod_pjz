-- CookieServerPatch: admin build plan, server side. Target: vanilla B42 build (ISBuildIsoEntity), 42.22.
-- save-bound: no (it builds ordinary vanilla objects; removing this file changes nothing in the world)
--
-- Problem (14 Nov 2026): an admin building with "instant" timed actions gets stuck
-- ("loading" forever) and has to place pieces one at a time. In multiplayer every
-- piece is its own timed action that waits for the server to answer, and the
-- game drops a player's packets of one type above MaxPacketsPerSecond (300),
-- so a fast run of instant actions can lose the answer it waits for.
--
-- What this does: the admin places pieces from the build menu into a plan (the
-- client part, client/CSP_AdminBuildPlan.lua, records them, nothing is sent per
-- piece). "Build all" sends the plan here in parts; the server builds the pieces
-- itself, a few milliseconds per tick, with the game's own build code
-- (ISBuildIsoEntity:new + Actions.build, the same path a finished build action
-- takes on the server), with Build Cheat on for that moment only (no materials,
-- nothing taken from anyone). Lower levels first; pieces that fail are tried once
-- more at the end (a window frame placed before its wall); pieces that still fail
-- stay in the admin's plan.
--
-- Players near the plan: when a player builds, the game rebuilds the rooms of
-- the player-made buildings in that 256 x 256 cell on every client, and a player
-- whose map is loading there at that moment can be thrown to the main menu
-- (IsoRoom.hasLightSwitches crash). Before building, the server counts other players in the cells
-- the plan touches (plus NEAR_MARGIN tiles); if there are any, the admin is asked
-- to confirm first.
--
-- Who: only players whose role may use Build Cheat (the server checks every
-- command; the game itself keeps Build Cheat off for anyone else).
--
-- Log: "[CookieServerPatch] admin-build-plan on" once, then one line when a plan
-- starts and one when it ends (user, pieces, built, failed, time).
-- ASCII only. No next() (Kahlua).

if isClient() then return end

local TAG = "[CookieServerPatch] admin-build-plan"
local MODULE = "CSPBuildPlan"

-- settings ------------------------------------------------------------------
local MAX_PIECES = 3000      -- per plan
local PART_MAX = 100         -- pieces per client command (the client sends the same)
local TICK_BUDGET_MS = 15    -- server time per tick spent building (at least 1 piece); a tick is 100 ms
local CELL = 256             -- IsoCell.CELL_SIZE_IN_SQUARES
local NEAR_MARGIN = 80       -- tiles around the touched cells where other players count as near
local PROGRESS_MS = 500      -- progress message at most this often
local WAIT_MS = 120000       -- plan parts not complete / confirm not answered: dropped after this
------------------------------------------------------------------------------

local jobs = {}   -- [username] = job
local jobCount = 0

local function isSP()
    return not isClient() and not isServer()
end

local function userOf(p)
    local u = nil
    pcall(function() u = p:getUsername() end)
    return tostring(u)
end

-- multiplayer only: in single player ISBuildIsoEntity:create reads the cursor's
-- player number (getSpecificPlayer(self.player)), which a piece made here does not have
local function mayBuild(p)
    if isSP() then return false end
    local ok, yes = pcall(function()
        local role = p:getRole()
        if not role then return false end
        return role:hasCapability(Capability.UseBuildCheat) == true
    end)
    return ok and yes == true
end

local function send(p, command, args)
    pcall(function() sendServerCommand(p, MODULE, command, args or {}) end)
end

local function dropJob(user)
    if jobs[user] then
        jobs[user] = nil
        jobCount = jobCount - 1
    end
end

local function isInt(v)
    return type(v) == "number" and v == math.floor(v) and v > -100000 and v < 100000
end

-- one piece as sent by the client; nil when anything is off
local function readPiece(t)
    if type(t) ~= "table" then return nil end
    if type(t.name) ~= "string" or #t.name == 0 or #t.name > 200 then return nil end
    if not (isInt(t.x) and isInt(t.y) and isInt(t.z)) then return nil end
    if t.z < -32 or t.z > 31 then return nil end
    if not (isInt(t.s) and t.s >= 1 and t.s <= 4) then return nil end
    local p = { name = t.name, x = t.x, y = t.y, z = t.z, s = t.s, north = t.north == true,
        spr = type(t.spr) == "string" and t.spr or "" }
    -- the tile used to see whether the piece was really built
    if isInt(t.cx) and isInt(t.cy) and isInt(t.cz) and type(t.cs) == "string" and #t.cs > 0 then
        p.cx, p.cy, p.cz, p.cs = t.cx, t.cy, t.cz, t.cs
    end
    return p
end

-- objects on a square that use this sprite, and all objects on it
local function countSprite(x, y, z, name)
    local n, all = 0, 0
    pcall(function()
        local sq = getCell():getGridSquare(x, y, z)
        if not sq then return end
        local objs = sq:getObjects()
        all = objs:size()
        for i = 0, all - 1 do
            local spr = objs:get(i):getSprite()
            if spr and spr:getName() == name then n = n + 1 end
        end
    end)
    return n, all
end

local function loaded(x, y)
    local sq = nil
    pcall(function() sq = getCell():getGridSquare(x, y, 0) end)
    return sq ~= nil
end

local function online(p)
    if isSP() then return true end
    local yes = false
    pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            if list:get(i) == p then
                yes = true
                return
            end
        end
    end)
    return yes
end

-- other players in the 256 x 256 cells the plan touches, plus NEAR_MARGIN tiles
local function nearCount(job)
    local minX, minY, maxX, maxY
    for k = 1, #job.pieces do
        local p = job.pieces[k]
        local cx, cy = math.floor(p.x / CELL), math.floor(p.y / CELL)
        if not minX or cx < minX then minX = cx end
        if not maxX or cx > maxX then maxX = cx end
        if not minY or cy < minY then minY = cy end
        if not maxY or cy > maxY then maxY = cy end
    end
    if not minX then return 0 end
    local x1, y1 = minX * CELL - NEAR_MARGIN, minY * CELL - NEAR_MARGIN
    local x2, y2 = (maxX + 1) * CELL + NEAR_MARGIN, (maxY + 1) * CELL + NEAR_MARGIN
    local n = 0
    pcall(function()
        local list = getOnlinePlayers()
        if not list then return end
        for i = 0, list:size() - 1 do
            local q = list:get(i)
            if q ~= job.player then
                local x, y = q:getX(), q:getY()
                if x >= x1 and x < x2 and y >= y1 and y < y2 then n = n + 1 end
            end
        end
    end)
    return n
end

-- "ok" | "fail" | "notloaded"
local function buildOne(job, p)
    if not loaded(p.x, p.y) then return "notloaded" end
    local info = SpriteConfigManager.GetObjectInfo(p.name)
    if not info then return "fail" end
    local before, beforeAll = 0, 0
    if p.cs then before, beforeAll = countSprite(p.cx, p.cy, p.cz, p.cs) end
    local item = ISBuildIsoEntity:new(job.player, info, p.s, ArrayList.new(), nil)
    Actions.build(job.player, { item = item, x = p.x, y = p.y, z = p.z, north = p.north, spriteName = p.spr })
    if p.cs then
        -- built = the piece's first tile shows up, or anything new appeared on that square
        -- (counting a built piece as failed would build it twice in the retry pass)
        local after, afterAll = countSprite(p.cx, p.cy, p.cz, p.cs)
        if after <= before and afterAll <= beforeAll then return "fail" end
    end
    return "ok"
end

local function finish(user, job, stopped)
    local failed = {}
    for k = 1, #job.failed do failed[k] = job.failed[k] end
    -- stopped early: pieces not tried yet go back too (the client keeps exactly this list)
    if stopped and job.order then
        if job.pass == 1 then
            for k = job.pos, #job.order do failed[#failed + 1] = job.order[k] end
            for k = 1, #job.retry do failed[#failed + 1] = job.retry[k] end
        else
            for k = job.pos, #job.retry do failed[#failed + 1] = job.retry[k] end
        end
    end
    send(job.player, "done", { job = job.id, built = job.built, failed = failed, nfailed = #failed,
        notLoaded = job.notLoaded, ms = getTimestampMs() - job.t0, stopped = stopped == true })
    print(TAG .. ": " .. user .. " done, built " .. job.built .. " of " .. #job.pieces .. ", not built "
        .. #failed .. " (map not loaded " .. job.notLoaded .. "), " .. (getTimestampMs() - job.t0) .. " ms"
        .. (stopped and ", stopped" or ""))
    dropJob(user)
end

-- lower levels first, then the order the admin placed them; broken slots left out
local function buildOrder(pieces)
    local order = {}
    for k = 1, #pieces do
        if not pieces[k].bad then order[#order + 1] = k end
    end
    table.sort(order, function(a, b)
        local za, zb = pieces[a].z, pieces[b].z
        if za ~= zb then return za < zb end
        return a < b
    end)
    return order
end

local function start(user, job)
    job.running = true
    job.order = buildOrder(job.pieces)
    job.pos, job.retry, job.pass = 1, {}, 1
    job.built, job.notLoaded, job.failed = 0, 0, {}
    -- broken slots (bad data from the client) come back as not built
    for k = 1, #job.pieces do
        if job.pieces[k].bad then job.failed[#job.failed + 1] = k end
    end
    job.t0, job.lastProgress = getTimestampMs(), 0
    send(job.player, "start", { job = job.id, total = #job.order })
    print(TAG .. ": " .. user .. " start " .. #job.order .. " pieces, other players near " .. tostring(job.near))
end

-- next piece index to build, nil when both passes are done
local function nextIndex(job)
    if job.pass == 1 then
        if job.pos <= #job.order then
            local k = job.order[job.pos]
            job.pos = job.pos + 1
            return k
        end
        job.pass, job.pos = 2, 1
    end
    if job.pos <= #job.retry then
        local k = job.retry[job.pos]
        job.pos = job.pos + 1
        return k
    end
    return nil
end

local function step(user, job)
    local p = job.player
    local prev = false
    pcall(function() prev = p:isBuildCheat() end)
    job.cheatBefore = prev
    pcall(function() p:setBuildCheat(true) end)
    local t0 = getTimestampMs()
    local done = false
    repeat
        local k = nextIndex(job)
        if not k then
            done = true
            break
        end
        local ok, res = pcall(buildOne, job, job.pieces[k])
        if ok and res == "ok" then
            job.built = job.built + 1
        elseif ok and res == "notloaded" then
            job.notLoaded = job.notLoaded + 1
            job.failed[#job.failed + 1] = k
        elseif job.pass == 1 then
            job.retry[#job.retry + 1] = k
        else
            job.failed[#job.failed + 1] = k
            if not ok and job.errors < 3 then
                job.errors = job.errors + 1
                print(TAG .. ": piece error " .. tostring(res))
            end
        end
    until getTimestampMs() - t0 >= TICK_BUDGET_MS
    pcall(function() p:setBuildCheat(prev) end)
    if done then
        finish(user, job, false)
        return
    end
    local now = getTimestampMs()
    if now - job.lastProgress >= PROGRESS_MS then
        job.lastProgress = now
        local handled = job.pass == 1 and (job.pos - 1) or (#job.order - #job.retry + job.pos - 1)
        send(p, "progress", { job = job.id, done = handled, built = job.built, total = #job.order })
    end
end

local function onTick()
    if jobCount <= 0 then return end
    local now = getTimestampMs()
    -- jobs are dropped after the loop (no table changes while pairs() walks it)
    local list = {}
    for user, job in pairs(jobs) do list[#list + 1] = { user = user, job = job } end
    for k = 1, #list do
        local user, job = list[k].user, list[k].job
        if not online(job.player) then
            print(TAG .. ": " .. user .. " left, plan dropped (built " .. tostring(job.built or 0) .. ")")
            dropJob(user)
        elseif job.running then
            local ok, err = pcall(step, user, job)
            if not ok then
                print(TAG .. ": stopped by error " .. tostring(err))
                pcall(function() job.player:setBuildCheat(job.cheatBefore == true) end)
                pcall(finish, user, job, true)
                dropJob(user)
            end
        elseif now - job.t >= WAIT_MS then
            send(job.player, "error", { job = job.id, code = "timeout" })
            dropJob(user)
        end
    end
end

local function onPart(p, user, args)
    local job = jobs[user]
    if job and job.running then
        send(p, "error", { job = args.job, code = "busy" })
        return
    end
    if args.i == 1 then
        if job then dropJob(user) end
        if not (isInt(args.n) and args.n >= 1 and isInt(args.total) and args.total >= 1) then
            send(p, "error", { job = args.job, code = "parts" })
            return
        end
        if args.total > MAX_PIECES or args.n > math.ceil(MAX_PIECES / PART_MAX) then
            send(p, "error", { job = args.job, code = "size", max = MAX_PIECES })
            return
        end
        job = { id = args.job, player = p, parts = args.n, total = args.total, got = 0,
            pieces = {}, bad = 0, t = getTimestampMs(), running = false, errors = 0 }
        jobs[user] = job
        jobCount = jobCount + 1
    end
    if not job or job.id ~= args.job or args.i ~= job.got + 1 then
        if job then dropJob(user) end
        send(p, "error", { job = args.job, code = "parts" })
        return
    end
    job.got = job.got + 1
    local list = args.pieces
    if type(list) == "table" then
        for k = 1, PART_MAX do
            local raw = list[k]
            if raw == nil then break end
            local piece = readPiece(raw)
            if piece then
                job.pieces[#job.pieces + 1] = piece
            else
                job.bad = job.bad + 1
                -- keep the client's numbering: a broken piece stays a failed slot
                job.pieces[#job.pieces + 1] = { bad = true, name = "", x = 0, y = 0, z = 0, s = 1 }
            end
        end
    end
end

local function onGo(p, user, args)
    local job = jobs[user]
    if not job or job.id ~= args.job or job.running then
        send(p, "error", { job = args.job, code = "parts" })
        return
    end
    if job.got ~= job.parts or #job.pieces ~= job.total then
        dropJob(user)
        send(p, "error", { job = args.job, code = "parts" })
        return
    end
    -- broken pieces are never built; they come back as failed
    local good = {}
    local missing = 0
    for k = 1, #job.pieces do
        local piece = job.pieces[k]
        if not piece.bad then
            good[#good + 1] = piece
            if not loaded(piece.x, piece.y) then missing = missing + 1 end
        end
    end
    if missing > 0 then
        dropJob(user)
        send(p, "error", { job = args.job, code = "notloaded", n = missing })
        return
    end
    job.near = nearCount({ pieces = good, player = p })
    if job.near > 0 and args.force ~= true then
        job.t = getTimestampMs()
        send(p, "confirm", { job = job.id, near = job.near, total = #good })
        return
    end
    start(user, job)
end

local function onCommand(module, command, p, args)
    if module ~= MODULE then return end
    if type(args) ~= "table" then return end
    local user = userOf(p)
    if not mayBuild(p) then
        send(p, "error", { job = args.job, code = "admin" })
        return
    end
    if command == "part" then
        onPart(p, user, args)
    elseif command == "go" then
        onGo(p, user, args)
    elseif command == "cancel" then
        local job = jobs[user]
        if job and job.id == args.job then
            if job.running then
                finish(user, job, true)
            else
                dropJob(user)
            end
        end
    end
end

Events.OnClientCommand.Add(function(module, command, p, args)
    if module ~= MODULE then return end
    local ok, err = pcall(onCommand, module, command, p, args)
    if not ok then print(TAG .. ": command error " .. tostring(err)) end
end)
Events.OnTick.Add(onTick)

-- for the mock test
CSPBuildPlanServer = { jobs = function() return jobs end, buildOrder = buildOrder, readPiece = readPiece }

print(TAG .. " on")
