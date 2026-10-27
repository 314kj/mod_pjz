--[[ ============================================================
  PROJECT DUNKA [MP] -- Full-screen WARNING gate   KACHASIG
  Shown first when opening the terminal. Acknowledge to proceed
  to the summoning terminal (DunKaSummonUI).
============================================================ ]]--

require "ISUI/ISPanel"

DunKaWarnUI = ISPanel:derive("DunKaWarnUI")

function DunKaWarnUI:initialise() ISPanel.initialise(self) end

function DunKaWarnUI.openFor(player, sq)
    if DunKaWarnUI.instance then pcall(function() DunKaWarnUI.instance:close() end) end
    local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = DunKaWarnUI:new(0, 0, w, h, player, sq)
    o:initialise(); o:addToUIManager()
    DunKaWarnUI.instance = o
    return o
end

function DunKaWarnUI:new(x, y, w, h, player, sq)
    local o = ISPanel.new(self, x, y, w, h)
    o:noBackground()
    o.player = player
    o.sq = sq
    return o
end

function DunKaWarnUI:close()
    DunKaWarnUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end

function DunKaWarnUI:rects()
    local W, H = self.width, self.height
    local cx = W/2
    local bw = 400
    return
        { x = cx - bw/2, y = H/2 + 60, w = bw, h = 56 },   -- acknowledge
        { x = cx - 70,   y = H/2 + 134, w = 140, h = 26 }  -- cancel
end

function DunKaWarnUI:render()
    local W, H = self.width, self.height
    local cx = W/2
    self:drawRect(0, 0, W, H, 0.9, 0.04, 0.03, 0.04)
    self:drawRectBorder(6, 6, W-12, H-12, 1, 0.64, 0.18, 0.18)

    self:drawText("haftfull // horde protocol", 20, 16, 0.42, 0.42, 0.39, 1, UIFont.Small)
    self:drawText("status: locked", W - 150, 16, 0.42, 0.42, 0.39, 1, UIFont.Small)

    self:drawTextCentre("!  W A R N I N G  !", cx, H/2 - 150, 0.95, 0.42, 0.42, 1, UIFont.Large)
    self:drawRect(cx - 210, H/2 - 108, 420, 2, 0.6, 0.5, 0.12, 0.12)

    self:drawTextCentre("This action will summon a hostile horde to your location.", cx, H/2 - 84, 0.84, 0.82, 0.78, 1, UIFont.Medium)
    self:drawTextCentre("Zombies will be drawn in from the surrounding area.",       cx, H/2 - 58, 0.84, 0.82, 0.78, 1, UIFont.Medium)
    self:drawTextCentre("Once armed it cannot be stopped. Make sure you are ready.",  cx, H/2 - 20, 0.55, 0.55, 0.52, 1, UIFont.Medium)

    local ack, cancel = self:rects()
    self:drawRect(ack.x, ack.y, ack.w, ack.h, 0.95, 0.64, 0.18, 0.18)
    self:drawRectBorder(ack.x, ack.y, ack.w, ack.h, 1, 0.89, 0.29, 0.29)
    self:drawTextCentre("I  ACKNOWLEDGE  THIS", cx, ack.y + ack.h/2 - 11, 0.99, 0.92, 0.92, 1, UIFont.Large)

    self:drawTextCentre("cancel", cx, cancel.y + 2, 0.55, 0.55, 0.52, 1, UIFont.Medium)
end

function DunKaWarnUI:onMouseDown(x, y)
    local ack, cancel = self:rects()
    if x>=ack.x and x<=ack.x+ack.w and y>=ack.y and y<=ack.y+ack.h then
        self:close()
        if DunKaSummonUI then DunKaSummonUI.openFor(self.player, self.sq) end
        return true
    end
    if x>=cancel.x and x<=cancel.x+cancel.w and y>=cancel.y and y<=cancel.y+cancel.h then
        self:close(); return true
    end
    return true   -- absorb (modal)
end
function DunKaWarnUI:onRightMouseDown(x, y) self:close(); return true end

print("[DunKa] WarnUI loaded")
