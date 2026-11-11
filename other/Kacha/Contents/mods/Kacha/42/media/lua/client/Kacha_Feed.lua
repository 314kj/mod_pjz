--[[ Kacha B42 [MP] - result feed toast (client)  by PIE
     หมุนได้ของ A-SS+ -> เด้ง toast มุมขวาบน (เห็นทั้งคนหมุน + แอดมิน)
     server ยิงคำสั่ง "feed" ผ่าน net module "Kacha"  BUILD=feed-A ]]
Kacha = Kacha or {}
Kacha.feedHistory = Kacha.feedHistory or {}

require "ISUI/ISUIElement"

local toasts = {}
local KachaToast = ISUIElement:derive("KachaToast")

function KachaToast:new(w, h, who, item)
    local o = ISUIElement:new(0, 0, w, h)
    setmetatable(o, self); self.__index = self
    o.who = who; o.item = item; o.born = getTimestampMs(); o.life = 6500
    return o
end
function KachaToast:render()
    local tc = Kacha.tierColor(self.item.tier)
    self:drawRect(0, 0, self.width, self.height, 0.92, 0.05, 0.05, 0.07)
    self:drawRectBorder(0, 0, self.width, self.height, 0.95, tc.r, tc.g, tc.b)
    self:drawRect(8, 8, 42, 22, 1.0, tc.r, tc.g, tc.b)
    self:drawTextCentre(self.item.tier, 29, 10, 1, 1, 1, 1, UIFont.Small)
    self:drawText(tostring(self.who) .. " won", 60, 6, 0.9, 0.92, 0.95, 1, UIFont.Small)
    self:drawText(tostring(self.item.name or self.item.id or "?"), 60, 22, tc.r, tc.g, tc.b, 1, UIFont.Medium)
    self:drawText("KACHA", 60, 42, 0.55, 0.58, 0.67, 1, UIFont.Small)
    if getTimestampMs() - self.born > self.life then
        self:removeSelf()
        for i = #toasts, 1, -1 do if toasts[i] == self then table.remove(toasts, i) end end
        Kacha.relayoutToasts()
    end
end
function KachaToast:removeSelf() self:removeFromUIManager() end

function Kacha.relayoutToasts()
    local sw = getCore():getScreenWidth()
    local y = 64
    for _, t in ipairs(toasts) do
        t:setX(sw - t.width - 16); t:setY(y); y = y + t.height + 8
    end
end

-- args = { who = "name", items = { { name, tier, id }, ... } }
function Kacha.showFeed(args)
    if not args or type(args.items) ~= "table" then return end
    for _, it in ipairs(args.items) do
        Kacha.feedHistory[#Kacha.feedHistory + 1] = { who = args.who, item = it, when = getTimestampMs() }
        while #Kacha.feedHistory > 30 do table.remove(Kacha.feedHistory, 1) end
        local t = KachaToast:new(300, 64, args.who or "?", it)
        t:initialise(); t:addToUIManager()
        toasts[#toasts + 1] = t
        while #toasts > 5 do local old = table.remove(toasts, 1); if old then old:removeSelf() end end
    end
    Kacha.relayoutToasts()
end

Kacha.__mark("feed")
