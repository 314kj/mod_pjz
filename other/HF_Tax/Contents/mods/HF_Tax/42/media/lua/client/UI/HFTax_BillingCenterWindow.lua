-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Original work: Copyright (c) 2026 matasa. All Rights Reserved.
-- UI revision: AKA (LOOKCHINNOL), published with the author's permission.
--
-- HFTax_BillingCenterWindow.lua -- the live window.
--
-- Split of responsibility, on purpose:
--   HFTax_BillingCenterUI.lua  draws a model and hands back click zones
--   this file                  builds the model from ModData and routes clicks
--
-- Nothing here draws, and nothing in the drawing file reads game state. That
-- is what lets _dev/render.lua produce the design frames from the real code.
-- =============================================================================

---@diagnostic disable: undefined-global
require "ISUI/ISPanel"
require "UI/HFTax_Theme"
require "UI/HFTax_BillingCenterUI"

HFTaxUI = HFTaxUI or {}
HFTaxUI.BillingWindow = ISPanel:derive("HFTax_BillingCenterWindow")
HFTaxUI.BillingWindow.instance = nil

local W = HFTaxUI.BillingWindow
local T = HFTaxUI.Theme
local BC = HFTaxUI.BillingCenter

local CFG = HFTax.Config

-- ---------------------------------------------------------------- helpers ---
local function cfgStatus(bill)
    if bill.status == CFG.BILL_STATUS.PAID then return "paid" end
    if bill.isCutoffStage then return "cut" end
    if bill.isOverdue then return "late" end
    return "due"
end

---How much of the current stage is left, 0..1. Feeds the block countdown.
local function fractionLeft(bill)
    local now = HFTax.Utils.getRealDaysEpoch()
    local due = bill.dueDaysEpoch or (now + CFG.STAGE1_DUE_DAYS)
    local st2 = bill.stage2Epoch or (due + CFG.STAGE2_CUTOFF_DAYS)
    local f
    if now < due then
        local span = math.max(0.001, due - (bill.createdEpoch or (due - CFG.STAGE1_DUE_DAYS)))
        f = (due - now) / span
    else
        f = (st2 - now) / math.max(0.001, st2 - due)
    end
    if f < 0 then return 0 end
    if f > 1 then return 1 end
    return f
end

local function shortNote(bill, queuedBehind)
    local status = cfgStatus(bill)
    if status == "paid" then
        local when = tostring(bill.paidDateStr or "")
        when = string.sub(when, 6, 10)             -- "MM-DD" out of "YYYY-MM-DD hh:mm"
        return when .. " - " .. string.upper(tostring(bill.paidMethod or "PAID"))
    end
    if queuedBehind then
        return "PAY " .. tostring(queuedBehind) .. " FIRST"
    end
    local now = HFTax.Utils.getRealDaysEpoch()
    local due = bill.dueDaysEpoch or now
    local st2 = bill.stage2Epoch or (due + CFG.STAGE2_CUTOFF_DAYS)
    local fee = (bill.penalty or 0) > 0 and (" - FEE +" .. T.money(bill.penalty)) or ""
    if status == "due" then
        return "DUE IN " .. T.dur(due - now) .. fee
    elseif status == "late" then
        return "CUT OFF IN " .. T.dur(st2 - now) .. fee
    end
    return "OVERDUE " .. T.dur(now - due) .. fee
end

local function cashOnPerson(player)
    local inv = player and player:getInventory()
    if not inv then return 0 end
    local items = inv:getItems()
    if not items then return 0 end
    local n = 0
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it:getFullType() == "Base.Money" then n = n + 1 end
    end
    return n
end

---Every safehouse this player belongs to. Sorted so the list does not jump
---around between frames.
local function mySafehouses(username)
    local out = {}
    local list = SafeHouse.getSafehouseList()
    if not list then return out end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh then
            local owner = sh:getOwner()
            local allowed = sh:playerAllowed(username)
            if owner == username or allowed then
                out[#out + 1] = sh
            end
        end
    end
    table.sort(out, function(a, b)
        return HFTax.Utils.getSafehouseKey(a) < HFTax.Utils.getSafehouseKey(b)
    end)
    return out
end

-- ------------------------------------------------------------------ model ---
---Turn one stored bill into the row shape the drawing code wants.
function W:billRow(bill, art, queuedBehind, canPay)
    local status = queuedBehind and "queued" or cfgStatus(bill)
    local row = {
        billId = bill.billId,
        no = "INV #" .. tostring(bill.billId and string.gsub(tostring(bill.billId), "^%a+_", "") or "?"),
        amount = bill.totalAmount or 0,
        status = status,
        note = shortNote(bill, queuedBehind),
        art = art,
        __bill = bill,
    }
    if status ~= "paid" then row.frac = fractionLeft(bill) end

    row.chips = {
        { art = "ic_due", text = string.sub(tostring(bill.createdDateStr or ""), 6, 16) },
    }
    if (bill.penalty or 0) > 0 then
        row.chips[#row.chips + 1] = { art = "ic_unpaid", text = "FEE " .. T.money(bill.penalty), warn = true }
    end

    row.actions = { { id = "receipt", label = "RECEIPT", style = "ghost", art = "btn_details" } }
    if status ~= "paid" and canPay and not queuedBehind then
        local ps = self.paySettings
        if ps.allowCash then
            row.actions[#row.actions + 1] = { id = "cash", label = "PAY CASH", style = "go", art = "ic_purse" }
        end
        if ps.allowBank then
            row.actions[#row.actions + 1] = { id = "bank", label = "PAY BANK", style = "bank", art = "ic_bank" }
        end
    end
    return row
end

---Oldest unpaid bill in a set. The server refuses anything else
---(MUST_PAY_OLDEST_FIRST), so the screen has to say so before the click, not
---as an error after it.
local function oldestUnpaid(bills)
    local best
    for i = 1, #bills do
        local b = bills[i]
        if b.status == CFG.BILL_STATUS.UNPAID then
            if not best or (b.createdEpoch or 0) < (best.createdEpoch or 0) then best = b end
        end
    end
    return best
end

function W:buildModel()
    local player = self.player
    local username = player:getUsername()
    local puuid = HFTax.Utils.getPlayerPUUID(username)
    local data = ModData.getOrCreate(CFG.GLOBAL_DATA_KEY)
    local allBills = data.Bills or {}
    self.paySettings = data.PaymentSettings or CFG.DefaultPaymentSettings

    local showPaid = (self.page == "history")

    -- personal ---------------------------------------------------------------
    local personal = {}
    for _, b in pairs(allBills) do
        if b.billType == CFG.BILL_TYPE.PERSONAL then
            local mine = (b.ownerPUUID == puuid) or (b.owner == username)
                or (b.visibilityPUUIDs and b.visibilityPUUIDs[puuid])
            if mine then personal[#personal + 1] = b end
        end
    end
    table.sort(personal, function(a, b) return (a.createdEpoch or 0) > (b.createdEpoch or 0) end)

    -- house ------------------------------------------------------------------
    self.houses = mySafehouses(username)
    if self.houseIndex > #self.houses then self.houseIndex = 1 end
    local sh = self.houses[self.houseIndex]
    local shKey = sh and HFTax.Utils.getSafehouseKey(sh) or nil
    local isOwner = sh and (sh:getOwner() == username) or false

    local houseBills = {}
    if shKey then
        for _, b in pairs(allBills) do
            if b.safehouseKey == shKey then houseBills[#houseBills + 1] = b end
        end
        table.sort(houseBills, function(a, b) return (a.createdEpoch or 0) > (b.createdEpoch or 0) end)
    end

    local pOldest = oldestUnpaid(personal)
    local hOldest = oldestUnpaid(houseBills)

    local function rowsFor(bills, art, oldest, canPay)
        local rows, due, unpaid = {}, 0, 0
        for i = 1, #bills do
            local b = bills[i]
            local isPaid = (b.status == CFG.BILL_STATUS.PAID)
            if isPaid == showPaid then
                local queued
                if not isPaid and oldest and b.billId ~= oldest.billId then
                    queued = "#" .. tostring(string.gsub(tostring(oldest.billId or ""), "^%a+_", ""))
                end
                rows[#rows + 1] = self:billRow(b, art, queued, canPay)
            end
            if not isPaid then
                due = due + (b.totalAmount or 0)
                unpaid = unpaid + 1
            end
        end
        return rows, due, unpaid
    end

    local pRows, pDue, pUnpaid = rowsFor(personal, "ic_invoice", pOldest, true)
    local hRows, hDue, hUnpaid = rowsFor(houseBills, "ic_house", hOldest, isOwner)

    -- utilities state for the header chips
    local cut = shKey and HFTax.ClientData and HFTax.ClientData.CutoffSafehouses
        and HFTax.ClientData.CutoffSafehouses[shKey] or false

    -- newest bill carries the tile/member snapshot worth showing
    local bd = (houseBills[1] and houseBills[1].breakdown) or {}
    local dim = bd.dimensions or {}

    local lateCount, cutCount = 0, 0
    local function tally(bills)
        for i = 1, #bills do
            local b = bills[i]
            if b.status == CFG.BILL_STATUS.UNPAID then
                if b.isCutoffStage then cutCount = cutCount + 1
                elseif b.isOverdue then lateCount = lateCount + 1 end
            end
        end
    end
    tally(personal); tally(houseBills)

    local houseFacts = {
        { art = "ic_recipient", text = isOwner and "OWNER" or "TENANT", good = isOwner },
    }
    if dim.totalTiles then
        houseFacts[#houseFacts + 1] = { art = "ic_tax", text = tostring(dim.totalTiles) }
    end
    if bd.memberCount then
        houseFacts[#houseFacts + 1] = { art = "ic_person",
            text = tostring(bd.memberCount) .. " / " .. tostring(bd.memberQuota or 0) }
    end
    houseFacts[#houseFacts + 1] = { art = "ic_water", text = cut and "OFF" or "ON", bad = cut, good = not cut }
    houseFacts[#houseFacts + 1] = { art = "ic_power", text = cut and "OFF" or "ON", bad = cut, good = not cut }

    local bank = (HFTax.ClientData and HFTax.ClientData.BankBalance) or 0

    return {
        page = self.page,
        helpAvailable = false,      -- turns on with the picture manual
        streak = self.streak or 0,
        totalDue = pDue + hDue,
        bills = pUnpaid + hUnpaid,
        late = lateCount,
        cut = cutCount,
        payable = (pUnpaid > 0) or (hUnpaid > 0 and isOwner),
        selected = self.selected,
        receipt = self.receipt,
        confirm = self.confirm,
        wallet = {
            cash = cashOnPerson(player), bank = bank,
            cashOn = self.paySettings.allowCash ~= false,
            bankOn = self.paySettings.allowBank ~= false,
        },
        colPersonal = {
            tag = "PERSONAL", name = username, id = "#" .. puuid,
            art = "ic_person", accent = T.C.cyan, due = pDue,
            scroll = self.scrollPersonal,
            facts = {
                { art = "ic_due", text = T.dur(CFG.DefaultPersonalTax.cycleDays) .. " CYCLE" },
                { art = "ic_cash", text = T.money(CFG.DefaultPersonalTax.rate) },
            },
            footStyle = (pDue > 0) and "go" or "off",
            footLabel = (pDue > 0) and ("CLEAR PERSONAL - " .. T.money(pDue)) or "NOTHING DUE",
            footArt = (pDue > 0) and "ic_cash" or nil,
            footZone = "payPersonal",
            emptyArt = "ic_paid",
            emptyTitle = showPaid and "NO HISTORY YET" or "ALL CLEAR",
            emptyNote = showPaid and "paid bills show up here" or "no personal tax outstanding",
            bills = pRows,
        },
        colHouse = {
            tag = "HOUSE",
            name = sh and tostring(sh:getTitle() or "Safehouse") or "NO SAFEHOUSE",
            id = sh and ("#" .. HFTax.Utils.getSafehouseSHID(sh)) or "",
            art = "ic_house", accent = T.C.amber, due = hDue,
            scroll = self.scrollHouse,
            selector = (#self.houses > 1) and ("MY HOUSES " .. tostring(#self.houses)) or nil,
            facts = sh and houseFacts or {},
            footStyle = (hDue > 0 and isOwner) and "go" or "off",
            footLabel = (hDue <= 0) and "NOTHING DUE"
                or (isOwner and ("CLEAR HOUSE - " .. T.money(hDue)) or "OWNER PAYS THIS"),
            footArt = (hDue > 0 and isOwner) and "ic_cash" or nil,
            footZone = "payHouse",
            emptyArt = "ic_house",
            emptyTitle = sh and (showPaid and "NO HISTORY YET" or "ALL CLEAR") or "NO SAFEHOUSE",
            emptyNote = sh and "no house tax outstanding" or "join a safehouse to see its bills",
            bills = hRows,
        },
    }
end

-- ------------------------------------------------------------------ paint ---
function W:prerender()
    local ok, err = pcall(function()
        self.model = self:buildModel()
        self.zones = BC.render(self, self.model, self.width, self.height) or {}
    end)
    if not ok then
        -- A crash in prerender fires every single frame and buries console.txt
        -- in tens of thousands of lines. Say it once, then draw something the
        -- player can actually close.
        if not self.errShown then
            self.errShown = true
            print("[HF_Tax] BillingCenter draw error: " .. tostring(err))
        end
        self:drawRect(0, 0, self.width, self.height, 0.98, 0.06, 0.07, 0.12)
        self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.55, 0.16, 0.19)
        self:drawText("HF_Tax UI error - see console.txt", 20, 20, 1, 0.78, 0.78, 1, UIFont.Medium)
        self:drawText("Click anywhere to close.", 20, 46, 0.7, 0.7, 0.8, 1, UIFont.Small)
        self.zones = { { name = "close", x = 0, y = 0, w = self.width, h = self.height } }
    end
end

function W:render() end

-- ------------------------------------------------------------------ input ---
local function hit(zones, x, y)
    -- Backwards: later draws sit on top, so they win the click.
    for i = #zones, 1, -1 do
        local z = zones[i]
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then return z end
    end
    return nil
end

function W:pay(billId, method)
    sendClientCommand(self.player, CFG.MOD_ID, "PayBill", {
        billId = billId, payMethod = method,
    })
end

function W:payMany(ids, method)
    if not ids or #ids == 0 then return end
    sendClientCommand(self.player, CFG.MOD_ID, "PayAllBills", { billIds = ids, payMethod = method })
end

---Bill ids in a set of rows that are actually payable right now. Queued bills
---are left out: the server would refuse them anyway, and sending them means a
---"payment failed" toast for something the screen already marked QUEUED.
local function payableIds(rows)
    local ids, total = {}, 0
    for i = 1, #rows do
        local r = rows[i]
        if r.status ~= "paid" and r.status ~= "queued" then
            ids[#ids + 1] = r.billId
            total = total + (r.amount or 0)
        end
    end
    return ids, total
end

---Open the wallet chooser. Nothing is sent until the player picks a method.
function W:askMethod(title, ids, amount)
    if not ids or #ids == 0 or amount <= 0 then return end
    local ps = self.paySettings or CFG.DefaultPaymentSettings
    self.confirm = {
        title = title,
        subtitle = (#ids == 1) and "1 BILL" or (tostring(#ids) .. " BILLS - OLDEST FIRST"),
        amount = amount,
        ids = ids,
        cash = cashOnPerson(self.player),
        bank = (HFTax.ClientData and HFTax.ClientData.BankBalance) or 0,
        cashOn = ps.allowCash ~= false,
        bankOn = ps.allowBank ~= false,
    }
end

function W:openReceipt(billId)
    local row
    local function look(rows)
        for i = 1, #rows do if rows[i].billId == billId then row = rows[i] end end
    end
    look(self.model.colPersonal.bills); look(self.model.colHouse.bills)
    if not row then return end

    local b = row.__bill
    local bd = b.breakdown or {}
    local dim = bd.dimensions or {}
    local isLand = (b.billType == CFG.BILL_TYPE.LAND)
    local lines = {}

    if isLand then
        lines[#lines + 1] = { art = "ic_tax", label = "LAND",
            note = tostring(dim.w or 0) .. " x " .. tostring(dim.h or 0) .. " = "
                .. tostring(dim.totalTiles or 0) .. " TILES @ " .. T.money(bd.landRate or 0),
            amount = b.landTax or 0 }
        lines[#lines + 1] = { art = "ic_person", label = "MEMBERS",
            note = tostring(bd.extraMembers or 0) .. " OVER QUOTA @ " .. T.money(bd.memberRate or 0),
            amount = b.memberTax or 0 }
    else
        lines[#lines + 1] = { art = "ic_person", label = "BASE RATE", amount = b.basePayable or b.totalAmount or 0 }
    end
    if (b.penalty or 0) > 0 then
        lines[#lines + 1] = { art = "ic_unpaid", label = "LATE FEE",
            note = "+2% / DAY x " .. tostring(b.overdueDays or 0), amount = b.penalty, neg = true }
    end

    local foot
    if bd.memberList and #bd.memberList > 0 then
        local names = {}
        for i = 1, math.min(2, #bd.memberList) do names[#names + 1] = tostring(bd.memberList[i]) end
        foot = "MEMBERS ON ISSUE DATE: " .. table.concat(names, ", ")
        if #bd.memberList > 2 then foot = foot .. ", +" .. (#bd.memberList - 2) .. " more" end
    end

    local acts = {}
    for i = 1, #(row.actions or {}) do
        local a = row.actions[i]
        if a.id ~= "receipt" then acts[#acts + 1] = a end
    end

    self.receipt = {
        billId = billId,
        title = row.no,
        subtitle = (isLand and string.upper(tostring(b.safehouseTitle or "SAFEHOUSE")) or "PERSONAL TAX")
            .. " - " .. tostring(b.createdDateStr or ""),
        art = isLand and "ic_house" or "ic_person",
        accent = isLand and T.C.amber or T.C.cyan,
        stamp = (row.status == "paid") and "stamp_paid"
            or ((row.status == "cut" or row.status == "queued") and "stamp_cut" or nil),
        total = b.totalAmount or 0,
        paid = (row.status == "paid"),
        lines = lines,
        footnote = foot,
        actions = acts,
    }
end

function W:onMouseDown(x, y)
    -- Clear the click state BEFORE doing anything that can throw, or a crash
    -- leaves the window believing the button is still held.
    -- (PZ-B42-lua-API-RULE: this is how "left click anywhere opens the shop"
    --  happened in Kuraya 0.2.4.)
    local zones = self.zones or {}
    self.zones = zones

    local z = hit(zones, x, y)
    if not z then
        if y <= T.h(T.F.M) + T.pad() * 2 then return ISPanel.onMouseDown(self, x, y) end
        return true
    end

    local ok, err = pcall(function() self:act(z) end)
    if not ok then print("[HF_Tax] click error: " .. tostring(err)) end
    return true
end

function W:act(z)
    local n = z.name
    local m = self.model

    if n == "confirm:close" then self.confirm = nil; return end
    if n == "confirm:cash" or n == "confirm:bank" then
        local c = self.confirm
        self.confirm = nil                       -- clear BEFORE sending
        if not c then return end
        local method = (n == "confirm:cash") and "CASH" or "BANK"
        if #c.ids == 1 then self:pay(c.ids[1], method) else self:payMany(c.ids, method) end
        return
    end

    if n == "close" or n == "receipt:close" or n == "receipt:closeBtn" then
        if self.receipt and n ~= "close" then self.receipt = nil else self:close() end
        return
    end

    if n == "page:bills" or n == "page:history" then
        self.page = string.sub(n, 6)
        self.scrollPersonal, self.scrollHouse = 1, 1
        self.selected = nil
        return
    end

    if n == "houses" then
        self.houseIndex = self.houseIndex + 1
        if self.houseIndex > #(self.houses or {}) then self.houseIndex = 1 end
        self.scrollHouse = 1
        return
    end

    -- The three green buttons all ask which wallet first. None of them moves
    -- money on the click that opened the question.
    if n == "payall" then
        local rows = {}
        for i = 1, #m.colPersonal.bills do rows[#rows + 1] = m.colPersonal.bills[i] end
        for i = 1, #m.colHouse.bills do rows[#rows + 1] = m.colHouse.bills[i] end
        local ids, total = payableIds(rows)
        return self:askMethod("PAY ALL OUTSTANDING", ids, total)
    end
    if n == "payPersonal" then
        local ids, total = payableIds(m.colPersonal.bills)
        return self:askMethod("CLEAR PERSONAL TAX", ids, total)
    end
    if n == "payHouse" then
        local ids, total = payableIds(m.colHouse.bills)
        return self:askMethod("CLEAR HOUSE TAX", ids, total)
    end

    local kind, rest = string.match(n, "^(%a+):(.+)$")
    if kind == "bill" then
        self.selected = (self.selected == rest) and nil or rest
        return
    end
    if kind == "act" then
        local id, billNo = string.match(rest, "^(%a+):(.+)$")
        local billId = self:idFromNo(billNo)
        if id == "receipt" then return self:openReceipt(billId) end
        if id == "cash" then return self:pay(billId, "CASH") end
        if id == "bank" then return self:pay(billId, "BANK") end
        return
    end
    if kind == "receipt" then
        local billId = self.receipt and self.receipt.billId
        if rest == "cash" then self.receipt = nil; return self:pay(billId, "CASH") end
        if rest == "bank" then self.receipt = nil; return self:pay(billId, "BANK") end
    end
end

function W:idFromNo(no)
    local function look(rows)
        for i = 1, #rows do if rows[i].no == no then return rows[i].billId end end
    end
    return look(self.model.colPersonal.bills) or look(self.model.colHouse.bills)
end

function W:onMouseWheel(del)
    -- An overlay owns the wheel too, or the list scrolls behind the dialog.
    if self.receipt or self.confirm then return true end
    if not self.model then return true end
    local mx = self:getMouseX()
    local col = (mx > self.width / 2) and "House" or "Personal"
    local key = "scroll" .. col
    local rows = (col == "House") and self.model.colHouse or self.model.colPersonal
    local shown = rows.__shown or 1
    local top = (self[key] or 1) + (del > 0 and 1 or -1)
    if top < 1 then top = 1 end
    local maxTop = math.max(1, #rows.bills - shown + 1)
    if top > maxTop then top = maxTop end
    self[key] = top
    return true
end

function W:onMouseUp(x, y) return ISPanel.onMouseUp(self, x, y) end
function W:onMouseUpOutside(x, y) return ISPanel.onMouseUpOutside(self, x, y) end

-- ------------------------------------------------------------------ life ----
function W:close()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.BillingWindow.instance = nil
end

function W:new(x, y, w, h, player)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.moveWithMouse = true
    o.page = "bills"
    o.houseIndex = 1
    o.confirm = nil
    o.receipt = nil
    o.scrollPersonal = 1
    o.scrollHouse = 1
    o.zones = {}
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

---@param safehouse SafeHouse|nil the one the player is standing in, if any
function W.openWindow(player, safehouse)
    player = player or getPlayer()
    if not player then return end

    sendClientCommand(player, CFG.MOD_ID, "RequestPlayerBills", {
        myPUUID = HFTax.Utils.getPlayerPUUID(player:getUsername()),
        username = player:getUsername(),
    })

    if HFTaxUI.BillingWindow.instance then HFTaxUI.BillingWindow.instance:close() end

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- Clamp against the real screen, always. 1360x820 is the design size, not
    -- a promise that the player's monitor is that big.
    local w = math.min(1360, sw - 20)
    local h = math.min(820, sh - 20)

    local ui = HFTaxUI.BillingWindow:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2),
        w, h, player)
    ui:initialise()
    ui:instantiate()

    -- Open on the safehouse the player is standing in, rather than making them
    -- find it in the selector.
    if safehouse then
        local want = HFTax.Utils.getSafehouseKey(safehouse)
        local list = mySafehouses(player:getUsername())
        for i = 1, #list do
            if HFTax.Utils.getSafehouseKey(list[i]) == want then ui.houseIndex = i end
        end
    end

    ui:addToUIManager()
    ui:bringToTop()
    HFTaxUI.BillingWindow.instance = ui
    return ui
end

return W
