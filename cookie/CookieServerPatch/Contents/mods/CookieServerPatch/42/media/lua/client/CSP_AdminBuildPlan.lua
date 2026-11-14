-- CookieServerPatch: admin build plan, client side. Target: vanilla B42 build cursor (ISBuildIsoEntity), 42.22.
-- save-bound: no
--
-- How to use (admins whose role may use Build Cheat):
--   * right-click the ground -> "Build plan (admin)": a small window opens and
--     plan mode is on while it is open.
--   * pick a piece in the build menu (vanilla or Neat Building) and click: the
--     piece goes into the plan instead of starting a build action. Pieces in the
--     plan show as light blue ghosts while a build cursor is out, and as small
--     dots on the ground.
--   * Shift + click: from the last piece of the same kind on the same level, a
--     line of walls (along the wall) or an area of floor-like pieces (at most
--     FILL_MAX pieces and GHOST_RANGE tiles; bigger = only the clicked piece).
--   * "Build all": the plan goes to the server, which builds it a few
--     milliseconds per server tick (server/CSP_AdminBuildPlan.lua); the button
--     turns into "Stop" meanwhile. Pieces it could not build stay in the plan.
--   * Multiplayer only (in single player the menu does not show).
--   * "Turn on Build Cheat" in the window is put back off when the window closes.
--   * Pieces that need another planned piece to exist first (a floor on level 2,
--     a door in a planned frame) cannot be placed yet: build, then plan the rest.
-- Other cursors (moving furniture, sledgehammer, Building Craft) work as usual.
-- Outside plan mode nothing changes: the game's own tryBuild runs.
--
-- The plan is kept in Zomboid\Lua\CSP_BuildPlan.txt (survives a crash or relog).
-- ASCII only. No next() (Kahlua). No percent sign in translation strings.

if isServer() then return end

local TAG = "[CookieServerPatch] admin-build-plan"
local MODULE = "CSPBuildPlan"
local FILE = "CSP_BuildPlan.txt"

-- settings ------------------------------------------------------------------
local MAX_PIECES = 3000      -- same as the server
local PART_MAX = 100         -- same as the server
local FILL_MAX = 400         -- pieces added by one Shift + click
local GHOST_RANGE = 60       -- tiles from the player
local GHOST = { 0.45, 0.8, 1.0, 0.5 }
local MARK = { 0.3, 0.75, 1.0 }
local MARK_RANGE = 80
local MARK_MAX = 600
local ANSWER_MS = 60000      -- no word from the server for this long: give up waiting
------------------------------------------------------------------------------

local BP = { on = false, plan = {}, keys = {}, busy = nil, status = "", panel = nil, marks = {} }
CSPBuildPlan = BP

local function T(key)
    return getText(key)
end

local function player()
    return getSpecificPlayer(0)
end

local function isSP()
    return not isClient() and not isServer()
end

-- dedicated / hosted multiplayer only: in single player the game's build code
-- reads the cursor's player number, which a server-made piece does not have
function BP.mayUse(p)
    if isSP() then return false end
    if not p then return false end
    local ok, yes = pcall(function()
        local role = p:getRole()
        if not role then return false end
        return role:hasCapability(Capability.UseBuildCheat) == true
    end)
    return ok and yes == true
end

local function halo(text, good)
    local p = player()
    if not p then return end
    pcall(function()
        local col = good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
        HaloTextHelper.addText(p, text, "", col)
    end)
end

local function keyOf(pc)
    return pc.name .. "|" .. pc.x .. "," .. pc.y .. "," .. pc.z .. "|" .. pc.s
end

-- printable ASCII without the plan file's separators (tab , ;)
local function ascii(s)
    if type(s) ~= "string" then return false end
    for i = 1, #s do
        local b = s:byte(i)
        if b < 32 or b > 126 or b == 44 or b == 59 then return false end
    end
    return true
end

-- ------------------------------------------------------------------ plan file
local function save()
    local ok, err = pcall(function()
        local w = getFileWriter(FILE, true, false)
        w:write("v1\n")
        for k = 1, #BP.plan do
            local pc = BP.plan[k]
            local t = {}
            for i = 1, #pc.tiles do
                local tl = pc.tiles[i]
                t[#t + 1] = tl[1] .. "," .. tl[2] .. "," .. tl[3] .. "," .. tl[4]
            end
            w:write(pc.name .. "\t" .. pc.x .. "\t" .. pc.y .. "\t" .. pc.z .. "\t" .. pc.s .. "\t"
                .. (pc.north and "1" or "0") .. "\t" .. pc.spr .. "\t" .. table.concat(t, ";") .. "\n")
        end
        w:close()
    end)
    if not ok then print(TAG .. ": save failed " .. tostring(err)) end
end

local function split(s, sep)
    local out = {}
    local from = 1
    while true do
        local i = s:find(sep, from)          -- separators are tab , ; (not pattern characters)
        if not i then
            out[#out + 1] = s:sub(from)
            return out
        end
        out[#out + 1] = s:sub(from, i - 1)
        from = i + #sep
    end
end

function BP.parseLine(line)
    local f = split(line, "\t")
    if #f < 8 then return nil end
    local pc = { name = f[1], x = tonumber(f[2]), y = tonumber(f[3]), z = tonumber(f[4]), s = tonumber(f[5]),
        north = f[6] == "1", spr = f[7], tiles = {} }
    if not (pc.x and pc.y and pc.z and pc.s) or pc.name == "" then return nil end
    if f[8] ~= "" then
        local parts = split(f[8], ";")
        for i = 1, #parts do
            local q = split(parts[i], ",")
            if #q == 4 and tonumber(q[1]) and tonumber(q[2]) and tonumber(q[3]) and q[4] ~= "" then
                pc.tiles[#pc.tiles + 1] = { tonumber(q[1]), tonumber(q[2]), tonumber(q[3]), q[4] }
            end
        end
    end
    return pc
end

local function load()
    BP.plan, BP.keys = {}, {}
    pcall(function()
        local r = getFileReader(FILE, false)
        if not r then return end
        local first = r:readLine()
        if first == "v1" then
            while true do
                local line = r:readLine()
                if not line then break end
                local pc = BP.parseLine(line)
                if pc and not BP.keys[keyOf(pc)] and #BP.plan < MAX_PIECES then
                    BP.plan[#BP.plan + 1] = pc
                    BP.keys[keyOf(pc)] = true
                end
            end
        end
        r:close()
    end)
end

-- ------------------------------------------------------------------ ground dots
local function clearMarks()
    for i = #BP.marks, 1, -1 do
        pcall(function() BP.marks[i]:remove() end)
        BP.marks[i] = nil
    end
end

local function drawMarks()
    clearMarks()
    if not BP.on then return end
    local p = player()
    local cell = getCell()
    if not p or not cell then return end
    local px, py = p:getX(), p:getY()
    BP.markAt = { px, py }
    local seen = {}
    for k = 1, #BP.plan do
        if #BP.marks >= MARK_MAX then break end
        local pc = BP.plan[k]
        local key = pc.x .. "," .. pc.y .. "," .. pc.z
        if not seen[key] and math.abs(pc.x - px) <= MARK_RANGE and math.abs(pc.y - py) <= MARK_RANGE then
            seen[key] = true
            local sq = cell:getGridSquare(pc.x, pc.y, pc.z)
            if sq then
                local ok, m = pcall(function()
                    return getWorldMarkers():addGridSquareMarker(sq, MARK[1], MARK[2], MARK[3], false, 0.35)
                end)
                if ok and m then BP.marks[#BP.marks + 1] = m end
            end
        end
    end
end

-- ------------------------------------------------------------------ ghosts
local sprites = {}

local function sprite(name)
    local s = sprites[name]
    if s == nil then
        s = false
        pcall(function()
            local spr = IsoSprite.new()
            spr:LoadSingleTexture(name)
            s = spr
        end)
        sprites[name] = s
    end
    return s or nil
end

local function drawGhosts()
    local p = player()
    if not p then return end
    local px, py = p:getX(), p:getY()
    local r, g, b, a = GHOST[1], GHOST[2], GHOST[3], GHOST[4]
    for k = 1, #BP.plan do
        local pc = BP.plan[k]
        if math.abs(pc.x - px) <= GHOST_RANGE and math.abs(pc.y - py) <= GHOST_RANGE then
            for i = 1, #pc.tiles do
                local tl = pc.tiles[i]
                local spr = sprite(tl[4])
                if spr then spr:RenderGhostTileColor(pc.x + tl[1], pc.y + tl[2], pc.z + tl[3], r, g, b, a) end
            end
        end
    end
end

-- ------------------------------------------------------------------ plan edits
-- the piece the cursor would build at x, y, z, as the server needs it
function BP.capture(item, x, y, z)
    local spr = item:getSprite()          -- also sets item.north / west from nSprite (as tryBuild does)
    local face = item:getFace()
    local tiles = {}
    if face then
        for zz = 0, face:getzLayers() - 1 do
            for xx = 0, face:getWidth() - 1 do
                for yy = 0, face:getHeight() - 1 do
                    local info = face:getTileInfo(xx, yy, zz)
                    local name = info and info:getSpriteName()
                    if name and ascii(name) then tiles[#tiles + 1] = { xx, yy, zz, name } end
                end
            end
        end
    end
    local name = item.objectInfo and item.objectInfo:getName()
    if not ascii(name) then return nil end
    if type(spr) ~= "string" or not ascii(spr) then spr = "" end
    return { name = name, x = x, y = y, z = z, s = item.nSprite, north = item.north == true, spr = spr, tiles = tiles }
end

local function addPiece(pc)
    if not pc then return false end
    local key = keyOf(pc)
    if BP.keys[key] then return false end
    if #BP.plan >= MAX_PIECES then
        halo(T("IGUI_CSP_BP_Full"), false)
        return false
    end
    BP.plan[#BP.plan + 1] = pc
    BP.keys[key] = true
    return true
end

-- squares from the last piece of the same kind (same level) to x, y
function BP.fillSquares(last, x, y, wallLike, north)
    local out = {}
    if not last then
        out[1] = { x, y }
        return out
    end
    local function range(a, b)
        if a <= b then return a, b, 1 end
        return a, b, -1
    end
    if wallLike then
        if north then
            local a, b, d = range(last.x, x)
            for xx = a, b, d do out[#out + 1] = { xx, y } end
        else
            local a, b, d = range(last.y, y)
            for yy = a, b, d do out[#out + 1] = { x, yy } end
        end
    else
        local ax, bx, dx = range(last.x, x)
        local ay, by, dy = range(last.y, y)
        for xx = ax, bx, dx do
            for yy = ay, by, dy do out[#out + 1] = { xx, yy } end
        end
    end
    return out
end

-- a Shift fill must stay near the player and small: checked before any list is made
function BP.fillFits(last, x, y, wallLike, north)
    local dx, dy = math.abs(x - last.x), math.abs(y - last.y)
    if dx > GHOST_RANGE or dy > GHOST_RANGE then return false end
    local n
    if wallLike then
        n = (north and dx or dy) + 1
    else
        n = (dx + 1) * (dy + 1)
    end
    return n <= FILL_MAX
end

local function lastOfKind(name, z)
    for k = #BP.plan, 1, -1 do
        local pc = BP.plan[k]
        if pc.name == name and pc.z == z then return pc end
    end
    return nil
end

local function shiftDown()
    local ok, yes = pcall(function()
        return isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT)
    end)
    return ok and yes == true
end

local function addFromCursor(item, x, y, z)
    if BP.busy then
        halo(T("IGUI_CSP_BP_Wait"), false)
        return
    end
    local first = BP.capture(item, x, y, z)
    if not first then return end
    local added = 0
    local last = shiftDown() and lastOfKind(first.name, z) or nil
    if last and not BP.fillFits(last, x, y, item.isWallLike == true, first.north) then
        halo(T("IGUI_CSP_BP_FillTooBig"), false)
        last = nil
    end
    if last then
        local squares = BP.fillSquares(last, x, y, item.isWallLike == true, first.north)
        local cell = getCell()
        for i = 1, #squares do
            if added >= FILL_MAX then break end
            local sx, sy = squares[i][1], squares[i][2]
            local sq = cell:getGridSquare(sx, sy, z)
            local valid = false
            if sx == x and sy == y then
                valid = true                 -- the cursor already checked this one
            elseif sq then
                pcall(function() valid = item:isValid(sq) == true end)
            end
            if valid then
                local pc = (sx == x and sy == y) and first or BP.capture(item, sx, sy, z)
                if addPiece(pc) then added = added + 1 end
            end
        end
    elseif addPiece(first) then
        added = 1
    end
    if added > 0 then
        save()
        drawMarks()
    end
end

function BP.undo()
    if BP.busy or #BP.plan == 0 then return end
    local pc = BP.plan[#BP.plan]
    BP.plan[#BP.plan] = nil
    BP.keys[keyOf(pc)] = nil
    save()
    drawMarks()
end

function BP.clear()
    if BP.busy then return end
    BP.plan, BP.keys = {}, {}
    save()
    drawMarks()
end

-- ------------------------------------------------------------------ server
local function wire(pc)
    local t = { name = pc.name, x = pc.x, y = pc.y, z = pc.z, s = pc.s, north = pc.north, spr = pc.spr }
    local c = pc.tiles[1]
    if c then
        t.cx, t.cy, t.cz, t.cs = pc.x + c[1], pc.y + c[2], pc.z + c[3], c[4]
    end
    return t
end

function BP.sendPlan()
    local p = player()
    if not p or BP.busy or #BP.plan == 0 then return end
    local snap = {}
    for k = 1, #BP.plan do snap[k] = BP.plan[k] end
    local id = getTimestampMs() % 1000000000
    BP.busy = { id = id, snapshot = snap, heard = getTimestampMs() }
    BP.status = T("IGUI_CSP_BP_Sending")
    local parts = math.ceil(#snap / PART_MAX)
    for i = 1, parts do
        local pieces = {}
        local from = (i - 1) * PART_MAX + 1
        local to = math.min(#snap, i * PART_MAX)
        for k = from, to do pieces[#pieces + 1] = wire(snap[k]) end
        sendClientCommand(p, MODULE, "part", { job = id, i = i, n = parts, total = #snap, pieces = pieces })
    end
    sendClientCommand(p, MODULE, "go", { job = id, force = false })
end

local function onConfirm(target, button, job)
    local p = player()
    if not p or not BP.busy or BP.busy.id ~= job then return end
    BP.busy.confirming = false
    if button and button.internal == "YES" then
        BP.busy.heard = getTimestampMs()
        sendClientCommand(p, MODULE, "go", { job = job, force = true })
    else
        sendClientCommand(p, MODULE, "cancel", { job = job })
        BP.busy = nil
        BP.status = T("IGUI_CSP_BP_Canceled")
    end
end

-- lines no wider than maxW pixels, broken at spaces (a word longer than that keeps its own line)
function BP.wrap(text, font, maxW)
    local tm = getTextManager()
    local words = split(text, " ")
    local lines, cur = {}, ""
    for i = 1, #words do
        local w = words[i]
        local try = cur == "" and w or (cur .. " " .. w)
        if cur ~= "" and tm:MeasureStringX(font, try) > maxW then
            lines[#lines + 1] = cur
            cur = w
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

local function dialog(text, onclick, param)
    local w, h = 440, 170
    text = table.concat(BP.wrap(text, UIFont.Small, w - 40), "\n")
    local x = math.floor((getCore():getScreenWidth() - w) / 2)
    local y = math.floor((getCore():getScreenHeight() - h) / 2)
    local dlg = ISModalDialog:new(x, y, w, h, text, true, nil, onclick, 0, param)
    dlg:initialise()
    dlg:addToUIManager()
end

local ERRORS = {
    admin = "IGUI_CSP_BP_ErrAdmin", busy = "IGUI_CSP_BP_ErrBusy", size = "IGUI_CSP_BP_ErrSize",
    parts = "IGUI_CSP_BP_ErrParts", timeout = "IGUI_CSP_BP_ErrTimeout", notloaded = "IGUI_CSP_BP_ErrNotLoaded",
}

function BP.onServer(command, args)
    if type(args) ~= "table" then return end
    local busy = BP.busy
    if not busy or args.job ~= busy.id then return end
    busy.heard = getTimestampMs()
    if command == "confirm" then
        busy.confirming = true           -- no client timeout while the admin reads the question
        dialog(T("IGUI_CSP_BP_Near1") .. " " .. tostring(args.near) .. " " .. T("IGUI_CSP_BP_Near2"), onConfirm, busy.id)
    elseif command == "start" then
        busy.started = true
        BP.status = T("IGUI_CSP_BP_Building") .. " 0 / " .. tostring(args.total)
    elseif command == "progress" then
        BP.status = T("IGUI_CSP_BP_Building") .. " " .. tostring(args.done) .. " / " .. tostring(args.total)
    elseif command == "done" then
        local keep = {}
        local failed = type(args.failed) == "table" and args.failed or {}
        local n = tonumber(args.nfailed) or 0
        for k = 1, n do
            local idx = tonumber(failed[k])
            local pc = idx and busy.snapshot[idx]
            if pc then keep[#keep + 1] = pc end
        end
        BP.plan, BP.keys = keep, {}
        for k = 1, #keep do BP.keys[keyOf(keep[k])] = true end
        BP.busy = nil
        BP.status = T("IGUI_CSP_BP_Built") .. " " .. tostring(args.built)
        if #keep > 0 then BP.status = BP.status .. " / " .. #keep .. " " .. T("IGUI_CSP_BP_NotBuilt") end
        if args.stopped then BP.status = BP.status .. " " .. T("IGUI_CSP_BP_Stopped") end
        save()
        drawMarks()
    elseif command == "error" then
        BP.busy = nil
        local text = T(ERRORS[args.code] or "IGUI_CSP_BP_ErrParts")
        if args.code == "notloaded" then text = text .. " " .. tostring(args.n) end
        BP.status = text
        halo(text, false)
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE then return end
    local ok, err = pcall(BP.onServer, command, args)
    if not ok then print(TAG .. ": server message error " .. tostring(err)) end
end)

-- ------------------------------------------------------------------ window
local Panel = ISCollapsableWindow:derive("CSPBuildPlanPanel")
local W, H = 520, 340
local PAD, BH = 12, 36

function Panel:new(x, y)
    local o = ISCollapsableWindow.new(self, x, y, W, H)
    o.title = T("IGUI_CSP_BP_Title")
    o.resizable = false
    return o
end

local function button(self, x, y, w, key, fn)
    local b = ISButton:new(x, y, w, BH, T(key), self, fn)
    b:initialise()
    b:instantiate()
    b.font = UIFont.Medium
    self:addChild(b)
    return b
end

function Panel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local bw = math.floor((W - PAD * 3) / 2)
    local y = H - PAD - BH * 2 - 8
    self.btnBuild = button(self, PAD, y, bw, "IGUI_CSP_BP_Build", Panel.onBuild)
    self.btnUndo = button(self, PAD * 2 + bw, y, bw, "IGUI_CSP_BP_Undo", Panel.onUndo)
    y = y + BH + 8
    self.btnClear = button(self, PAD, y, bw, "IGUI_CSP_BP_Clear", Panel.onClear)
    self.btnCheat = button(self, PAD * 2 + bw, y, bw, "IGUI_CSP_BP_CheatOn", Panel.onCheat)
end

-- "Build all", or "Stop" while the server is building
function Panel:onBuild()
    local busy = BP.busy
    if busy and busy.started then
        local p = player()
        if p then sendClientCommand(p, MODULE, "cancel", { job = busy.id }) end
        return
    end
    BP.sendPlan()
end

function Panel:onUndo()
    BP.undo()
end

local function onClearAnswer(target, button)
    if button and button.internal == "YES" then BP.clear() end
end

function Panel:onClear()
    if #BP.plan > 0 and not BP.busy then dialog(T("IGUI_CSP_BP_ClearAsk"), onClearAnswer) end
end

local function cheatOn(p)
    local yes = false
    pcall(function() yes = p:isBuildCheat() == true end)
    return yes
end

-- same switch as the admin power window; put back when this window closes
local function setCheat(p, on)
    pcall(function()
        ISBuildMenu.cheat = on
        p:setBuildCheat(on)
        sendPlayerExtraInfo(p)
    end)
end

function Panel:onCheat()
    local p = player()
    if not p then return end
    setCheat(p, true)
    BP.cheatByUs = cheatOn(p)
end

function Panel:prerender()
    ISCollapsableWindow.prerender(self)
    local p = player()
    local n = #BP.plan
    local busy = BP.busy ~= nil
    if busy and not BP.busy.confirming and getTimestampMs() - BP.busy.heard > ANSWER_MS then
        BP.busy = nil
        BP.status = T("IGUI_CSP_BP_ErrTimeout")
        busy = false
    end
    local stop = busy and BP.busy.started == true
    self.btnBuild:setTitle(T(stop and "IGUI_CSP_BP_Stop" or "IGUI_CSP_BP_Build"))
    self.btnBuild:setEnable(stop or (not busy and n > 0))
    self.btnUndo:setEnable(not busy and n > 0)
    self.btnClear:setEnable(not busy and n > 0)
    self.btnCheat:setVisible(p ~= nil and not cheatOn(p))
    -- dots follow the player
    if p and BP.markAt and (math.abs(p:getX() - BP.markAt[1]) > 20 or math.abs(p:getY() - BP.markAt[2]) > 20) then
        drawMarks()
    end
end

function Panel:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    local x = PAD
    local y = self:titleBarHeight() + 10
    local small = getTextManager():getFontHeight(UIFont.Small) + 3
    local medium = getTextManager():getFontHeight(UIFont.Medium) + 4
    local maxW = W - PAD * 2
    local function lines(text, font, h, r, g, b, most)
        local list = BP.wrap(text, font, maxW)
        for i = 1, math.min(#list, most) do
            self:drawText(list[i], x, y, r, g, b, 1, font)
            y = y + h
        end
    end
    lines(T("IGUI_CSP_BP_Hint1"), UIFont.Small, small, 0.9, 0.9, 0.9, 2)
    lines(T("IGUI_CSP_BP_Hint2"), UIFont.Small, small, 0.9, 0.9, 0.9, 2)
    y = y + 6
    local zMin, zMax = nil, nil
    for k = 1, #BP.plan do
        local z = BP.plan[k].z
        if not zMin or z < zMin then zMin = z end
        if not zMax or z > zMax then zMax = z end
    end
    local count = T("IGUI_CSP_BP_Count") .. " " .. #BP.plan
    if zMin then
        count = count .. "   (" .. T("IGUI_CSP_BP_Levels") .. " " .. zMin .. (zMax ~= zMin and (" - " .. zMax) or "") .. ")"
    end
    self:drawText(count, x, y, 1, 1, 1, 1, UIFont.Medium)
    y = y + medium
    local p = player()
    if p and not cheatOn(p) then
        lines(T("IGUI_CSP_BP_CheatOff"), UIFont.Small, small, 1, 0.55, 0.45, 2)
    end
    y = y + 2
    if BP.status ~= "" then
        lines(BP.status, UIFont.Small, small, 0.55, 0.85, 1, 2)
    end
end

function Panel:close()
    local p = player()
    if p and BP.cheatByUs and cheatOn(p) then setCheat(p, false) end
    BP.cheatByUs = false
    BP.setOn(false)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    BP.panel = nil
end

function BP.setOn(on)
    BP.on = on == true
    drawMarks()
end

function BP.toggle()
    if BP.panel then
        BP.panel:close()
        return
    end
    local p = player()
    if not BP.mayUse(p) then
        halo(T("IGUI_CSP_BP_ErrAdmin"), false)
        return
    end
    local panel = Panel:new(80, 140)
    panel:initialise()
    panel:addToUIManager()
    BP.panel = panel
    BP.setOn(true)
end

-- ------------------------------------------------------------------ hooks
local function install()
    if BP.installed then return end
    if not ISBuildIsoEntity or type(ISBuildIsoEntity.tryBuild) ~= "function" or type(ISBuildIsoEntity.render) ~= "function" then
        print(TAG .. ": ISBuildIsoEntity not found, plan mode off")
        return
    end
    BP.installed = true
    local tryBuild = ISBuildIsoEntity.tryBuild
    ISBuildIsoEntity.tryBuild = function(self, x, y, z, ...)
        if not BP.on or not BP.mayUse(player()) then return tryBuild(self, x, y, z, ...) end
        local ok, err = pcall(addFromCursor, self, x, y, z)
        if not ok then print(TAG .. ": add failed " .. tostring(err)) end
        return nil
    end
    local render = ISBuildIsoEntity.render
    ISBuildIsoEntity.render = function(self, ...)
        local r = render(self, ...)
        if BP.on and #BP.plan > 0 then
            local ok, err = pcall(drawGhosts)
            if not ok and not BP.ghostError then
                BP.ghostError = true
                print(TAG .. ": ghost error " .. tostring(err))
            end
        end
        return r
    end
    load()
    print(TAG .. " on (plan file " .. #BP.plan .. " pieces)")
end

Events.OnGameStart.Add(install)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(function()
        if not BP.mayUse(getSpecificPlayer(playerNum)) or not BP.installed then return end
        local label = T("IGUI_CSP_BP_Menu")
        if #BP.plan > 0 then label = label .. " (" .. #BP.plan .. ")" end
        context:addOption(label, nil, function()
            local ok2, err2 = pcall(BP.toggle)
            if not ok2 then print(TAG .. ": open failed " .. tostring(err2)) end
        end)
    end)
    if not ok then print(TAG .. ": menu error " .. tostring(err)) end
end)

Events.OnPlayerDeath.Add(function(p)
    if BP.panel and p == player() then pcall(function() BP.panel:close() end) end
end)
