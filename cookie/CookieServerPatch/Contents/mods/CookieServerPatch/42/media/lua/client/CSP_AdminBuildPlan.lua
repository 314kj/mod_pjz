-- CookieServerPatch: admin build plan, client side. Target: vanilla B42 build cursor (ISBuildIsoEntity), 42.22.
-- save-bound: no
--
-- How to use (admins whose role may use Build Cheat):
--   * right-click the ground -> "Build plan (admin)": a window opens and plan
--     mode is on while it is open.
--   * pick a piece in the window's list (left: Vanilla -> the build menu's
--     categories; the search box finds pieces whose name holds every word typed,
--     in any order) or in the build menu (vanilla or Neat Building), then click
--     the ground: the piece goes into the plan instead of starting a build
--     action. Pieces in the plan show as light blue ghosts while a build cursor
--     is out, and as small dots on the ground.
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
--   * Building Craft (when on): its tiles are in the list too (Building Craft ->
--     tab -> type), and its own cursors also go into the plan while plan mode
--     is on. The server builds them with Building Craft's own classes. Its
--     garage doors are left out (their width is set in its own window).
-- Other cursors (moving furniture, sledgehammer) work as usual.
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

local BP = { on = false, plan = {}, keys = {}, busy = nil, status = "", panel = nil, marks = {},
    find = { node = "v", shown = {}, counts = {} } }
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
-- Building Craft's data for one of its tiles (tab, type, tile numbers), or nil
local function bcItem(i, k, n)
    if type(i) ~= "number" or type(k) ~= "number" or type(n) ~= "number" then return nil end
    local list = Building_Data and Building_Data.BuildingList
    local tab = type(list) == "table" and list[i]
    local typ = type(tab) == "table" and type(tab.subBuildData) == "table" and tab.subBuildData[k]
    local item = type(typ) == "table" and type(typ.ItemDate) == "table" and typ.ItemDate[n]
    if type(item) ~= "table" or type(item.Sprite) ~= "table" then return nil end
    return item
end

-- a garage door is as wide as the number in Building Craft's window (2 to 20), which a plan does not keep
local function bcGarage(item)
    return item.IsGarageDoor == true or (type(item.Default) == "table" and item.Default.IsGarageDoor == true)
end

-- a Building Craft piece: "BC:<tab>:<type>:<tile>:<the tile's first sprite>" (the server checks that sprite)
local function captureBC(item, x, y, z)
    local i, k, n = item.tabindex, item.listindex, item.sel
    local data = bcItem(i, k, n)
    if not data or bcGarage(data) or item.gridCount ~= nil then return nil end
    local s1 = data.Sprite[1]
    if not ascii(s1) then return nil end
    local spr = item:getSprite()          -- also sets item.north / west from nSprite
    if not ascii(spr) then return nil end
    local s = item.nSprite
    if type(s) ~= "number" or s < 1 or s > 4 or s ~= math.floor(s) then s = 1 end
    return { name = "BC:" .. i .. ":" .. k .. ":" .. n .. ":" .. s1, x = x, y = y, z = z, s = s,
        north = item.north == true, spr = spr, tiles = { { 0, 0, 0, spr } } }
end

-- the piece the cursor would build at x, y, z, as the server needs it
function BP.capture(item, x, y, z)
    if item.isBetterBuilding then return captureBC(item, x, y, z) end
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
    if not first then
        halo(T("IGUI_CSP_BP_NoPiece"), false)
        return
    end
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

-- ------------------------------------------------------------------ piece list
-- What the window lists: the pieces of the vanilla build menu that place a piece
-- (paint, wallpaper and plaster recipes have none), grouped Vanilla -> category
-- the way the build menu groups them, and Building Craft's tiles (Building Craft
-- -> tab -> type) when it is on. Made the first time the window opens.
--   node  = { key, label, depth, kids = { node }, open }
--   entry = { src, id (name in the plan), name, where (its nodes), keys = { [node key] = true },
--             hay (lower case search text), tex | sprite (picture) }

local function lower(s)
    return string.lower(tostring(s or ""))
end

-- what the admin typed, as lower case words
function BP.words(text)
    local out = {}
    local s = lower(text)
    local from = 1
    while true do
        local a, b = s:find("%S+", from)
        if not a then return out end
        out[#out + 1] = s:sub(a, b)
        from = b + 1
    end
end

-- every word somewhere in the text, in any order
function BP.matches(hay, words)
    for i = 1, #words do
        if not hay:find(words[i], 1, true) then return false end
    end
    return true
end

-- the build menu's own name for a category: its translation, else the raw name
local function categoryName(c)
    if c == "" then return "-" end
    local key = "IGUI_CraftingCategories_" .. string.upper(c:sub(1, 1)) .. c:sub(2)
    local text = getText(key)
    if type(text) ~= "string" or text == "" or text == key then return c end
    return text
end

function BP.newCatalog()
    return { entries = {}, roots = {}, byKey = {} }
end

-- the node for key under parent, made on first use
function BP.node(cat, key, label, parent)
    local n = cat.byKey[key]
    if n then return n end
    n = { key = key, label = label, depth = parent and parent.depth + 1 or 0, kids = {}, open = false }
    cat.byKey[key] = n
    if parent then parent.kids[#parent.kids + 1] = n else cat.roots[#cat.roots + 1] = n end
    return n
end

-- one piece under a path of nodes; its search text = its shown name and its script name (extra)
function BP.addEntry(cat, e, path)
    e.keys = {}
    local labels = {}
    for i = 1, #path do
        e.keys[path[i].key] = true
        labels[#labels + 1] = path[i].label
    end
    e.where = table.concat(labels, " > ")
    e.hay = lower(e.name .. " " .. (e.extra or ""))
    cat.entries[#cat.entries + 1] = e
end

-- the vanilla build menu's list (BuildLogic:getAllBuildableRecipes) through the menu's own
-- filter (OnAddToMenu: debug-only pieces out; shouldShowAll keeps every skill level, as the
-- menu's "show all"), with the piece each recipe places; categories by name, pieces in the menu's order
function BP.addVanilla(cat, p)
    local byRecipe = {}
    local infos = SpriteConfigManager.GetObjectInfoList()
    for i = 0, infos:size() - 1 do
        pcall(function()
            local info = infos:get(i)
            local comp = info:getRecipe()
            local r = comp and comp:getCraftRecipe()
            local rn = r and r:getName()
            if rn and not byRecipe[rn] then byRecipe[rn] = info end
        end)
    end
    local found = {}
    local hidden, nopiece, errors = 0, 0, 0
    local recipes = BuildLogic.new(p, nil, nil):getAllBuildableRecipes()
    for i = 0, recipes:size() - 1 do
        local ok = pcall(function()
            local r = recipes:get(i)
            local test = r:getOnAddToMenu()
            if test and not callLuaBool(test, { player = p, recipe = r, shouldShowAll = true }) then
                hidden = hidden + 1
                return
            end
            local info = byRecipe[r:getName()]
            local id = info and info:getName()
            if not ascii(id) then
                nopiece = nopiece + 1
                return
            end
            local c = tostring(r:getCategory() or "")
            found[#found + 1] = { n = i, r = r, info = info, id = id, c = c, cname = categoryName(c) }
        end)
        if not ok then errors = errors + 1 end
    end
    print(TAG .. ": vanilla list " .. #found .. " pieces (" .. hidden .. " hidden by the build menu, "
        .. nopiece .. " without a piece, " .. errors .. " errors)")
    table.sort(found, function(a, b)
        if a.cname ~= b.cname then return a.cname < b.cname end
        return a.n < b.n
    end)
    local root = BP.node(cat, "v", "Vanilla", nil)
    root.open = true
    for i = 1, #found do
        local f = found[i]
        local e = { src = "v", id = f.id, name = f.id, extra = (f.id:gsub("_", " ")) }
        pcall(function()
            e.name = tostring(f.r:getTranslationName() or f.id)
            e.tex = f.r:getIconTexture() or f.info:getIconTexture()
            if not e.tex then e.sprite = f.info:getMainSpriteNameUI() end
        end)
        BP.addEntry(cat, e, { root, BP.node(cat, "v|" .. f.c, f.cname, root) })
    end
end

-- Building Craft's lists (its tile packs add theirs at game start, before the window can open).
-- A tile has no name of its own: it shows as "<type> <number>".
function BP.addBuildingCraft(cat)
    local list = Building_Data and Building_Data.BuildingList
    if type(list) ~= "table" then return end
    local tabs = {}
    for i, tab in pairs(list) do
        if type(i) == "number" and type(tab) == "table" and type(tab.subBuildData) == "table" then tabs[#tabs + 1] = i end
    end
    if #tabs == 0 then return end
    table.sort(tabs)
    local root = BP.node(cat, "bc", "Building Craft", nil)
    for t = 1, #tabs do
        local i = tabs[t]
        local tab = list[i]
        local tn = BP.node(cat, "bc|" .. i, tostring(tab.TabName or i), root)
        for k = 1, #tab.subBuildData do
            local typ = tab.subBuildData[k]
            if type(typ) == "table" and type(typ.ItemDate) == "table" then
                local label = tostring(typ.TypeName or k)
                local yn = BP.node(cat, "bc|" .. i .. "|" .. k, label, tn)
                for n = 1, #typ.ItemDate do
                    local item = bcItem(i, k, n)
                    local s1 = item and not bcGarage(item) and item.Sprite[1]
                    if ascii(s1) then
                        BP.addEntry(cat, { src = "bc", i = i, k = k, n = n, sprite = s1, extra = s1,
                            id = "BC:" .. i .. ":" .. k .. ":" .. n .. ":" .. s1, name = label .. " " .. n }, { root, tn, yn })
                    end
                end
            end
        end
    end
end

-- made once, the first time the window opens
function BP.catalog()
    if BP.cat then return BP.cat end
    local cat = BP.newCatalog()
    local ok, err = pcall(BP.addVanilla, cat, player())
    if not ok then print(TAG .. ": vanilla list failed " .. tostring(err)) end
    ok, err = pcall(BP.addBuildingCraft, cat)
    if not ok then print(TAG .. ": Building Craft list failed " .. tostring(err)) end
    BP.cat = cat
    print(TAG .. ": piece list " .. #cat.entries .. " pieces")
    return cat
end

-- the pieces under the chosen node that match the search, and how many match under every node
function BP.filter(cat, key, text)
    local words = BP.words(text)
    local shown, counts = {}, { [""] = 0 }
    for i = 1, #cat.entries do
        local e = cat.entries[i]
        if #words == 0 or BP.matches(e.hay, words) then
            counts[""] = counts[""] + 1
            for k in pairs(e.keys) do counts[k] = (counts[k] or 0) + 1 end
            if key == "" or e.keys[key] then shown[#shown + 1] = e end
        end
    end
    return shown, counts
end

-- rows of the list on the left: All, then every open branch
function BP.treeRows(cat)
    if not BP.allNode then BP.allNode = { key = "", label = T("IGUI_CSP_BP_All"), depth = 0, kids = {} } end
    local rows = { BP.allNode }
    local function walk(n)
        rows[#rows + 1] = n
        if n.open then
            for i = 1, #n.kids do walk(n.kids[i]) end
        end
    end
    for i = 1, #cat.roots do walk(cat.roots[i]) end
    return rows
end

-- a click on the left: show that node; a node with branches opens, or closes when clicked again
function BP.selectNode(cat, key)
    local n = cat.byKey[key]
    if n and #n.kids > 0 then
        if BP.find.node == key then n.open = not n.open else n.open = true end
        n.short = nil
    end
    BP.find.node = key
end

-- the picture of a piece: its icon, else its first tile
function BP.icon(e)
    if e.tex == nil then
        e.tex = false
        if e.sprite then pcall(function() e.tex = getTexture(e.sprite) or false end) end
    end
    return e.tex or nil
end

-- the cursor this window handed out is still out
local function cursorOut()
    local p = player()
    if not p or not BP.cursor then return false end
    local yes = false
    pcall(function() yes = getCell():getDrag(p:getPlayerNum()) == BP.cursor end)
    return yes
end

local function dropCursor()
    local p = player()
    if p and cursorOut() then pcall(function() getCell():setDrag(nil, p:getPlayerNum()) end) end
    BP.cursor, BP.find.picked = nil, nil
end

-- plan ghosts also show while a Building Craft cursor is out: each of its classes has its own
-- render, so a class is wrapped the first time one of its cursors is seen
local ghostClasses = {}
local function ghostsOn(cls)
    if type(cls) ~= "table" or ghostClasses[cls] or type(cls.render) ~= "function" then return end
    ghostClasses[cls] = true
    local render = cls.render
    cls.render = function(self, ...)
        local r = render(self, ...)
        if BP.on and #BP.plan > 0 then pcall(drawGhosts) end
        return r
    end
end

-- Building Craft makes the cursor for one of its tiles itself (the tile's Func, as its own
-- window does, which hands the cursor to getCell():setDrag); read it back
function BP.bcCursor(e, p)
    local item = bcItem(e.i, e.k, e.n)
    if not item then return nil end
    local data = item.IsDefault and item.Default or item
    if type(data) ~= "table" or type(data.Func) ~= "function" then return nil end
    local sprite = {}
    for s = 1, 12 do sprite["sprite" .. s] = item.Sprite[s] end
    local num = p:getPlayerNum()
    data.Func(e.i, e.k, e.n, sprite, num)
    local cur = getCell():getDrag(num)
    if type(cur) ~= "table" or not cur.isBetterBuilding then return nil end
    ghostsOn(getmetatable(cur))
    return cur
end

-- a piece picked in the list becomes the build cursor; clicking the ground puts it into the plan
function BP.choose(e)
    local p = player()
    if not p or not BP.on or not e then return end
    local cursor = nil
    local ok, err = pcall(function()
        if e.src == "v" then
            local info = SpriteConfigManager.GetObjectInfo(e.id)
            if not info then return end
            local containers = ArrayList.new()
            pcall(function() containers = ISInventoryPaneContextMenu.getContainers(p) or containers end)
            cursor = ISBuildIsoEntity:new(p, info, 1, containers, nil)
        elseif e.src == "bc" then
            cursor = BP.bcCursor(e, p)
        end
        if cursor then
            cursor.dragNilAfterPlace = false      -- stays out for the next click, as in the build menu
            getCell():setDrag(cursor, p:getPlayerNum())
        end
    end)
    if not ok then
        print(TAG .. ": pick failed " .. tostring(err))
        cursor = nil
    end
    if cursor then
        BP.cursor, BP.find.picked = cursor, e
    else
        halo(T("IGUI_CSP_BP_NoPiece"), false)
    end
end

-- ------------------------------------------------------------------ window
local Panel = ISCollapsableWindow:derive("CSPBuildPlanPanel")
local W, H = 800, 660
local PAD, BH = 12, 36
local TREE_W = 220
local CELL_W, CELL_H, ICON = 74, 80, 50

-- text cut to maxW pixels, ".." at the end when cut
function BP.fit(text, font, maxW)
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxW then return text end
    local n = #text
    while n > 1 and tm:MeasureStringX(font, text:sub(1, n) .. "..") > maxW do n = n - 1 end
    return text:sub(1, n) .. ".."
end

-- left: All, then Vanilla -> category and Building Craft -> tab -> type; the number = pieces matching the search
local Tree = ISScrollingListBox:derive("CSPBuildPlanTree")

function Tree:doDrawItem(y, item, alt)
    local h = self.itemheight
    local top = y + self:getYScroll()
    if top + h < 0 or top > self.height then return y + h end
    local n = item.item
    local w = self:getWidth()
    if n.key == BP.find.node then
        self:drawRect(1, y, w - 2, h - 1, 0.35, 0.7, 0.35, 0.15)
    elseif self.mouseoverselected == item.index then
        self:drawRect(1, y, w - 2, h - 1, 0.1, 1, 1, 1)
    end
    local x = 6 + n.depth * 12
    if not n.short then
        local mark = #n.kids > 0 and (n.open and "- " or "+ ") or ""
        n.short = BP.fit(mark .. n.label, UIFont.Small, w - x - 60)
    end
    local count = BP.find.counts[n.key] or 0
    local c = count > 0 and 0.95 or 0.5
    self:drawText(n.short, x, y + 2, c, c, c, 1, UIFont.Small)
    self:drawTextRight(tostring(count), w - 20, y + 2, 0.6, 0.6, 0.6, 1, UIFont.Small)
    return y + h
end

-- right: the pieces, one list row per row of cells; click = pick
local Grid = ISScrollingListBox:derive("CSPBuildPlanGrid")

function Grid:prerender()
    BP.find.hover = nil
    ISScrollingListBox.prerender(self)
end

function Grid:doDrawItem(y, item, alt)
    local h = self.itemheight
    local top = y + self:getYScroll()
    if top + h < 0 or top > self.height then return y + h end
    local over = self:isMouseOver()
    local mx, my = self:getMouseX(), self:getMouseY()
    for c = 1, #item.item do
        local e = item.item[c]
        local x = (c - 1) * CELL_W
        if e == BP.find.picked then
            self:drawRect(x + 1, y + 1, CELL_W - 2, h - 2, 0.4, 0.7, 0.35, 0.15)
        end
        if over and mx >= x and mx < x + CELL_W and my >= y and my < y + h then
            self:drawRect(x + 1, y + 1, CELL_W - 2, h - 2, 0.15, 1, 1, 1)
            BP.find.hover = e
        end
        local tex = BP.icon(e)
        if tex then self:drawTextureScaledAspect(tex, x + (CELL_W - ICON) / 2, y + 4, ICON, ICON, 1, 1, 1, 1) end
        if not e.short then e.short = BP.fit(e.name, UIFont.Small, CELL_W - 6) end
        self:drawTextCentre(e.short, x + CELL_W / 2, y + ICON + 8, 0.9, 0.9, 0.9, 1, UIFont.Small)
    end
    return y + h
end

function Grid:onMouseDown(x, y)
    local item = self.items[self:rowAt(x, y)]
    local e = item and item.item[math.floor(x / CELL_W) + 1]
    if e then
        pcall(function() getSoundManager():playUISound("UISelectListItem") end)
        BP.choose(e)
    end
    return true
end

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

local function lineHeights()
    local tm = getTextManager()
    return tm:getFontHeight(UIFont.Small) + 3, tm:getFontHeight(UIFont.Medium) + 4
end

function Panel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local small, medium = lineHeights()
    local bw = math.floor((W - PAD * 3) / 2)
    local y = H - PAD - BH * 2 - 8
    self.btnBuild = button(self, PAD, y, bw, "IGUI_CSP_BP_Build", Panel.onBuild)
    self.btnUndo = button(self, PAD * 2 + bw, y, bw, "IGUI_CSP_BP_Undo", Panel.onUndo)
    y = y + BH + 8
    self.btnClear = button(self, PAD, y, bw, "IGUI_CSP_BP_Clear", Panel.onClear)
    self.btnCheat = button(self, PAD * 2 + bw, y, bw, "IGUI_CSP_BP_CheatOn", Panel.onCheat)
    -- above the buttons: the piece under the mouse, pieces in the plan, Build Cheat warning, status
    self.textTop = H - PAD - BH * 2 - 16 - small * 5 - medium - 6
    -- below the two hint lines: search box, then the list
    local ys = self:titleBarHeight() + 8 + small * 2 + 4
    local sh = small + 6
    self.search = ISTextEntryBox:new("", PAD, ys, W - PAD * 2, sh)
    self.search.font = UIFont.Small
    self.search:initialise()
    self.search:instantiate()
    pcall(function()
        self.search:setClearButton(true)
        self.search:setPlaceholderText(T("IGUI_CSP_BP_Search"))
    end)
    local panel = self
    self.search.onTextChange = function() panel:refresh() end
    self:addChild(self.search)
    local yl = ys + sh + 6
    local lh = self.textTop - 6 - yl
    self.tree = Tree:new(PAD, yl, TREE_W, lh)
    self.tree:initialise()
    self.tree:instantiate()
    self.tree.itemheight = small + 4
    self.tree.drawBorder = true
    self.tree:setOnMouseDownFunction(self, Panel.onNode)
    self:addChild(self.tree)
    local gx = PAD + TREE_W + 8
    self.grid = Grid:new(gx, yl, W - PAD - gx, lh)
    self.grid:initialise()
    self.grid:instantiate()
    self.grid.itemheight = CELL_H
    self.grid.drawBorder = true
    self:addChild(self.grid)
    self.cols = math.max(1, math.floor((W - PAD - gx - 18) / CELL_W))
    self:fillTree()
    self:refresh()
end

function Panel:fillTree()
    local rows = BP.treeRows(BP.catalog())
    self.tree:clear()
    for i = 1, #rows do self.tree:addItem(rows[i].label, rows[i]) end
end

-- after typing or a click on the left: count again and fill the cells
function Panel:refresh()
    local text = self.search and self.search:getInternalText() or ""
    BP.find.shown, BP.find.counts = BP.filter(BP.catalog(), BP.find.node, text)
    self.grid:clear()
    local row = nil
    for i = 1, #BP.find.shown do
        if not row or #row >= self.cols then
            row = {}
            self.grid:addItem("", row)
        end
        row[#row + 1] = BP.find.shown[i]
    end
    self.grid.smoothScrollTargetY = nil
    self.grid:setYScroll(0)
end

function Panel:onNode(n)
    if not n then return end
    BP.selectNode(BP.catalog(), n.key)
    self:fillTree()
    self:refresh()
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
    -- the picked piece stays marked only while its cursor is out
    if BP.find.picked and not cursorOut() then BP.cursor, BP.find.picked = nil, nil end
end

function Panel:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    local x = PAD
    local y = self:titleBarHeight() + 8
    local small, medium = lineHeights()
    local maxW = W - PAD * 2
    local function lines(text, font, h, r, g, b, most)
        local list = BP.wrap(text, font, maxW)
        for i = 1, math.min(#list, most) do
            self:drawText(list[i], x, y, r, g, b, 1, font)
            y = y + h
        end
    end
    lines(T("IGUI_CSP_BP_Hint1"), UIFont.Small, small, 0.9, 0.9, 0.9, 1)
    lines(T("IGUI_CSP_BP_Hint2"), UIFont.Small, small, 0.9, 0.9, 0.9, 1)
    y = self.textTop
    -- the piece under the mouse, else how many pieces the list shows
    local e = BP.find.hover
    if e then
        lines(e.name .. "   (" .. e.where .. ")", UIFont.Small, small, 0.75, 0.9, 1, 1)
    else
        lines(#BP.find.shown .. " " .. T("IGUI_CSP_BP_Pieces"), UIFont.Small, small, 0.6, 0.6, 0.6, 1)
    end
    y = y + 4
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
    dropCursor()                  -- a picked piece would build for real once plan mode is off
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
    local x, y = 80, 140
    pcall(function()
        x = math.max(10, math.min(x, getCore():getScreenWidth() - W - 10))
        y = math.max(10, math.min(y, getCore():getScreenHeight() - H - 10))
    end)
    local panel = Panel:new(x, y)
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
    -- Building Craft cursors (isBetterBuilding): Building Craft replaces ISBuildingObject.tryBuild
    -- for every cursor; while plan mode is on its pieces go into the plan, everything else passes
    if ISBuildingObject and type(ISBuildingObject.tryBuild) == "function" then
        local baseTry = ISBuildingObject.tryBuild
        ISBuildingObject.tryBuild = function(self, x, y, z, ...)
            if type(self) ~= "table" or not self.isBetterBuilding or not BP.on or not BP.mayUse(player()) then
                return baseTry(self, x, y, z, ...)
            end
            ghostsOn(getmetatable(self))
            local ok, err = pcall(addFromCursor, self, x, y, z)
            if not ok then print(TAG .. ": add failed " .. tostring(err)) end
            return nil
        end
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
