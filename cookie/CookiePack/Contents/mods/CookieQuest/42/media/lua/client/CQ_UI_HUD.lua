-- Cookie Quest - HUD: buff chips (next to moodles), mission tracker, toasts
require "CQ_UI_Kit"

CQHUD = CQHUD or {}
local C = CQUI.C
local T = CQC.txt
local FS = UIFont.Small

-- ===================================================================== buff chip data
function CQHUD.chips()
    local out = {}
    local now = CQC.now()
    local pub = CQC.pub
    if pub and pub.buffs then
        for _, b in ipairs(pub.buffs) do
            if CQ.num(b.untilTs, 0) > now then
                local skills = ""
                if b.skills and #b.skills > 0 then
                    local names = {}
                    for i = 1, #b.skills do names[#names + 1] = CQC.skillName(b.skills[i]) end
                    skills = table.concat(names, ", ")
                else
                    skills = T("IGUI_CQ_AllSkills")
                end
                local tip = T("IGUI_CQ_BuffTip", "x" .. CQ.fmt(b.mult, 2), skills)
                if b.label and b.label ~= "" then tip = b.label .. "\n" .. tip end
                out[#out + 1] = { up = b.mult >= 1, text = "EXP x" .. CQ.fmt(b.mult, 2), left = b.untilTs - now, tip = tip }
            end
        end
    end
    local pen = CQC.me and CQC.me.pen
    if pen and CQ.num(pen.untilTs, 0) > now then
        local tip = T("IGUI_CQ_PenTip", "x" .. CQ.fmt(pen.mult, 2), pen.reason or "")
        out[#out + 1] = { up = false, text = "EXP x" .. CQ.fmt(pen.mult, 2), left = pen.untilTs - now, tip = tip, pen = true }
    end
    return out
end

-- ===================================================================== HUD panel
CQHUD.Panel = CQUI.Window:derive("CQHUD_Panel")
local P = CQHUD.Panel
P.WIDTH = 296

function P:new(x, y)
    local o = CQUI.Window.new(self, x, y, math.floor(P.WIDTH * CQUI.fontScale()), 30)
    o.headerH = 0
    return o
end

function P:onMouseDown(x, y)
    self.downX, self.downY = getMouseX(), getMouseY()
    self.dragging = false
    self.mouseHeld = true
    self.pressed = self:findHit(x, y)
    return true
end

function P:onMouseMove(dx, dy)
    if self.mouseHeld then
        if not self.dragging and (math.abs(getMouseX() - self.downX) + math.abs(getMouseY() - self.downY)) > 5 then
            self.dragging = true
        end
        if self.dragging then
            self:setX(self:getX() + dx)
            self:setY(self:getY() + dy)
        end
    end
end
P.onMouseMoveOutside = P.onMouseMove

function P:onMouseUp(x, y)
    local was = self.pressed
    local dragged = self.dragging
    self.mouseHeld = false
    self.dragging = false
    self.pressed = nil
    if dragged then
        CQC.cfg.hudX = tostring(math.floor(self:getX()))
        CQC.cfg.hudY = tostring(math.floor(self:getY()))
        CQC.saveCfg()
        return true
    end
    if was and was.fn then pcall(was.fn) end
    return true
end

function P:onMouseUpOutside(x, y)
    if self.dragging then
        CQC.cfg.hudX = tostring(math.floor(self:getX()))
        CQC.cfg.hudY = tostring(math.floor(self:getY()))
        CQC.saveCfg()
    end
    self.mouseHeld = false
    self.dragging = false
    self.pressed = nil
end

local function openBoard()
    if CQBoard and CQBoard.toggle then CQBoard.toggle("missions") end
end

function P:drawBody() end

function P:prerenderBody()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self:getX() > sw - self.width then self:setX(math.max(0, sw - self.width)) end
    if self:getY() > sh - math.max(40, self.height) then self:setY(math.max(0, sh - math.max(40, self.height))) end
    self.hits = {}
    self.scrollAreas = {}
    self.clipStack = {}
    self.curArea = nil
    self.clip = nil
    self.tipText = nil
    local W = self.width
    local y = 0
    local fh = CQUI.fh(FS)
    -- chips (right aligned)
    local chips = CQHUD.chips()
    if #chips > 0 then
        local x = W
        local ch = fh + 8
        for i = #chips, 1, -1 do
            local c = chips[i]
            local left = CQUI.dur(c.left)
            local cw = 8 + 16 + 6 + CQUI.tw(FS, c.text) + 8 + CQUI.tw(FS, left) + 10
            if x - cw < 0 then x = W; y = y + ch + 4 end
            x = x - cw
            local col = c.up and C.gold or C.bad
            self:hit(x, y, cw, ch, openBoard, c.tip)
            CQUI.rbox(self, x, y, cw, ch, C.dark, 0.82, 7)
            CQUI.rbox(self, x, y, 3, ch, col, 1, 1)
            if not CQUI.icon(self, c.up and "cq_buff_up" or "cq_buff_down", x + 8, y + (ch - 16) / 2, 16, col) then
                CQUI.text(self, c.up and "+" or "-", x + 10, y + 4, col)
            end
            CQUI.text(self, c.text, x + 30, y + 4, col)
            CQUI.text(self, left, x + 30 + CQUI.tw(FS, c.text) + 8, y + 4, C.dim)
            x = x - 6
        end
        y = y + ch + 6
    end
    -- tracker
    local inst = CQC.cfg.hud ~= "0" and CQC.cfg.track and CQC.instById(CQC.cfg.track) or nil
    if inst and inst.status == "active" then
        local st = CQC.curStep(inst)
        local x0, w = 0, W
        local lines = 0
        local hgt = 10 + fh + 4 + fh + 4
        local goal = CQUI.stepGoal(st)
        if goal ~= "" then hgt = hgt + fh + 2 end
        local barNeeded = st and (st.t == "kill" or st.t == "deliver" or st.t == "collect" or st.t == "others" or st.t == "hold")
        if barNeeded then hgt = hgt + 10 end
        local tgt = CQC.trackTarget()
        if tgt then hgt = hgt + fh + 4 end
        if inst.wait and #inst.wait > 0 then hgt = hgt + fh + 2 end
        if inst.deadline then hgt = hgt + fh + 2 end
        hgt = hgt + 6
        self:hit(x0, y, w, hgt, openBoard, T("IGUI_CQ_TrackerTip"))
        CQUI.rbox(self, x0, y, w, hgt, C.dark, 0.80, 8)
        CQUI.rbox(self, x0, y, 3, hgt, C.accent, 1, 1)
        local cy = y + 8
        local ic = st and CQUI.STEP_ICON[st.t]
        if ic then CQUI.icon(self, ic, x0 + 10, cy, fh, CQUI.STEP_COLOR[st.t] or C.accent) end
        CQUI.text(self, CQUI.fit(inst.title or "", FS, w - 70), x0 + 14 + fh, cy, C.gold)
        CQUI.textR(self, tostring(inst.step) .. "/" .. tostring(inst.nSteps), x0 + w - 10, cy, C.dim)
        cy = cy + fh + 4
        CQUI.text(self, CQUI.fit(CQUI.stepLabel(st), FS, w - 24), x0 + 12, cy, C.text)
        cy = cy + fh + 4
        if goal ~= "" then
            CQUI.text(self, CQUI.fit(goal, FS, w - 24), x0 + 12, cy, C.dim)
            cy = cy + fh + 2
        end
        if barNeeded then
            local frac, txt = 0, ""
            if st.t == "hold" then
                frac = (inst.hold or 0) / math.max(1, st.sec or 60)
            else
                frac = (inst.cnt or 0) / math.max(1, st.n or 1)
            end
            CQUI.bar(self, x0 + 12, cy + 2, w - 24, 5, frac, CQUI.STEP_COLOR[st.t] or C.accent)
            cy = cy + 10
        end
        if tgt then
            local p = CQC.player()
            if p then
                local d = CQ.distToZone(tgt.zone, p:getX(), p:getY())
                local inside = CQ.inZone(tgt.zone, p:getX(), p:getY(), p:getZ())
                local wrong = CQUI.wrongFloor(tgt.zone, p:getX(), p:getY(), p:getZ())
                if inside then
                    CQUI.text(self, T("IGUI_CQ_InZone"), x0 + 12, cy, C.good)
                elseif wrong then
                    CQUI.text(self, CQUI.fit(wrong, FS, w - 24), x0 + 12, cy, C.accent)
                else
                    local dk = CQUI.dirKey(tgt.x - p:getX(), tgt.y - p:getY())
                    if not CQUI.icon(self, "cq_dir_" .. dk, x0 + 12, cy, fh, C.accent) then
                        CQUI.text(self, dk, x0 + 12, cy, C.accent)
                    end
                    local txt = T("IGUI_CQ_Dist", math.floor(d + 0.5)) .. "  " .. CQUI.floorInfo(tgt.zone, p:getZ())
                    CQUI.text(self, txt, x0 + 16 + fh, cy, C.text)
                end
                cy = cy + fh + 4
            end
        end
        if inst.wait and #inst.wait > 0 then
            CQUI.text(self, CQUI.fit(T("IGUI_CQ_WaitFor", table.concat(inst.wait, ", ")), FS, w - 24), x0 + 12, cy, C.accent)
            cy = cy + fh + 2
        end
        if inst.deadline then
            CQUI.text(self, T("IGUI_CQ_TimeLeft", CQUI.dur(inst.deadline - CQC.now())), x0 + 12, cy, C.bad)
        end
        y = y + hgt
    end
    if y < 1 then y = 1 end
    if self.height ~= y then self:setHeight(y) end
end

function P:renderBody()
    if not self.tipText then return end
    local lines = CQUI.wrap(self.tipText, FS, 250)
    local lh = CQUI.fh(FS) + 2
    local w = 0
    for i = 1, #lines do w = math.max(w, CQUI.tw(FS, lines[i])) end
    w = w + 16
    local h = #lines * lh + 10
    local x = math.min(self:getMouseX() - w / 2, self.width - w)
    local y = self:getMouseY() + 18
    CQUI.rbox(self, x, y, w, h, C.dark, 0.95, 5)
    CQUI.border(self, x, y, w, h, C.accent, 0.5)
    for i = 1, #lines do CQUI.text(self, lines[i], x + 8, y + 5 + (i - 1) * lh, C.text) end
end

-- ===================================================================== toasts
CQHUD.Toast = ISPanel:derive("CQHUD_Toast")
local TP = CQHUD.Toast
local TOAST_MS = 5200

function TP:new()
    local w = 460
    local o = ISPanel.new(self, (getCore():getScreenWidth() - w) / 2, 70, w, 10)
    o.background = false
    return o
end

local STYLE_COL = { good = C.good, gold = C.gold, accent = C.accent, bad = C.bad, dim = C.dim, radio = { 0.55, 0.9, 0.95 } }

function TP:prerenderBody()
    local now = getTimestampMs()
    local live = {}
    for _, t in ipairs(CQC.toasts) do
        if now - t.ms < TOAST_MS then live[#live + 1] = t end
    end
    CQC.toasts = live
    local y = 0
    local fh = CQUI.fh(FS)
    local fm = CQUI.fh(UIFont.Medium)
    for i = #live, math.max(1, #live - 2), -1 do
        local t = live[i]
        local age = now - t.ms
        local a = 1
        if age > TOAST_MS - 700 then a = (TOAST_MS - age) / 700 end
        if age < 180 then a = age / 180 end
        local col = STYLE_COL[t.style] or C.accent
        local lines = CQUI.wrap(t.text or "", UIFont.Medium, self.width - 40)
        local h = 12 + #lines * (fm + 2) + (t.sub and (fh + 4) or 0) + 8
        CQUI.rbox(self, 0, y, self.width, h, C.dark, 0.88 * a, 9)
        CQUI.rbox(self, 0, y, 4, h, col, a, 2)
        local ty = y + 8
        for j = 1, #lines do
            CQUI.textC(self, lines[j], self.width / 2, ty, col, a, UIFont.Medium)
            ty = ty + fm + 2
        end
        if t.sub then
            CQUI.textC(self, CQUI.fit(t.sub, FS, self.width - 30), self.width / 2, ty + 2, C.dim, a, FS)
        end
        y = y + h + 6
    end
    if y < 1 then y = 1 end
    self:setHeight(y)
    self:setX((getCore():getScreenWidth() - self.width) / 2)
    if #live == 0 then self:setVisible(false) end
end

function TP:onMouseDown(x, y)
    CQC.toasts = {}
    self:setVisible(false)
    return true
end

-- ===================================================================== lifecycle
-- a drawing error must never spam the console every frame: log once, keep the game running
local function safe(self, fn, tag)
    local ok, err = pcall(fn, self)
    if not ok and not self["err" .. tag] then
        self["err" .. tag] = true
        CQ.log("hud " .. tag .. " error: " .. tostring(err))
    end
end
function P:prerender() safe(self, P.prerenderBody, "pre") end
function P:render() safe(self, P.renderBody, "ren") end
function TP:prerender() safe(self, TP.prerenderBody, "toast") end

function CQHUD.ensure()
    if not CQHUD.hud then
        local sw = getCore():getScreenWidth()
        local hw = math.floor(P.WIDTH * CQUI.fontScale())
        local x = CQC.cfgNum("hudX", sw - 52 - hw - 12)
        local y = CQC.cfgNum("hudY", 10)
        x = CQ.clamp(x, 0, math.max(0, sw - hw))
        y = CQ.clamp(y, 0, math.max(0, getCore():getScreenHeight() - 40))
        CQHUD.hud = P:new(x, y)
        CQHUD.hud:initialise()
        CQHUD.hud:instantiate()
        CQHUD.hud:addToUIManager()
        CQHUD.hud:setAlwaysOnTop(false)
    end
    if not CQHUD.toast then
        CQHUD.toast = TP:new()
        CQHUD.toast:initialise()
        CQHUD.toast:instantiate()
        CQHUD.toast:addToUIManager()
        CQHUD.toast:setAlwaysOnTop(true)
        CQHUD.toast:setVisible(false)
    end
end

local tickN = 0
local function refresh()
    tickN = tickN + 1
    if CQ.mod(tickN, 15) ~= 0 then return end
    local p = CQC.player()
    if not p then return end
    CQHUD.ensure()
    local need = #CQHUD.chips() > 0
    if not need and CQC.cfg.hud ~= "0" and CQC.cfg.track then
        local inst = CQC.instById(CQC.cfg.track)
        need = inst ~= nil and inst.status == "active"
    end
    if CQHUD.hud:isVisible() ~= need then CQHUD.hud:setVisible(need) end
    if #CQC.toasts > 0 and not CQHUD.toast:isVisible() then
        CQHUD.toast:setVisible(true)
        CQHUD.toast:bringToTop()
    end
end

Events.OnTick.Add(function()
    local ok, err = pcall(refresh)
    if not ok then CQ.log("hud error: " .. tostring(err)) end
end)

CQC.on(function(what)
    if what == "toast" and CQHUD.toast then
        CQHUD.toast:setVisible(true)
        CQHUD.toast:bringToTop()
    end
end)

return CQHUD
