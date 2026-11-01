-- Cookie Helper : recipe list widget shared by Auto Count and Vehicle Zone
-- "Can I craft this?" is answered lazily: only rows that are on screen are checked, two per
-- frame, with one reused HandcraftLogic. No frame ever pays for the whole list.
if isServer() then return end

require "CookieHelper/CH_UI"
require "CookieHelper/CH_Craft"

CHelp.RecipeBox = CHelp.RecipeBox or {}
local RB = CHelp.RecipeBox
local UI = CHelp.UI
local Craft = CHelp.Craft
local t = CHelp.t

RB.__index = RB

-- opts: { getEntries = fn() -> zone entries, canCraft = fn() -> bool, why = text key }
function RB.create(parent, x, y, w, h, opts)
    local o = setmetatable({}, RB)
    o.parent = parent
    o.opts = opts or {}
    o.recipes = {}
    o.status = {}
    o.queue = {}
    o.queued = {}
    o.gen = 0
    local rowH = UI.HS * 2 + 12
    local listH = h - UI.BTN_H - 8
    o.list = UI.makeList(parent, x, y, w, listH, rowH, o, RB.drawRow)
    local by = y + listH + 6
    o.qty = UI.entry(parent, x, by, 56, "1")
    o.qty:setOnlyNumbers(true)
    o.maxBtn = UI.button(parent, x + 62, by, 60, t("Max"), o, RB.onMax)
    o.craftBtn = UI.button(parent, x + w - 170, by, 170, t("CraftFromZone"), o, RB.onCraft, "mint")
    return o
end

function RB:setRecipes(list)
    self.recipes = list or {}
    self.list:clear()
    for _, r in ipairs(self.recipes) do self.list:addItem(Craft.label(r), r) end
    self.list.selected = (#self.recipes > 0) and 1 or 0
    self.queue, self.queued = {}, {}
end

-- new stock -> every cached answer becomes stale (still shown until rechecked)
function RB:invalidate(containers)
    self.containers = containers
    self.logic = nil
    self.gen = self.gen + 1
    self.queue, self.queued = {}, {}
end

function RB:need(r)
    local st = self.status[r]
    if (not st or st.gen ~= self.gen) and not self.queued[r] then
        self.queued[r] = true
        self.queue[#self.queue + 1] = r
    end
end

function RB:pump(n)
    if not self.containers or #self.queue == 0 then return end
    if not self.logic then
        local p = getSpecificPlayer(0)
        if not p then return end
        self.logic = HandcraftLogic.new(p, nil, nil)
        self.logic:setContainers(self.containers)
    end
    for _ = 1, n or 2 do
        local r = table.remove(self.queue, 1)
        if not r then break end
        self.queued[r] = nil
        local st = Craft.statusOne(self.logic, r)
        st.gen = self.gen
        self.status[r] = st
    end
end

function RB:selected()
    local it = self.list.items[self.list.selected]
    return it and it.item or nil
end

function RB.drawRow(self, list, r, x, y, w, h, hover)
    self:need(r)
    local st = self.status[r]
    local ok, tex = pcall(function() return r:getIconTexture() end)
    if ok and tex then list:drawTextureScaledAspect(tex, x + 6, y + 6, h - 12, h - 12, 1, 1, 1, 1) end
    local tx0 = x + h + 2
    UI.text(list, UI.fit(Craft.label(r), w - h - 12), tx0, y + 5, UI.C.text)
    local line2, col = t("St_Checking"), UI.C.muted
    if st then
        if not st.known then line2, col = t("St_NotLearned"), UI.C.red
        elseif st.bench then line2, col = t("St_NeedBench"), UI.C.gold
        elseif st.can then line2, col = t("St_Can", st.max), UI.C.mint
        else line2, col = t("St_Missing"), UI.C.red end
    end
    UI.text(list, UI.fit(line2, w - h - 20), tx0, y + 7 + UI.HS, col)
end

function RB:onMax()
    local r = self:selected()
    local st = r and self.status[r]
    if st and st.max and st.max > 0 then self.qty:setText(tostring(math.min(st.max, 50))) end
end

function RB:onCraft()
    local r = self:selected()
    if not r then return end
    if self.opts.canCraft and not self.opts.canCraft() then
        UI.toast(t(self.opts.why or "Msg_StandInZone"), false)
        return
    end
    local st = self.status[r]
    if st and not st.known then UI.toast(t("St_NotLearned"), false) return end
    if st and st.bench then UI.toast(t("St_NeedBench"), false) return end
    local q = tonumber(self.qty:getInternalText()) or 1
    q = math.max(1, math.min(q, 50))
    Craft.start(getSpecificPlayer(0), r, q, self.opts.getEntries)
end
