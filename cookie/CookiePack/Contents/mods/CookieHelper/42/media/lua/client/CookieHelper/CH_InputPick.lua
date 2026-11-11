-- Cookie Helper : "which items may this recipe use" window (one input of one recipe)
-- Tick the items that may be used; the order is the order they are used in - the craft takes the
-- first ticked one in reach and moves to the next when it runs out. Saved on this computer.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Inputs"

CHelp.InputPick = CHelp.InputPick or {}
local IP = CHelp.InputPick
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local In = CHelp.Inputs
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpInputPick")
local ROW_H = 44

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 4 + UI.HS * 2 + 16
    local fh = UI.BTN_H + UI.PAD + 8
    self.list = UI.makeList(self, x, y, w, self.height - y - fh, ROW_H, self, W.drawRow)
    self.list.noSelect = true
    self.list.rowGap = 4
    self.list.onMouseDown = function(l, mx, my)
        local row = l:rowAt(mx, my)
        local it = l.items[row]
        if it then
            local d = it.item
            if d.upX and mx >= d.upX and mx < d.upX + d.upW then
                self:move(d.i, -1)
            else
                self:toggle(d.i)
            end
        end
        return true
    end
    local by = self.height - UI.PAD - UI.BTN_H
    local half = floor((w - 8) / 2)
    UI.button(self, x, by, half, t("InputsReset"), self, W.onReset, "ghost")
    UI.button(self, x + half + 8, by, w - half - 8, t("Done"), self, W.onDone, "pri")
    self:load()
end

function W:load()
    self.order = In.ordered(self.recipe, self.idx, self.fts)
    self.off = {}
    for _, ft in ipairs(self.order) do
        if not In.isOn(self.recipe, self.idx, ft) then self.off[ft] = true end
    end
    self:fill()
end

function W:fill()
    self.list:clear()
    for i, ft in ipairs(self.order) do
        self.list:addItem(Scan.itemName(ft), { i = i, ft = ft })
    end
end

function W:save()
    In.set(self.recipe, self.idx, self.order, self.off)
    C.emit("inputs")
end

function W:toggle(i)
    local ft = self.order[i]
    if not ft then return end
    if not self.off[ft] then
        -- at least one stays ticked
        local on = 0
        for _, f in ipairs(self.order) do if not self.off[f] then on = on + 1 end end
        if on <= 1 then
            UI.toast(t("InputsKeepOne"), false)
            return
        end
        self.off[ft] = true
    else
        self.off[ft] = nil
    end
    self:save()
end

function W:move(i, d)
    local k = i + d
    if k < 1 or k > #self.order then return end
    self.order[i], self.order[k] = self.order[k], self.order[i]
    self:fill()
    self:save()
end

function W:onReset()
    In.reset(self.recipe, self.idx)
    C.emit("inputs")
    self:load()
end

function W:onDone() self:close() end

function W.drawRow(self, list, d, x, y, w, h)
    local on = not self.off[d.ft]
    local rank = 0
    for _, f in ipairs(self.order) do
        if not self.off[f] then rank = rank + 1 end
        if f == d.ft then break end
    end
    T.rrect(list, x, y, w, h, 10, on and K.surf2 or K.surf)
    -- tick box
    local bs = 20
    local bx, by = x + 12, y + floor((h - bs) / 2)
    T.rrect(list, bx, by, bs, bs, 6, on and K.acc or K.bar)
    if on then T.icon(list, "check", bx + 3, by + 3, bs - 6, K.onAcc or K.bar) end
    T.slot(list, bx + bs + 10, y + 4, h - 8, Scan.itemTex(d.ft), nil)
    local tx = bx + bs + 10 + h - 8 + 10
    local have = self.counts and self.counts[d.ft] and self.counts[d.ft].n or 0
    local right = t("HaveN", have)
    T.text(list, T.fit(Scan.itemName(d.ft), w - (tx - x) - 140), tx, y + floor(h / 2) - UI.HS - 1, on and K.text or K.text3)
    T.text(list, on and t("InputsRank", rank) or t("InputsOff"), tx, y + floor(h / 2) + 1, on and K.acc or K.text3)
    -- move up
    local ux = x + w - 40
    d.upX, d.upW = ux - x, 32
    if d.i > 1 then
        local mx, my = list:getMouseX(), list:getMouseY()
        local hov = my >= y and my < y + h and mx >= ux and mx < ux + 32
        T.rrect(list, ux, y + floor((h - 32) / 2), 32, 32, 8, hov and K.surf3 or K.bar)
        T.icon(list, "up", ux + 8, y + floor((h - 32) / 2) + 8, 16, K.text2)
    end
    T.textR(list, right, ux - 10, y + floor((h - UI.HS) / 2), have > 0 and K.text2 or K.text3)
end

function W:drawBody()
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 4
    T.text(self, T.fit(t("InputsFor", CHelp.Craft.label(self.recipe)), w), x, y, K.text)
    T.text(self, T.fit(t("InputsHint"), w), x, y + UI.HS + 6, K.text3)
end

function W:onClose()
    if IP.instance == self then IP.instance = nil end
end

-- counts = ft -> { n } (what is in reach now, for the "have" column)
function IP.open(recipe, idx, fts, counts)
    if IP.instance then IP.instance:close() end
    local rows = math.min(#fts, 8)
    local w = 440
    local h = UI.HEAD_H + 4 + UI.HS * 2 + 16 + rows * (ROW_H + 4) + 8 + UI.BTN_H + UI.PAD + 8
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, t("InputsTitle"))
    win.recipe, win.idx, win.fts, win.counts = recipe, idx, fts, counts
    win:show()
    IP.instance = win
    return win
end
