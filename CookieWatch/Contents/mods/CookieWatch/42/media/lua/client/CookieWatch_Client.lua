-- CookieWatch_Client.lua  (Cookie Cheetah)
-- Translucent centre popup (logo + 3 lines) and a small top countdown chip.
-- Text comes from the server; live placeholders filled here:
--   {minutes}  minutes left (rounded up)    {countdown}  mm:ss    {seconds}  seconds left
-- Click the popup to hide it, click the chip to show it again.

if isServer() then return end

require "ISUI/ISPanel"

CookieWatch = CookieWatch or {}
local CW = CookieWatch

CW.TEX_PATH = "media/textures/CookieWatch_Logo.png"
CW.state = nil
CW.popup = nil
CW.mini = nil
CW.syncAt = nil

local FADE_IN = 350
local FADE_OUT = 600

local function nowMs()
    return getTimestampMs()
end

local function plainReplace(s, key, val)
    if not s or s == "" then return "" end
    local out, i = "", 1
    while true do
        local a, b = string.find(s, key, i, true)
        if not a then return out .. string.sub(s, i) end
        out = out .. string.sub(s, i, a - 1) .. val
        i = b + 1
    end
end

local function pad2(n)
    n = math.floor(n)
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

local function hexColor(h, dr, dg, db)
    if type(h) ~= "string" then return dr, dg, db end
    h = (string.gsub(h, "#", ""))
    if string.len(h) ~= 6 then return dr, dg, db end
    local r = tonumber(string.sub(h, 1, 2), 16)
    local g = tonumber(string.sub(h, 3, 4), 16)
    local b = tonumber(string.sub(h, 5, 6), 16)
    if not (r and g and b) then return dr, dg, db end
    return r / 255, g / 255, b / 255
end

function CW.remain()
    local st = CW.state
    if not st then return 0 end
    local r = (st.deadline - nowMs()) / 1000
    if r < 0 then r = 0 end
    return r
end

function CW.fill(s)
    local r = CW.remain()
    s = plainReplace(s, "{minutes}", tostring(math.ceil(r / 60)))
    s = plainReplace(s, "{seconds}", tostring(math.ceil(r)))
    s = plainReplace(s, "{countdown}", pad2(r / 60) .. ":" .. pad2(r % 60))
    return s
end

local function texSize(tex, h)
    if tex and tex:getHeight() > 0 then
        return math.floor(h * tex:getWidth() / tex:getHeight()), h
    end
    return h, h
end

-- ---------------------------------------------------------------- popup
CookieWatchPopup = ISPanel:derive("CookieWatchPopup")

function CookieWatchPopup:new()
    local o = ISPanel:new(0, 0, 420, 300)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.tex = getTexture(CW.TEX_PATH)
    o.fonts = { UIFont.Large, UIFont.Medium, UIFont.Medium }
    o.curAlpha = 0
    return o
end

function CookieWatchPopup:alphaNow()
    local st = CW.state
    if not st or not st.popupStart then return 0 end
    local t = nowMs()
    local a = 1
    if t < st.popupStart + FADE_IN then a = (t - st.popupStart) / FADE_IN end
    if st.popupEnd then
        local left = st.popupEnd - t
        if left < FADE_OUT then a = math.min(a, left / FADE_OUT) end
    end
    if a < 0 then a = 0 end
    return a
end

function CookieWatchPopup:layout()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local tm = getTextManager()
    local logoH = math.floor(math.min(180, sh * 0.2))
    local logoW
    logoW, logoH = texSize(self.tex, logoH)
    if not self.tex then logoH = 0; logoW = 0 end
    local w = logoW
    local textH = 0
    for i = 1, 3 do
        local s = self.lines[i]
        if s ~= "" then
            local tw = tm:MeasureStringX(self.fonts[i], s)
            if tw > w then w = tw end
            textH = textH + tm:getFontHeight(self.fonts[i]) + 4
        end
    end
    w = w + 80
    local h = 24 + logoH + 12 + textH + 20
    self.logoW = logoW
    self.logoH = logoH
    self:setWidth(w)
    self:setHeight(h)
    self:setX(math.floor((sw - w) / 2))
    self:setY(math.floor((sh - h) / 2 - sh * 0.08))
end

function CookieWatchPopup:prerender()
    local st = CW.state
    if not st then return end
    self.lines = { CW.fill(st.l1), CW.fill(st.l2), CW.fill(st.l3) }
    self:layout()
    local a = self:alphaNow()
    self.curAlpha = a
    self:drawRect(0, 0, self.width, self.height, st.bgAlpha * a, 0.04, 0.05, 0.15)
    self:drawRectBorder(0, 0, self.width, self.height, 0.8 * a, st.ar, st.ag, st.ab)
    self:drawRect(0, 0, self.width, 3, 0.9 * a, st.ar, st.ag, st.ab)
end

function CookieWatchPopup:render()
    local st = CW.state
    local a = self.curAlpha or 0
    if not st or not self.lines or a <= 0 then return end
    local y = 24
    if self.tex then
        local x = math.floor((self.width - self.logoW) / 2)
        self:drawTextureScaledAspect(self.tex, x + 3, y + 4, self.logoW, self.logoH, 0.35 * a, 0, 0, 0)
        self:drawTextureScaledAspect(self.tex, x, y, self.logoW, self.logoH, a, 1, 1, 1)
    end
    y = y + self.logoH + 12
    local cx = self.width / 2
    local colors = { { st.ar, st.ag, st.ab }, { 1, 1, 1 }, { 0.82, 0.84, 0.92 } }
    local tm = getTextManager()
    for i = 1, 3 do
        local s = self.lines[i]
        if s ~= "" then
            local c = colors[i]
            local f = self.fonts[i]
            self:drawTextCentre(s, cx + 1, y + 1, 0, 0, 0, 0.6 * a, f)
            self:drawTextCentre(s, cx, y, c[1], c[2], c[3], a, f)
            y = y + tm:getFontHeight(f) + 4
        end
    end
end

function CookieWatchPopup:onMouseDown(x, y)
    CW.closePopup()
    return true
end

-- ---------------------------------------------------------------- mini chip
CookieWatchMini = ISPanel:derive("CookieWatchMini")

function CookieWatchMini:new()
    local o = ISPanel:new(0, 0, 220, 36)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.tex = getTexture(CW.TEX_PATH)
    o.font = UIFont.Medium
    return o
end

function CookieWatchMini:prerender()
    local st = CW.state
    if not st then return end
    local tm = getTextManager()
    self.text = CW.fill(st.mini)
    local fh = tm:getFontHeight(self.font)
    self.iconW, self.iconH = texSize(self.tex, fh + 8)
    if not self.tex then self.iconW = 0 end
    local w = 10 + self.iconW + 8 + tm:MeasureStringX(self.font, self.text) + 14
    local h = self.iconH + 8
    self:setWidth(w)
    self:setHeight(h)
    self:setX(math.floor((getCore():getScreenWidth() - w) / 2))
    self:setY(36)
    self.urgent = CW.remain() <= 60
    local pulse = 1
    if self.urgent then pulse = 0.65 + 0.35 * math.abs(math.sin(nowMs() / 300)) end
    self.pulse = pulse
    self:drawRect(0, 0, w, h, math.min(0.9, st.bgAlpha + 0.1), 0.04, 0.05, 0.15)
    self:drawRectBorder(0, 0, w, h, 0.75 * pulse, st.ar, st.ag, st.ab)
end

function CookieWatchMini:render()
    local st = CW.state
    if not st or not self.text then return end
    if self.tex then
        self:drawTextureScaledAspect(self.tex, 10, 4, self.iconW, self.iconH, 1, 1, 1, 1)
    end
    local tx = 10 + self.iconW + 8
    local ty = math.floor((self.height - getTextManager():getFontHeight(self.font)) / 2)
    local r, g, b = 1, 1, 1
    if self.urgent then r, g, b = st.ar, st.ag, st.ab end
    self:drawText(self.text, tx + 1, ty + 1, 0, 0, 0, 0.6, self.font)
    self:drawText(self.text, tx, ty, r, g, b, self.pulse or 1, self.font)
end

function CookieWatchMini:onMouseDown(x, y)
    CW.openPopup()
    return true
end

-- ---------------------------------------------------------------- control
function CW.ensureUI()
    if not CW.popup then
        CW.popup = CookieWatchPopup:new()
        CW.popup:initialise()
        CW.popup:addToUIManager()
        CW.popup:setAlwaysOnTop(true)
        CW.popup:setVisible(false)
    end
    if not CW.mini then
        CW.mini = CookieWatchMini:new()
        CW.mini:initialise()
        CW.mini:addToUIManager()
        CW.mini:setAlwaysOnTop(true)
        CW.mini:setVisible(false)
    end
end

function CW.openPopup(sec)
    local st = CW.state
    if not st then return end
    local t = nowMs()
    st.popupStart = t
    st.popupEnd = t + (sec or st.popupSec) * 1000
end

function CW.closePopup()
    local st = CW.state
    if st and st.popupEnd then
        local t = nowMs()
        if st.popupEnd > t + FADE_OUT then st.popupEnd = t + FADE_OUT end
    end
end

function CW.clear()
    CW.state = nil
    if CW.popup then CW.popup:setVisible(false) end
    if CW.mini then CW.mini:setVisible(false) end
end

function CW.onNotice(args)
    if args.kind == "clear" then
        CW.clear()
        return
    end
    local remain = tonumber(args.remain) or 0
    local ar, ag, ab = hexColor(args.accent, 1.0, 0.71, 0.33)
    CW.state = {
        id = args.id,
        kind = args.kind,
        deadline = nowMs() + remain * 1000,
        l1 = args.l1 or "",
        l2 = args.l2 or "",
        l3 = args.l3 or "",
        mini = args.mini or "",
        popupSec = tonumber(args.popup) or 15,
        bgAlpha = tonumber(args.alpha) or 0.6,
        ar = ar, ag = ag, ab = ab,
        showMini = args.showmini ~= "false" and args.mini ~= nil and args.mini ~= "",
    }
    CW.ensureUI()
    local sec = CW.state.popupSec
    if args.kind == "final" then sec = remain + 60 end
    CW.openPopup(sec)
    print("[CookieWatch] notice " .. tostring(args.kind) .. " remain=" .. tostring(remain))
end

function CW.onTick()
    if CW.syncAt and nowMs() >= CW.syncAt then
        CW.syncAt = nil
        local p = getPlayer()
        if p then sendClientCommand(p, "CookieWatch", "Sync", {}) end
    end
    local st = CW.state
    if not st then return end
    local t = nowMs()
    if t > st.deadline + 300000 then
        CW.clear()
        return
    end
    local popupOn = st.popupEnd ~= nil and t < st.popupEnd
    if CW.popup then CW.popup:setVisible(popupOn) end
    if CW.mini then CW.mini:setVisible((not popupOn) and st.showMini) end
end

local function onServerCommand(module, command, args)
    if module ~= "CookieWatch" then return end
    if command == "Notice" and type(args) == "table" then CW.onNotice(args) end
end

local function onGameStart()
    CW.syncAt = nowMs() + 5000
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(CW.onTick)
Events.OnGameStart.Add(onGameStart)
