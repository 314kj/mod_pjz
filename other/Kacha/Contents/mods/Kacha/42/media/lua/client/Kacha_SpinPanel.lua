--[[ ============================================================
     Kacha B42 [MP]  -  Wheel Spin panel (player)  by PIE
     Scroll mouse UP to spin. Item-icon reel spins a FIXED 2s; result from
     the result the SERVER already rolled by real % (no cheating).
     x N  = N independent rolls from the whole pool (1 coin = 1 roll).
     Result shows on a GREEN banner, then the UI auto-closes.
     English UI only.                                    BUILD=wheel-A
   ============================================================ ]]
require "ISUI/ISPanel"
require "ISUI/ISButton"

Kacha = Kacha or {}
KachaSpin = ISPanel:derive("KachaSpin")

local SPIN_MS   = 6000

function KachaSpin:new(obj, pl)
    local w, h = 430, 460
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.obj = obj; o.pl = pl or getPlayer(); o.titleH = 38; o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.count = 1; o.spinning = false; o.wheelFrame = 0
    return o
end

function KachaSpin:createChildren()
    local W, H = self:getWidth(), self:getHeight()
    self.closeBtn = ISButton:new(W - 30, 8, 22, 22, "X", self, KachaSpin.onClose)
    self.closeBtn:initialise(); self.closeBtn.backgroundColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.7 }
    self:addChild(self.closeBtn)

    self.oddsBtn = ISButton:new(8, 9, 70, 22, "Items", self, KachaSpin.onOdds)
    self.oddsBtn:initialise(); self.oddsBtn.backgroundColor = { r = 0.16, g = 0.30, b = 0.55, a = 0.85 }
    self:addChild(self.oddsBtn)

    self.countBtns = {}
    local cnts = { 1, 5, 10, 20, 100 }
    local bw, gap = 66, 8
    local total = #cnts * bw + (#cnts - 1) * gap
    local sx = W / 2 - total / 2
    for i, n in ipairs(cnts) do
        local b = ISButton:new(sx + (i - 1) * (bw + gap), H - 52, bw, 30, "x" .. n, self, KachaSpin.onPickCount)
        b.kachaCount = n; b:initialise(); self:addChild(b); self.countBtns[i] = b
    end
end

function KachaSpin:onClose() self:removeFromUIManager(); KachaSpin.instance = nil end
function KachaSpin:onOdds() if Kacha.openOdds then Kacha.openOdds(self.obj) end end
function KachaSpin:onPickCount(button) self.count = button.kachaCount end

function KachaSpin:balance()
    local d = Kacha.getConfig(self.obj)
    local ti = d.tokenItem or "Base.KachaCoin"
    local inv = self.pl and self.pl:getInventory()
    return inv and inv:getItemCount(ti) or 0
end

-- scroll UP over the panel = spin (the gesture only triggers; it never
-- controls speed or outcome, so it cannot be used to cheat)
function KachaSpin:onMouseWheel(del)
    if del < 0 then self:startSpin() end   -- del<0 = scroll up
    return true
end

function KachaSpin:startSpin()
    if self.spinning then return end
    local res = Kacha.requestSpin(self.obj, self.pl, self.count)
    if res == nil then self.flash = "Not enough coins"; self.flashT = 120; return end
    self.spinning = true; self.spinStart = getTimestampMs(); self.reelOffset = 0
    self.pool = (Kacha.mushTextures and Kacha.mushTextures()) or {}
    self.soundPlays = 1; self.soundNext = self.spinStart + 2000   -- loop 2s clip ~3x over 6s
    self.green = nil; self.greenWin = false; self.list = nil; self.closeAt = nil
    if res == "pending" then
        self.results = nil; self.resultReady = false
    else
        self.results = res; self.resultReady = true       -- SP
    end
    if Kacha.playSpin then Kacha.playSpin(self.pl) end
end

function Kacha.deliverResults(args)
    local p = KachaSpin.instance
    if not p then return end
    if not args or args.ok == false then
        p.flash = (args and args.reason == "poor") and "Not enough coins"
            or (args and args.reason == "noitems") and "Admin has not added items"
            or "Spin failed"
        p.flashT = 150; p.spinning = false; return
    end
    p.results = args.results or {}
    p.resultReady = true
    -- reveal is handled by the animation once the fixed 3s elapses
end

function KachaSpin:reveal()
    local wins = {}
    for _, r in ipairs(self.results or {}) do if r and not r.salt then wins[#wins + 1] = r end end
    local gotWin = #wins > 0
    if self.count == 1 then
        local r = (self.results and self.results[1]) or nil
        if r and not r.salt then
            self.green = r.name or r.id or "?"; self.greenWin = true
        else
            self.green = (r and (r.name or "Salt")) or "Salt"; self.greenWin = false
        end
    else
        self.green = "Won " .. #wins .. " / " .. self.count; self.greenWin = gotWin
        self.list = {}
        for i = 1, math.min(#wins, 10) do self.list[i] = wins[i] end
    end
    local rares = {}
    for _, r in ipairs(self.results or {}) do
        if r and (r.tier == "S" or r.tier == "SS" or r.tier == "SS+") then rares[#rares + 1] = r end
    end
    if #rares > 0 and Kacha.openRarePopup then Kacha.openRarePopup(rares) end
    if Kacha.playResult then Kacha.playResult(self.pl, gotWin) end
    self.closeAt = getTimestampMs() + 2800
end

function KachaSpin:prerender()
    local W, H = self:getWidth(), self:getHeight()
    local T, S, A, R = Kacha.COL.text, Kacha.COL.sub, Kacha.COL.accent, Kacha.COL.red
    self:drawRect(0, 0, W, H, Kacha.COL.bg.a, Kacha.COL.bg.r, Kacha.COL.bg.g, Kacha.COL.bg.b)
    self:drawRectBorder(0, 0, W, H, A.a, A.r, A.g, A.b)
    self:drawRect(0, 0, W, self.titleH, R.a, R.r, R.g, R.b)
    self:drawText(Kacha.machineName(self.obj), 88, 10, 1, 1, 1, 1, UIFont.Medium)

    -- coin + balance
    local d = Kacha.getConfig(self.obj)
    local coin = Kacha.coinByItem(d.tokenItem or "Base.KachaCoin")
    local ctex = Kacha.coinTexture(coin)
    if ctex then self:drawTextureScaled(ctex, W - 116, 7, 24, 24, 1, 1, 1, 1)
    else self:drawRect(W - 116, 7, 24, 24, 1, coin.col.r, coin.col.g, coin.col.b) end
    self:drawText(tostring(self:balance()), W - 86, 10, 1, 1, 1, 1, UIFont.Medium)

    -- green result banner
    local by = self.titleH + 8
    if self.green then
        self:drawRect(14, by, W - 28, 34, 0.95, 0.06, 0.16, 0.11)
        local gc = self.greenWin and { 0.22, 0.82, 0.48 } or { 0.55, 0.62, 0.72 }
        self:drawRectBorder(14, by, W - 28, 34, 1, gc[1], gc[2], gc[3])
        self:drawTextCentre((self.greenWin and "WON:  " or "") .. tostring(self.green), W / 2, by + 8, gc[1], gc[2], gc[3], 1, UIFont.Medium)
    end

    -- item-icon REEL (item textures load reliably; loose wheel PNGs did not)
    local ws, wh = 300, 92
    local wx, wy = W / 2 - ws / 2, self.titleH + 60
    self:drawRect(wx, wy, ws, wh, 0.95, 0.04, 0.06, 0.12)
    self:drawRectBorder(wx, wy, ws, wh, A.a, A.r, A.g, A.b)
    local pool = self.pool or {}
    local iconW, ic = 78, 64
    if self.spinning then
        local el = getTimestampMs() - (self.spinStart or 0)
        local p = el / SPIN_MS; if p > 1 then p = 1 end
        local eased = 1 - (1 - p) * (1 - p) * (1 - p)
        local strip = (#pool > 0 and #pool or 1) * iconW
        self.reelOffset = eased * (9 * strip)
        if self.soundNext and getTimestampMs() >= self.soundNext and (self.soundPlays or 0) < 3 then
            if Kacha.playSpin then Kacha.playSpin(self.pl) end
            self.soundPlays = (self.soundPlays or 1) + 1; self.soundNext = self.soundNext + 2000
        end
        if p >= 1 and self.resultReady then self.spinning = false; self:reveal() end
    end
    if #pool > 0 then
        local offset = self.reelOffset or 0
        local centerX = wx + ws / 2
        local first = math.floor((offset - ws / 2) / iconW) - 1
        local last  = math.ceil((offset + ws / 2) / iconW) + 1
        for c = first, last do
            local tex = pool[(c % #pool) + 1]
            if tex then
                local x = centerX - ic / 2 + (c * iconW - offset)
                if x + ic > wx + 2 and x < wx + ws - 2 then   -- manual clip to reel box
                    self:drawTextureScaled(tex, x, wy + (wh - ic) / 2, ic, ic, 1, 1, 1, 1)
                end
            end
        end
    else
        self:drawTextCentre("...", wx + ws / 2, wy + wh / 2 - 8, S.r, S.g, S.b, 1, UIFont.Medium)
    end
    -- centre pointer
    self:drawRect(wx + ws / 2 - 2, wy - 8, 4, 12, 1, A.r, A.g, A.b)
    self:drawRect(wx + ws / 2 - 2, wy + wh - 4, 4, 12, 1, A.r, A.g, A.b)

    -- multi list
    if self.list and #self.list > 0 then
        local ly = wy + wh + 10
        local line = ""
        for _, r in ipairs(self.list) do line = line .. (r.name or r.id or "?") .. "   " end
        self:drawTextCentre(line, W / 2, ly, T.r, T.g, T.b, 1, UIFont.Small)
    end

    -- hint / cost
    local cost = tonumber(d.costPerRoll) or 1
    if not self.spinning and not self.green then
        self:drawTextCentre("scroll mouse up to spin", W / 2, wy + wh + 28, A.r, A.g, A.b, 1, UIFont.Medium)
    elseif self.spinning then
        self:drawTextCentre("spinning...", W / 2, wy + wh + 28, S.r, S.g, S.b, 1, UIFont.Small)
    end
    self:drawTextCentre("x" .. self.count .. "  =  " .. (cost * self.count) .. "   (each coin = 1 roll)",
        W / 2, H - 74, S.r, S.g, S.b, 1, UIFont.Small)

    -- count highlight
    for _, b in ipairs(self.countBtns) do
        b.backgroundColor = (b.kachaCount == self.count)
            and { r = 0.18, g = 0.42, b = 1.0, a = 0.95 } or { r = 0.14, g = 0.18, b = 0.28, a = 0.85 }
    end

    -- flash + auto-close
    if self.flash and self.flashT and self.flashT > 0 then
        self.flashT = self.flashT - 1
        self:drawTextCentre(self.flash, W / 2, H - 96, 0.9, 0.4, 0.4, 1, UIFont.Small)
    end
    if self.closeAt and getTimestampMs() >= self.closeAt then self:onClose() end
end

function Kacha.openSpin(obj, pl)
    if Kacha.pushCfg then Kacha.pushCfg(obj) end
    if KachaSpin.instance then KachaSpin.instance:onClose() end
    local p = KachaSpin:new(obj, pl)
    p:initialise(); p:instantiate(); p:addToUIManager()
    KachaSpin.instance = p
end

Kacha.__mark("spin")
