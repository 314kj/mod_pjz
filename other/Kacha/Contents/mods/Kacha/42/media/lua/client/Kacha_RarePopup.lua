--[[ ============================================================
     Kacha B42 [MP]  -  Rare win popup (S/SS/SS+)  by PIE
     Center-screen celebration with a 5s countdown, any count.
     English UI only.                                 BUILD=rare-A
   ============================================================ ]]
require "ISUI/ISPanel"

Kacha = Kacha or {}
KachaRarePopup = ISPanel:derive("KachaRarePopup")

function KachaRarePopup:new(rares)
    local n = math.min(#rares, 5)
    local w = math.max(340, 40 + n * 130)
    local h = 260
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.rares = rares; o.n = n
    o.moveWithMouse = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.endAt = getTimestampMs() + 5000
    for _, r in ipairs(rares) do r.tex = r.tex or Kacha.itemTexture(r.id) end
    return o
end

function KachaRarePopup:createChildren() end

function KachaRarePopup:prerender()
    local W, H = self:getWidth(), self:getHeight()
    local remain = math.ceil((self.endAt - getTimestampMs()) / 1000)
    if remain <= 0 then self:close(); return end

    -- glow-ish backdrop
    self:drawRect(0, 0, W, H, 0.97, 0.05, 0.07, 0.13)
    self:drawRectBorder(0, 0, W, H, 1, 1.0, 0.30, 0.55)
    self:drawRectBorder(2, 2, W - 4, H - 4, 1, 0.96, 0.77, 0.26)
    self:drawTextCentre("RARE  DROP !", W / 2, 16, 1.0, 0.30, 0.55, 1, UIFont.Large)

    local slot = (W - 40) / self.n
    for i = 1, self.n do
        local r = self.rares[i]
        local cx = 20 + (i - 1) * slot + slot / 2
        local tc = Kacha.tierColor(r.tier)
        if r.tex then self:drawTextureScaled(r.tex, cx - 40, 60, 80, 80, 1, 1, 1, 1) end
        self:drawRect(cx + 14, 58, 34, 18, 0.95, tc.r, tc.g, tc.b)
        self:drawTextCentre(r.tier, cx + 31, 59, 1, 1, 1, 1, UIFont.Small)
        local nm = r.name or r.id or "?"; if #nm > 14 then nm = string.sub(nm, 1, 13) .. ".." end
        self:drawTextCentre(nm, cx, 148, 0.95, 0.97, 1.0, 1, UIFont.Medium)
    end
    if #self.rares > self.n then
        self:drawTextCentre("+ " .. (#self.rares - self.n) .. " more", W / 2, 176, 0.7, 0.74, 0.82, 1, UIFont.Small)
    end
    self:drawTextCentre("closing in " .. remain .. "s", W / 2, H - 34, 0.6, 0.66, 0.76, 1, UIFont.Small)
end

function KachaRarePopup:onMouseDown() self:close(); return true end
function KachaRarePopup:close() self:removeFromUIManager(); KachaRarePopup.instance = nil end

function Kacha.openRarePopup(rares)
    if KachaRarePopup.instance then KachaRarePopup.instance:close() end
    local p = KachaRarePopup:new(rares)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaRarePopup.instance = p
end

Kacha.__mark("rare")
