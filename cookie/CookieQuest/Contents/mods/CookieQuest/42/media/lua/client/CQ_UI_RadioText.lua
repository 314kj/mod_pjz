-- Cookie Quest - radio hints over the listener's head, vanilla-radio style:
-- coloured text with a black outline, a bit higher than normal speech text
require "CQ_UI_Kit"

CQRT = CQRT or {}
CQRT.lines = CQRT.lines or {}
CQRT.MAX = 3            -- broadcasts kept on screen at once (newest nearest the head)
CQRT.Z_OFFSET = 1.05    -- floors above the feet; speech text sits lower, so these never overlap
CQRT.FONT = UIFont.Medium
CQRT.WRAP = 420

local OUTLINE = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 },
                  { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }

local function project(p, z)
    local sx = isoToScreenX(0, p:getX(), p:getY(), z)
    local sy = isoToScreenY(0, p:getX(), p:getY(), z)
    return sx, sy
end

-- true when this game build can place text in the world (checked once)
function CQRT.available()
    if CQRT.ok == nil then
        CQRT.ok = pcall(function()
            local p = getSpecificPlayer(0)
            if p then project(p, p:getZ()) else isoToScreenX(0, 0, 0, 0) end
        end) == true
        if not CQRT.ok then CQ.log("radio text: world projection unavailable, using screen toasts") end
    end
    return CQRT.ok
end

function CQRT.add(text, col)
    if not text or text == "" then return end
    col = col or { 1, 1, 1 }
    local dur = CQ.clamp(4000 + 80 * #text, 6000, 12000)
    table.insert(CQRT.lines, { lines = CQUI.wrap(text, CQRT.FONT, CQRT.WRAP), col = col, t = getTimestampMs(), dur = dur })
    while #CQRT.lines > CQRT.MAX do table.remove(CQRT.lines, 1) end
end

local function outlined(el, s, cx, y, col, a, font)
    font = font or CQRT.FONT
    local x = cx - CQUI.tw(font, s) / 2
    for i = 1, #OUTLINE do
        el:drawText(s, x + OUTLINE[i][1], y + OUTLINE[i][2], 0, 0, 0, a * 0.9, font)
    end
    el:drawText(s, x, y, col[1], col[2], col[3], a, font)
end
CQRT.outlined = outlined

function CQRT.draw(el)
    if #CQRT.lines == 0 then return end
    local now = getTimestampMs()
    local keep = {}
    for _, e in ipairs(CQRT.lines) do
        if now >= e.t and now - e.t < e.dur then keep[#keep + 1] = e end
    end
    CQRT.lines = keep
    if #keep == 0 then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    local sx, sy = project(p, p:getZ() + CQRT.Z_OFFSET)
    local lh = CQUI.fh(CQRT.FONT) + 1
    local y = sy
    for i = #keep, 1, -1 do
        local e = keep[i]
        local age = now - e.t
        local a = 1
        if age < 250 then a = age / 250 end
        if e.dur - age < 1000 then a = math.min(a, (e.dur - age) / 1000) end
        for j = #e.lines, 1, -1 do
            y = y - lh
            outlined(el, e.lines[j], sx, y, e.col, a)
        end
        y = y - 6
    end
end

-- a 1x1 element in the corner: draws anywhere on screen without catching mouse clicks
local R = ISUIElement:derive("CQRadioText")

function R:new()
    local o = ISUIElement.new(self, 0, 0, 1, 1)
    o.anchorLeft, o.anchorTop = true, true
    return o
end

function R:prerender() end

function R:render()
    local ok, err = pcall(CQRT.draw, self)
    if not ok and not self.errLogged then
        self.errLogged = true
        CQ.log("radio text error: " .. tostring(err))
    end
end

function CQRT.ensure()
    if CQRT.el then return end
    local el = R:new()
    el:initialise()
    el:instantiate()
    el:addToUIManager()
    if el.backMost then el:backMost() end
    CQRT.el = el
end

Events.OnGameStart.Add(function() CQRT.ensure() end)

return CQRT
