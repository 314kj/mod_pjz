-- Cookie On the Way : world map (pick a place, draw the route, home and pins)
-- Right-click on the world map: go here (opens the booking panel), navigate here (drive yourself),
-- set My Home, save as My Pin 1-5, and for admins measure the reference fare / delete an admin road /
-- clear trouble spots (drawn for admins: red = closed, routes go round it; orange = watched).
-- Admins keep the vanilla debug menu with ours as a submenu, or ours alone when the map was opened
-- from the booking panel (pick mode).

require "CookieOnTheWay/COTW_Client"
require "ISUI/Maps/ISWorldMap"

COTW.Map = COTW.Map or { picking = false }
local M = COTW.Map

local COL_TRIP = { 0.95, 0.55, 0.10 }
local COL_NAV  = { 0.15, 0.55, 0.95 }
local COL_PREV = { 0.55, 0.55, 0.55 }
local COL_ADMIN = { 0.75, 0.20, 0.75 }
local COL_SHUT = { 0.85, 0.10, 0.10 }
local COL_WATCH = { 0.95, 0.60, 0.15 }

function M.pick()
    M.picking = true
    local p = COTW.player()
    if not p then return end
    ISWorldMap.ShowWorldMap(p:getPlayerNum())
end

local function closeMap()
    if ISWorldMap_instance then ISWorldMap_instance:close() end
end

-- ------------------------------------------------------------------------------
-- context menu
-- ------------------------------------------------------------------------------
local function onGoHere(_, x, y)
    COTW.setDest(x, y, nil)
    M.picking = false
    closeMap()
    COTWPanel.open()
end

local function onNavHere(_, x, y)
    if COTW.startNav(x, y) then
        M.picking = false
        closeMap()
    end
end

local function onSetHome(_, x, y) COTW.send("setHome", { x = x, y = y }) end

local function onPinNamed(_, button, x, y, i)
    if button.internal ~= "OK" then return end
    local name = button.parent.entry:getText()
    if not name or name == "" then name = "Pin " .. i end
    COTW.send("setPin", { i = i, n = name, x = x, y = y })
end

local function onSetPin(_, x, y, i)
    local old = COTW.C.pins[i]
    local box = ISTextBox:new(0, 0, 280, 180, getText("IGUI_COTW_PinName", tostring(i)), old and old.n or ("Pin " .. i), nil, onPinNamed, 0, x, y, i)
    box:initialise()
    box:addToUIManager()
    box:setX(getCore():getScreenWidth() / 2 - 140)
    box:setY(getCore():getScreenHeight() / 2 - 90)
end

local function onMeasure(_, x, y)
    local r = COTW.Graph.route(COTW.REF_FROM[1], COTW.REF_FROM[2], x, y, true)
    if not r then COTW.say("IGUI_COTW_Err_unreachable"); return end
    COTW.say("IGUI_COTW_Measure", string.format("%.2f", r.len / 1000), COTW.money(COTW.fare(r.len)))
end

local function onDelRoad(_, x, y) COTW.send("delRoad", { x = x, y = y }) end

local function onClearSpot(_, x, y) COTW.send("clearClosed", { x = x, y = y }) end

local function onClearAll() COTW.send("clearClosed", { all = true }) end

-- a trouble spot within 30 tiles of (x, y)?
local function spotNear(x, y)
    for _, s in ipairs(COTW.C.closed or {}) do
        if COTW.dist(x, y, s.x, s.y) < 30 then return s end
    end
    return nil
end

local function fillMenu(context, x, y)
    context:addOption(getText("IGUI_COTW_GoHere"), nil, onGoHere, x, y)
    context:addOption(getText("IGUI_COTW_NavHere"), nil, onNavHere, x, y)
    if COTW.C.nav then context:addOption(getText("IGUI_COTW_NavStop"), nil, function() COTW.stopNav() end) end
    if COTW.C.dest and not COTW.C.trip then context:addOption(getText("IGUI_COTW_ClearDest"), nil, function() COTW.clearDest() end) end
    context:addOption(getText("IGUI_COTW_SetHome"), nil, onSetHome, x, y)
    local pinOpt = context:addOption(getText("IGUI_COTW_SetPin"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(pinOpt, sub)
    for i = 1, COTW.PINS do
        local pin = COTW.C.pins[i]
        sub:addOption(tostring(i) .. ". " .. (pin and pin.n or getText("IGUI_COTW_Empty")), nil, onSetPin, x, y, i)
    end
    if COTW.isAdmin() then
        context:addOption(getText("IGUI_COTW_Measure_Opt"), nil, onMeasure, x, y)
        context:addOption(getText("IGUI_COTW_DelRoad"), nil, onDelRoad, x, y)
        if spotNear(x, y) then context:addOption(getText("IGUI_COTW_ClosedClear"), nil, onClearSpot, x, y) end
        local n = #(COTW.C.closed or {})
        if n > 0 then context:addOption(getText("IGUI_COTW_ClosedClearAll", tostring(n)), nil, onClearAll) end
    end
end

local origRightUp = ISWorldMap.onRightMouseUp
function ISWorldMap:onRightMouseUp(x, y)
    if self.symbolsUI and self.symbolsUI:onRightMouseUpMap(x, y) then return true end
    local wx = math.floor(self.mapAPI:uiToWorldX(x, y))
    local wy = math.floor(self.mapAPI:uiToWorldY(x, y))
    if COTW.isAdmin() and not M.picking and origRightUp and origRightUp(self, x, y) then
        -- admins keep the vanilla menu (teleport ...); ours goes at the end as a submenu
        local context = getPlayerContextMenu(0)
        local opt = context:addOption(getText("IGUI_COTW_Title"))
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(opt, sub)
        fillMenu(sub, wx, wy)
        return true
    end
    local context = ISContextMenu.get(0, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    fillMenu(context, wx, wy)
    return true
end

local origClose = ISWorldMap.close
function ISWorldMap:close()
    M.picking = false
    return origClose(self)
end

-- ------------------------------------------------------------------------------
-- drawing
-- ------------------------------------------------------------------------------
local function thickLine(ui, x1, y1, x2, y2, t, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local L = math.sqrt(dx * dx + dy * dy)
    if L < 0.5 then return end
    local nx, ny = -dy / L * t / 2, dx / L * t / 2
    ui.javaObject:DrawTexture(nil, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny, c[1], c[2], c[3], a)
end

local function drawPolyline(map, xs, ys, from, c, a)
    local api = map.mapAPI
    local zoom = api:getZoomF()
    local t = math.max(2, math.min(6, zoom / 3))
    local px, py = nil, nil
    for i = from or 1, #xs do
        local sx, sy = api:worldToUIX(xs[i], ys[i]), api:worldToUIY(xs[i], ys[i])
        if px then thickLine(map, px, py, sx, sy, t, c, a) end
        px, py = sx, sy
    end
end

local function marker(map, x, y, label, c)
    local api = map.mapAPI
    local sx, sy = api:worldToUIX(x, y), api:worldToUIY(x, y)
    map:drawRect(sx - 5, sy - 5, 10, 10, 1, c[1], c[2], c[3])
    map:drawRectBorder(sx - 6, sy - 6, 12, 12, 1, 0, 0, 0)
    if label then map:drawText(label, sx + 8, sy - 8, 0, 0, 0, 1, UIFont.Small) end
end

local origRender = ISWorldMap.render
function ISWorldMap:render()
    origRender(self)
    local ok, err = pcall(function()
        local C = COTW.C
        if COTW.isAdmin() then
            -- admin roads, so missing links are easy to see
            local roads = COTW.Graph.extraList and COTW.Graph.extraList() or {}
            for _, r in ipairs(roads) do
                local xs, ys = {}, {}
                for k = 1, #r.p, 2 do xs[#xs + 1] = r.p[k]; ys[#ys + 1] = r.p[k + 1] end
                drawPolyline(self, xs, ys, 1, COL_ADMIN, 0.8)
            end
            -- trouble spots: weight and hours since the last trip gave up there
            local now = getTimestampMs()
            for _, s in ipairs(C.closed or {}) do
                local hrs = s.t and s.t > 0 and math.max(0, math.floor((now - s.t) / 3600000)) or 0
                marker(self, s.x, s.y, getText("IGUI_COTW_ClosedSpot", string.format("%.1f", s.w or 0), tostring(hrs)), s.on and COL_SHUT or COL_WATCH)
            end
        end
        local st = COTW.Driver.status()
        if st and st.R then
            drawPolyline(self, st.R.x, st.R.y, st.idx, COL_TRIP, 0.9)
        elseif C.nav then
            drawPolyline(self, C.nav.route.x, C.nav.route.y, C.navIdx or 1, COL_NAV, 0.9)
        elseif C.quote and C.quote.route then
            drawPolyline(self, C.quote.route.x, C.quote.route.y, 1, COL_PREV, 0.8)
        end
        if C.home then marker(self, C.home.x, C.home.y, getText("IGUI_COTW_Home"), { 0.2, 0.8, 0.3 }) end
        for i = 1, COTW.PINS do
            local pin = C.pins[i]
            if pin then marker(self, pin.x, pin.y, tostring(i) .. ". " .. pin.n, { 0.95, 0.75, 0.2 }) end
        end
        if C.dest then marker(self, C.dest.x, C.dest.y, getText("IGUI_COTW_Dest"), COL_TRIP) end
        if M.picking then
            self:drawTextCentre(getText("IGUI_COTW_PickHint"), self.width / 2, 40, 0, 0, 0, 1, UIFont.Medium)
        end
    end)
    if not ok and not M.drawErrLogged then
        M.drawErrLogged = true
        COTW.log("map draw error (logged once): " .. tostring(err))
    end
end
