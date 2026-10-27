--[[===========================================================================
    AkaShop - customer window. Browse a shop, fill a cart, apply a code, pay.
============================================================================]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"

AkaShopBuyUI = ISCollapsableWindow:derive("AkaShopBuyUI")
AkaShopBuyUI.instance = nil

-- Colours live in AkaShop_UICommon.lua, which may load after this file, so the
-- palette is resolved on first use rather than captured at load time.
local C
local function col(name)
    if not C then C = AkaShopUI.C end
    return C[name]
end

local W, H = 1000, 640
local ROWH   = 26      -- tall enough for an item icon
local LISTW  = 566     -- goods list width; the stepper hangs off its right

-- x offsets inside the goods row, measured from the right edge. The stepper
-- hit test in onGoodsMouseDown reads the same numbers, so a layout change can
-- never leave the buttons pointing at the wrong pixels.
local GX = { minus = 96, count = 74, plus = 34, stock = 128, price = 186, cond = 300 }

local function drawGoodsRow(lb, y, item, alt)
    local d, w = item.item, lb:getWidth()
    local h = ROWH

    if alt then lb:drawRect(0, y, w, h, 0.05, 1, 1, 1) end
    if lb.selected == item.index then
        local c = AkaShopUI.THEME.rowSel
        lb:drawRect(0, y, w, h, c.a, c.r, c.g, c.b)
    end

    AkaShopUI.drawItemIcon(lb, d.ft, 4, y + 3, 20, 20, true)

    local out = (d.qty or 0) <= 0
    local nc  = out and col("dim") or col("text")
    lb:drawText(d.name, 30, y + 5, nc[1], nc[2], nc[3], 1, AkaShopUI.FONT)

    -- state of the goods on offer: wear bar, plus tags for anything the item
    -- carries that a buyer would want to know before paying
    local rows = d.rows or {}
    local r1 = rows[1]
    if r1 then
        local tags = {}
        if r1.frozen then table.insert(tags, "frozen") end
        if r1.cooked then table.insert(tags, "cooked") end
        if #tags > 0 then
            local tc = r1.frozen and { 0.62, 0.82, 0.95 } or { 0.90, 0.76, 0.52 }
            lb:drawText(table.concat(tags, " "), 30 + 118, y + 5,
                        tc[1], tc[2], tc[3], 1, AkaShopUI.FONT)
        end
    end
    if r1 and (r1.wear or 0) > 0.001 then
        local frac = 1 - r1.wear
        local cc = AkaShopUI.wearColour(r1.wear)
        AkaShopUI.bar(lb, w - GX.cond, y + 10, 44, 6, frac, cc)
        lb:drawText(tostring(math.floor(frac * 100 + 0.5)) .. "%", w - GX.cond + 50,
                    y + 5, cc[1], cc[2], cc[3], 1, AkaShopUI.FONT)
    elseif r1 then
        local c2 = col("good")
        lb:drawText("100%", w - GX.cond, y + 5, c2[1], c2[2], c2[3], 1, AkaShopUI.FONT)
    end

    local unit = (r1 and r1.unit) or d.price or 0
    local mc = out and col("dim") or col("money")
    lb:drawText(AkaShop.money(unit), w - GX.price, y + 5, mc[1], mc[2], mc[3], 1, AkaShopUI.FONT)

    local sc = out and col("bad") or col("good")
    lb:drawText(out and (d.outToday and "sold out" or "-") or tostring(d.qty),
                w - GX.stock, y + 5, sc[1], sc[2], sc[3], 1, AkaShopUI.FONT)

    -- the - n + stepper, drawn rather than built from real buttons: a
    -- ScrollingListBox cannot host child widgets per row
    local ui   = lb.parentUI
    local want = (ui and ui:cartQty(d.uid)) or 0
    local canM, canP = want > 0, want < (d.qty or 0)
    local function key(x, on, glyph)
        lb:drawRect(w - x, y + 3, 20, 20, 0.9, 0.165, 0.180, 0.196)
        lb:drawRectBorder(w - x, y + 3, 20, 20, 0.6, 0.28, 0.30, 0.32)
        local c3 = on and col("text") or col("dim")
        lb:drawText(glyph, w - x + 7, y + 4, c3[1], c3[2], c3[3], 1, AkaShopUI.FONT)
    end
    key(GX.minus, canM, "-")
    key(GX.plus,  canP, "+")
    local qc = want > 0 and col("money") or col("dim")
    lb:drawText(tostring(want), w - GX.count + 6, y + 5, qc[1], qc[2], qc[3], 1, AkaShopUI.FONT)

    lb:drawRect(0, y + h - 1, w, 1, 0.28, 0.45, 0.47, 0.49)
    return y + h
end

local function drawCartRow(lb, y, item, alt)
    local d = item.item
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.name .. "  x" .. d.qty, x = 6 },
        { text = AkaShop.money(d.cost or (d.price * d.qty)), x = lb:getWidth() - 90,
          c = col("money") },
    })
end

--- One of this customer's waiting orders. The countdown is the point of the
--- row: an order that expires quietly, with the goods going back on sale and
--- nobody told why, is the kind of thing players call a bug.
local function drawOrderRow(lb, y, item, alt)
    local d = item.item
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = "#" .. d.id .. "  " .. tostring(d.what), x = 6 },
        { text = AkaShop.money(d.total), x = lb:getWidth() - 170, c = col("money") },
        -- durationText says "ready" at zero, which reads as nonsense on a
        -- countdown ("ready left"). At zero this order is about to be swept.
        { text = (d.left or 0) > 0
                 and (AkaShop.durationText(d.left) .. " left") or "expiring",
          x = lb:getWidth() - 90, c = col("dim") },
    })
end

--=================================================================== build ==

function AkaShopBuyUI:new(x, y)
    local o = ISCollapsableWindow:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.title = "Traka"
    o.resizable = false
    AkaShopUI.skin(o)
    o.cart = {}
    o.codePercent = 0
    o.codeText = ""
    o.snap = nil
    o.shopKey = nil
    return o
end

function AkaShopBuyUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- header band: shop name centred, one meta line under it
    self.lblShop  = AkaShopUI.label(self, 0, 28, "", col("title"))
    self.lblOwner = AkaShopUI.label(self, 0, 48, "", col("dim"))
    self.lblMode  = AkaShopUI.label(self, 12, 28, "", col("money"))
    self.lblOpen  = AkaShopUI.label(self, W - 90, 28, "", col("good"))

    -- goods
    AkaShopUI.label(self, 12, 78, "ITEM", col("dim"))
    self.lblHdrCond  = AkaShopUI.label(self, LISTW - 292, 78, "CONDITION", col("dim"))
    self.lblHdrPrice = AkaShopUI.label(self, LISTW - 186, 78, "PRICE", col("dim"))
    self.lblHdrStock = AkaShopUI.label(self, LISTW - 132, 78, "LEFT", col("dim"))
    self.lblHdrQty   = AkaShopUI.label(self, LISTW - 96, 78, "QTY", col("dim"))

    self.goodsList = AkaShopUI.list(self, 10, 96, LISTW, 386, drawGoodsRow, self)
    self.goodsList.itemheight = ROWH
    self.goodsList.parentUI   = self
    -- inline +/- : a list box cannot hold child widgets, so the row draws the
    -- keys and the hit test lives here, reading the same GX offsets
    self.goodsList.onMouseDown = function(lb, x, y)
        return self:onGoodsMouseDown(lb, x, y)
    end

    -- right column
    local RX = LISTW + 22
    AkaShopUI.label(self, RX, 78, "CART", col("dim"))
    self.cartList = AkaShopUI.list(self, RX, 96, W - RX - 12, 150, drawCartRow, self)
    AkaShopUI.button(self, RX, 252, 138, 22, "Remove", self, self.onRemoveFromCart)
    AkaShopUI.button(self, RX + 144, 252, 138, 22, "Empty", self, self.onClearCart)

    AkaShopUI.label(self, RX, 286, "DISCOUNT CODE", col("dim"))
    self.eCode = AkaShopUI.entry(self, RX, 304, 160, 22, "", false)
    AkaShopUI.button(self, RX + 168, 304, 114, 22, "Apply", self, self.onApplyCode)

    self.lblSubK  = AkaShopUI.label(self, RX, 344, "Subtotal", col("dim"))
    self.lblSub   = AkaShopUI.label(self, RX, 342, "", col("text"))
    self.lblDisc  = AkaShopUI.label(self, RX, 368, "", col("good"))
    self.lblTotK  = AkaShopUI.label(self, RX, 400, "TOTAL DUE", col("dim"))
    self.lblTotal = AkaShopUI.label(self, RX, 416, "", col("money"))
    self.lblAfter = AkaShopUI.label(self, RX, 446, "", col("dim"))

    self.btnBuy = AkaShopUI.button(self, RX, 472, W - RX - 12, 30, "Buy", self, self.onBuy)

    -- Waiting orders. Only ever this player's own - the shop keeper's Orders
    -- tab is where the whole queue lives, and who else is buying what is not
    -- a customer's business.
    self.lblMine = AkaShopUI.label(self, RX, 506, "", col("dim"))
    self.mineList = AkaShopUI.list(self, RX, 522, W - RX - 12, 54,
                                   drawOrderRow, self)
    -- Stops at 602. The Close button starts at 606; two pixels of overlap is
    -- still a button you cannot press.
    self.btnDrop = AkaShopUI.button(self, RX, 580, W - RX - 12, 22,
                                    "Cancel selected order", self, self.onDropOrder)

    self.lblFoot = AkaShopUI.label(self, 12, H - 30, "", col("dim"))
    AkaShopUI.button(self, W - 110, H - 34, 100, 24, "Close", self, self.close)
end

function AkaShopBuyUI:onDropOrder()
    local o = AkaShopUI.selected(self.mineList)
    if not o then return AkaShopClient.notify("Pick one of your orders first.", true) end
    AkaShopUI.confirm("Cancel order #" .. o.id .. "? The goods go back on sale.",
        self, function(me)
            AkaShopClient.send("orderCancel", { key = me.shopKey, id = o.id })
        end)
end

--- Which stepper key (if any) is under the cursor. Mirrors drawGoodsRow.
function AkaShopBuyUI:onGoodsMouseDown(lb, x, y)
    local idx
    if type(lb.rowAt) == "function" then
        idx = lb:rowAt(x, y)
    else
        idx = math.floor((y - (lb:getYScroll() or 0)) / ROWH) + 1
    end
    local it = lb.items and lb.items[idx]
    if not it then return end
    lb.selected = idx
    local d, w = it.item, lb:getWidth()
    if x >= w - GX.minus and x <= w - GX.minus + 20 then
        self:bump(d, -1)
    elseif x >= w - GX.plus and x <= w - GX.plus + 20 then
        self:bump(d, 1)
    end
end

--- Move a listing's cart quantity by `delta`, clamped to what is in stock.
function AkaShopBuyUI:bump(d, delta)
    if not d then return end
    local c, idx = self:cartEntry(d.uid)
    local want = (c and c.qty or 0) + delta
    if want < 0 then want = 0 end
    if want > (d.qty or 0) then
        want = d.qty or 0
        if delta > 0 then
            AkaShopClient.notify("Only " .. tostring(d.qty) .. " left.", true)
        end
    end
    if want <= 0 then
        if idx then table.remove(self.cart, idx) end
    elseif c then
        c.qty = want
    else
        table.insert(self.cart, { uid = d.uid, name = d.name, price = d.price, qty = want })
    end
    self:refreshCart()
end

function AkaShopBuyUI:cartQty(uid)
    local c = self:cartEntry(uid)
    return c and c.qty or 0
end

--================================================================= helpers ==

function AkaShopBuyUI:findListing(uid)
    for _, e in ipairs((self.snap and self.snap.items) or {}) do
        if e.uid == uid then return e end
    end
    return nil
end

function AkaShopBuyUI:cartEntry(uid)
    for i = 1, #self.cart do
        if self.cart[i].uid == uid then return self.cart[i], i end
    end
    return nil, nil
end

--- Cost of `qty` units of a listing, priced exactly the way the server will:
--- worst/cheapest rows first, each at its own discounted unit price.
function AkaShopBuyUI:lineCost(uid, qty)
    local live = self:findListing(uid)
    if not live then return 0 end
    if live.rows and #live.rows > 0 then
        return (AkaShopStock.quoteRows(live.rows, qty))
    end
    return (live.price or 0) * qty          -- listing with no row data
end

function AkaShopBuyUI:recalc()
    local subtotal = 0
    for i = 1, #self.cart do
        local c = self.cart[i]
        c.cost   = self:lineCost(c.uid, c.qty)
        subtotal = subtotal + c.cost
    end
    local discount = math.floor(subtotal * (self.codePercent or 0) / 100)
    local total = subtotal - discount
    if total < 0 then total = 0 end

    local cur = (self.snap and self.snap.currency) or ""
    local wallet = AkaShopUI.walletOf()

    self.lblSubK:setName("Subtotal")
    self.lblSub:setName(AkaShop.money(subtotal))
    self.lblSub:setX(self.lblSubK:getX() + 210 - 0)
    if self.codePercent > 0 then
        self.lblDisc:setName(self.codeText .. "  -" .. self.codePercent ..
                             "%      -" .. AkaShop.money(discount))
    else
        self.lblDisc:setName("")
    end
    self.lblTotK:setName("TOTAL DUE")
    self.lblTotal:setName(AkaShop.money(total) .. "  " .. cur)
    self.lblAfter:setName(total > 0
        and ("You carry " .. AkaShop.money(wallet) .. ", left after: " ..
             AkaShop.money(math.max(0, wallet - total)))
        or  ("You carry " .. AkaShop.money(wallet)))
    -- Outside self-service hours the same cart becomes an ORDER. The button
    -- changes verb rather than greying out, because "closed, go away" was the
    -- old behaviour and it left the customer nothing to do.
    local ordering = ((self.snap or {}).canBuyNow == false)
    if ordering then
        self.btnBuy:setTitle(total > 0
            and ("Place order - " .. AkaShop.money(total) .. " " .. cur .. " on collection")
            or  "Place order")
        -- No wallet check: they pay at the counter, and refusing an order
        -- because they are short right now would stop somebody who fully
        -- intends to go and earn it before the shop keeper shows up.
        self.btnBuy:setEnable(#self.cart > 0)
    else
        self.btnBuy:setTitle(total > 0 and ("Buy - pay " .. AkaShop.money(total) .. " " .. cur)
                                        or "Buy")
        self.btnBuy:setEnable(#self.cart > 0 and wallet >= total)
    end
    self.total = total
end

function AkaShopBuyUI:refreshCart()
    local sel = self.cartList.selected
    self.cartList:clear()
    for _, c in ipairs(self.cart) do
        self.cartList:addItem(c.name, c)
    end
    self.cartList.selected = sel
    self:recalc()
end

--================================================================ refresh ===

function AkaShopBuyUI:refresh(snap)
    self.snap = snap
    self.shopKey = snap.key
    self.title = "Traka - " .. AkaShop.shopName(snap)

    self.lblShop:setName(AkaShop.shopBoth(snap))
    self.lblOwner:setName("Owner " .. tostring(snap.owner) ..
                          "   -   prices in " .. (snap.currency or "?"))
    AkaShopUI.centre(self.lblShop, W)
    AkaShopUI.centre(self.lblOwner, W)
    self.lblMode:setName(snap.modeLabel or "ONLINE")
    self.lblOpen:setName(snap.enabled and "OPEN" or "CLOSED")
    self.lblOpen.r, self.lblOpen.g, self.lblOpen.b =
        (snap.enabled and col("good") or col("bad"))[1],
        (snap.enabled and col("good") or col("bad"))[2],
        (snap.enabled and col("good") or col("bad"))[3]
    if snap.canBuyNow == false then
        self.lblFoot:setName("Self-service is open " .. (snap.hoursText or "") ..
            " - right now you can place an order and collect it from " ..
            tostring(snap.owner) .. " at this counter. No sales tax on orders.")
    else
        self.lblFoot:setName("Self-service open " .. (snap.hoursText or "") ..
                             ".   Sold-out lines disappear at the end of the day.")
    end

    local mine = snap.myOrders or {}
    local selO = AkaShopUI.selected(self.mineList)
    self.mineList:clear()
    for _, o in ipairs(mine) do self.mineList:addItem("#" .. o.id, o) end
    if selO then
        for i, row in ipairs(self.mineList.items or {}) do
            if row.item and row.item.id == selO.id then self.mineList.selected = i end
        end
    end
    self.lblMine:setName(#mine > 0
        and ("Your waiting orders (" .. #mine .. ") - collect from " ..
             tostring(snap.owner) .. " here")
        or  "")
    self.mineList:setVisible(#mine > 0)
    self.btnDrop:setVisible(#mine > 0)

    local selUid = nil
    local s = AkaShopUI.selected(self.goodsList)
    if s then selUid = s.uid end
    self.goodsList:clear()
    for i, e in ipairs(snap.items or {}) do
        self.goodsList:addItem(e.name, e)
        if selUid and e.uid == selUid then self.goodsList.selected = i end
    end

    -- drop cart lines that no longer exist / clamp to live stock
    for i = #self.cart, 1, -1 do
        local live = self:findListing(self.cart[i].uid)
        if not live then
            table.remove(self.cart, i)
        else
            self.cart[i].price = live.price
            if self.cart[i].qty > live.qty then self.cart[i].qty = live.qty end
            self.cart[i].cost = self:lineCost(live.uid, self.cart[i].qty)
            if self.cart[i].qty < 1 then table.remove(self.cart, i) end
        end
    end
    self:refreshCart()
end

--================================================================ actions ===

--- The +/- keys in each row replaced the old quantity box and Add button.
--- Kept only so an older keybind or call site cannot crash: it adds one of
--- whatever is selected.
function AkaShopBuyUI:onAddToCart()
    local pick = AkaShopUI.selected(self.goodsList)
    if not pick then return AkaShopClient.notify("Pick an item first.", true) end
    self:bump(pick, 1)
end

function AkaShopBuyUI:onRemoveFromCart()
    local c = AkaShopUI.selected(self.cartList)
    if not c then return AkaShopClient.notify("Pick a cart line.", true) end
    local _, idx = self:cartEntry(c.uid)
    if idx then table.remove(self.cart, idx) end
    self.cartList.selected = 0
    self:refreshCart()
end

function AkaShopBuyUI:onClearCart()
    self.cart = {}
    self.cartList.selected = 0
    self:refreshCart()
end

function AkaShopBuyUI:onApplyCode()
    local code = AkaShop.normCode(self.eCode:getInternalText())
    if code == "" then
        self.codePercent, self.codeText = 0, ""
        return self:recalc()
    end
    AkaShopClient.send("checkCode", { key = self.shopKey, code = code })
end

function AkaShopBuyUI:setCode(code, percent, ok, msg)
    if ok then
        self.codeText = code
        self.codePercent = percent or 0
    else
        self.codeText = ""
        self.codePercent = 0
    end
    AkaShopClient.notify(msg, not ok)
    self:recalc()
end

function AkaShopBuyUI:onBuy()
    if #self.cart == 0 then return AkaShopClient.notify("Your cart is empty.", true) end
    local cart = {}
    for _, c in ipairs(self.cart) do
        table.insert(cart, { uid = c.uid, qty = c.qty })
    end
    -- `expect` is the total this window is showing. If the owner changed a
    -- price while the customer was browsing, the server refuses the sale and
    -- says so rather than silently charging a different amount. The cart is
    -- emptied by the "charge" handler, i.e. only once the money really left.
    local payload = {
        key    = self.shopKey,
        cart   = cart,
        code   = (self.codePercent > 0) and self.codeText or "",
        expect = math.floor(self.total or 0),
    }

    if (self.snap or {}).canBuyNow == false then
        AkaShopClient.send("order", payload)
        -- An order takes nothing from the player right now, so there is no
        -- "charge" round trip to clear the cart afterwards. Clear it here.
        self.cart = {}
        self:refreshCart()
        return
    end
    AkaShopClient.send("buy", payload)
end

--=================================================================== open ===

function AkaShopBuyUI:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if AkaShopBuyUI.instance == self then AkaShopBuyUI.instance = nil end
end

function AkaShopBuyUI.openWith(snap)
    local ui = AkaShopBuyUI.instance
    if not ui then
        local x = math.max(20, (getCore():getScreenWidth() - W) / 2)
        local y = math.max(20, (getCore():getScreenHeight() - H) / 2)
        ui = AkaShopBuyUI:new(x, y)
        ui:initialise()
        ui:addToUIManager()
        AkaShopBuyUI.instance = ui
    end
    if ui.shopKey ~= snap.key then
        ui.cart = {}
        ui.codePercent = 0
        ui.codeText = ""
        ui.eCode:setText("")
    end
    ui:setVisible(true)
    ui:bringToTop()
    ui:refresh(snap)
    return ui
end
