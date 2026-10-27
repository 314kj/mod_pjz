--[[===========================================================================
    AkaShop - shop management window (owner / staff / admin).
    Tabs: Items | Codes | Staff | Sales | Settings
============================================================================]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"

AkaShopManageUI = ISCollapsableWindow:derive("AkaShopManageUI")
AkaShopManageUI.instance = nil

-- Colours live in AkaShop_UICommon.lua, which may load after this file, so the
-- palette is resolved on first use rather than captured at load time.
local C
local function col(name)
    if not C then C = AkaShopUI.C end
    return C[name]
end

local W, H = 1020, 680
local LIST_Y, LIST_H = 156, 280
local ROW1, ROW2 = 444, 472

--================================================================ helpers ===

local function drawInvRow(lb, y, item, alt)
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = item.item.name, x = 6 },
        { text = "x" .. item.item.count, x = lb:getWidth() - 58, c = col("good") },
    })
end

local function drawSaleRow(lb, y, item, alt)
    local d = item.item
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.name, x = 6 },
        { text = "sold " .. (d.sold or 0), x = lb:getWidth() - 214, c = col("dim") },
        { text = AkaShop.money(d.price), x = lb:getWidth() - 146, c = col("money") },
        { text = "x" .. d.qty, x = lb:getWidth() - 62,
          c = (d.qty > 0) and col("good") or col("bad") },
    })
end

local function drawCodeRow(lb, y, item, alt)
    local d = item.item
    local uses = (d.maxUses > 0) and (d.used .. "/" .. d.maxUses) or (d.used .. "/unlimited")
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.code, x = 6, c = col("money") },
        { text = "-" .. d.percent .. "%", x = 200, c = col("good") },
        { text = "used " .. uses, x = 300, c = col("dim") },
    })
end

local function drawStaffRow(lb, y, item, alt)
    return AkaShopUI.drawColumns(lb, y, item, alt, { { text = item.item.user, x = 6 } })
end

--- A candidate for hire. The distance is the useful column: on a server with
--- forty people online, the one you mean is almost always the one standing in
--- front of you.
local function drawOnlineRow(lb, y, item, alt)
    local d = item.item
    local far
    if (d.dist or -1) < 0 then     far = "?"
    elseif d.dist < 1000 then      far = d.dist .. " tiles"
    else                           far = string.format("%.1f km", d.dist / 1000) end
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.user or "?", x = 6, c = col("who") },
        { text = far, x = lb:getWidth() - 110,
          c = (d.dist or 9999) <= 20 and col("good") or col("dim") },
    })
end

local function drawSalesRow(lb, y, item, alt)
    local d = item.item
    local what = d.what or ""
    if #what > 46 then what = string.sub(what, 1, 44) .. ".." end
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.when or "", x = 6, c = d.today and col("good") or col("dim") },
        { text = d.buyer or "?", x = 150, c = col("who") },
        { text = what, x = 290 },
        { text = AkaShop.money(d.total) .. (d.code and ("  [" .. d.code .. "]") or ""),
          x = lb:getWidth() - 150, c = col("money") },
    })
end

--- One waiting order. "AT THE COUNTER" in green is the whole row: it is the
--- only thing that tells the shop keeper whether pressing Hand over will do
--- anything, and it is the answer to "why is this button refusing me".
local function drawOrderRow(lb, y, item, alt)
    local d = item.item
    local what = d.what or ""
    if #what > 44 then what = string.sub(what, 1, 42) .. ".." end
    local state, sc
    if d.pending then      state, sc = "handing over...", col("money")
    elseif d.here then     state, sc = "AT THE COUNTER",  col("good")
    else                   state, sc = "not here",        col("dim") end
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = "#" .. d.id, x = 6, c = col("dim") },
        { text = d.buyer or "?", x = 60, c = col("who") },
        { text = what, x = 200 },
        { text = AkaShop.money(d.total), x = lb:getWidth() - 300, c = col("money") },
        { text = (d.left or 0) > 0
                 and (AkaShop.durationText(d.left) .. " left") or "expiring",
          x = lb:getWidth() - 210, c = col("dim") },
        { text = state, x = lb:getWidth() - 130, c = sc },
    })
end

--=================================================================== build ==

function AkaShopManageUI:new(x, y)
    local o = ISCollapsableWindow:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.title = "Traka"
    o.resizable = false
    AkaShopUI.skin(o)
    o.tabWidgets = {}
    o.tab = "Items"
    o.snap = nil
    o.shopKey = nil
    return o
end

function AkaShopManageUI:reg(tab, widget)
    self.tabWidgets[tab] = self.tabWidgets[tab] or {}
    table.insert(self.tabWidgets[tab], widget)
    return widget
end

--- Panels and the shelf gauge. Drawn rather than built from widgets because
--- ISUI has no panel primitive; prerender runs before the children paint, so
--- the labels sit on top of these.
function AkaShopManageUI:prerender()
    ISCollapsableWindow.prerender(self)
    local w = self:getWidth()
    -- header band
    self:drawRect(1, 22, w - 2, 40, 0.35, 0.13, 0.14, 0.15)
    self:drawRect(1, 61, w - 2, 1, 0.5, 0.28, 0.30, 0.32)
    -- stat strip
    self:drawRect(1, 62, w - 2, 40, 0.25, 0.10, 0.11, 0.12)
    for i = 1, 3 do
        self:drawRect(10 + i * 176, 66, 1, 32, 0.35, 0.30, 0.32, 0.34)
    end
    self:drawRect(1, 101, w - 2, 1, 0.5, 0.28, 0.30, 0.32)
    if self.shelfFrac and not self.hideShelfBar then
        AkaShopUI.bar(self, 542, 92, 150, 6, self.shelfFrac,
            self.shelfFrac > 0.9 and AkaShopUI.C.bad or AkaShopUI.C.good)
    end
end

function AkaShopManageUI:onBuyCapacity()
    local snap = self.snap or {}
    local cost = snap.capPrice or 0
    AkaShopUI.confirm(string.format(
        "Expand the shelves by %d kg for %s, taken from the till?",
        snap.capStep or 10, AkaShop.money(cost)), self, function(me)
        AkaShopClient.send("buyCapacity", { key = me.shopKey })
    end)
end

function AkaShopManageUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- Header. Every label owns its own row: the previous version had the
    -- centred name and the totals line both sitting near y=45 and they drew
    -- straight through each other.
    self.lblHeader  = AkaShopUI.label(self, 0, 26, "", col("title"))   -- name, centred
    self.lblSub     = AkaShopUI.label(self, 0, 46, "", col("dim"))     -- owner / status
    self.lblMode    = AkaShopUI.label(self, 12, 26, "", col("money"))  -- left pill
    self.lblOpen    = AkaShopUI.label(self, 0, 26, "", col("good"))    -- right pill

    -- stat strip
    self.statToday = AkaShopUI.label(self, 14,  76, "", col("good"))
    self.statTill  = AkaShopUI.label(self, 190, 76, "", col("money"))
    self.statLife  = AkaShopUI.label(self, 366, 76, "", col("text"))
    self.statShelf = AkaShopUI.label(self, 542, 76, "", col("text"))
    self.statTodayK = AkaShopUI.label(self, 14,  62, "TODAY", col("dim"))
    self.statTillK  = AkaShopUI.label(self, 190, 62, "IN THE TILL", col("dim"))
    self.statLifeK  = AkaShopUI.label(self, 366, 62, "LIFETIME", col("dim"))
    self.statShelfK = AkaShopUI.label(self, 542, 62, "SHELF SPACE", col("dim"))
    self.lblShelfBar = true          -- drawn in :prerender

    -- tab bar
    local names = { "Items", "Orders", "Codes", "Staff", "Sales", "Settings" }
    self.tabButtons = {}
    local tx = 10
    for i = 1, #names do
        local n = names[i]
        local b = AkaShopUI.button(self, tx, 106, 96, 22, n, self,
            function(me) me:setTab(n) end, "tab_" .. n)
        self.tabButtons[n] = b
        tx = tx + 100
    end

    ---------------------------------------------------------------- Items --
    self:reg("Items", AkaShopUI.label(self, 12, 136, "Your inventory", col("text")))
    self.invList = self:reg("Items",
        AkaShopUI.list(self, 10, LIST_Y, 380, LIST_H, drawInvRow, self))

    self:reg("Items", AkaShopUI.label(self, 402, 136, "On sale in this shop", col("text")))
    self.saleList = self:reg("Items",
        AkaShopUI.list(self, 400, LIST_Y, 410, LIST_H, drawSaleRow, self))

    self:reg("Items", AkaShopUI.label(self, 12, ROW1 + 4, "Price", col("text")))
    self.ePrice = self:reg("Items", AkaShopUI.entry(self, 55, ROW1, 80, 22, "10", true))
    self:reg("Items", AkaShopUI.label(self, 145, ROW1 + 4, "Qty", col("text")))
    self.eQty = self:reg("Items", AkaShopUI.entry(self, 175, ROW1, 60, 22, "1", true))
    self:reg("Items", AkaShopUI.button(self, 245, ROW1, 145, 22, "Add / Restock",
        self, self.onAddStock))

    self:reg("Items", AkaShopUI.button(self, 400, ROW1, 120, 22, "Set price",
        self, self.onSetPrice))
    self:reg("Items", AkaShopUI.button(self, 526, ROW1, 130, 22, "Take back (Qty)",
        self, self.onTakeStock))
    self:reg("Items", AkaShopUI.button(self, 662, ROW1, 148, 22, "Remove listing",
        self, self.onRemoveListing))

    self:reg("Items", AkaShopUI.label(self, 12, ROW2 + 4,
        "Pick an item on the left, set Price and Qty, then Add / Restock. " ..
        "Qty can never exceed what you really carry.", col("dim")))

    ---------------------------------------------------------------- Codes --
    self:reg("Codes", AkaShopUI.label(self, 12, 136, "Discount codes", col("text")))
    self.codeList = self:reg("Codes",
        AkaShopUI.list(self, 10, LIST_Y, 560, LIST_H, drawCodeRow, self))

    self:reg("Codes", AkaShopUI.label(self, 12, ROW1 + 4, "Code", col("text")))
    self.eCode = self:reg("Codes", AkaShopUI.entry(self, 55, ROW1, 130, 22, "", false))
    self:reg("Codes", AkaShopUI.label(self, 195, ROW1 + 4, "Discount %", col("text")))
    self.eCodePct = self:reg("Codes", AkaShopUI.entry(self, 275, ROW1, 50, 22, "10", true))
    self:reg("Codes", AkaShopUI.label(self, 335, ROW1 + 4, "Max uses (0 = unlimited)", col("text")))
    self.eCodeMax = self:reg("Codes", AkaShopUI.entry(self, 490, ROW1, 50, 22, "0", true))
    self:reg("Codes", AkaShopUI.button(self, 550, ROW1, 110, 22, "Add code",
        self, self.onAddCode))
    self:reg("Codes", AkaShopUI.button(self, 670, ROW1, 140, 22, "Delete selected",
        self, self.onDelCode))

    ---------------------------------------------------------------- Staff --
    self:reg("Staff", AkaShopUI.label(self, 12, 136,
        "Staff can add stock, set prices, manage codes and read the sales log.", col("text")))
    self.staffList = self:reg("Staff",
        AkaShopUI.list(self, 10, LIST_Y, 400, LIST_H, drawStaffRow, self))

    self:reg("Staff", AkaShopUI.label(self, 430, 136, "Players online now", col("text")))
    self.onlineList = self:reg("Staff",
        AkaShopUI.list(self, 428, LIST_Y, 380, LIST_H, drawOnlineRow, self))
    self:reg("Staff", AkaShopUI.button(self, 428, ROW1, 150, 22, "Refresh list",
        self, self.onRefreshOnline))
    self:reg("Staff", AkaShopUI.button(self, 586, ROW1, 222, 22, "Hire selected player",
        self, self.onHireOnline))

    -- The typed box stays as a fallback, because somebody you want to hire is
    -- not necessarily online at the moment you decide to hire them.
    self:reg("Staff", AkaShopUI.label(self, 12, ROW1 + 4, "or type a name", col("dim")))
    self.eStaff = self:reg("Staff", AkaShopUI.entry(self, 118, ROW1, 150, 22, "", false))
    self:reg("Staff", AkaShopUI.button(self, 276, ROW1, 60, 22, "Add",
        self, self.onAddStaff))
    self:reg("Staff", AkaShopUI.button(self, 12, ROW1 + 30, 200, 22, "Remove selected staff",
        self, self.onDelStaff))
    self:reg("Staff", AkaShopUI.label(self, 12, ROW1 + 60,
        "Staff can only open the Orders tab and hand orders over. Nothing else.",
        col("dim")))

    ---------------------------------------------------------------- Sales --
    self:reg("Sales", AkaShopUI.label(self, 12, 136,
        "Newest first. Green rows happened today.", col("text")))
    self.salesList = self:reg("Sales",
        AkaShopUI.list(self, 10, LIST_Y, 800, LIST_H, drawSalesRow, self))
    self.lblSales = self:reg("Sales", AkaShopUI.label(self, 12, ROW1 + 4, "", col("money")))
    self:reg("Sales", AkaShopUI.button(self, 660, ROW1, 150, 22, "Clear history",
        self, self.onClearSales))

    ------------------------------------------------------------- Settings --
    self:reg("Settings", AkaShopUI.label(self, 12, 140, "Name (Thai)", col("text")))
    self.eNameTH = self:reg("Settings", AkaShopUI.entry(self, 118, 136, 280, 22, "", false))
    self:reg("Settings", AkaShopUI.label(self, 12, 170, "Name (English)", col("text")))
    self.eName = self:reg("Settings", AkaShopUI.entry(self, 118, 166, 280, 22, "", false))
    self:reg("Settings", AkaShopUI.button(self, 408, 150, 110, 24, "Rename",
        self, self.onRename))
    self:reg("Settings", AkaShopUI.label(self, 528, 142,
        "Both names are always shown together as", col("dim")))
    self:reg("Settings", AkaShopUI.label(self, 528, 160,
        "\"Thai / English\". Fill in just one and only", col("dim")))
    self:reg("Settings", AkaShopUI.label(self, 528, 178,
        "that one is used.", col("dim")))

    self.btnToggle = self:reg("Settings", AkaShopUI.button(self, 12, 210, 200, 22,
        "Close shop", self, self.onToggleOpen))

    self.lblBank = self:reg("Settings", AkaShopUI.label(self, 12, 252, "", col("money")))
    self:reg("Settings", AkaShopUI.label(self, 12, 278, "Withdraw", col("text")))
    self.eWithdraw = self:reg("Settings", AkaShopUI.entry(self, 90, 274, 90, 22, "0", true))
    self:reg("Settings", AkaShopUI.button(self, 190, 274, 150, 22, "Take the money",
        self, self.onWithdraw))
    -- Akacount. Pays the till into the owner's bank account without building
    -- a single item, so it has no per-click cap. Only offered when the bank can
    -- actually hold what this till holds (AkaShop.bankLink); setTab decides,
    -- after its tab loop, for the reason written there.
    self.btnToBank = self:reg("Settings", AkaShopUI.button(self, 350, 274, 150, 22,
        "Send to bank", self, self.onToBank))
    -- The cap is a sandbox option now, so the sentence under the box has to
    -- read it rather than promise a number the server may not be using.
    self.lblWithdrawNote = self:reg("Settings", AkaShopUI.label(self, 12, 304, "", col("dim")))

    -- Shelf space. The server has had buyCapacity since v2.0.0 but nothing
    -- ever called it, so the whole weight-quota economy was unreachable.
    self:reg("Settings", AkaShopUI.label(self, 12, 330, "SHELF SPACE", col("dim")))
    self.lblShelf = self:reg("Settings", AkaShopUI.label(self, 12, 348, "", col("text")))
    self.btnExpand = self:reg("Settings", AkaShopUI.button(self, 300, 344, 200, 22,
        "Expand", self, self.onBuyCapacity))
    self.lblShelfNote = self:reg("Settings", AkaShopUI.label(self, 510, 348, "", col("dim")))

    self.lblTax = self:reg("Settings", AkaShopUI.label(self, 12, 378, "", col("dim")))
    self.lblWhere = self:reg("Settings", AkaShopUI.label(self, 12, 400, "", col("dim")))

    self.btnAlways = self:reg("Settings", AkaShopUI.button(self, 12, 370, 220, 22,
        "Server shop: OFF", self, self.onToggleAlwaysOpen))
    self.lblAlways = self:reg("Settings", AkaShopUI.label(self, 240, 374, "", col("dim")))

    self:reg("Settings", AkaShopUI.button(self, 12, 400, 220, 22,
        "Hand this shop to a player...", self, self.onTransfer))
    self.lblOwnerNote = self:reg("Settings", AkaShopUI.label(self, 240, 404, "", col("dim")))

    self:reg("Settings", AkaShopUI.button(self, 12, 432, 220, 22,
        "Delete this shop", self, self.onDeleteShop))
    self:reg("Settings", AkaShopUI.label(self, 240, 436,
        "Anything still in stock is returned to you.", col("bad")))

    --------------------------------------------------------------- Orders --
    self:reg("Orders", AkaShopUI.label(self, 12, 136,
        "Orders waiting to be collected", col("text")))
    self.orderList = self:reg("Orders",
        AkaShopUI.list(self, 10, LIST_Y, W - 20, LIST_H, drawOrderRow, self))
    self.btnHand = self:reg("Orders", AkaShopUI.button(self, 12, ROW1, 260, 24,
        "Hand over selected", self, self.onHandOrder))
    self.btnDecline = self:reg("Orders", AkaShopUI.button(self, 282, ROW1, 200, 24,
        "Decline selected", self, self.onDeclineOrder))
    -- Below the buttons, not above them: the list runs to y=436 and ROW1-24
    -- would have painted this line straight over the last order row.
    self.lblOrderNote = self:reg("Orders",
        AkaShopUI.label(self, 12, ROW1 + 32, "", col("dim")))

    ---------------------------------------------------------------- close --
    self.btnClose2 = AkaShopUI.button(self, W - 110, H - 34, 100, 24, "Close",
        self, self.close)

    self:setTab("Items")
end

--================================================================= orders ===

function AkaShopManageUI:onHandOrder()
    local o = AkaShopUI.selected(self.orderList)
    if not o then return AkaShopClient.notify("Pick an order first.", true) end
    if not o.here then
        return AkaShopClient.notify(
            o.buyer .. " has to be standing at this counter to collect.", true)
    end
    AkaShopClient.send("orderHand", { key = self.shopKey, id = o.id })
end

function AkaShopManageUI:onDeclineOrder()
    local o = AkaShopUI.selected(self.orderList)
    if not o then return AkaShopClient.notify("Pick an order first.", true) end
    AkaShopUI.confirm("Decline order #" .. o.id .. " from " .. tostring(o.buyer) ..
        "? The goods go back on sale.", self, function(me)
        AkaShopClient.send("orderDecline", { key = me.shopKey, id = o.id })
    end)
end

--=================================================================== tabs ===

--- Tabs a staff member is allowed to see. Everything else is hidden outright
--- rather than shown greyed out: a disabled tab invites "why can't I click
--- this", and the honest answer - "because you are staff" - is better told by
--- the tab simply not being part of their shop.
local STAFF_TABS = { Orders = true }

function AkaShopManageUI:allowedTab(name)
    if (self.snap or {}).full ~= false then return true end
    return STAFF_TABS[name] == true
end

function AkaShopManageUI:setTab(name)
    if not self:allowedTab(name) then name = "Orders" end
    self.tab = name
    for tab, widgets in pairs(self.tabWidgets) do
        local on = (tab == name)
        for i = 1, #widgets do widgets[i]:setVisible(on) end
    end
    for n, b in pairs(self.tabButtons) do
        b:setVisible(self:allowedTab(n))
        AkaShopUI.setButtonActive(b, n == name)
    end

    -- Declining destroys the order and puts the goods back on sale, so it is
    -- the owner's call. Hidden from staff rather than shown and refused: a
    -- button whose only job is to say no is worse than no button.
    --
    -- This lives here, AFTER the tab loop, because that loop has just made
    -- every widget on the visible tab visible - including this one. Doing it
    -- in refresh() looked right and was silently undone a moment later.
    if self.btnDecline then
        self.btnDecline:setVisible(name == "Orders" and (self.snap or {}).full ~= false)
    end

    -- Same rule, same reason: the tab loop above just turned these back on.
    -- Anything whose visibility depends on WHO is looking has to be decided
    -- here, after the tab has finished deciding WHAT is looking.
    local isAdmin = AkaShop.isAdmin(AkaShopClient.me())
    if self.btnAlways then self.btnAlways:setVisible(name == "Settings" and isAdmin) end
    if self.lblAlways then self.lblAlways:setVisible(name == "Settings" and isAdmin) end

    -- Not WHO but WHAT the server runs - still decided here, for the same
    -- reason: the loop above has just made every Settings widget visible.
    if self.btnToBank then
        local linked = AkaShop.bankLink()
        self.btnToBank:setVisible(name == "Settings" and linked == true)
    end

    if name == "Items" then self:refreshInventory() end
end

--================================================================ refresh ===

function AkaShopManageUI:refreshInventory()
    if not self.invList then return end
    local sel = AkaShopUI.selected(self.invList)
    local keepFt = sel and sel.ft or nil
    self.invList:clear()
    local stock = AkaShopUI.playerStock()
    for i = 1, #stock do
        self.invList:addItem(stock[i].name, stock[i])
        if keepFt and stock[i].ft == keepFt then self.invList.selected = i end
    end
end

function AkaShopManageUI:refresh(snap)
    self.snap = snap
    self.shopKey = snap.key
    self.title = "Traka - " .. AkaShop.shopName(snap)

    local status = snap.enabled and "OPEN" or "CLOSED"
    self.lblHeader:setName(AkaShop.shopBoth(snap))
    self.lblSub:setName("owner " .. tostring(snap.owner) ..
                        "   -   prices in " .. (snap.currency or "?"))
    AkaShopUI.centre(self.lblHeader, self:getWidth())
    AkaShopUI.centre(self.lblSub, self:getWidth())

    self.lblMode:setName((snap.modeLabel or "ONLINE") .. "  " .. (snap.hoursText or ""))
    self.lblOpen:setName(status)
    local oc = snap.enabled and col("good") or col("bad")
    self.lblOpen.r, self.lblOpen.g, self.lblOpen.b = oc[1], oc[2], oc[3]
    self.lblOpen:setX(self:getWidth() - 78)

    -- Staff do not get a snapshot with totals in it at all, so there is
    -- nothing to print. Blank the strip rather than show zeros, which would
    -- read as "this shop has taken nothing today" instead of "not your books".
    local staffOnly = (snap.full == false)
    for _, w in ipairs({ self.statToday, self.statTill, self.statLife, self.statShelf,
                         self.statTodayK, self.statTillK, self.statLifeK, self.statShelfK }) do
        if w then w:setVisible(not staffOnly) end
    end
    self.hideShelfBar = staffOnly

    local t = snap.totals or {}
    self.statToday:setName(AkaShop.money(t.today or 0) ..
                           "   (" .. tostring(t.todayCount or 0) .. ")")
    self.statTill:setName(AkaShop.money(t.bank or 0))
    self.statLife:setName(AkaShop.money(t.revenue or 0))
    self.statShelf:setName(string.format("%.1f / %d kg",
        snap.weightKg or 0, snap.capacityKg or 0))
    self.shelfFrac = (snap.capacityKg or 0) > 0
        and math.min(1, (snap.weightKg or 0) / snap.capacityKg) or 0

    local t = snap.totals or {}


    -- listings
    local selUid = nil
    local s = AkaShopUI.selected(self.saleList)
    if s then selUid = s.uid end
    self.saleList:clear()
    for i, e in ipairs(snap.items or {}) do
        self.saleList:addItem(e.name, e)
        if selUid and e.uid == selUid then self.saleList.selected = i end
    end

    -- orders. The selection is kept across refreshes: this list repaints every
    -- time the buyer takes a step (their "at the counter" flag moves), and a
    -- selection that jumped every second would be unclickable.
    local selId = nil
    local so = AkaShopUI.selected(self.orderList)
    if so then selId = so.id end
    self.orderList:clear()
    local orders = snap.orders or {}
    for i, o in ipairs(orders) do
        self.orderList:addItem("#" .. o.id, o)
        if selId and o.id == selId then self.orderList.selected = i end
    end
    if self.tabButtons and self.tabButtons["Orders"] then
        self.tabButtons["Orders"]:setTitle(#orders > 0
            and ("Orders (" .. #orders .. ")") or "Orders")
    end
    if self.lblOrderNote then
        local staffNote = (snap.full == false)
            and "You are staff here: handing orders over is what you can do."
            or  "The customer pays on collection, and orders are never taxed."

        local note
        if snap.ordersOn == false then
            -- An empty list because the feature is switched off looks exactly
            -- like an empty list because the feature is broken. Say which.
            note = "ORDERS ARE OFF on this server. Customers can always buy " ..
                   "for themselves, so they never need to order and this list " ..
                   "will always be empty. Turn on the sandbox option " ..
                   "\"Restrict self-service hours\" to switch orders on."
        elseif #orders > 0 then
            note = "Pick a row that says AT THE COUNTER, then Hand over. Both " ..
                   "of you must stand within " .. AkaShop.useDistance() ..
                   " tiles.  " .. staffNote ..
                   "  Uncollected orders go back on sale after " ..
                   tostring(snap.orderHours or 12) .. "h."
        else
            note = "No orders waiting. Customers place one whenever " ..
                   "self-service is closed (" .. tostring(snap.hoursText or "") ..
                   ").  " .. staffNote
        end
        self.lblOrderNote:setName(note)
    end

    -- codes
    self.codeList:clear()
    for _, c in ipairs(snap.codes or {}) do self.codeList:addItem(c.code, c) end

    -- staff
    self.staffList:clear()
    for _, u in ipairs(snap.staff or {}) do self.staffList:addItem(u, { user = u }) end

    if self.lblOwnerNote then
        self.lblOwnerNote:setName("Currently " .. tostring(snap.owner) ..
                                  ". Only players who are online can be picked.")
    end

    -- Only an admin decides which clock a counter keeps, so an owner never
    -- sees this row at all rather than seeing one they cannot press.
    local isAdmin = AkaShop.isAdmin(AkaShopClient.me())
    if self.btnAlways then
        self.btnAlways:setVisible(isAdmin)
        self.btnAlways:setTitle("Server shop: " .. (snap.alwaysOpen and "ON" or "OFF"))
    end
    if self.lblAlways then
        self.lblAlways:setVisible(isAdmin)
        self.lblAlways:setName(snap.alwaysOpen
            and "Open 24h, ignores trading hours, takes no orders."
            or  "Follows the server's trading hours like any player shop.")
    end

    -- Re-apply the tab rules every refresh. A player can be hired or fired
    -- while their window is open, and the window has to follow.
    self:setTab(self.tab or "Items")

    -- sales
    self.salesList:clear()
    for _, sale in ipairs(snap.sales or {}) do
        self.salesList:addItem(sale.when or "", sale)
    end
    self.lblSales:setName(string.format("Today: %s from %d sale(s).   Shown: %d entries.",
        AkaShop.money(t.today or 0), t.todayCount or 0, #(snap.sales or {})))

    -- settings
    self.eName:setText(snap.name or "")
    self.eNameTH:setText(snap.nameTH or "")
    self.btnToggle:setTitle(snap.enabled and "Close shop (stop selling)" or "Open shop")
    self.lblBank:setName("In the till: " .. AkaShop.money(t.bank or 0) .. " " ..
        (snap.currency or ""))
    if self.lblWithdrawNote then
        local cap = AkaShop.money(AkaShop.withdrawMax())
        local linked = AkaShop.bankLink()
        self.lblWithdrawNote:setName(linked == true
            and ("Cash: up to " .. cap .. " per click.   Bank: any amount, the bank's fee applies." ..
                 "   Leave 0 for as much as allowed.")
            or  ("Max " .. cap .. " per withdrawal. Leave 0 to take as much as allowed."))
    end
    if self.lblShelf then
        self.lblShelf:setName(string.format("%.1f / %d kg used   (%.1f kg free)",
            snap.weightKg or 0, snap.capacityKg or 0,
            math.max(0, (snap.capacityKg or 0) - (snap.weightKg or 0))))
        local atMax = (snap.capacityKg or 0) >= (snap.capMax or 100)
        self.btnExpand:setTitle(atMax and "At maximum"
            or ("Expand +" .. (snap.capStep or 10) .. " kg"))
        self.btnExpand:setEnable(not atMax)
        self.lblShelfNote:setName(atMax
            and ("Cap is " .. (snap.capMax or 100) .. " kg.")
            or (AkaShop.money(snap.capPrice or 0) .. " from the till   (max " ..
                (snap.capMax or 100) .. " kg)"))
    end
    self.lblTax:setName("Server sales tax: " .. tostring(snap.tax or 0) ..
        "%  (deducted from the owner's cut, the buyer pays the listed price)")
    self.lblWhere:setName(string.format("Registered at %d, %d, %d   -   created %s",
        snap.x or 0, snap.y or 0, snap.z or 0, tostring(snap.created or "?")))

    self:refreshInventory()
end

--================================================================ actions ===

function AkaShopManageUI:onAddStock()
    local pick = AkaShopUI.selected(self.invList)
    if not pick then
        return AkaShopClient.notify("Select an item from your inventory first.", true)
    end
    local qty = AkaShopUI.num(self.eQty, 1)
    if qty < 1 then return AkaShopClient.notify("Quantity must be at least 1.", true) end
    if qty > pick.count then
        return AkaShopClient.notify("You only carry " .. pick.count .. ".", true)
    end
    -- an empty Price box means "leave the existing price alone" rather than
    -- silently resetting an established listing to free
    AkaShopClient.send("addStock", {
        key = self.shopKey, ft = pick.ft,
        qty = qty, price = AkaShopUI.num(self.ePrice, nil),
    })
end

function AkaShopManageUI:onSetPrice()
    local e = AkaShopUI.selected(self.saleList)
    if not e then return AkaShopClient.notify("Select a listing on the right.", true) end
    local price = AkaShopUI.num(self.ePrice, nil)
    if not price then return AkaShopClient.notify("Type a price first.", true) end
    AkaShopClient.send("setPrice", { key = self.shopKey, uid = e.uid, price = price })
end

function AkaShopManageUI:onTakeStock()
    local e = AkaShopUI.selected(self.saleList)
    if not e then return AkaShopClient.notify("Select a listing on the right.", true) end
    AkaShopClient.send("takeStock", {
        key = self.shopKey, uid = e.uid, qty = AkaShopUI.num(self.eQty, 1),
    })
end

function AkaShopManageUI:onRemoveListing()
    local e = AkaShopUI.selected(self.saleList)
    if not e then return AkaShopClient.notify("Select a listing on the right.", true) end
    local key, uid = self.shopKey, e.uid
    AkaShopUI.confirm("Remove \"" .. e.name .. "\" and take back " .. e.qty .. " in stock?",
        self, function()
            AkaShopClient.send("removeListing", { key = key, uid = uid })
        end)
end

function AkaShopManageUI:onAddCode()
    AkaShopClient.send("addCode", {
        key     = self.shopKey,
        code    = self.eCode:getInternalText(),
        percent = AkaShopUI.num(self.eCodePct, 10),
        maxUses = AkaShopUI.num(self.eCodeMax, 0),
    })
    self.eCode:setText("")
end

function AkaShopManageUI:onDelCode()
    local c = AkaShopUI.selected(self.codeList)
    if not c then return AkaShopClient.notify("Select a code.", true) end
    AkaShopClient.send("delCode", { key = self.shopKey, code = c.code })
end

function AkaShopManageUI:onToggleAlwaysOpen()
    local snap = self.snap or {}
    local on = not snap.alwaysOpen
    AkaShopUI.confirm(on
        and ("Make " .. AkaShop.shopName(snap) .. " a SERVER SHOP?\n" ..
             "It will serve customers 24 hours and stop taking orders.")
        or  ("Put " .. AkaShop.shopName(snap) .. " back on the server's " ..
             "trading hours?\nCustomers will have to order outside them."),
        self, function(me)
            AkaShopClient.send("setAlwaysOpen", { key = me.shopKey, on = on })
        end)
end

function AkaShopManageUI:onTransfer()
    local key = self.shopKey
    AkaShopOwnerPick.open("Hand this shop to whom?", function(username)
        AkaShopUI.confirm("Hand " .. AkaShop.shopName(self.snap or {}) .. " to " ..
            username .. "?\nThe stock, the till and the sales history go with it, " ..
            "and you lose control of the shop.", self, function()
            AkaShopClient.send("setOwner", { key = key, user = username })
        end)
    end, { query = { mode = "owner", key = key },
           note = "Everything in the shop goes with it. This cannot be undone " ..
                  "except by the new owner handing it back." })
end

function AkaShopManageUI:onRefreshOnline()
    AkaShopClient.send("whoOnline", { key = self.shopKey })
end

function AkaShopManageUI:fillOnline(players)
    if not self.onlineList then return end
    local sel = AkaShopUI.selected(self.onlineList)
    self.onlineList:clear()
    for i, p in ipairs(players) do
        self.onlineList:addItem(p.user, p)
        if sel and sel.user == p.user then self.onlineList.selected = i end
    end
    if #players == 0 then
        self.onlineList:addItem("-", { user = "nobody else is online", dist = -1 })
    end
end

function AkaShopManageUI:onHireOnline()
    local p = AkaShopUI.selected(self.onlineList)
    if not p then return AkaShopClient.notify("Pick a player from the list first.", true) end
    AkaShopClient.send("addStaff", { key = self.shopKey, user = p.user })
    -- The server rebuilds the list on the next push, but asking now means the
    -- hired player leaves the candidate list immediately instead of sitting
    -- there looking hireable twice.
    self:onRefreshOnline()
end

function AkaShopManageUI:onAddStaff()
    AkaShopClient.send("addStaff", {
        key = self.shopKey, user = self.eStaff:getInternalText(),
    })
    self.eStaff:setText("")
end

function AkaShopManageUI:onDelStaff()
    local s = AkaShopUI.selected(self.staffList)
    if not s then return AkaShopClient.notify("Select a staff member.", true) end
    AkaShopClient.send("delStaff", { key = self.shopKey, user = s.user })
end

function AkaShopManageUI:onClearSales()
    local key = self.shopKey
    AkaShopUI.confirm("Erase the whole sales history of this shop?", self, function()
        AkaShopClient.send("clearSales", { key = key })
    end)
end

function AkaShopManageUI:onRename()
    AkaShopClient.send("setName", {
        key    = self.shopKey,
        name   = self.eName:getInternalText(),
        nameTH = self.eNameTH:getInternalText(),
    })
end

function AkaShopManageUI:onToggleOpen()
    AkaShopClient.send("setEnabled", {
        key = self.shopKey, on = not (self.snap and self.snap.enabled),
    })
end

function AkaShopManageUI:onWithdraw()
    AkaShopClient.send("withdraw", {
        key = self.shopKey, amount = AkaShopUI.num(self.eWithdraw, 0),
    })
end

--- Till -> bank, after saying exactly what will land and what the bank keeps.
--- The fee is worked out with Akacount's own calculator (AkaShop.bankFee), so
--- the figure in this box is the figure charged.
function AkaShopManageUI:onToBank()
    local key  = self.shopKey
    local till = math.floor(((self.snap or {}).totals or {}).bank or 0)
    if till <= 0 then return AkaShopClient.notify("The till is empty.", true) end
    local want = AkaShopUI.num(self.eWithdraw, 0)
    if want <= 0 or want > till then want = till end

    local text = "Send " .. AkaShop.money(want) .. " from the till to your bank account?"
    local fee = AkaShop.bankFee(want)
    if fee and fee > 0 then
        text = text .. "\nThe bank keeps a fee of " .. AkaShop.bankMoney(fee) .. "."
    end
    AkaShopUI.confirm(text, self, function()
        AkaShopClient.send("toBank", { key = key, amount = want })
    end)
end

function AkaShopManageUI:onDeleteShop()
    local key = self.shopKey
    AkaShopUI.confirm("Delete this shop for good?", self, function()
        AkaShopClient.send("deleteShop", { key = key })
    end)
end

--=================================================================== open ===

function AkaShopManageUI:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if AkaShopManageUI.instance == self then AkaShopManageUI.instance = nil end
end

function AkaShopManageUI.openWith(snap)
    local ui = AkaShopManageUI.instance
    if not ui then
        local x = math.max(20, (getCore():getScreenWidth() - W) / 2)
        local y = math.max(20, (getCore():getScreenHeight() - H) / 2)
        ui = AkaShopManageUI:new(x, y)
        ui:initialise()
        ui:addToUIManager()
        AkaShopManageUI.instance = ui
    end
    ui:setVisible(true)
    ui:bringToTop()
    ui:refresh(snap)
    return ui
end
