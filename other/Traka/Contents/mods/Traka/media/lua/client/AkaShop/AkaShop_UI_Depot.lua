--[[===========================================================================
    Traka - the buy-back depot window.

    A BOARD, NOT A SPREADSHEET. The old list-of-rows treated a depot like an
    inventory screen; it is really a shop window. So: cards four across, the
    item's own picture on top, the price large underneath, and a Sell strip on
    every card. One click sells one item. There is deliberately no quantity
    stepper - the moment you add one, the card stops being a price tag and
    becomes a form.

    Anything the admin put a deadline on gets its own background colour, a
    SPECIAL flag and a live countdown. That is what the colour is for: a player
    walking up should see at a glance which two of the twelve cards are worth
    hurrying for.

    An offer that ran out of time or ran out of quota is simply NOT HERE. The
    server deletes it rather than greying it out, so every card on this board is
    a deal that can be taken right now.

    DO NOT cache AkaShopUI in a local at the top of this file. Project Zomboid
    loads lua in lowercased name order and "akashop_ui_depot" sorts before
    "akashop_uicommon" ('_' is 0x5F, 'c' is 0x63), so at load time that global
    does not exist yet. Doing it cost a whole release in which this window could
    not open even once.
============================================================================]]

require "ISUI/ISCollapsableWindow"

AkaShopDepotUI = ISCollapsableWindow:derive("AkaShopDepotUI")
AkaShopDepotUI.instance = nil

local PAD          = 12
local W, H         = 1000, 640
local CARDW, CARDH = 168, 200
local GAP          = 10
local RAILW        = 250

--============================================================== open/close ==

function AkaShopDepotUI.openWith(snap)
    local ui = AkaShopDepotUI.instance
    if ui then
        ui:setSnap(snap)
        ui:addToUIManager(); ui:setVisible(true); ui:bringToTop()
        return ui
    end
    ui = AkaShopDepotUI:new(snap)
    ui:initialise(); ui:addToUIManager()
    AkaShopDepotUI.instance = ui
    return ui
end

function AkaShopDepotUI.closeKey(key)
    local ui = AkaShopDepotUI.instance
    if ui and (not key or ui.key == key) then ui:close() end
end

function AkaShopDepotUI:new(snap)
    local x = (getCore():getScreenWidth()  - W) / 2
    local y = (getCore():getScreenHeight() - H) / 2
    local o = ISCollapsableWindow.new(self, x, y, W, H)
    setmetatable(o, self); self.__index = self
    AkaShopUI.skin(o)
    o.snap, o.key = snap, snap.key
    o.pick   = nil        -- uid of the highlighted card
    -- Stamp the moment this snapshot was received, NOT zero. leftOf() measures
    -- "how long since the snapshot", so a zero stamp means "1.7 billion seconds
    -- ago" and every countdown reads as finished - which painted every SPECIAL
    -- card as an ordinary one on the first open and after every reopen.
    o.scroll = 0
    o.colour = 1
    o.stamp  = o:nowSec()
    o:setResizable(false)
    o.title = "Traka"
    return o
end

function AkaShopDepotUI:close()
    AkaShopDepotUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
    ISCollapsableWindow.close(self)
end

function AkaShopDepotUI:setSnap(snap)
    self.snap  = snap
    self.key   = snap.key
    self.stamp = self:nowSec()
    self:rebuild()
end

function AkaShopDepotUI:nowSec()
    local t
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t end
    return 0
end

--- Seconds left on an offer, ticking down from the snapshot we were sent.
--- `left == 0` in a snapshot means "never expires", so it stays 0 here.
function AkaShopDepotUI:leftOf(row)
    local base = math.floor(row.left or 0)
    if base <= 0 then return 0 end
    local n = base - (self:nowSec() - (self.stamp or 0))
    if n < 0 then return 0 end
    return n
end

--============================================================== children ====

function AkaShopDepotUI:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()

    self.lblName = AkaShopUI.label(self, PAD, th + 8, "", AkaShopUI.C.title,
                                   AkaShopUI.FONT_BIG)
    self.lblSub  = AkaShopUI.label(self, PAD, th + 36, "", AkaShopUI.C.dim)

    local top = th + 62
    self.boardX, self.boardY = PAD, top
    self.boardW = W - RAILW - PAD * 3
    self.boardH = H - top - PAD

    local rx = PAD + self.boardW + PAD * 2
    local rw = RAILW - PAD
    local y  = top

    -- The rail runs the full height of the window and v3.6.0 added a row to it,
    -- so the headings sit BESIDE their values rather than above them. Two lines
    -- reclaimed here are what let the barter button exist without the Delete
    -- button falling off the bottom edge.
    AkaShopUI.label(self, rx, y + 8, "Wallet", AkaShopUI.C.dim)
    self.lblWallet = AkaShopUI.label(self, rx + 76, y, "0", AkaShopUI.C.money,
                                     AkaShopUI.FONT_BIG); y = y + 34

    AkaShopUI.label(self, rx, y, "Selected", AkaShopUI.C.dim)
    self.lblPick  = AkaShopUI.label(self, rx + 76, y, "-", AkaShopUI.C.text); y = y + 24
    self.lblCarry = AkaShopUI.label(self, rx, y, "", AkaShopUI.C.dim);   y = y + 28

    self.btnAll = AkaShopUI.button(self, rx, y, rw, 30, "Sell everything I carry",
                                   self, AkaShopDepotUI.onSellAll, "DepotSellAll")
    y = y + 42

    ------------------------------------------------------------ admin panel
    self.adm = {}
    local function keep(w) table.insert(self.adm, w); return w end

    keep(AkaShopUI.label(self, rx, y, "Admin", AkaShopUI.C.title)); y = y + 26

    keep(AkaShopUI.label(self, rx, y, "Item", AkaShopUI.C.dim)); y = y + 20
    self.ddBtn = keep(AkaShopUI.button(self, rx, y, rw, 26, "pick an item...",
                      self, AkaShopDepotUI.onOpenPicker, "DepotPick")); y = y + 32

    local halfw = (rw - 8) / 2
    keep(AkaShopUI.label(self, rx, y, "Price each", AkaShopUI.C.dim))
    keep(AkaShopUI.label(self, rx + halfw + 8, y, "Quantity", AkaShopUI.C.dim))
    y = y + 20
    self.ePrice = keep(AkaShopUI.entry(self, rx, y, halfw, 24, "10", true))
    self.eQty   = keep(AkaShopUI.entry(self, rx + halfw + 8, y, halfw, 24, "", true))
    y = y + 26
    keep(AkaShopUI.label(self, rx, y, "blank qty = no limit,  0 min = forever",
                         AkaShopUI.C.dim))
    y = y + 24

    -- What this offer pays with. Money is the default and stays a single word;
    -- a barter deal needs three numbers, which live in their own little window
    -- rather than eating three more rows of a rail that has none to spare.
    keep(AkaShopUI.label(self, rx, y, "Pays with", AkaShopUI.C.dim)); y = y + 20
    self.btnPay = keep(AkaShopUI.button(self, rx, y, rw, 26, "Money",
                       self, AkaShopDepotUI.onOpenPay, "DepotPay")); y = y + 32

    keep(AkaShopUI.label(self, rx, y + 3, "Buying for (min)", AkaShopUI.C.dim))
    self.eMin = keep(AkaShopUI.entry(self, rx + halfw + 8, y, halfw, 24, "0", true))
    y = y + 30

    keep(AkaShopUI.label(self, rx, y, "Card colour", AkaShopUI.C.dim)); y = y + 20
    self.swX, self.swY = rx, y
    y = y + 28

    self.btnOpen = keep(AkaShopUI.button(self, rx, y, rw, 24, "Open / Close this point",
                        self, AkaShopDepotUI.onToggleOpen, "DepotOpen")); y = y + 30

    self.btnAdd = keep(AkaShopUI.button(self, rx, y, rw, 28, "Add / update offer",
                       self, AkaShopDepotUI.onAdd, "DepotAdd")); y = y + 32
    self.btnDel = keep(AkaShopUI.button(self, rx, y, rw, 24, "Remove selected",
                       self, AkaShopDepotUI.onDel, "DepotDel")); y = y + 32

    keep(AkaShopUI.button(self, rx, y, halfw, 24, "Link...", self,
                          AkaShopDepotUI.onLink, "DepotLink"))
    keep(AkaShopUI.button(self, rx + halfw + 8, y, halfw, 24, "Unlink", self,
                          AkaShopDepotUI.onUnlink, "DepotUnlink")); y = y + 28
    keep(AkaShopUI.button(self, rx, y, halfw, 24, "Rename", self,
                          AkaShopDepotUI.onRename, "DepotRename"))
    keep(AkaShopUI.button(self, rx + halfw + 8, y, halfw, 24, "Delete", self,
                          AkaShopDepotUI.onDelete, "DepotDelete"))

    self:rebuild()
end

--================================================================ rebuild ===

function AkaShopDepotUI:rebuild()
    local snap = self.snap or {}
    if self.lblName then self.lblName:setName(AkaShop.shopName(snap)) end
    local shut = (snap.enabled == false)
    if self.lblSub then
        local bits = {}
        if shut then table.insert(bits, "CLOSED - buying nothing right now") end
        table.insert(bits, #(snap.rows or {}) .. " item(s) wanted")
        if (snap.linked or 1) > 1 then
            table.insert(bits, (snap.linked - 1) .. " linked point(s)")
        end
        -- "pays in Money" is a lie on a board where half the cards trade goods,
        -- and the header is the first thing a player reads.
        local barter = false
        for _, r in ipairs(snap.rows or {}) do
            if r.payFt then barter = true; break end
        end
        table.insert(bits, barter
            and ("pays in goods or " .. tostring(snap.currency or "money"))
            or  ("pays in " .. tostring(snap.currency or "money")))
        table.insert(bits, "stand within " .. AkaShop.useDistance() .. " tiles")
        self.lblSub:setName(table.concat(bits, "   -   "))
        local c = shut and AkaShopUI.C.bad or AkaShopUI.C.dim
        self.lblSub.r, self.lblSub.g, self.lblSub.b = c[1], c[2], c[3]
    end
    if self.btnOpen then
        self.btnOpen:setTitle(shut and "Reopen this point" or "Close this point")
    end
    -- A closed counter still shows its board to an admin, so they can set the
    -- weekend's prices before opening. To a customer the Sell strips simply
    -- stop working, and the header says why.
    if self.btnAll then self.btnAll:setEnable(not shut) end

    local admin = snap.admin and true or false
    for _, w in ipairs(self.adm or {}) do w:setVisible(admin) end

    -- A card that vanished (sold out, or the clock ran down) must not stay
    -- selected, or the rail would keep describing an offer nobody can take.
    if self.pick and not self:rowOf(self.pick) then self.pick = nil end
    self:refreshRail()
end

function AkaShopDepotUI:rowOf(uid)
    for _, r in ipairs((self.snap or {}).rows or {}) do
        if r.uid == uid then return r end
    end
    return nil
end

function AkaShopDepotUI:carrying(ft)
    return AkaShopUI.stockCount(ft)
end

--- What ONE of this row's item causes the server to build when it is sold.
--- Money rows pay their price each; a barter row pays its whole payout once per
--- lot, so the per-item figure is the payout divided by the lot. This is the
--- number the sell queue paces itself on - see the note over the queue.
local function payPerItem(row)
    if not row then return 0 end
    if row.payFt then
        return (row.payN or 1) / math.max(1, math.floor(row.lot or 1))
    end
    return math.max(0, math.floor(row.price or 0))
end

--- How many of a row the player is carrying, and which concrete item type
--- would be handed over first.
---
--- For an ordinary row that is just "how many of this item". For a PACK the
--- client has to choose, because the server cannot know which of fourteen
--- rings is in the bag. The choice is the worst-condition member first:
--- somebody walking up to a buy-back counter wants to dump their junk, not
--- have the machine take the good one and leave them the scrap.
--- Both answers now come out of AkaShopUI.stock(), which walks the inventory
--- once and buckets it. This function used to do one full walk per member type
--- of a pack, on the rail, ten times a second - see the note over the index in
--- AkaShop_UICommon for how badly that scaled.
function AkaShopDepotUI:carryingRow(row)
    if not row.pack then
        return self:carrying(row.ft), row.ft
    end
    return AkaShopUI.packCarry(row.pack)
end

--- The numbers on the rail change perhaps once a minute, and prerender runs
--- every frame. Ten times a second is already far more often than an eye can
--- read them - and behind this the index has its own half-second cache, so a
--- quiet window costs a couple of inventory walks a second at most.
function AkaShopDepotUI:refreshRailSlow()
    local n = (self.railTick or 0) + 1
    self.railTick = n
    if n % 6 ~= 0 then return end
    self:refreshRail()
end

function AkaShopDepotUI:refreshRail()
    if self.lblWallet then
        self.lblWallet:setName(AkaShop.money(AkaShopUI.walletOf() or 0))
    end
    local row = self.pick and self:rowOf(self.pick)
    if self.lblPick then self.lblPick:setName(row and row.name or "-") end

    -- The button only changes when the sale is BIG enough to be paced. An
    -- ordinary sale is one request and is over before the next frame, so
    -- flashing a progress readout at it would be a flicker rather than
    -- information - and the whole point of the payout budget is that ordinary
    -- sales feel exactly as they always did.
    if self.btnAll then
        if AkaShopClient.sellPaced() then
            local left = AkaShopClient.sellProgress()
            self.btnAll:setTitle("selling...  " .. left .. " left   (Stop)")
        else
            self.btnAll:setTitle("Sell everything I carry")
        end
    end
    if self.lblCarry then
        if row then
            local n = self:carryingRow(row)
            if row.payFt then
                -- What the player would actually walk away with, which on a
                -- barter row is not "n times a price" - it is whole trades, and
                -- the remainder is worth nothing until they find more.
                local lot  = math.max(1, math.floor(row.lot or 1))
                local lots = math.floor(n / lot)
                self.lblCarry:setName("you carry " .. n .. "   (= " ..
                    (lots * (row.payN or 1)) .. " " ..
                    tostring(row.payName or "?") .. ")")
            else
                self.lblCarry:setName("you carry " .. n .. "   (" ..
                                      AkaShop.money(n * (row.price or 0)) .. ")")
            end
        else
            self.lblCarry:setName("")
        end
    end
end

--============================================================== the board ===

function AkaShopDepotUI:cardRect(i)
    local col  = (i - 1) % 4
    local line = math.floor((i - 1) / 4)
    return self.boardX + col * (CARDW + GAP),
           self.boardY + line * (CARDH + GAP) - (self.scroll or 0),
           CARDW, CARDH
end

function AkaShopDepotUI:prerender()
    ISCollapsableWindow.prerender(self)
    local snap = self.snap or {}
    local th, C = AkaShopUI.THEME, AkaShopUI.C

    self:drawRect(self.boardX - 4, self.boardY - 4, self.boardW + 8, self.boardH + 8,
                  th.panel.a, th.panel.r, th.panel.g, th.panel.b)
    self:drawRectBorder(self.boardX - 4, self.boardY - 4, self.boardW + 8, self.boardH + 8,
                        th.border.a, th.border.r, th.border.g, th.border.b)

    local rows = snap.rows or {}
    if #rows == 0 then
        self:drawText("This depot is not buying anything right now.",
                      self.boardX + 14, self.boardY + 16,
                      C.dim[1], C.dim[2], C.dim[3], 1, AkaShopUI.FONT)
    end

    -- Clip to the board. Without this a half-scrolled card paints straight over
    -- the title and the rail, because nothing in ISUIElement bounds a drawRect
    -- to its parent.
    local clipped = type(self.setStencilRect) == "function"
    if clipped then
        self:setStencilRect(self.boardX, self.boardY, self.boardW, self.boardH)
    end

    for i, r in ipairs(rows) do
        local x, y, w, h = self:cardRect(i)
        -- only paint what is actually on the board; a long list must not cost
        -- a texture draw per off-screen card every frame
        if y + h > self.boardY - 2 and y < self.boardY + self.boardH then
            self:drawCard(x, y, w, h, r)
        end
    end

    if clipped then self:clearStencilRect() end

    if snap.admin and self.swX then
        for i, c in ipairs(AkaShop.CARD_COLOURS) do
            local sx = self.swX + (i - 1) * 30
            self:drawRect(sx, self.swY, 26, 21, 1, c[1], c[2], c[3])
            local on = (self.colour == i)
            self:drawRectBorder(sx, self.swY, 26, 21, on and 1 or 0.55,
                                on and 0.98 or 0.35, on and 0.83 or 0.37,
                                on and 0.42 or 0.38)
        end
    end

    self:refreshRailSlow()
end

function AkaShopDepotUI:drawCard(x, y, w, h, r)
    local th, C = AkaShopUI.THEME, AkaShopUI.C
    local left    = self:leftOf(r)
    local special = r.special and left > 0

    if special then
        local col = AkaShop.cardColour(r.colour)
        self:drawRect(x, y, w, h, 1, col[1], col[2], col[3])
    else
        self:drawRect(x, y, w, h, th.button.a, th.button.r, th.button.g, th.button.b)
    end

    local sel = (self.pick == r.uid)
    self:drawRectBorder(x, y, w, h, sel and 1 or th.border.a,
                        sel and 0.98 or th.border.r,
                        sel and 0.83 or th.border.g,
                        sel and 0.42 or th.border.b)

    -- A pack owns no item of its own, so the first member lends its picture.
    -- For a ring pack that is a ring, which is exactly what the card should
    -- look like.
    local iconFt = r.pack and AkaShopPacks.iconFt(r.pack) or r.ft
    AkaShopUI.drawItemIcon(self, iconFt, x + (w - 58) / 2, y + 14, 58, 58)

    local function fit(s, font, room)
        if getTextManager():MeasureStringX(font, s) <= room then return s end
        while #s > 4 and getTextManager():MeasureStringX(font, s .. "..") > room do
            s = string.sub(s, 1, #s - 1)
        end
        return s .. ".."
    end

    self:drawText(fit(r.name, AkaShopUI.FONT, w - 20), x + 10, y + 80,
                  C.text[1], C.text[2], C.text[3], 1, AkaShopUI.FONT)

    if r.payFt then
        -- A barter rate will not fit at the price font, and shrinking the price
        -- font on money cards to match would make every ordinary card worse.
        -- The rate gets the body font and two lines of its own.
        self:drawText(fit((r.lot or 1) .. " ->", AkaShopUI.FONT, w - 20),
                      x + 10, y + 102, C.dim[1], C.dim[2], C.dim[3], 1, AkaShopUI.FONT)
        self:drawText(fit((r.payN or 1) .. " " .. tostring(r.payName or "?"),
                          AkaShopUI.FONT, w - 20),
                      x + 10, y + 122, C.money[1], C.money[2], C.money[3], 1,
                      AkaShopUI.FONT)
    else
        self:drawText(AkaShop.money(r.price or 0), x + 10, y + 102,
                      C.money[1], C.money[2], C.money[3], 1, AkaShopUI.FONT_BIG)
    end

    local qt, qc
    if not r.qty or r.qty < 0 then qt, qc = "no limit", C.dim
    else qt, qc = r.qty .. " wanted", C.good end
    if r.pack then
        qt = qt .. "  -  any of " .. #AkaShopPacks.members(r.pack)
    end
    self:drawText(qt, x + 10, y + 130, qc[1], qc[2], qc[3], 1, UIFont.Small)

    if r.pack then
        local pw = getTextManager():MeasureStringX(UIFont.Small, "PACK") + 10
        self:drawRect(x + 1, y + 1, pw, 16, 1, 0.306, 0.498, 0.682)
        self:drawText("PACK", x + 6, y + 1, 0.03, 0.07, 0.10, 1, UIFont.Small)
    end

    if special then
        self:drawText("ends in " .. AkaShop.durationText(left), x + 10, y + 148,
                      C.bad[1], C.bad[2], C.bad[3], 1, UIFont.Small)
        local tw = getTextManager():MeasureStringX(UIFont.Small, "SPECIAL") + 12
        self:drawRect(x + w - tw, y, tw, 18, 1, 0.788, 0.573, 0.180)
        self:drawText("SPECIAL", x + w - tw + 6, y + 1, 0.10, 0.07, 0.03, 1, UIFont.Small)
    end

    local by = y + h - 32
    self:drawRect(x + 1, by, w - 2, 31, 1, 0.180, 0.196, 0.212)
    self:drawRectBorder(x + 1, by, w - 2, 31, th.border.a, th.border.r, th.border.g, th.border.b)
    local lw = getTextManager():MeasureStringX(AkaShopUI.FONT, "Sell")
    self:drawText("Sell", x + (w - lw) / 2, by + 5,
                  C.text[1], C.text[2], C.text[3], 1, AkaShopUI.FONT)
end

--============================================================== clicking ====

function AkaShopDepotUI:onMouseDown(x, y)
    if (self.snap or {}).admin and self.swX
       and y >= self.swY and y <= self.swY + 21 then
        for i = 1, #AkaShop.CARD_COLOURS do
            local sx = self.swX + (i - 1) * 30
            if x >= sx and x <= sx + 26 then self.colour = i; return true end
        end
    end

    -- The click has to land on the board itself, not merely inside a card's
    -- rectangle. A card scrolled half off the top still has coordinates up
    -- there in the title bar, and clicking the title must not sell an axe.
    local onBoard = x >= self.boardX and x <= self.boardX + self.boardW
                and y >= self.boardY and y <= self.boardY + self.boardH
    if onBoard then
        for i, r in ipairs((self.snap or {}).rows or {}) do
            local cx, cy, w, h = self:cardRect(i)
            if x >= cx and x <= cx + w and y >= cy and y <= cy + h then
                self.pick = r.uid
                if (self.snap or {}).admin then self:loadForm(r) end
                if y >= cy + h - 32 then self:sellOne(r) end  -- bottom strip = Sell
                self:refreshRail()
                return true
            end
        end
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function AkaShopDepotUI:onMouseWheel(del)
    local lines = math.ceil(#((self.snap or {}).rows or {}) / 4)
    local max   = math.max(0, lines * (CARDH + GAP) - self.boardH)
    self.scroll = math.max(0, math.min(max, (self.scroll or 0) + del * 44))
    return true
end

--============================================================== selling =====

function AkaShopDepotUI:sellOne(row)
    if (self.snap or {}).enabled == false then
        return AkaShopClient.notify("This buying point is closed right now.", true)
    end
    local n, ft = self:carryingRow(row)
    if n < 1 or not ft then
        return AkaShopClient.notify("You are not carrying any " .. row.name .. ".", true)
    end
    -- On a barter row "one" is one TRADE, not one item. Sending qty 1 for a
    -- twenty-for-one deal would be refused by the server every single time,
    -- and the button would look broken rather than strict.
    local lot = math.max(1, math.floor(row.lot or 1))
    if n < lot then
        return AkaShopClient.notify("This deal trades " .. lot .. " at a time - " ..
                                    "you have " .. n .. ".", true)
    end
    -- Even one click goes through the queue. A single lot of two hundred is a
    -- bulk sale wearing a different hat, and it deserves the same budget.
    AkaShopClient.queueSell(self.key, row.uid, ft, lot, lot, payPerItem(row))
    self:startSellAction()
end

--- One click per item is right for a price tag and wrong for two hundred nails,
--- so the bulk verb lives on the rail where it cannot be hit by accident.
function AkaShopDepotUI:onSellAll()
    -- While a PACED run is going the same button is the way to stop it. One
    -- button that starts and stops beats a second button that is greyed out
    -- most of the time and unreachable exactly when it is wanted. A run that is
    -- not paced is over within the frame, so there is nothing to stop.
    if AkaShopClient.sellPaced() then
        return AkaShopClient.cancelSell("Stopped. What you have already sold is paid.")
    end

    local row = self.pick and self:rowOf(self.pick)
    if not row then return AkaShopClient.notify("Pick a card first.", true) end
    local n, ft = self:carryingRow(row)
    if n < 1 or not ft then
        return AkaShopClient.notify("You are not carrying any " .. row.name .. ".", true)
    end
    if row.qty and row.qty >= 0 then n = math.min(n, row.qty) end

    -- Whole trades only. Sending a remainder the server will round off anyway
    -- just produces a confusing "you need 20" on the last request of a burst.
    local lot = math.max(1, math.floor(row.lot or 1))
    n = math.floor(n / lot) * lot
    if n < lot then
        return AkaShopClient.notify("This deal trades " .. lot .. " at a time.", true)
    end

    if row.pack then
        -- One job per member type. A pack sale hands over ONE fullType at a
        -- time because that is all the take/took handshake can carry, so
        -- "everything I have" becomes a run of ordinary sales rather than a new
        -- protocol nobody else uses.
        --
        -- With a lot in play each of those must itself be whole trades, because
        -- each one is a separate transaction. Twenty rings of one kind and
        -- nineteen of another is one trade, not two - the nineteen wait.
        local left = n
        for _, member in ipairs(AkaShopPacks.members(row.pack)) do
            if left < lot then break end
            local have = math.min(self:carrying(member), left)
            have = math.floor(have / lot) * lot
            if have >= lot then
                AkaShopClient.queueSell(self.key, row.uid, member, have, lot,
                                        payPerItem(row))
                left = left - have
            end
        end
        self:startSellAction()
        return
    end
    AkaShopClient.queueSell(self.key, row.uid, ft, n, lot, payPerItem(row))
    self:startSellAction()
end

--- Put the character to work, but only for a sale big enough to be worth
--- watching. A sale that finishes in one hand-over would show a progress bar
--- for a single frame, which is worse than showing nothing.
function AkaShopDepotUI:startSellAction()
    if not AkaShopClient.sellWillPace() then return end
    if not AkaShopSellAction then return end
    local left = AkaShopClient.sellProgress()
    AkaShopSellAction.begin(AkaShopClient.me(), left)
end

--============================================================== admin acts ==

function AkaShopDepotUI:loadForm(row)
    self.ft = row.ft
    if self.ddBtn  then self.ddBtn:setTitle(row.name) end
    if self.ePrice then AkaShopUI.setNum(self.ePrice, row.price or 0) end
    if self.eQty   then
        self.eQty:setText((row.qty and row.qty >= 0) and tostring(row.qty) or "")
    end
    if self.eMin   then AkaShopUI.setNum(self.eMin, math.ceil((row.left or 0) / 60)) end
    self.colour = row.colour or 1
    self:setPay(row.payFt, row.payN or 1, row.lot or 1)
end

function AkaShopDepotUI:onToggleOpen()
    local snap = self.snap or {}
    local on = (snap.enabled == false)
    AkaShopClient.send("depotEnable", { key = self.key, on = on })
end

function AkaShopDepotUI:onOpenPicker()
    AkaShopItemPicker.open(self)
end

function AkaShopDepotUI:setItem(ft, name)
    self.ft = ft
    if self.ddBtn then self.ddBtn:setTitle(name or ft) end
end

--=============================================================== bartering ==

--- The three barter numbers as the admin panel currently holds them.
--- `ft = nil` means money, which is the state every offer starts in.
function AkaShopDepotUI:payState()
    local p = self.pay
    if type(p) ~= "table" then p = { ft = nil, n = 1, lot = 1 }; self.pay = p end
    return p
end

function AkaShopDepotUI:payLabel()
    local p = self:payState()
    if not p.ft then return "Money" end
    return AkaShop.rateText(p.lot, p.n, AkaShop.displayNameOf(p.ft))
end

function AkaShopDepotUI:setPay(ft, n, lot)
    self.pay = { ft = ft, n = n or 1, lot = lot or 1 }
    if self.btnPay then self.btnPay:setTitle(self:payLabel()) end
end

function AkaShopDepotUI:onOpenPay()
    AkaShopPayDialog.open(self, self:payState())
end

function AkaShopDepotUI:onAdd()
    local ft = self.ft
    if not ft or ft == "" then
        return AkaShopClient.notify("Pick an item first.", true)
    end
    local qtyText = self.eQty and self.eQty:getInternalText() or ""
    local qty = (qtyText == "") and -1 or (tonumber(qtyText) or -1)

    -- Already on the board? Then this is an EDIT. Making the admin delete and
    -- re-add would silently restart the countdown on a running special.
    for _, r in ipairs((self.snap or {}).rows or {}) do
        if r.ft == ft then
            local k = self.key
            -- Quantity goes LAST on purpose. Typing 0 into the box is a valid
            -- way to say "stop buying this", and the row deletes itself the
            -- moment the server next reads the list - so anything sent after it
            -- would come back as "that item is not on the list any more".
            AkaShopClient.send("depotSet", { key = k, uid = r.uid, field = "price",
                                             value = AkaShopUI.num(self.ePrice, 0) })
            AkaShopClient.send("depotSet", { key = k, uid = r.uid, field = "minutes",
                                             value = AkaShopUI.num(self.eMin, 0) })
            AkaShopClient.send("depotSet", { key = k, uid = r.uid, field = "colour",
                                             value = self.colour })
            local p = self:payState()
            AkaShopClient.send("depotSet", { key = k, uid = r.uid, field = "pay",
                                             value = { ft = p.ft, n = p.n, lot = p.lot } })
            AkaShopClient.send("depotSet", { key = k, uid = r.uid, field = "qty",
                                             value = qty })
            return
        end
    end

    local p = self:payState()
    AkaShopClient.send("depotAdd", {
        key = self.key, ft = ft,
        price   = AkaShopUI.num(self.ePrice, 0),
        qty     = qty,
        minutes = AkaShopUI.num(self.eMin, 0),
        colour  = self.colour,
        pay     = { ft = p.ft, n = p.n, lot = p.lot },
    })
end

function AkaShopDepotUI:onDel()
    local row = self.pick and self:rowOf(self.pick)
    if not row then return AkaShopClient.notify("Pick a card first.", true) end
    AkaShopClient.send("depotDel", { key = self.key, uid = row.uid })
end

function AkaShopDepotUI:onLink()
    local choices = {}
    for _, g in ipairs((self.snap or {}).groups or {}) do
        if g.gid ~= self.snap.group then table.insert(choices, g) end
    end
    if #choices == 0 then
        return AkaShopClient.notify("There is no other depot to link to.", true)
    end
    AkaShopDepotPick.open(choices, self.key)
end

function AkaShopDepotUI:onUnlink()
    AkaShopClient.send("depotUnlink", { key = self.key })
end

function AkaShopDepotUI:onRename()
    local snap = self.snap or {}
    AkaShopUI.askNames("Rename depot", snap.name, snap.nameTH, function(en, th)
        AkaShopClient.send("depotRename", { key = self.key, name = en, nameTH = th })
    end)
end

function AkaShopDepotUI:onDelete()
    AkaShopUI.confirm("Delete this depot? The tile stays, the deal goes.", self,
        function(s) AkaShopClient.send("depotRemove", { key = s.key }) end)
end

--========================================================== item picker =====
--[[ A dropdown with pictures, because "Base.GardenSaw" is not something anyone
     should have to remember, and a plain text list of four thousand item ids is
     no better. Icon, display name, and the id in grey behind it, filtered as
     you type. The list is built once and cached: walking the whole script
     manager takes a moment and doing it on every open would be felt. ]]

AkaShopItemPicker = ISCollapsableWindow:derive("AkaShopItemPicker")
AkaShopItemPicker.cache = nil

local function allItems()
    if AkaShopItemPicker.cache then return AkaShopItemPicker.cache end
    local out = {}

    -- Packs first, always, filter or no filter. The whole reason they exist is
    -- that an admin looking for "ring" should find ONE row that means every
    -- ring, before the fourteen rows that each mean one finger.
    local packs = AkaShopPacks.list()
    for _, pk in ipairs(packs) do
        table.insert(out, {
            ft = AkaShopPacks.key(pk.id),
            name = pk.name,
            pack = pk.id,
            note = pk.n .. " items",
        })
    end

    -- Nothing to offer. Say so IN THE LIST rather than showing a list with no
    -- packs in it, because those two look identical and the second one sends
    -- the admin scrolling four thousand rows hunting for a feature that is not
    -- there. `dead` rows draw greyed and refuse to be picked.
    if #packs == 0 then
        table.insert(out, {
            ft   = "",
            name = "(no jewelry packs on this server)",
            dead = true,
            note = "see console.txt: [Traka] item packs",
        })
    end

    local items = {}
    pcall(function()
        local list = getScriptManager():getAllItems()
        for i = 0, list:size() - 1 do
            local it = list:get(i)
            local ft = it:getFullName()
            if ft and ft ~= "" and not it:isHidden() then
                table.insert(items, { ft = ft, name = it:getDisplayName() or ft, note = ft })
            end
        end
    end)
    table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, e in ipairs(items) do table.insert(out, e) end

    AkaShopItemPicker.cache = out
    return out
end

function AkaShopItemPicker.open(owner)
    local w, h = 460, 520
    local o = AkaShopItemPicker:new((getCore():getScreenWidth() - w) / 2,
                                    (getCore():getScreenHeight() - h) / 2, w, h)
    o.owner = owner
    o:initialise(); o:addToUIManager()
    return o
end

function AkaShopItemPicker:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    AkaShopUI.skin(o)
    o.title = "Pick an item"
    o:setResizable(false)
    return o
end

function AkaShopItemPicker:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()

    AkaShopUI.label(self, 12, th + 8, "Type to filter", AkaShopUI.C.dim)

    -- The filter box no longer runs the full width. A pack sits at the top of
    -- a four-thousand-row list, which is the right place for it and also the
    -- easiest place in the world to scroll straight past - so there is now a
    -- button that throws every ordinary item away and leaves only the packs.
    local bw = 92
    self.eFind = AkaShopUI.entry(self, 12, th + 30,
                                 self:getWidth() - 24 - bw - 6, 26, "")
    self.btnPacks = AkaShopUI.button(self, self:getWidth() - 12 - bw, th + 30,
                                     bw, 26, "Packs",
                                     self, AkaShopItemPicker.onPacks, "PickPacks")

    self.lb = AkaShopUI.list(self, 12, th + 64, self:getWidth() - 24,
                             self:getHeight() - th - 110,
                             AkaShopItemPicker.drawRow, self)
    self.lb.itemheight = 30
    -- Double-click a row to take it. This is a convenience, NOT the only way in:
    -- the Select button below is what makes the window usable at all.
    self.lb.ondblclick = AkaShopItemPicker.onListDouble
    self.lb.target     = self

    local w  = self:getWidth()
    local by = self:getHeight() - 38
    AkaShopUI.button(self, 12, by, 132, 28, "Use my held item",
                     self, AkaShopItemPicker.onHeld, "PickHeld")
    AkaShopUI.button(self, w - 250, by, 110, 28, "Select",
                     self, AkaShopItemPicker.onPick, "PickYes")
    AkaShopUI.button(self, w - 132, by, 120, 28, "Cancel",
                     self, AkaShopItemPicker.onCancel, "PickNo")
    self:fill("")
end

--- Hand the highlighted row back to the depot window.
---
--- There used to be no button here at all - selection relied on the window's
--- own onMouseDown, which never fires, because the list box is a CHILD and
--- swallows the click before the window ever sees it. The result was a picker
--- you could scroll and filter but never actually pick anything from.
function AkaShopItemPicker:onPick()
    local e = AkaShopUI.selected(self.lb)
    if not e then
        return AkaShopClient.notify("Click an item in the list first.", true)
    end
    if e.dead then
        return AkaShopClient.notify("That row is a message, not an item.", true)
    end
    if self.owner then self.owner:setItem(e.ft, e.name) end
    self:onCancel()
end

function AkaShopItemPicker.onListDouble(target, item)
    local win = target
    if not win or not item or item.dead then return end
    if win.owner then win.owner:setItem(item.ft, item.name) end
    win:onCancel()
end

--- Show only the packs, or go back to everything.
function AkaShopItemPicker:onPacks()
    self.packsOnly = not self.packsOnly
    if self.btnPacks then
        self.btnPacks:setTitle(self.packsOnly and "All items" or "Packs")
    end
    -- Clearing the remembered filter is what makes prerender rebuild the list;
    -- calling fill() directly here as well would just do the work twice.
    self.lastFilter = nil
end

function AkaShopItemPicker:fill(filter)
    filter = string.lower(filter or "")
    self.lb:clear()
    local n = 0
    for _, e in ipairs(allItems()) do
        -- Packs ignore the 300-row cap and are never filtered out by an empty
        -- box. There are five of them; losing the one row that means "every
        -- ring" behind a truncated list of individual rings would defeat the
        -- feature at the exact moment it is most wanted. The "no packs here"
        -- notice is pinned the same way, for the same reason.
        local pinned = (e.pack or e.dead) and true or false
        local hit
        if self.packsOnly then
            hit = pinned
        else
            hit = (filter == "")
               or string.find(string.lower(e.name), filter, 1, true)
               or string.find(string.lower(e.ft), filter, 1, true)
        end
        if hit and (pinned or n < 300) then
            self.lb:addItem(e.name, e)
            if not pinned then n = n + 1 end
        end
    end
end

function AkaShopItemPicker:drawRow(y, item, alt)
    local e  = item.item
    local th, C = AkaShopUI.THEME, AkaShopUI.C
    local h  = 30
    local w  = self:getWidth()

    if self.selected == item.index then
        self:drawRect(0, y, w, h - 1, th.rowSel.a, th.rowSel.r, th.rowSel.g, th.rowSel.b)
    elseif alt then
        self:drawRect(0, y, w, h - 1, th.rowAlt.a, th.rowAlt.r, th.rowAlt.g, th.rowAlt.b)
    end

    local icon = e.pack and AkaShopPacks.iconFt(e.pack) or e.ft
    AkaShopUI.drawItemIcon(self, icon, 5, y + 4, 22, 22)

    local nx = 34
    if e.pack then
        local pw = getTextManager():MeasureStringX(UIFont.Small, "PACK") + 10
        self:drawRect(nx, y + 6, pw, 16, 1, 0.306, 0.498, 0.682)
        self:drawText("PACK", nx + 5, y + 6, 0.03, 0.07, 0.10, 1, UIFont.Small)
        nx = nx + pw + 8
    end
    local col = e.dead and C.dim or C.text
    self:drawText(e.name, nx, y + 5, col[1], col[2], col[3], 1, AkaShopUI.FONT)

    local note = e.note or e.ft
    local idw = getTextManager():MeasureStringX(UIFont.Small, note)
    self:drawText(note, w - idw - 8, y + 7, C.dim[1], C.dim[2], C.dim[3], 1, UIFont.Small)
    return y + h
end

function AkaShopItemPicker:prerender()
    ISCollapsableWindow.prerender(self)
    local txt = self.eFind and self.eFind:getInternalText() or ""
    if txt ~= self.lastFilter then
        self.lastFilter = txt
        self:fill(txt)
    end
end

-- NOTE: there is deliberately no onMouseDown override here. Clicks inside the
-- list box never reach the window, so an override would be dead code that
-- looks like it works. Selection goes through the Select button or a
-- double-click, both of which read the list box directly.

function AkaShopItemPicker:onHeld()
    local stock = AkaShopUI.playerStock() or {}
    if #stock == 0 then
        return AkaShopClient.notify("You are not carrying anything sellable.", true)
    end
    if self.owner then
        self.owner:setItem(stock[1].ft, AkaShop.displayNameOf(stock[1].ft))
    end
    self:onCancel()
end

function AkaShopItemPicker:onCancel()
    self:setVisible(false); self:removeFromUIManager()
end

--============================================================ pay dialog ====
--[[ What one offer pays with.

     A rate is three facts that only mean anything together - the item, how many
     of it, and how many of the WANTED item buy that. Twenty handfuls of grass
     for one tin of dog food is not "a price of 0.05 dog food"; it is a lot of
     twenty and a payout of one, and typing it any other way invites the admin
     to write something the game cannot pay out in whole items.

     So the three live in one small window with the sentence spelled out at the
     bottom in the exact words the card will use. An admin should never have to
     open the depot board to find out what they just wrote. ]]

AkaShopPayDialog = ISCollapsableWindow:derive("AkaShopPayDialog")

function AkaShopPayDialog.open(owner, pay)
    local w, h = 400, 250
    local o = AkaShopPayDialog:new((getCore():getScreenWidth() - w) / 2,
                                   (getCore():getScreenHeight() - h) / 2, w, h)
    o.owner = owner
    o.payFt = pay and pay.ft or nil
    o.startN   = pay and pay.n or 1
    o.startLot = pay and pay.lot or 1
    o:initialise(); o:addToUIManager()
    return o
end

function AkaShopPayDialog:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    AkaShopUI.skin(o)
    o.title = "What does this offer pay?"
    o:setResizable(false)
    return o
end

function AkaShopPayDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local w  = self:getWidth()
    local y  = th + 10

    AkaShopUI.label(self, 12, y, "Pay with this item", AkaShopUI.C.dim); y = y + 20
    self.btnItem = AkaShopUI.button(self, 12, y, w - 24, 26,
                                    self.payFt and AkaShop.displayNameOf(self.payFt)
                                    or "pick an item...",
                                    self, AkaShopPayDialog.onPick, "PayItem")
    y = y + 34

    local halfw = (w - 32) / 2
    AkaShopUI.label(self, 12, y, "Give this many", AkaShopUI.C.dim)
    AkaShopUI.label(self, 20 + halfw, y, "for every this many", AkaShopUI.C.dim)
    y = y + 20
    self.eN   = AkaShopUI.entry(self, 12, y, halfw, 24, tostring(self.startN or 1), true)
    self.eLot = AkaShopUI.entry(self, 20 + halfw, y, halfw, 24,
                                tostring(self.startLot or 1), true)
    y = y + 32

    self.lblPreview = AkaShopUI.label(self, 12, y, "", AkaShopUI.C.money)
    y = y + 30

    AkaShopUI.button(self, 12, y, halfw, 26, "Pay money instead",
                     self, AkaShopPayDialog.onMoney, "PayMoney")
    y = y + 34

    AkaShopUI.button(self, 12, y, halfw, 26, "OK", self, AkaShopPayDialog.onOK, "PayOK")
    AkaShopUI.button(self, 20 + halfw, y, halfw, 26, "Cancel",
                     self, AkaShopPayDialog.onCancel, "PayNo")
end

--- The item picker calls this on whoever opened it.
function AkaShopPayDialog:setItem(ft, name)
    if AkaShopPacks.idOf(ft) then
        return AkaShopClient.notify(
            "A pack cannot be the payment - the depot has to hand over one " ..
            "definite item.", true)
    end
    self.payFt = ft
    if self.btnItem then self.btnItem:setTitle(name or ft) end
end

function AkaShopPayDialog:onPick() AkaShopItemPicker.open(self) end

function AkaShopPayDialog:onMoney()
    if self.owner then self.owner:setPay(nil, 1, 1) end
    self:onCancel()
end

function AkaShopPayDialog:onOK()
    if not self.payFt then
        return AkaShopClient.notify("Pick the item this offer pays with, or " ..
                                    "choose Pay money instead.", true)
    end
    local n   = math.max(1, AkaShopUI.num(self.eN, 1))
    local lot = math.max(1, AkaShopUI.num(self.eLot, 1))
    if self.owner then self.owner:setPay(self.payFt, n, lot) end
    self:onCancel()
end

function AkaShopPayDialog:prerender()
    ISCollapsableWindow.prerender(self)
    if not self.lblPreview then return end
    if not self.payFt then
        self.lblPreview:setName("pays money")
        return
    end
    self.lblPreview:setName(AkaShop.rateText(
        math.max(1, AkaShopUI.num(self.eLot, 1)),
        math.max(1, AkaShopUI.num(self.eN, 1)),
        AkaShop.displayNameOf(self.payFt)))
end

function AkaShopPayDialog:onCancel()
    self:setVisible(false); self:removeFromUIManager()
end

--=========================================================== link picker ====

AkaShopDepotPick = ISCollapsableWindow:derive("AkaShopDepotPick")

function AkaShopDepotPick.open(choices, key)
    local w, h = 400, 300
    local o = AkaShopDepotPick:new((getCore():getScreenWidth() - w) / 2,
                                   (getCore():getScreenHeight() - h) / 2, w, h)
    o.choices, o.key = choices, key
    o:initialise(); o:addToUIManager()
    return o
end

function AkaShopDepotPick:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    AkaShopUI.skin(o)
    o.title = "Link to which depot?"
    o:setResizable(false)
    return o
end

function AkaShopDepotPick:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    self.lb = AkaShopUI.list(self, 12, th + 8, self:getWidth() - 24,
                             self:getHeight() - th - 56, nil, self)
    self.lb.itemheight = 28
    for _, g in ipairs(self.choices or {}) do
        self.lb:addItem(AkaShop.shopName(g) .. "   (" .. g.n .. " point(s), " ..
                        g.rows .. " item(s))", g)
    end
    AkaShopUI.button(self, 12, self:getHeight() - 38, 170, 28, "Link", self,
                     AkaShopDepotPick.onOk, "DepotPickOk")
    AkaShopUI.button(self, self:getWidth() - 182, self:getHeight() - 38, 170, 28,
                     "Cancel", self, AkaShopDepotPick.onCancel, "DepotPickNo")
end

function AkaShopDepotPick:onOk()
    local g = AkaShopUI.selected(self.lb)
    if g then AkaShopClient.send("depotLink", { key = self.key, other = g.key }) end
    self:onCancel()
end

function AkaShopDepotPick:onCancel()
    self:setVisible(false); self:removeFromUIManager()
end
