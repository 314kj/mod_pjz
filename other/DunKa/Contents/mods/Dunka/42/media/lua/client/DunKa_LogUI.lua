--[[ ============================================================
  PROJECT DUNKA [MP] -- per-box Usage Log viewer (admin)   KACHASIG
  Shows who used this horde box, when (in-game day/time), and which
  rank card. Opened from the box right-click menu (admin only).
============================================================ ]]--

require "ISUI/ISPanel"

DunKaLogUI = ISPanel:derive("DunKaLogUI")

function DunKaLogUI:initialise() ISPanel.initialise(self) end

function DunKaLogUI.openFor(entries, bx, by, bz)
    if DunKaLogUI.instance then pcall(function() DunKaLogUI.instance:close() end) end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = 440, 380
    local o = DunKaLogUI:new((sw-w)/2, (sh-h)/2, w, h, entries or {}, bx, by, bz)
    o:initialise(); o:addToUIManager()
    DunKaLogUI.instance = o
    return o
end

function DunKaLogUI:new(x, y, w, h, entries, bx, by, bz)
    local o = ISPanel.new(self, x, y, w, h)
    o:noBackground()
    o.moveWithMouse = true
    o.entries = entries or {}
    o.bx, o.by, o.bz = bx, by, bz
    return o
end

function DunKaLogUI:close()
    DunKaLogUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end

function DunKaLogUI:onMouseDown(x, y)
    if x >= self.width-32 and y <= 28 then self:close(); return true end
    return ISPanel.onMouseDown(self, x, y)
end
function DunKaLogUI:onRightMouseDown(x, y) self:close(); return true end

function DunKaLogUI:render()
    self:drawRect(0, 0, self.width, self.height, 0.95, 0.06, 0.06, 0.07)
    self:drawRectBorder(0, 0, self.width, self.height, 1, 0.55, 0.42, 0.2)
    self:drawRect(0, 0, self.width, 30, 1, 0.12, 0.10, 0.08)
    self:drawText("Horde Box  -  Usage Log", 14, 7, 0.95, 0.85, 0.5, 1, UIFont.Medium)
    self:drawText("X", self.width-22, 6, 0.9, 0.7, 0.7, 1, UIFont.Medium)

    local n = #self.entries
    if n == 0 then
        self:drawText("No usage recorded yet.", 16, 46, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end

    -- header row
    self:drawText("Player", 16, 40, 0.7, 0.7, 0.6, 1, UIFont.Small)
    self:drawText("When", 180, 40, 0.7, 0.7, 0.6, 1, UIFont.Small)
    self:drawText("Card", 350, 40, 0.7, 0.7, 0.6, 1, UIFont.Small)
    self:drawRect(10, 58, self.width-20, 1, 0.5, 0.6, 0.5, 0.3)

    -- newest first
    local y = 64
    local shown = 0
    for i = n, 1, -1 do
        local e = self.entries[i]
        self:drawText(tostring(e.u), 16, y, 0.92, 0.92, 0.85, 1, UIFont.Small)
        self:drawText(tostring(e.t), 180, y, 0.85, 0.85, 0.8, 1, UIFont.Small)
        self:drawText("Rank " .. tostring(e.r), 350, y, 0.9, 0.8, 0.5, 1, UIFont.Small)
        y = y + 18
        shown = shown + 1
        if y > self.height - 20 then break end
    end
    if shown < n then
        self:drawText("(" .. (n - shown) .. " older entries hidden)", 16, self.height-18, 0.6, 0.6, 0.6, 1, UIFont.Small)
    end
end

print("[DunKa] LogUI loaded")
