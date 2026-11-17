-- Cookie On the Way : part damage toasts, one small row each, centred just above the car's dashboard,
-- whenever the player drives a car (autopilot, navigator or neither). Every 250 ms the driven car's
-- parts are read; a part whose condition went down gets a toast: its name, what is left (green /
-- amber / red), a down arrow and how much it lost. Shown 3 s, then it fades out. More hits on the
-- same part while its toast is up update it. Getting into a car (or another one) only takes a first
-- reading, so old damage never shows. Click-through: the toasts never catch the mouse.

require "CookieOnTheWay/COTW_Client"
require "CookieOnTheWay/COTW_UI"
require "ISUI/ISPanel"

COTWToast = ISPanel:derive("COTWToast")

local U = COTW.UI
local K = U.C
local MIN_W, MAX_W = 150, 260
local H = math.max(24, U.FONT_S + 10)
local GAP = 3
local ABOVE_DASH = 6               -- px between the stack and the top of the dashboard
local BOTTOM = 190                 -- px from the screen's bottom edge when there is no dashboard
local DIM = 0.75                   -- the whole toast is drawn this see-through
local IN_MS, SHOW_MS, FADE_MS = 150, 3000, 600
local MAX = 4
local POLL_MS = 250

local list = {}                    -- { id, name, cond, lost, t = ms when (last) shown }, oldest first
local seen = { v = nil, cond = {} }
local lastPoll = 0
local warned = false

-- the game's own name for the part; parts from car mods without one: "FrontBumper" -> "Front Bumper"
local function partName(id)
    local name = nil
    if type(getTextOrNull) == "function" then name = getTextOrNull("IGUI_VehiclePart" .. id) end
    return name or (string.gsub(tostring(id), "(%l)(%u)", "%1 %2"))
end

local function levelColor(cond)
    if cond > 60 then return K.g end
    if cond > 30 then return K.amber end
    return K.red
end

-- a part lost condition: new toast, or the one already up for it updated and moved to the bottom
function COTWToast.push(id, cond, lost, now)
    for i, e in ipairs(list) do
        if e.id == id then
            table.remove(list, i)
            e.cond, e.lost, e.t = cond, e.lost + lost, now
            list[#list + 1] = e
            return
        end
    end
    list[#list + 1] = { id = id, name = partName(id), cond = cond, lost = lost, t = now }
    while #list > MAX do table.remove(list, 1) end
end

-- read every shown part of the car the player drives; compare with the last reading of that car
local function poll(now)
    local v = COTW.driving()
    if v ~= seen.v then
        seen.v, seen.cond = v, {}
    end
    if not v then return end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        if part and (part:getCategory() or "Other") ~= "nodisplay" then
            local id = part:getId()
            local c = part:getCondition()
            local was = seen.cond[id]
            if was and c < was then COTWToast.push(id, c, was - c, now) end
            seen.cond[id] = c
        end
    end
end

-- ------------------------------------------------------------------------------
-- panel: as tall as the stack, newest at the bottom, each row centred
-- ------------------------------------------------------------------------------
function COTWToast:new()
    local o = ISPanel.new(self, 0, 0, MAX_W, H)
    o.background = false
    o.moveWithMouse = false
    return o
end

function COTWToast:instantiate()
    ISPanel.instantiate(self)
    pcall(function() self.javaObject:setConsumeMouseEvents(false) end)
end

-- one row: badge, part name, what is left, down arrow, how much it lost; a thin condition bar under it
function COTWToast:drawToast(e, y, now)
    local age = now - e.t
    local a = 1
    if age < IN_MS then a = age / IN_MS elseif age > SHOW_MS then a = 1 - (age - SHOW_MS) / FADE_MS end
    if a <= 0 then return end
    a = a * DIM
    local pct = tostring(math.floor(e.cond + 0.5)) .. "%"
    local lost = "-" .. tostring(math.floor(e.lost + 0.5))
    local bs = H - 8
    local tx = 6 + bs + 6
    local rightW = U.textW(pct) + 4 + 12 + 2 + U.textW(lost)
    local w = math.min(MAX_W, math.max(MIN_W, tx + U.textW(e.name) + 10 + rightW + 8))
    -- long names from car mods: cut with "..." so they never run into the numbers
    local room = w - tx - 10 - rightW - 8
    if not e.short or e.shortFor ~= room then
        local s = e.name
        if U.textW(s) > room then
            while #s > 1 and U.textW(s .. "...") > room do s = string.sub(s, 1, -2) end
            s = s .. "..."
        end
        e.short, e.shortFor = s, room
    end
    -- rises in from below
    local x = (self.width - w) / 2
    y = y + (age < IN_MS and (1 - age / IN_MS) * 8 or 0)
    local col = levelColor(e.cond)
    U.chamfer(self, x, y, w, H, 6, K.panel, 0.8 * a)
    U.rect(self, x + 1, y + 5, 2, H - 10, col, a)
    U.chamferLine(self, x, y, w, H, 6, col, 0.45 * a)
    -- badge
    local by = y + (H - bs) / 2
    U.hex(self, x + 6, by, bs, bs, col, a)
    U.icon(self, "car", x + 6 + (bs - 12) / 2, by + (bs - 12) / 2, 12, K.dark, a)
    -- name on the left, what is left + arrow + how much it lost on the right
    local ty = y + (H - U.FONT_S) / 2 - 1
    local rx = x + w - 8 - rightW
    U.text(self, e.short, x + tx, ty, K.ink, UIFont.Small, a)
    U.text(self, pct, rx, ty, col, UIFont.Small, a)
    local ax = rx + U.textW(pct) + 4
    U.icon(self, "down", ax, y + (H - 12) / 2, 12, K.red, a)
    U.text(self, lost, ax + 14, ty, K.mute, UIFont.Small, a)
    -- condition bar
    local bx, bw = x + tx, w - tx - 8
    U.rect(self, bx, y + H - 4, bw, 2, K.white, 0.08 * a)
    U.rect(self, bx, y + H - 4, bw * math.max(0, math.min(100, e.cond)) / 100, 2, col, a)
end

-- centre x and top edge of the vanilla dashboard while it shows a car; nil without one
local function dashAnchor()
    if type(getPlayerVehicleDashboard) ~= "function" then return nil end
    local ok, d = pcall(getPlayerVehicleDashboard, 0)
    if not ok or not d or not d.vehicle then return nil end
    local okP, x, y, w = pcall(function() return d:getX(), d:getY(), d:getWidth() end)
    if not okP or not x or y <= 0 then return nil end
    return x + w / 2, y
end

function COTWToast:prerender()
    local now = getTimestampMs()
    for i = #list, 1, -1 do
        if now - list[i].t > SHOW_MS + FADE_MS then table.remove(list, i) end
    end
    local h = math.max(H, #list * (H + GAP) - GAP)
    if self.height ~= h then self:setHeight(h) end
    local cx, top = dashAnchor()
    if not cx then cx, top = getCore():getScreenWidth() / 2, getCore():getScreenHeight() - BOTTOM end
    self:setX(cx - self.width / 2)
    self:setY(top - ABOVE_DASH - h)
    for i, e in ipairs(list) do self:drawToast(e, (i - 1) * (H + GAP), now) end
end

function COTWToast:render() end

local function onGameStart()
    local t = COTWToast:new()
    t:initialise()
    t:addToUIManager()
    t:setVisible(false)
    COTWToast.instance = t
end

local function onTick()
    local now = getTimestampMs()
    if now - lastPoll >= POLL_MS then
        lastPoll = now
        local ok, err = pcall(poll, now)
        if not ok and not warned then
            warned = true
            COTW.log("damage toast: " .. tostring(err))
        end
    end
    local t = COTWToast.instance
    if not t then return end
    local want = #list > 0
    if want ~= t:isVisible() then t:setVisible(want) end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
