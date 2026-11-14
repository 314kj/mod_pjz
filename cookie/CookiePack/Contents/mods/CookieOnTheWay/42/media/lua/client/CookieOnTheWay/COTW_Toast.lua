-- Cookie On the Way : part damage toasts, bottom right, whenever the player drives a car (autopilot,
-- navigator or neither). Every 250 ms the driven car's parts are read; a part whose condition went
-- down gets a toast: its name, what is left (green / amber / red), a down arrow and how much it
-- lost. Shown 3 s, then it fades out. More hits on the same part while its toast is up update it.
-- Getting into a car (or another one) only takes a first reading, so old damage never shows.
-- Click-through: the toasts never catch the mouse.

require "CookieOnTheWay/COTW_Client"
require "CookieOnTheWay/COTW_UI"
require "ISUI/ISPanel"

COTWToast = ISPanel:derive("COTWToast")

local U = COTW.UI
local K = U.C
local MIN_W, MAX_W = 230, 340
local H = math.max(52, 8 + U.FONT_S + U.FONT_M + 12)
local GAP = 6
local RIGHT, BOTTOM = 24, 110      -- px from the screen's right / bottom edge
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
-- panel: as tall as the stack, newest at the bottom, right-aligned
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

function COTWToast:drawToast(e, y, now)
    local age = now - e.t
    local a = 1
    if age < IN_MS then a = age / IN_MS elseif age > SHOW_MS then a = 1 - (age - SHOW_MS) / FADE_MS end
    if a <= 0 then return end
    local w = math.min(MAX_W, math.max(MIN_W, 58 + U.textW(e.name) + 16))
    -- slides in from the right
    local x = self.width - w + (age < IN_MS and (1 - age / IN_MS) * 16 or 0)
    local col = levelColor(e.cond)
    U.chamfer(self, x + 3, y + 5, w, H, 10, K.black, 0.4 * a)
    U.chamfer(self, x, y, w, H, 10, K.panel, 0.94 * a)
    U.rect(self, x + 2, y + 10, 3, H - 20, col, a)
    U.chamferLine(self, x, y, w, H, 10, col, 0.6 * a)
    -- badge
    local bs = 36
    local by = y + (H - bs) / 2
    U.hex(self, x + 12, by, bs, bs, col, 0.18 * a)
    U.hex(self, x + 14, by + 2, bs - 4, bs - 4, col, a)
    U.icon(self, "car", x + 12 + (bs - 20) / 2, by + (bs - 20) / 2, 20, K.dark, a)
    -- name, then what is left + arrow + how much it lost
    local tx = x + 58
    U.text(self, e.name, tx, y + 7, K.ink, UIFont.Small, a)
    local py = y + 7 + U.FONT_S
    local pct = tostring(math.floor(e.cond + 0.5)) .. "%"
    U.text(self, pct, tx, py, col, UIFont.Medium, a)
    local ax = tx + U.textW(pct, UIFont.Medium) + 6
    U.icon(self, "down", ax, py + (U.FONT_M - 16) / 2, 16, K.red, a)
    U.text(self, "-" .. tostring(math.floor(e.lost + 0.5)), ax + 18, py + (U.FONT_M - U.FONT_S) / 2, K.mute, UIFont.Small, a)
    -- condition bar
    local bx, bw = tx, w - 58 - 14
    U.rect(self, bx, y + H - 8, bw, 3, K.white, 0.08 * a)
    U.rect(self, bx, y + H - 8, bw * math.max(0, math.min(100, e.cond)) / 100, 3, col, a)
end

function COTWToast:prerender()
    local now = getTimestampMs()
    for i = #list, 1, -1 do
        if now - list[i].t > SHOW_MS + FADE_MS then table.remove(list, i) end
    end
    local h = math.max(H, #list * (H + GAP) - GAP)
    if self.height ~= h then self:setHeight(h) end
    self:setX(getCore():getScreenWidth() - self.width - RIGHT)
    self:setY(getCore():getScreenHeight() - h - BOTTOM)
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
