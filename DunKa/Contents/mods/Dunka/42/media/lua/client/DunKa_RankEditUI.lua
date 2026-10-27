--[[ ============================================================
  PROJECT DUNKA [MP] -- Rank Rewards Editor (admin)   KACHASIG
  Set how many White / Yellow / Blue slips each rank (C/B/A/S)
  gives on summon. 0 = that colour is not given. Saved to server
  ModData -> changeable anytime. applyReward reads it (no ghosts).
============================================================ ]]--

require "ISUI/ISPanel"

DunKaRankEditUI = ISPanel:derive("DunKaRankEditUI")

local W, H    = 480, 356
local RANKS   = { "C", "B", "A", "S" }
local COLS    = { { k="White", x=104 }, { k="Yellow", x=240 }, { k="Blue", x=376 } }
local ROW0    = 84
local ROWH    = 52

local function hit(x,y, rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end

function DunKaRankEditUI:initialise() ISPanel.initialise(self) end

function DunKaRankEditUI.openFor(cfg)
    if DunKaRankEditUI.instance then pcall(function() DunKaRankEditUI.instance:close() end) end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = DunKaRankEditUI:new((sw-W)/2, (sh-H)/2, cfg)
    o:initialise(); o:addToUIManager()
    DunKaRankEditUI.instance = o
    return o
end

function DunKaRankEditUI:new(x, y, cfg)
    local o = ISPanel.new(self, x, y, W, H)
    o:noBackground(); o.moveWithMouse = true
    o.cfg = cfg or {}
    for _, r in ipairs(RANKS) do
        o.cfg[r] = o.cfg[r] or {}
        o.cfg[r].White  = o.cfg[r].White  or 0
        o.cfg[r].Yellow = o.cfg[r].Yellow or 0
        o.cfg[r].Blue   = o.cfg[r].Blue   or 0
    end
    return o
end

function DunKaRankEditUI:close()
    DunKaRankEditUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end
function DunKaRankEditUI:onRightMouseDown(x,y) self:close(); return true end

function DunKaRankEditUI:btn(label, x, y, w, h, primary)
    self:drawRect(x, y, w, h, 0.9, primary and 0.14 or 0.2, primary and 0.30 or 0.16, primary and 0.12 or 0.1)
    self:drawRectBorder(x, y, w, h, 0.9, 0.55, 0.45, 0.25)
    self:drawTextCentre(label, x + w/2, y + h/2 - 8, 0.95, 0.9, 0.75, 1, UIFont.Small)
end

function DunKaRankEditUI:render()
    self:drawRect(0, 0, W, H, 0.96, 0.07, 0.07, 0.08)
    self:drawRectBorder(0, 0, W, H, 1, 0.55, 0.42, 0.2)
    self:drawRect(0, 0, W, 30, 1, 0.13, 0.11, 0.09)
    self:drawText("Rank Rewards  (slips given on summon)", 14, 7, 0.95, 0.85, 0.5, 1, UIFont.Medium)
    self:drawText("X", W-22, 6, 0.9, 0.7, 0.7, 1, UIFont.Medium)

    -- column headers
    self:drawText("RANK", 22, 54, 0.6, 0.6, 0.55, 1, UIFont.Small)
    self:drawText("White",  COLS[1].x-4, 54, 0.8, 0.8, 0.78, 1, UIFont.Small)
    self:drawText("Yellow", COLS[2].x-4, 54, 0.9, 0.85, 0.4, 1, UIFont.Small)
    self:drawText("Blue",   COLS[3].x-4, 54, 0.5, 0.7, 0.95, 1, UIFont.Small)
    self:drawRect(12, 74, W-24, 1, 0.5, 0.5, 0.4, 0.25)

    for ri, r in ipairs(RANKS) do
        local y = ROW0 + (ri-1)*ROWH
        self:drawText("Rank " .. r, 22, y+6, 0.94, 0.62, 0.15, 1, UIFont.Large)
        for _, c in ipairs(COLS) do
            local v = self.cfg[r][c.k] or 0
            self:btn("-", c.x, y+2, 26, 26)
            self:drawTextCentre(tostring(v), c.x+52, y+5, 1, 0.9, 0.6, 1, UIFont.Large)
            self:btn("+", c.x+66, y+2, 26, 26)
        end
    end

    self:btn("Save", W-130, H-40, 110, 30, true)
    self:drawText("0 = colour not given", 20, H-34, 0.55, 0.55, 0.52, 1, UIFont.Small)
end

function DunKaRankEditUI:onMouseDown(x, y)
    if hit(x, y, W-24, 4, 24, 24) then self:close(); return true end
    for ri, r in ipairs(RANKS) do
        local ry = ROW0 + (ri-1)*ROWH
        for _, c in ipairs(COLS) do
            if hit(x, y, c.x, ry+2, 26, 26) then
                self.cfg[r][c.k] = math.max(0, (self.cfg[r][c.k] or 0) - 1); return true
            end
            if hit(x, y, c.x+66, ry+2, 26, 26) then
                self.cfg[r][c.k] = math.min(9, (self.cfg[r][c.k] or 0) + 1); return true
            end
        end
    end
    if hit(x, y, W-130, H-40, 110, 30) then self:save(); return true end
    return ISPanel.onMouseDown(self, x, y)
end

function DunKaRankEditUI:save()
    local pl = getPlayer()
    for _, r in ipairs(RANKS) do
        local c = self.cfg[r]
        if DunKa.isSP() then
            DunKa.setRankReward(r, c.White, c.Yellow, c.Blue)
        else
            sendClientCommand(pl, "DunKa", "setRankCfg", { rank = r, white = c.White, yellow = c.Yellow, blue = c.Blue })
        end
    end
    if pl then pl:setHaloNote("Rank rewards saved", 150, 230, 150, 250) end
end

print("[DunKa] RankEditUI loaded")
