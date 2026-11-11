-- Cookie Mastery - a mastery card at the top of the vanilla Skills page (ISCharacterInfo).
-- The vanilla page draws everything from a local y, so we cannot just move its start. Instead, while
-- its render runs, drawText / drawTexture / setScrollHeight / setHeightAndParentHeight on that one panel
-- are shadowed to add the card height, and the child widgets (collapse buttons, skill bars) are moved
-- by the same amount afterwards. Nothing in vanilla is copied, so other mods that wrap render still work.
-- Clicking the card opens the skill tree.
if isServer() and not isClient() then return end

require "CMM_Client"
require "CM_UI_Kit"
require "XpSystem/ISUI/ISCharacterInfo"
require "CMM_Tree"

CMMK = CMMK or {}
local C = CMUI.C
local S = CMUI.S
local T = CMMC.txt
local GAP = 10           -- vanilla UI_BORDER_SPACING
local SCROLL = 13        -- vanilla scroll bar width
local SHADOW = { "drawText", "drawTexture", "setHeightAndParentHeight", "setScrollHeight" }

-- card height for the current font size
function CMMK.height()
    local fs = CMUI.fh(UIFont.Small)
    local ts = fs * 2 + S(8)
    return S(8) + fs + S(6) + ts + S(8) + S(4) + S(9)
end

-- ===================================================================== the card
CMMK.Card = ISPanel:derive("CMMK_Card")
local K = CMMK.Card

function K:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o:noBackground()
    return o
end

function K:onMouseDown() return true end

function K:onMouseUp()
    if CMMT and CMMT.toggle then CMMT.toggle() end
    return true
end

function K:render()
    local info = self.parent
    -- only draw while our render hook is the one laying out the page (another mod may have replaced it)
    if not (info and info.cmmHooked) then return end
    info.cmmHooked = false
    if not CMUI.k or CMUI.k <= 0 then CMUI.k = CMUI.fontScale() end
    local w, h = self.width, self.height
    local over = self:isMouseOver()
    local m = CMMC.me
    local fs = CMUI.fh(UIFont.Small)
    local has = m and m.br
    local side = has and CMM.sideOf(m.br) or nil
    local col = side and side.color or C.line
    CMUI.glass(self, 0, 0, w, h, { tint = C.panel, a = over and 0.80 or 0.68, rad = 8,
        rim = over and C.gold or (has and col or C.line), rimA = over and 0.9 or 0.55 })
    local pad = S(8)
    -- header: pip + "Mastery", "open tree" on the right
    local hy = pad
    local ps = math.max(6, math.floor(fs * 0.55))
    CMUI.icon(self, "cm_pip", pad, hy + (fs - ps) / 2, ps, C.gold, 1)
    CMUI.text(self, T("IGUI_CMM_Tab"), pad + ps + S(6), hy, C.gold, 1, UIFont.Small)
    CMUI.textR(self, T("IGUI_CMM_SkOpen") .. " >", w - pad, hy, over and C.white or C.accent, 1, UIFont.Small)
    -- level tile + branch + progress text
    local ty = hy + fs + S(6)
    local ts = fs * 2 + S(8)
    if not m then
        CMUI.text(self, T("IGUI_CMM_Wait"), pad, ty + (ts - fs) / 2, C.dim, 1, UIFont.Small)
        return
    end
    local lv, into, need = CMM.level(m.pts or 0)
    if has then CMUI.glow(self, pad + ts / 2, ty + ts / 2, ts * 0.8, ts * 0.8, C.accent, 0.25) end
    CMUI.glass(self, pad, ty, ts, ts, { tint = C.dark, a = 0.75, rad = 6, rim = has and C.gold or C.line, rimA = has and 0.8 or 0.45 })
    CMUI.textC(self, tostring(lv), pad + ts / 2, ty + (ts - CMUI.fh(UIFont.Medium)) / 2, has and C.white or C.dim, 1, UIFont.Medium)
    local tx = pad + ts + S(8)
    local tw = w - tx - pad
    if has then
        CMUI.text(self, CMUI.fit(CMMC.brName(m.br), UIFont.Small, tw), tx, ty + S(2), C.white, 1, UIFont.Small)
        local line2 = lv >= 10 and T("IGUI_CMM_Max") or T("IGUI_CMM_Next", CMMC.num(into), CMMC.num(need), lv + 1)
        CMUI.text(self, CMUI.fit(line2, UIFont.Small, tw), tx, ty + S(4) + fs, C.dim, 1, UIFont.Small)
    else
        CMUI.text(self, T("IGUI_CMM_NoBranchShort"), tx, ty + S(2), C.text, 1, UIFont.Small)
        local banked = 0
        for _, v in pairs(m.pre or {}) do banked = banked + CM.num(v, 0) end
        local can = false
        local el = CMMC.eligible()
        for _ in pairs(el) do can = true; break end
        local line2, lc = T("IGUI_CMM_SkHint"), C.faint
        if can then
            line2, lc = T("IGUI_CMM_SkCanPick"), C.gold
            if banked > 0 then line2 = line2 .. CMMT.SEP .. T("IGUI_CMM_K_banked") .. " " .. CMMC.num(banked) end
        end
        CMUI.text(self, CMUI.fit(line2, UIFont.Small, tw), tx, ty + S(4) + fs, lc, 1, UIFont.Small)
    end
    -- progress to the next mastery level
    local by = ty + ts + S(8)
    local frac = lv >= 10 and 1 or into / math.max(1, need)
    CMUI.segbar(self, pad, by, w - pad * 2, S(4), frac, has and C.accent or C.faint, 20)
end

-- ===================================================================== hooking the skills page
function CMMK.attach(info)
    if not info or info.cmmCard then return end
    local card = K:new(GAP, GAP, math.max(S(120), info.width - GAP * 2 - SCROLL), CMMK.height())
    card:initialise()
    card:instantiate()
    info:addChild(card)
    info.cmmCard = card
end

function CMMK.render(self, orig)
    local card = self.cmmCard
    if not card or CMM.sv("Enabled") == false then return orig(self) end
    card:setHeight(CMMK.height())
    card:setWidth(math.max(S(120), self.width - GAP * 2 - SCROLL))
    local H = card:getHeight() + GAP
    local saved = {}
    for i = 1, #SHADOW do saved[i] = rawget(self, SHADOW[i]) end
    local dT, dX = self.drawText, self.drawTexture
    local hp, sh = self.setHeightAndParentHeight, self.setScrollHeight
    self.drawText = function(s, str, x, y, ...) return dT(s, str, x, y + H, ...) end
    self.drawTexture = function(s, tex, x, y, ...) return dX(s, tex, x, y + H, ...) end
    self.setHeightAndParentHeight = function(s, hh) return hp(s, math.min(hh + H, 800)) end
    self.setScrollHeight = function(s, v) return sh(s, v + H) end
    local ok, err = pcall(orig, self)
    for i = 1, #SHADOW do self[SHADOW[i]] = saved[i] end
    if not ok then
        pcall(function() self:clearStencilRect() end)
        if not CMMK.warned then
            CMMK.warned = true
            CMM.log("skills page render error: " .. tostring(err))
        end
        return
    end
    -- vanilla places the collapse buttons every frame and the skill bars once, both without the card
    local bl = self.buttonList or {}
    for i = 1, #bl do bl[i]:setY(bl[i]:getY() + H) end
    local bars = self.progressBars or {}
    for i = 1, #bars do
        local b = bars[i]
        local d = H - (b.cmmDY or 0)
        if d ~= 0 then
            b:setY(b:getY() + d)
            b.cmmDY = H
        end
    end
    self.cmmHooked = true
    pcall(CMMK.marks, self)
end

-- a small diamond in front of every level-10 skill that feeds a mastery branch:
-- gold = feeds your branch, side colour = could feed that branch
function CMMK.marks(self)
    local bars = self.progressBars or {}
    if #bars == 0 then return end
    local p = CMMC.player()
    local m = CMMC.me
    local fs = CMUI.fh(UIFont.Small)
    local ps = math.max(6, math.floor(fs * 0.45))
    self:setStencilRect(0, 0, self.width, self.height)
    for i = 1, #bars do
        local b = bars[i]
        local id = b.perk and CMM.perkId(b.perk) or nil
        local bid = id and CMM.PERK_BRANCH[id] or nil
        if bid and CMM.perkLevel(p, b.perk) >= 10 then
            local mine = m and m.br == bid
            local side = CMM.sideOf(bid)
            local col = mine and C.gold or (side and side.color or C.accent)
            local x = b:getX() - ps - S(4)
            local y = b:getY() + (b:getHeight() - ps) / 2
            if mine then CMUI.glow(self, x + ps / 2, y + ps / 2, ps * 2.2, ps * 2.2, C.gold, 0.45) end
            CMUI.icon(self, "cm_pip", x, y, ps, col, mine and 1 or 0.85)
        end
    end
    self:clearStencilRect()
end

function CMMK.install()
    if ISCharacterInfo.__cmmCard then return end
    ISCharacterInfo.__cmmCard = true
    local origCC = ISCharacterInfo.createChildren
    function ISCharacterInfo:createChildren()
        origCC(self)
        local ok, err = pcall(CMMK.attach, self)
        if not ok then CMM.log("skills card error: " .. tostring(err)) end
    end
    local origR = ISCharacterInfo.render
    function ISCharacterInfo:render()
        return CMMK.render(self, origR)
    end
end

CMMK.install()

-- the skills page may already exist (Lua reload)
Events.OnGameStart.Add(function()
    local info = ISCharacterInfo.instance
    if info and not info.cmmCard then pcall(CMMK.attach, info) end
end)

return CMMK
