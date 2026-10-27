--[[===========================================================================
    AkaShop - admin manager. Every shop on the server, the approval queue and
    the cash-register sprite whitelist.
============================================================================]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"

AkaShopAdminUI = ISCollapsableWindow:derive("AkaShopAdminUI")
AkaShopAdminUI.instance = nil

-- Colours live in AkaShop_UICommon.lua, which may load after this file, so the
-- palette is resolved on first use rather than captured at load time.
local C
local function col(name)
    if not C then C = AkaShopUI.C end
    return C[name]
end

local W, H = 1020, 640
local LIST_Y, LIST_H = 100, 316
local ROW = 424

local function drawShopRow(lb, y, item, alt)
    local d = item.item
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = AkaShop.shopName(d), x = 6 },
        { text = d.owner, x = 210, c = col("who") },
        { text = d.x .. "," .. d.y .. "," .. d.z, x = 360, c = col("dim") },
        { text = d.listings .. " items", x = 490, c = col("dim") },
        { text = "today " .. AkaShop.money(d.today), x = 580, c = col("good") },
        { text = "total " .. AkaShop.money(d.revenue), x = 690, c = col("money") },
        { text = d.enabled and "OPEN" or "CLOSED", x = 810,
          c = d.enabled and col("good") or col("bad") },
    })
end

local function drawReqRow(lb, y, item, alt)
    local d = item.item
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = "#" .. d.id, x = 6, c = col("dim") },
        { text = d.user, x = 60, c = col("who") },
        { text = AkaShop.shopBoth(d), x = 230 },
        { text = d.x .. "," .. d.y .. "," .. d.z, x = 480, c = col("dim") },
        { text = d.when or "", x = 620, c = col("dim") },
    })
end

local function drawSpriteRow(lb, y, item, alt)
    return AkaShopUI.drawColumns(lb, y, item, alt, { { text = item.item.sprite, x = 6 } })
end

local function teleportTo(x, y, z)
    AkaShopClient.teleport(x, y, z)
end

--=================================================================== build ==

function AkaShopAdminUI:new(x, y)
    local o = ISCollapsableWindow:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.title = "Traka - Admin"
    o.resizable = false
    AkaShopUI.skin(o)
    o.tabWidgets = {}
    o.tab = "Shops"
    o.data = nil
    return o
end

function AkaShopAdminUI:reg(tab, widget)
    self.tabWidgets[tab] = self.tabWidgets[tab] or {}
    table.insert(self.tabWidgets[tab], widget)
    return widget
end

function AkaShopAdminUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.lblHeader = AkaShopUI.label(self, 12, 26, "", col("title"))

    local names = { "Shops", "Requests", "Sprites" }
    self.tabButtons = {}
    local tx = 10
    for i = 1, #names do
        local n = names[i]
        self.tabButtons[n] = AkaShopUI.button(self, tx, 50, 120, 22, n, self,
            function(me) me:setTab(n) end, "tab_" .. n)
        tx = tx + 124
    end
    AkaShopUI.button(self, W - 130, 50, 120, 22, "Refresh", self, self.onRefresh)

    ---------------------------------------------------------------- Shops --
    self.shopList = self:reg("Shops",
        AkaShopUI.list(self, 10, LIST_Y, W - 20, LIST_H, drawShopRow, self))
    self:reg("Shops", AkaShopUI.button(self, 10, ROW, 150, 22, "Teleport to shop",
        self, self.onTeleportShop))
    self:reg("Shops", AkaShopUI.button(self, 170, ROW, 180, 22, "Open management",
        self, self.onManageShop))
    self:reg("Shops", AkaShopUI.button(self, 360, ROW, 160, 22, "Open / Close shop",
        self, self.onToggleShop))
    self:reg("Shops", AkaShopUI.button(self, 530, ROW, 160, 22, "Delete shop",
        self, self.onDeleteShop))
    self:reg("Shops", AkaShopUI.label(self, 12, ROW + 30,
        "Deleting a shop hands its remaining stock and till to whoever presses the button.", col("dim")))

    ------------------------------------------------------------- Requests --
    self.reqList = self:reg("Requests",
        AkaShopUI.list(self, 10, LIST_Y, W - 20, LIST_H, drawReqRow, self))
    self:reg("Requests", AkaShopUI.button(self, 10, ROW, 150, 22, "Approve",
        self, self.onApprove))
    self:reg("Requests", AkaShopUI.button(self, 170, ROW, 150, 22, "Decline",
        self, self.onDeny))
    self:reg("Requests", AkaShopUI.button(self, 330, ROW, 180, 22, "Teleport to register",
        self, self.onTeleportReq))
    self:reg("Requests", AkaShopUI.label(self, 12, ROW + 30,
        "Approving turns that cash register into a shop owned by the requesting player.", col("dim")))

    -------------------------------------------------------------- Sprites --
    self.spriteList = self:reg("Sprites",
        AkaShopUI.list(self, 10, LIST_Y, 560, LIST_H, drawSpriteRow, self))
    self:reg("Sprites", AkaShopUI.button(self, 10, ROW, 200, 22, "Remove selected",
        self, self.onRemoveSprite))
    self:reg("Sprites", AkaShopUI.label(self, 12, ROW + 30,
        "Right-click a register in the world > Traka (Admin) > 'Allow this tile to be claimed as a shop'", col("dim")))
    self:reg("Sprites", AkaShopUI.label(self, 12, ROW + 50,
        "to teach the mod about registers it does not recognise on its own (black, white, modded).", col("dim")))

    AkaShopUI.button(self, W - 110, H - 34, 100, 24, "Close", self, self.close)

    self:setTab("Shops")
end

function AkaShopAdminUI:setTab(name)
    self.tab = name
    for tab, widgets in pairs(self.tabWidgets) do
        local on = (tab == name)
        for i = 1, #widgets do widgets[i]:setVisible(on) end
    end
    for n, b in pairs(self.tabButtons) do
        AkaShopUI.setButtonActive(b, n == name)
    end
end

--================================================================ refresh ===

function AkaShopAdminUI:refresh(data)
    self.data = data or { shops = {}, requests = {}, whitelist = {} }

    local shops, todayAll, pending = self.data.shops or {}, 0, #(self.data.requests or {})
    for _, s in ipairs(shops) do todayAll = todayAll + (s.today or 0) end

    self.lblHeader:setName(string.format(
        "%d shop(s)   |   %d pending request(s)   |   sold today across all shops: %s %s",
        #shops, pending, AkaShop.money(todayAll), self.data.currency or ""))

    self.tabButtons["Requests"]:setTitle(pending > 0 and ("Requests (" .. pending .. ")")
                                                      or "Requests")

    self.shopList:clear()
    for _, s in ipairs(shops) do self.shopList:addItem(AkaShop.shopName(s), s) end

    self.reqList:clear()
    for _, r in ipairs(self.data.requests or {}) do self.reqList:addItem(r.user, r) end

    self.spriteList:clear()
    for _, sp in ipairs(self.data.whitelist or {}) do
        self.spriteList:addItem(sp, { sprite = sp })
    end
end

--================================================================ actions ===

function AkaShopAdminUI:onRefresh()
    AkaShopClient.send("adminList", {})
end

function AkaShopAdminUI:onTeleportShop()
    local s = AkaShopUI.selected(self.shopList)
    if not s then return AkaShopClient.notify("Pick a shop.", true) end
    teleportTo(s.x, s.y, s.z)
end

function AkaShopAdminUI:onManageShop()
    local s = AkaShopUI.selected(self.shopList)
    if not s then return AkaShopClient.notify("Pick a shop.", true) end
    AkaShopClient.send("open", { key = s.key, mode = "manage" })
end

function AkaShopAdminUI:onToggleShop()
    local s = AkaShopUI.selected(self.shopList)
    if not s then return AkaShopClient.notify("Pick a shop.", true) end
    -- A buying point has no open/closed state. It has always been listed here
    -- anyway, and this button silently did nothing to it.
    if s.depot then
        return AkaShopClient.notify("A buying point is always open.", true)
    end
    AkaShopClient.send("setEnabled", { key = s.key, on = not s.enabled })
    AkaShopClient.send("adminList", {})
end

--- Delete whatever the selected row actually IS.
---
--- This list has always shown buying points alongside player shops, but the
--- button only ever spoke "deleteShop" - so selecting a depot and pressing
--- Delete answered "Shop not found." and left it standing. The row already
--- carried a `depot` flag; nothing was reading it.
function AkaShopAdminUI:onDeleteShop()
    local s = AkaShopUI.selected(self.shopList)
    if not s then return AkaShopClient.notify("Pick a shop.", true) end

    local what = s.depot
        and ("Delete the buying point \"" .. AkaShop.shopName(s) ..
             "\"?\nThe tile stays where it is; only the deal goes.")
        or  ("Delete \"" .. AkaShop.shopName(s) .. "\" owned by " .. s.owner ..
             "?\nAnything still in stock comes to you.")

    AkaShopUI.confirm(what, self, function()
        AkaShopClient.send(s.depot and "depotRemove" or "deleteShop", { key = s.key })
        AkaShopClient.send("adminList", {})
    end)
end

function AkaShopAdminUI:onApprove()
    local r = AkaShopUI.selected(self.reqList)
    if not r then return AkaShopClient.notify("Pick a request.", true) end
    AkaShopClient.send("reqApprove", { id = r.id })
end

function AkaShopAdminUI:onDeny()
    local r = AkaShopUI.selected(self.reqList)
    if not r then return AkaShopClient.notify("Pick a request.", true) end
    AkaShopClient.send("reqDeny", { id = r.id })
end

function AkaShopAdminUI:onTeleportReq()
    local r = AkaShopUI.selected(self.reqList)
    if not r then return AkaShopClient.notify("Pick a request.", true) end
    teleportTo(r.x, r.y, r.z)
end

function AkaShopAdminUI:onRemoveSprite()
    local sp = AkaShopUI.selected(self.spriteList)
    if not sp then return AkaShopClient.notify("Pick a sprite.", true) end
    AkaShopClient.send("whitelistSprite", { sprite = sp.sprite, on = false })
end

--=================================================================== open ===

function AkaShopAdminUI:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if AkaShopAdminUI.instance == self then AkaShopAdminUI.instance = nil end
end

function AkaShopAdminUI.openWith(data)
    local ui = AkaShopAdminUI.instance
    if not ui then
        local x = math.max(20, (getCore():getScreenWidth() - W) / 2)
        local y = math.max(20, (getCore():getScreenHeight() - H) / 2)
        ui = AkaShopAdminUI:new(x, y)
        ui:initialise()
        ui:addToUIManager()
        AkaShopAdminUI.instance = ui
    end
    ui:setVisible(true)
    ui:bringToTop()
    ui:refresh(data)
    return ui
end
