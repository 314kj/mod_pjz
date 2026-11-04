-- Cookie Mission - warp fade, mission tracker, result card, toasts
require "CM_UI_Kit"

local C = CMUI.C
local T = CMC.txt

-- ===================================================================== fade (full screen, during warps)
CMFade = CMFade or {}
CMFade.Panel = ISUIElement:derive("CMFade_Panel")
local FP = CMFade.Panel

function FP:new()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISUIElement.new(self, 0, 0, sw, sh)
    o.a = 0
    o.phase = "in"
    o.t0 = CMC.ms()
    return o
end

function FP:render()
    local t = CMC.ms()
    local el = t - self.t0
    if self.phase == "in" then
        self.a = math.min(1, el / 450)
        if el >= 450 then
            self.phase = "hold"; self.t0 = t
            if self.mid then
                local fn = self.mid
                self.mid = nil
                local ok, err = pcall(fn)
                if not ok then CM.log("warp error: " .. tostring(err)); self.phase = "out"; self.t0 = t end
            end
        end
    elseif self.phase == "hold" then
        self.a = 1
        if self.released or el > 8000 then self.phase = "out"; self.t0 = t end
    elseif self.phase == "out" then
        self.a = math.max(0, 1 - el / 600)
        if el >= 600 then
            self:setVisible(false)
            self:removeFromUIManager()
            if CMFade.cur == self then CMFade.cur = nil end
            return
        end
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= sw then self:setWidth(sw) end
    if self.height ~= sh then self:setHeight(sh) end
    self:drawRect(0, 0, sw, sh, self.a, 0.010, 0.018, 0.045)
    local fh = CMUI.fh(UIFont.Large)
    local cy = sh / 2 - fh
    local aw = math.min(sw * 0.7, 900)
    CMUI.texBox(self, "cm_dots", (sw - aw) / 2, cy - aw * 0.24, aw, aw * 0.21, C.white, self.a * 0.9)
    CMUI.glow(self, sw / 2, cy + fh / 2, aw * 0.3, fh * 2.2, C.accent, self.a * 0.25)
    self:drawTextCentre(tostring(self.text or ""), sw / 2, cy, C.text[1], C.text[2], C.text[3], self.a, UIFont.Large)
    -- scanning bar under the text
    local bw = math.min(360, sw * 0.4)
    local bx = (sw - bw) / 2
    local by = cy + fh + 14
    self:drawRect(bx, by, bw, 2, self.a * 0.25, C.accent[1], C.accent[2], C.accent[3])
    local k = CM.mod(t / 900, 1)
    CMUI.texBox(self, "cm_hline", bx + (bw - 120) * k, by - 1, 120, 4, C.gold, self.a)
end

function CMFade.run(text, mid)
    if CMFade.cur then
        pcall(function() CMFade.cur:removeFromUIManager() end)
        CMFade.cur = nil
    end
    local f = FP:new()
    f.text = text
    f.mid = mid
    f:initialise()
    f:addToUIManager()
    pcall(function() f:setAlwaysOnTop(true) end)
    f:bringToTop()
    CMFade.cur = f
end

function CMFade.release()
    if CMFade.cur then CMFade.cur.released = true end
end

-- ===================================================================== tracker
CMHud = CMHud or {}
CMHud.Panel = CMUI.Window:derive("CMHud_Panel")
local HP = CMHud.Panel

function HP:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.headerH = 0
    o.title = ""
    return o
end

function HP:drawFrame() end

-- drag from anywhere that is not a button
function HP:onMouseDown(x, y)
    local h = self:findHit(x, y)
    if h then self.pressed = h; return true end
    self.dragging = true
    return true
end

function HP:onMouseUp(x, y)
    local moved = self.dragging and self.dragMoved
    CMUI.Window.onMouseUp(self, x, y)
    if moved then
        CMHud.savePos(self:getX(), self:getY())
    end
    self.dragMoved = false
    return true
end

function HP:onMouseMove(dx, dy)
    if self.dragging then
        self.dragMoved = true
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end
HP.onMouseMoveOutside = HP.onMouseMove

-- world: +x = east, +y = south; tan(22.5 deg) ~ 0.414 splits the 8 sectors without trig
local function dirOf(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax < 0.001 and ay < 0.001 then return "N" end
    local ns = dy < 0 and "N" or "S"
    local ew = dx > 0 and "E" or "W"
    if ay <= ax * 0.414 then return ew end
    if ax <= ay * 0.414 then return ns end
    return ns .. ew
end
CMHud.dirOf = dirOf

local confirmLeave = 0

local function drawRun(self, x, y, w, run)
    local S = CMUI.S
    local tc = CMUI.tierColor(run.tier)
    local fs, fm = UIFont.Small, UIFont.Medium
    local lh = CMUI.fh(fs) + S(4)
    -- header row
    local pw = CMUI.pill(self, x, y + 2, CMC.tierName(run.tier), tc, fs, false)
    CMUI.text(self, CMUI.fit(CMC.typeName(run.type), fm, w - pw - S(80)), x + pw + S(8), y, C.white, 1, fm)
    local left = CMC.left(run.left, CMC.meAt) or 0
    if run.phase == "live" then
        local col = left <= 60 and C.bad or C.gold
        CMUI.textR(self, CM.clock(left), x + w, y, col, 1, fm)
    end
    y = y + CMUI.fh(fm) + S(4)
    CMUI.text(self, CMUI.fit(CMC.kindName(run.kind) .. " - " .. tostring(run.town), fs, w), x, y, C.dim)
    y = y + lh
    if run.phase == "live" then
        -- progress
        local cur, goal = run.cur or 0, math.max(1, run.goal or 1)
        local label
        if run.type == "survive" then
            local held = math.min(goal, cur + (CMC.age(CMC.meAt)))
            label = T("IGUI_CM_Prog_survive", CM.clock(held), CM.clock(goal))
            cur = held
        else
            label = T("IGUI_CM_Prog_" .. run.type, cur, goal)
        end
        CMUI.text(self, label, x, y, C.text, 1, fs)
        CMUI.textR(self, tostring(math.floor(cur * 100 / goal)) .. "%", x + w, y, tc, 1, fs)
        y = y + CMUI.fh(fs) + S(4)
        CMUI.segbar(self, x, y, w, S(8), cur / goal, tc, 24)
        y = y + S(8) + S(8)
        local nIn = 0
        for _, m in ipairs(run.members or {}) do if m.st == "in" then nIn = nIn + 1 end end
        CMUI.text(self, T("IGUI_CM_Team", nIn), x, y, C.text)
        CMUI.textR(self, T("IGUI_CM_Near", run.alive or 0), x + w, y, C.dim)
        y = y + lh
        if run.type ~= "survive" and (run.myKills or 0) > 0 then
            CMUI.text(self, T("IGUI_CM_MyKills", run.myKills), x, y, C.dim)
            y = y + lh
        end
        local p = CMC.player()
        local px, py = 0, 0
        if p then px, py = p:getX(), p:getY() end
        -- supply caches: hot / cold
        if run.type == "find" and run.caches and p then
            local best = 99999
            for _, c in ipairs(run.caches) do
                local dx, dy = c.x - px, c.y - py
                local d = math.sqrt(dx * dx + dy * dy)
                if d < best then best = d end
            end
            if #run.caches > 0 then
                local key, col = "cold", C.blue
                if best <= 4 then key, col = "burning", C.bad
                elseif best <= 10 then key, col = "hot", C.white
                elseif best <= 22 then key, col = "warm", C.gold end
                CMUI.text(self, T("IGUI_CM_Heat_" .. key), x, y, col)
                y = y + lh
            end
        end
        -- where is the building / leaving warning
        if run.zone and p then
            local d = CM.rectDist(run.zone, px, py)
            if d > 2 then
                local cx = (run.zone.x1 + run.zone.x2) / 2
                local cy = (run.zone.y1 + run.zone.y2) / 2
                CMUI.text(self, T("IGUI_CM_Where", T("IGUI_CM_Dir_" .. dirOf(cx - px, cy - py)), math.floor(d)), x, y, C.gold)
                y = y + lh
            end
            if (run.out or 0) > 0 then
                local rest = math.max(0, CM.sv("LeaveSeconds") - run.out - CMC.age(CMC.meAt))
                CMUI.text(self, T("IGUI_CM_OutWarn", math.ceil(rest)), x, y, C.bad)
                y = y + lh
            end
        end
        if run.claimed then
            CMUI.text(self, T("IGUI_CM_HelperOnly"), x, y, C.faint)
            y = y + lh
        end
        y = y + S(2)
        local armed = CMC.ms() - confirmLeave < 4000
        local bw = CMUI.btnA(self, x, y, S(24), T(armed and "IGUI_CM_LeaveSure" or "IGUI_CM_Leave"), function()
            if CMC.ms() - confirmLeave < 4000 then
                confirmLeave = 0
                CMC.send("leave", {})
            else
                confirmLeave = CMC.ms()
            end
        end, "danger", { tip = T("IGUI_CM_LeaveTip") })
        local _ = bw
        y = y + S(24) + S(4)
    else
        -- finished, waiting for the trip home
        local ok = run.res == "ok"
        CMUI.text(self, T(ok and "IGUI_CM_ResOk" or ("IGUI_CM_Res_" .. tostring(run.res))), x, y, ok and C.good or C.bad, 1, fm)
        y = y + CMUI.fh(fm) + S(4)
        y = CMHud.drawRewards(self, x, y, w, CMC.result and CMC.result.rw or nil, CMC.result and CMC.result.nr or nil)
        local back = CMC.left(run.backIn, CMC.meAt) or 0
        CMUI.text(self, T("IGUI_CM_BackIn", math.ceil(back)), x, y + S(4), C.dim)
        CMUI.btnA(self, x + w - S(120), y, S(24), T("IGUI_CM_GoHome"), function() CMC.send("home", {}) end, "primary",
            { minW = S(120) })
        y = y + S(24) + S(4)
    end
    return y
end

function CMHud.drawRewards(self, x, y, w, list, why)
    local lh = CMUI.fh(UIFont.Small) + CMUI.S(3)
    if list and #list > 0 then
        CMUI.text(self, T("IGUI_CM_YouGot"), x, y, C.gold)
        y = y + lh
        for _, it in ipairs(list) do
            local s = CMC.itemName(it.t)
            if (it.n or 1) > 1 then s = s .. " x" .. tostring(it.n) end
            CMUI.text(self, CMUI.fit("+ " .. s, UIFont.Small, w), x + CMUI.S(6), y, C.text)
            y = y + lh
        end
    elseif why then
        CMUI.text(self, CMUI.fit(T("IGUI_CM_NoReward_" .. tostring(why)), UIFont.Small, w), x, y, C.dim)
        y = y + lh
    end
    return y
end

local function drawResult(self, x, y, w, res)
    local S = CMUI.S
    local fm = UIFont.Medium
    local ok = res.res == "ok" or res.res == "late" or res.res == "test"
    local key = "IGUI_CM_Res_" .. tostring(res.res)
    if res.res == "ok" then key = "IGUI_CM_ResOk" end
    CMUI.text(self, T(key), x, y, ok and C.good or C.bad, 1, fm)
    y = y + CMUI.fh(fm) + S(4)
    y = CMHud.drawRewards(self, x, y, w, res.rw, res.nr)
    CMUI.btnA(self, x + w - S(80), y, S(22), T("IGUI_CM_Close"), function() CMC.result = nil end, "ghost", { minW = S(80) })
    return y + S(26)
end

local function drawToasts(self, x, y, w)
    local lh = CMUI.fh(UIFont.Small) + CMUI.S(6)
    for i = 1, #CMC.toasts do
        local t = CMC.toasts[i]
        local c = C[t.c or "text"] or C.text
        local lines = CMUI.wrap(t.s, UIFont.Small, w - CMUI.S(16))
        local h = #lines * (CMUI.fh(UIFont.Small) + 2) + CMUI.S(8)
        CMUI.rbox(self, x + 4, y, w - 8, h, C.bg, 0.78, 6)
        CMUI.rborder(self, x + 4, y, w - 8, h, c, 0.45, 6)
        CMUI.rect(self, x + 4, y + 4, 2, h - 8, c, 1)
        CMUI.glow(self, x + 6, y + h / 2, 14, h * 0.6, c, 0.35)
        for j = 1, #lines do
            CMUI.text(self, lines[j], x + CMUI.S(14), y + CMUI.S(4) + (j - 1) * (CMUI.fh(UIFont.Small) + 2), c)
        end
        y = y + h + CMUI.S(4)
        local _ = lh
    end
    return y
end

function HP:drawBody()
    local S = CMUI.S
    local w = self.width
    local pad = S(10)
    local run = CMC.run()
    local res = CMC.result
    if res and CMC.age(CMC.resultAt) > 40 then CMC.result = nil; res = nil end
    local y = 0
    if run or res then
        -- measure once: draw at y then size the box to what was drawn
        local top = y
        local bh = self.lastBoxH or S(120)
        local tc = CMUI.tierColor(run and run.tier or 1)
        CMUI.glow(self, w / 2, top + S(4), w * 0.45, S(40), tc, 0.18)
        CMUI.rbox(self, 4, top + 4, w - 8, bh - 8, C.bg, 0.62, 10)
        CMUI.glass(self, 4, top + 4, w - 8, bh - 8, { tint = C.panel, a = 0.35, rad = 10, rim = tc, rimA = 0.55 })
        CMUI.brackets(self, 4, top + 4, w - 8, bh - 8, tc, 0.85, S(10), 2)
        local ny
        if run then ny = drawRun(self, pad + 4, top + pad + 2, w - pad * 2 - 8, run)
        else ny = drawResult(self, pad + 4, top + pad + 2, w - pad * 2 - 8, res) end
        self.lastBoxH = ny - top + pad - S(4)
        y = top + self.lastBoxH + S(6)
    end
    if #CMC.toasts > 0 then y = drawToasts(self, 0, y, w) end
    local wantH = math.max(10, y)
    if math.abs(self.height - wantH) > 1 then self:setHeight(wantH) end
end

function CMHud.savePos(x, y)
    CMHud.pos = { x = math.floor(x), y = math.floor(y) }
end

function CMHud.wanted()
    return CMC.run() ~= nil or CMC.result ~= nil or #CMC.toasts > 0
end

function CMHud.update()
    local want = CMHud.wanted()
    if want and not CMHud.panel then
        local w = CMUI.S(330)
        CMUI.k = CMUI.fontScale()
        w = math.floor(330 * CMUI.k)
        local sw = getCore():getScreenWidth()
        local x = CMHud.pos and CMHud.pos.x or math.floor(sw - w - 230)
        local y = CMHud.pos and CMHud.pos.y or 90
        local p = HP:new(x, y, w, 60)
        p:show()
        CMHud.panel = p
    elseif not want and CMHud.panel then
        CMHud.panel:close()
        CMHud.panel = nil
    end
end

Events.OnTick.Add(function()
    local ok, err = pcall(CMHud.update)
    if not ok then CM.log("hud error: " .. tostring(err)) end
end)

return CMHud
