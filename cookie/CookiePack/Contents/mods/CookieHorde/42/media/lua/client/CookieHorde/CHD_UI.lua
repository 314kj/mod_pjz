-- Cookie Horde - admin window: a spawn tab (new spot, lag advice, running spots) and a preset tab
-- Opened from the ground's right-click menu ("Cookie Horde: spawn here").
if isServer() and not isClient() then return end

require "ISUI/ISPanel"
require "CM_UI_Kit"
require "CookieHorde/CHD_Client"

CHDUI = CHDUI or {}
local C = CMUI.C
local T = CHDC.txt
local S = CMUI.S
local N = CHDC.n
local ORANGE = { 1.00, 0.72, 0.30 }
local LEVEL_COLOR = { low = C.good, mid = ORANGE, high = C.bad }

local function fh() return CMUI.fh(UIFont.Small) end

local function metrics()
    return {
        pad = S(14),
        gap = S(10),
        rowH = math.max(S(30), fh() + S(10)),
        tabH = math.max(S(32), fh() + S(14)),
        labelW = S(150),
    }
end

local function newEdit()
    return { id = "", name = "Horde", speed = "server", slow = 100, hp = 1, res = CHD.cleanRes(nil), outfits = {}, drops = {} }
end

-- ===================================================================== window
CHDUI.Win = CMUI.Window:derive("CHD_Window")
local W = CHDUI.Win

function W:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = "COOKIE HORDE"
    o.titleIcon = nil
    o.tab = "spawn"
    o.edit = newEdit()
    o.bgAlpha = 0.90
    return o
end

function W:makeEntries()
    self.eName = CMUI.entry(self, 0, 0, 100, 24, { max = 40, text = self.edit.name })
    self.eOutfit = CMUI.entry(self, 0, 0, 100, 24, { max = 40, tip = T("IGUI_CHD_SearchTip") })
    self.eItem = CMUI.entry(self, 0, 0, 100, 24, { max = 40, tip = T("IGUI_CHD_SearchTip") })
end

local function place(e, x, y, w, h, vis)
    if not e then return end
    e:setVisible(vis)
    if not vis then return end
    if e:getX() ~= x then e:setX(x) end
    if e:getY() ~= y then e:setY(y) end
    if e:getWidth() ~= w then e:setWidth(w) end
    if e:getHeight() ~= h then e:setHeight(h) end
end

function W:setTab(k)
    self.tab = k
    if k == "spawn" then CHDC.touchDraft() end
end

function W:loadEdit(pre)
    local e = newEdit()
    if pre then
        e.id = pre.id
        e.name = pre.name
        e.speed = pre.speed
        e.slow = CHD.slowOf(pre.slow)
        e.hp = CHD.hpOf(pre.hp)
        e.res = CHD.cleanRes(pre.res)
        e.outfits = CHDC.arr(pre.outfits)
        e.drops = {}
        for _, d in ipairs(CHDC.arr(pre.drops)) do e.drops[#e.drops + 1] = { ft = d.ft, pct = d.pct, n = d.n } end
    end
    self.edit = e
    CMUI.setVal(self.eName, e.name)
    CMUI.setVal(self.eOutfit, "")
    CMUI.setVal(self.eItem, "")
end

function W:label(s, x, y, rh)
    CMUI.text(self, s, x, y + (rh - fh()) / 2, C.dim)
end

-- small quick-pick buttons; returns the x after them
function W:quick(x, y, h, values, cur, fn, fmt)
    for _, v in ipairs(values) do
        local label = fmt and fmt(v) or N(v)
        local bw = CMUI.btnA(self, x, y, h, label, function() fn(v) end, v == cur and "sel" or "flat", { minW = S(44) })
        x = x + bw + S(4)
    end
    return x
end

-- ===================================================================== spawn tab
function W:drawLag(x, y, w)
    local d = CHDC.draft
    local est = CHDC.est
    local lh = fh() + S(3)
    if d.x == nil then
        return y + CMUI.para(self, T("IGUI_CHD_PickFirst"), x, y, w, C.faint)
    end
    if not est then
        CMUI.text(self, T("IGUI_CHD_LagWait"), x, y, C.faint)
        return y + lh
    end
    local col = LEVEL_COLOR[est.level] or C.dim
    local pw = CMUI.pill(self, x, y, T("IGUI_CHD_Lag_" .. tostring(est.level)), col, UIFont.Small, true)
    CMUI.text(self, T("IGUI_CHD_Expected", CM.num(est.expected, 0)), x + pw + S(10), y + 1, C.text)
    y = y + lh + S(6)
    for _, r in ipairs(est.reasons) do
        local s = T("IGUI_CHD_R_" .. tostring(r.key), r.a, r.b)
        y = y + CMUI.para(self, "- " .. s, x + S(6), y, w - S(6), r.key == "ok" and C.good or C.text)
    end
    if est.suggest ~= nil then
        local n = CM.int(est.suggest, 0)
        y = y + S(4)
        if n >= 10 and n < d.total then
            local tens = math.floor(n / 10) * 10
            CMUI.btnA(self, x, y, S(28), T("IGUI_CHD_UseSuggest", tens), function()
                d.total = tens
                CHDC.touchDraft()
            end, "ghost")
            y = y + S(28) + S(4)
        elseif n < 10 then
            y = y + CMUI.para(self, T("IGUI_CHD_ClearFirst"), x, y, w, ORANGE)
        end
    end
    y = y + S(4)
    y = y + CMUI.para(self, T("IGUI_CHD_LagNote"), x, y, w, C.faint)
    return y
end

function W:drawPoints(x, y, w)
    local pts = CHDC.points
    local rh = metrics().rowH
    if #pts == 0 then
        CMUI.text(self, T("IGUI_CHD_NoSpots"), x, y, C.faint)
        return y + fh() + S(6)
    end
    for _, pt in ipairs(pts) do
        local h = fh() * 2 + S(22)
        CMUI.rbox(self, x, y, w, h, C.panel2, 0.55, 6)
        local bw = S(90)
        CMUI.btn(self, x + w - bw - S(8), y + (h - rh) / 2, bw, rh, T("IGUI_CHD_Cancel"), function()
            CHDC.send("cancel", { id = pt.id })
        end, "danger", { tip = T("IGUI_CHD_CancelTip") })
        local tw = w - bw - S(28)
        local name = (pt.name ~= nil and pt.name ~= "") and pt.name or T("IGUI_CHD_NoPreset")
        CMUI.text(self, CMUI.fit(name .. "  " .. N(pt.x) .. ", " .. N(pt.y) .. ", " .. N(pt.z), UIFont.Small, tw),
            x + S(10), y + S(6), C.text)
        local by = y + S(8) + fh()
        CMUI.bar(self, x + S(10), by + S(2), S(120), S(8), CM.num(pt.done, 0) / math.max(1, CM.num(pt.total, 1)), C.accent)
        local line = T("IGUI_CHD_SpotLine", pt.done, pt.total, pt.perMin) .. "  " .. T("IGUI_CHD_Alive", pt.alive)
        if pt.wait == "area" then line = line .. "  " .. T("IGUI_CHD_WaitArea") end
        if pt.wait == "fail" then line = line .. "  " .. T("IGUI_CHD_WaitFail") end
        CMUI.text(self, CMUI.fit(line, UIFont.Small, tw - S(130)), x + S(140), by - S(2), pt.wait and ORANGE or C.dim)
        y = y + h + S(6)
    end
    return y
end

function W:drawSpawn(x, y, w, h)
    local m = metrics()
    local d = CHDC.draft
    local rh = m.rowH
    local lw = m.labelW
    CHDC.pumpEstimate()
    self:form("spawn", x, y, w, h, function(top)
        local yy = top
        local cw = w - S(14)
        yy = yy + CMUI.section(self, x, yy, cw, T("IGUI_CHD_NewSpot"))
        -- spot
        self:label(T("IGUI_CHD_Spot"), x, yy, rh)
        if d.x ~= nil then
            CMUI.text(self, N(d.x) .. ", " .. N(d.y) .. ", " .. N(d.z), x + lw, yy + (rh - fh()) / 2, C.text)
        else
            CMUI.text(self, T("IGUI_CHD_SpotNone"), x + lw, yy + (rh - fh()) / 2, C.faint)
        end
        local hereW = CMUI.tw(UIFont.Small, T("IGUI_CHD_Here")) + 22
        CMUI.btn(self, x + cw - hereW, yy, hereW, rh, T("IGUI_CHD_Here"), function()
            local p = CHDC.player()
            if p then CHDC.setSpot(p:getX(), p:getY(), p:getZ()) end
        end, "ghost")
        yy = yy + rh + S(6)
        -- preset
        self:label(T("IGUI_CHD_Preset"), x, yy, rh)
        local ids = { "" }
        for _, pr in ipairs(CHDC.presets) do ids[#ids + 1] = pr.id end
        local cur = 1
        for i = 1, #ids do if ids[i] == d.pid then cur = i end end
        local pre = CHDC.presetById(d.pid)
        local ptxt = pre and pre.name or T("IGUI_CHD_NoPreset")
        CMUI.cycle(self, x + lw, yy, math.min(S(320), cw - lw), rh, ptxt,
            function() d.pid = ids[CM.mod(cur - 2, #ids) + 1] end,
            function() d.pid = ids[CM.mod(cur, #ids) + 1] end)
        yy = yy + rh + S(6)
        if pre then
            local sum = T("IGUI_CHD_Speed_" .. tostring(pre.speed))
            local slow = CHD.slowOf(pre.slow)
            if slow < 100 then sum = sum .. " " .. T("IGUI_CHD_SlowV", slow) end
            sum = sum .. " / HP x" .. N(pre.hp)
            local res = CHD.cleanRes(pre.res)
            if CHD.hasRes(res) then sum = sum .. " / " .. T("IGUI_CHD_ResSum", res.pct) end
            sum = sum .. " / " .. T("IGUI_CHD_OutfitsN", #CHDC.arr(pre.outfits)) .. " / " .. T("IGUI_CHD_DropsN", #CHDC.arr(pre.drops))
            CMUI.text(self, CMUI.fit(sum, UIFont.Small, cw - lw), x + lw, yy, C.faint)
            yy = yy + fh() + S(6)
        end
        -- count
        self:label(T("IGUI_CHD_Count"), x, yy, rh)
        CMUI.stepper(self, x + lw, yy, S(150), rh, N(d.total),
            function() d.total = math.max(10, d.total - 10); CHDC.touchDraft() end,
            function() d.total = math.min(CHD.MAX_TOTAL, d.total + 10); CHDC.touchDraft() end)
        self:quick(x + lw + S(160), yy, rh, { 50, 100, 300, 500, 1000 }, d.total, function(v) d.total = v; CHDC.touchDraft() end)
        yy = yy + rh + S(6)
        -- rate
        self:label(T("IGUI_CHD_PerMin"), x, yy, rh)
        CMUI.stepper(self, x + lw, yy, S(150), rh, T("IGUI_CHD_PerMinV", d.perMin),
            function() d.perMin = math.max(10, d.perMin - 10); CHDC.touchDraft() end,
            function() d.perMin = math.min(CHD.MAX_PER_MIN, d.perMin + 10); CHDC.touchDraft() end)
        self:quick(x + lw + S(160), yy, rh, { 30, 60, 100 }, d.perMin, function(v) d.perMin = v; CHDC.touchDraft() end)
        yy = yy + rh + S(6)
        -- radius
        self:label(T("IGUI_CHD_Radius"), x, yy, rh)
        CMUI.stepper(self, x + lw, yy, S(150), rh, T("IGUI_CHD_RadiusV", d.r),
            function() d.r = math.max(1, d.r - 1) end,
            function() d.r = math.min(CHD.MAX_RADIUS, d.r + 1) end)
        yy = yy + rh + S(6)
        local mins = math.ceil(d.total / math.max(1, d.perMin))
        CMUI.text(self, T("IGUI_CHD_Takes", mins), x + lw, yy, C.dim)
        yy = yy + fh() + S(10)
        -- lag advice
        yy = yy + CMUI.section(self, x, yy, cw, T("IGUI_CHD_LagTitle"))
        yy = self:drawLag(x, yy, cw)
        yy = yy + S(10)
        local sw = S(220)
        CMUI.btn(self, x + (cw - sw) / 2, yy, sw, rh + S(6), T("IGUI_CHD_Start", d.total), function() CHDC.start() end,
            "primary", { disabled = not CHDC.canStart(), font = UIFont.Medium })
        yy = yy + rh + S(6) + S(14)
        -- running spots
        yy = yy + CMUI.section(self, x, yy, cw, T("IGUI_CHD_Running", #CHDC.points))
        yy = self:drawPoints(x, yy, cw)
        self:grow(yy + S(6))
    end)
end

-- ===================================================================== preset tab
function W:drawPresetList(x, y, w, h)
    local rh = metrics().rowH
    CMUI.btn(self, x, y, w, rh, T("IGUI_CHD_NewPreset"), function() self:loadEdit(nil) end, "good")
    y = y + rh + S(8)
    local lh = h - rh - S(8)
    local off = self:beginScroll("plist", x, y, w, lh)
    local yy = y - off
    if #CHDC.presets == 0 then
        CMUI.para(self, T("IGUI_CHD_NoPresets"), x, yy, w - S(10), C.faint)
    end
    for _, pr in ipairs(CHDC.presets) do
        local sel = self.edit.id ~= "" and self.edit.id == pr.id
        CMUI.btn(self, x, yy, w - S(10), rh, pr.name, function() self:loadEdit(pr) end, sel and "sel" or "ghost")
        yy = yy + rh + S(4)
    end
    self:endScroll(0)
end

function W:drawOutfits(x, y, w, h, showEntry)
    local rh = metrics().rowH
    local e = self.edit
    local otitle = T("IGUI_CHD_Outfits", #e.outfits)
    if #e.outfits >= CHD.MAX_OUTFITS then otitle = otitle .. "  " .. T("IGUI_CHD_Full") end
    y = y + CMUI.section(self, x, y, w, otitle)
    place(self.eOutfit, x, y, w, rh, showEntry)
    local ey = y
    y = y + rh + S(6)
    local lh = h - (y - ey) - CMUI.fh(UIFont.Small) - 6
    local off = self:beginScroll("olist", x, y, w, lh)
    local yy = y - off
    if #e.outfits == 0 then
        CMUI.para(self, T("IGUI_CHD_OutfitsEmpty"), x, yy, w - S(10), C.faint)
    end
    local list = e.outfits
    for i, name in ipairs(list) do
        CMUI.rbox(self, x, yy, w - S(10), rh, C.panel2, 0.5, 5)
        CMUI.text(self, CMUI.fit(name, UIFont.Small, w - S(60)), x + S(8), yy + (rh - fh()) / 2, C.text)
        CMUI.btn(self, x + w - S(10) - rh, yy, rh, rh, "x", function() table.remove(list, i) end, "danger")
        yy = yy + rh + S(4)
    end
    self:endScroll(0)
    return ey + rh
end

function W:drawDrops(x, y, w, h, showEntry)
    local rh = metrics().rowH
    local e = self.edit
    local dtitle = T("IGUI_CHD_Drops", #e.drops)
    if #e.drops >= CHD.MAX_DROPS then dtitle = dtitle .. "  " .. T("IGUI_CHD_Full") end
    y = y + CMUI.section(self, x, y, w, dtitle)
    place(self.eItem, x, y, w, rh, showEntry)
    local ey = y
    y = y + rh + S(6)
    local lh = h - (y - ey) - CMUI.fh(UIFont.Small) - 6
    local off = self:beginScroll("dlist", x, y, w, lh)
    local yy = y - off
    if #e.drops == 0 then
        CMUI.para(self, T("IGUI_CHD_DropsEmpty"), x, yy, w - S(10), C.faint)
    end
    local list = e.drops
    local is = rh - S(6)
    for i, d in ipairs(list) do
        local bh = rh * 2 + S(10)
        CMUI.rbox(self, x, yy, w - S(10), bh, C.panel2, 0.5, 5)
        local tex = CHDC.itemTex(d.ft)
        if tex then self:drawTextureScaledAspect(tex, x + S(6), yy + S(3), is, is, 1, 1, 1, 1) end
        CMUI.text(self, CMUI.fit(CHDC.itemName(d.ft), UIFont.Small, w - S(30) - is - rh), x + is + S(12), yy + (rh - fh()) / 2, C.text)
        CMUI.btn(self, x + w - S(10) - rh, yy + S(2), rh, rh - S(4), "x", function() table.remove(list, i) end, "danger")
        local sy = yy + rh + S(4)
        local sw = math.floor((w - S(30)) / 2)
        CMUI.stepper(self, x + S(6), sy, sw, rh, T("IGUI_CHD_Chance", d.pct),
            function() d.pct = math.max(1, (d.pct > 5 and d.pct - 5) or (d.pct - 1)) end,
            function() d.pct = math.min(100, (d.pct >= 5 and d.pct + 5) or (d.pct + 1)) end)
        CMUI.stepper(self, x + S(12) + sw, sy, sw, rh, T("IGUI_CHD_Amount", d.n),
            function() d.n = math.max(1, d.n - 1) end,
            function() d.n = math.min(CHD.MAX_DROP_N, d.n + 1) end)
        yy = yy + bh + S(4)
    end
    self:endScroll(0)
    return ey + rh
end

-- matches under a search box, drawn last so they sit on top and take the click
function W:drawSuggest(x, y, w, list, labelOf, onPick)
    if #list == 0 then return end
    local rh = metrics().rowH
    local h = #list * rh + S(8)
    CMUI.rbox(self, x, y, w, h, C.dark, 0.97, 6)
    CMUI.rborder(self, x, y, w, h, C.accent, 0.7, 6)
    local yy = y + S(4)
    for _, v in ipairs(list) do
        local over = self:hit(x + S(4), yy, w - S(8), rh, function() onPick(v) end)
        if over then CMUI.rbox(self, x + S(4), yy, w - S(8), rh, C.accentD, 0.9, 4) end
        CMUI.text(self, CMUI.fit(labelOf(v), UIFont.Small, w - S(16)), x + S(10), yy + (rh - fh()) / 2, C.text)
        yy = yy + rh
    end
end

-- next damage cut for one kind; a third "immune" is skipped
function W:stepCut(kind, dir)
    local r = self.edit.res
    local steps = CHD.CUT_STEPS
    local ci = 1
    for i = 1, #steps do if steps[i] == r[kind] then ci = i end end
    local immune = 0
    for _, k in ipairs(CHD.RES_KINDS) do
        if k ~= kind and r[k] >= 100 then immune = immune + 1 end
    end
    for _ = 1, #steps do
        ci = CM.mod(ci - 1 + dir, #steps) + 1
        if steps[ci] < 100 or immune < CHD.MAX_IMMUNE then break end
    end
    r[kind] = steps[ci]
end

function W:savePreset()
    local e = self.edit
    e.name = CM.trim(CMUI.val(self.eName))
    if e.name == "" then e.name = "Horde" end
    CHDC.savePreset(e)
end

function W:drawPresets(x, y, w, h, vis)
    local m = metrics()
    local rh = m.rowH
    local e = self.edit
    if CHDC.savedId and e.id == "" then
        e.id = CHDC.savedId
        CHDC.savedId = nil
    end
    local lw = S(200)
    self:drawPresetList(x, y, lw, h)
    local rx = x + lw + m.gap
    local rw = w - lw - m.gap
    local yy = y
    -- name
    self:label(T("IGUI_CHD_Name"), rx, yy, rh)
    place(self.eName, rx + S(110), yy, rw - S(110), rh, vis)
    yy = yy + rh + S(6)
    local half = math.floor((rw - m.gap) / 2)
    local fl = S(110)
    local fw = half - fl
    local rx2 = rx + half + m.gap
    -- speed + sluggish
    self:label(T("IGUI_CHD_SpeedL"), rx, yy, rh)
    local si = 1
    for i = 1, #CHD.SPEEDS do if CHD.SPEEDS[i] == e.speed then si = i end end
    CMUI.cycle(self, rx + fl, yy, fw, rh, T("IGUI_CHD_Speed_" .. e.speed),
        function() e.speed = CHD.SPEEDS[CM.mod(si - 2, #CHD.SPEEDS) + 1] end,
        function() e.speed = CHD.SPEEDS[CM.mod(si, #CHD.SPEEDS) + 1] end)
    self:label(T("IGUI_CHD_SlowL"), rx2, yy, rh)
    local wi = 1
    for i = 1, #CHD.SLOW_STEPS do if CHD.SLOW_STEPS[i] == e.slow then wi = i end end
    local slowTxt = e.slow >= 100 and T("IGUI_CHD_SlowNone") or T("IGUI_CHD_SlowV", e.slow)
    CMUI.cycle(self, rx2 + fl, yy, fw, rh, slowTxt,
        function() e.slow = CHD.SLOW_STEPS[CM.mod(wi - 2, #CHD.SLOW_STEPS) + 1] end,
        function() e.slow = CHD.SLOW_STEPS[CM.mod(wi, #CHD.SLOW_STEPS) + 1] end, { tip = T("IGUI_CHD_SlowTip") })
    yy = yy + rh + S(6)
    -- toughness + how many get the resistance
    self:label(T("IGUI_CHD_HP"), rx, yy, rh)
    CMUI.stepper(self, rx + fl, yy, fw, rh, "x" .. N(e.hp),
        function() e.hp = CHD.hpOf(e.hp - CHD.HP_STEP) end,
        function() e.hp = CHD.hpOf(e.hp + CHD.HP_STEP) end, { tip = T("IGUI_CHD_HPTip") })
    self:label(T("IGUI_CHD_ResL"), rx2, yy, rh)
    CMUI.stepper(self, rx2 + fl, yy, fw, rh, T("IGUI_CHD_ResPct", e.res.pct),
        function() e.res.pct = math.max(0, e.res.pct - 10) end,
        function() e.res.pct = math.min(100, e.res.pct + 10) end, { tip = T("IGUI_CHD_ResTip") })
    yy = yy + rh + S(6)
    -- the three kinds of hit
    local kw = math.floor((rw - S(12)) / 3)
    for i, k in ipairs(CHD.RES_KINDS) do
        local kx = rx + (i - 1) * (kw + S(6))
        local txt = T("IGUI_CHD_Kind_" .. k) .. ": " .. T("IGUI_CHD_Cut_" .. N(e.res[k]))
        local col = (e.res.pct > 0 and e.res[k] > 0) and C.gold or C.dim
        CMUI.cycle(self, kx, yy, kw, rh, txt,
            function() self:stepCut(k, -1) end,
            function() self:stepCut(k, 1) end, { color = col, tip = T("IGUI_CHD_CutTip") })
    end
    yy = yy + rh + S(10)
    -- outfits and drops side by side, buttons under them
    local bh = rh + S(4)
    local listH = (y + h) - yy - bh - S(10)
    local cw = math.floor((rw - m.gap) / 2)
    local oy = self:drawOutfits(rx, yy, cw, listH, vis)
    local dy = self:drawDrops(rx + cw + m.gap, yy, cw, listH, vis)
    -- buttons
    local by = y + h - bh
    local bx = rx
    bx = bx + CMUI.btnA(self, bx, by, bh, T("IGUI_CHD_Save"), function() self:savePreset() end, "primary",
        { minW = S(120), disabled = not CHDC.canSave() }) + S(8)
    if e.id ~= "" then
        bx = bx + CMUI.btnA(self, bx, by, bh, T("IGUI_CHD_UsePreset"), function()
            CHDC.draft.pid = e.id
            self:setTab("spawn")
        end, "ghost", { tip = T("IGUI_CHD_UsePresetTip") }) + S(8)
        CMUI.btnA(self, bx, by, bh, T("IGUI_CHD_Delete"), function()
            CHDC.send("delPreset", { id = e.id })
            self:loadEdit(nil)
        end, "danger")
    end
    -- search results on top of everything
    local qo = CMUI.val(self.eOutfit)
    if vis and #CM.trim(qo) >= 2 then
        self:drawSuggest(rx, oy + S(2), cw, CHDC.findOutfits(qo, 8), function(v) return v end, function(v)
            for _, have in ipairs(e.outfits) do if have == v then return end end
            if #e.outfits < CHD.MAX_OUTFITS then e.outfits[#e.outfits + 1] = v end
            CMUI.setVal(self.eOutfit, "")
        end)
    end
    local qi = CMUI.val(self.eItem)
    if vis and #CM.trim(qi) >= 2 then
        self:drawSuggest(rx + cw + m.gap, dy + S(2), cw, CHDC.findItems(qi, 8), function(v)
            return CHDC.itemName(v) .. "  (" .. v .. ")"
        end, function(v)
            if #e.drops < CHD.MAX_DROPS then e.drops[#e.drops + 1] = { ft = v, pct = 10, n = 1 } end
            CMUI.setVal(self.eItem, "")
        end)
    end
end

function W:drawBody()
    local m = metrics()
    local x = m.pad
    local w = self.width - m.pad * 2
    local y = self.headerH + m.pad
    CMUI.tabs(self, x, y, w, m.tabH, {
        { key = "spawn", label = T("IGUI_CHD_TabSpawn"), badge = N(#CHDC.points) },
        { key = "presets", label = T("IGUI_CHD_TabPresets"), badge = N(#CHDC.presets) },
    }, self.tab, function(k) self:setTab(k) end)
    y = y + m.tabH + m.gap
    local h = self.height - y - m.pad
    local presets = self.tab == "presets"
    if not presets then
        place(self.eName, 0, 0, 1, 1, false)
        place(self.eOutfit, 0, 0, 1, 1, false)
        place(self.eItem, 0, 0, 1, 1, false)
        self:drawSpawn(x, y, w, h)
    else
        self:drawPresets(x, y, w, h, true)
    end
end

function W:onClosed()
    CHDUI.win = nil
end

-- ===================================================================== open
function CHDUI.open(tab)
    if not CHDC.isAdmin() then return end
    local win = CHDUI.win
    if not win or not win:isVisible() then
        local w, h = CMUI.size(780, 660)
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        win = W:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
        win:show()
        win:makeEntries()
        CHDUI.win = win
    end
    if tab then win:setTab(tab) end
    win:bringToTop()
    CHDC.send("state", {})
end

return CHDUI
