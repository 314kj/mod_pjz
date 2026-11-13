-- Cookie Exchange : Cookie Shop, client side
-- Keeps the catalog the server sends, the right-click menus (sell for $X, unpack a slip), the orange
-- names of things the shop buys, and applies a bought trait to the local character.
-- The client never prices anything: it sends a row id (and the price it saw) or item ids.

require "CookieExchange/CX_Const"
require "CookieExchange/CX_ShopDefs"

CX.shop = nil            -- catalog from the server: { ver, cats, items, sell, mine, admin }
CX.shopStatus = nil
CX.shopOk = false
CX.wallets = {}          -- admin list { {n, c}, ... }

local sellPrice = {}     -- fullType -> dollars
local sellNames = {}     -- display name -> true (orange in the inventory)

local function T(key, ...) return getText(key, ...) end

local function halo(text, good)
    local p = getPlayer()
    if not p or type(HaloTextHelper) ~= "table" then return end
    local fn = good and HaloTextHelper.addGoodText or HaloTextHelper.addBadText
    if type(fn) == "function" then pcall(fn, p, text) end
end

local function send(cmd, args)
    local p = getPlayer()
    if p then sendClientCommand(p, CX.MOD, cmd, args or {}) end
end
CX.shopSend = send

function CX.itemName(ft)
    local ok, n = pcall(getItemNameFromFullType, ft)
    if ok and n and n ~= "" then return n end
    return tostring(ft)
end

-- ------------------------------------------------------------------------------
-- server answers
-- ------------------------------------------------------------------------------
local R = {}

function R.catalog(a)
    CX.shop = a
    CX.shop.mine = type(a.mine) == "table" and a.mine or {}
    sellPrice, sellNames = {}, {}
    for _, s in ipairs(type(a.sell) == "table" and a.sell or {}) do
        sellPrice[s.ft] = s.price
        sellNames[CX.itemName(s.ft)] = true
    end
    if CX.shopWindow then CX.shopWindow:onCatalog() end
end

function R.shopres(a)
    local key = tostring(a.key)
    local text
    if key == "Bought" then
        text = T("IGUI_CX_Shop_Bought", tostring(a.name), CX.money(a.d))
        if CX.shop and a.id then CX.shop.mine[a.id] = tonumber(a.n) or 1 end
    elseif key == "Sold" then
        text = T("IGUI_CX_Shop_Sold", CX.money(a.d))
    elseif key == "Adjusted" then
        text = T("IGUI_CX_Shop_Adjusted", tostring(a.who), CX.money(a.d))
    elseif key == "CarReady" or key == "PetReady" then
        text = T("IGUI_CX_Shop_" .. key, tostring(a.name))
    else
        text = T("IGUI_CX_Shop_" .. key)
        if a.why then text = text .. " (" .. tostring(a.why) .. ")" end
    end
    CX.shopStatus = text
    CX.shopOk = a.ok == true
    if not CX.shopWindow or not CX.shopWindow:isVisible() then halo(text, CX.shopOk) end
end

function R.wallets(a)
    CX.wallets = type(a.list) == "table" and a.list or {}
end

-- a bought trait: the server applied it to its copy, this keeps the local character the same and
-- syncs it the way the admin trait screen does
function R.trait(a)
    local p = getPlayer()
    if not p then return end
    local ok, t = pcall(function() return CharacterTrait.get(ResourceLocation.of(tostring(a.id))) end)
    if not ok or t == nil then return end
    -- single player / host: the server half already changed this same character, do not do it twice
    local okH, has = pcall(function() return p:hasTrait(t) end)
    if okH and (has == true) == (a.add == true) then return end
    pcall(function()
        if a.add then p:getCharacterTraits():add(t) else p:getCharacterTraits():remove(t) end
    end)
    pcall(function() p:modifyTraitXPBoost(t, not a.add) end)
    if type(SyncXp) == "function" then pcall(SyncXp, p) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CX.MOD then return end
    local fn = R[command]
    if fn then pcall(fn, args or {}) end
end)

Events.OnGameStart.Add(function() send("shop") end)

-- ------------------------------------------------------------------------------
-- right-click: sell for $X / unpack a slip
-- ------------------------------------------------------------------------------
local function inMyBags(p, item)
    local cont = item:getContainer()
    if not cont then return false end
    if cont == p:getInventory() then return true end
    if type(cont.isInCharacterInventory) == "function" then
        local ok, v = pcall(cont.isInCharacterInventory, cont, p)
        if ok then return v == true end
    end
    return false
end

local function worn(p, item)
    local ok, v = pcall(function() return p:isEquipped(item) end)
    if ok and v then return true end
    ok, v = pcall(function() return item:isEquipped() end)
    return ok and v == true
end

local function doSell(ids)
    send("sell", { ids = ids })
end

local function doUnpack(id)
    send("unpack", { id = id })
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local p = getSpecificPlayer(playerNum)
    if not p or not items then return end
    local ids, seen, dollars = {}, {}, 0
    local slip = nil
    for _, v in ipairs(items) do
        local list = (type(v) == "table" and v.items) or { v }
        for _, it in ipairs(list) do
            if it and type(it.getFullType) == "function" then
                local id = it:getID()
                local ft = it:getFullType()
                if not seen[id] and inMyBags(p, it) then
                    seen[id] = true
                    local price = sellPrice[ft]
                    if price and not worn(p, it) and #ids < CX.MAX_SELL then
                        ids[#ids + 1] = id
                        dollars = dollars + price
                    end
                    if not slip and (ft == CX.SLIP_CAR or ft == CX.SLIP_PET) then slip = it end
                end
            end
        end
    end
    if #ids > 0 then
        context:addOption(T("IGUI_CX_SellFor", CX.money(dollars * 100)), ids, doSell)
    end
    if slip then
        context:addOption(T("IGUI_CX_Unpack"), slip:getID(), doUnpack)
    end
end)

-- ------------------------------------------------------------------------------
-- orange names: things the shop buys show orange in the inventory list
-- (renderdetails is wrapped; drawText is swapped on the pane only while it draws, then put back)
-- ------------------------------------------------------------------------------
local ORANGE = { r = 1, g = 0.6, b = 0.15 }

local function isSellName(text)
    if sellNames[text] then return true end
    local base = string.match(text, "^(.-) %(%d+%)$")
    return base ~= nil and sellNames[base] == true
end

local hooked = false
local function hookPane()
    if hooked or not (ISInventoryPane and ISInventoryPane.renderdetails) then return end
    hooked = true
    local orig = ISInventoryPane.renderdetails
    function ISInventoryPane:renderdetails(doDragged)
        if next(sellNames) == nil then return orig(self, doDragged) end
        local had = rawget(self, "drawText")
        local draw = had or ISInventoryPane.drawText
        self.drawText = function(s, text, x, y, r, g, b, a, font)
            if type(text) == "string" and isSellName(text) then
                return draw(s, text, x, y, ORANGE.r, ORANGE.g, ORANGE.b, a, font)
            end
            return draw(s, text, x, y, r, g, b, a, font)
        end
        local ok, err = pcall(orig, self, doDragged)
        self.drawText = had
        if not ok then error(err, 0) end
    end
end

Events.OnGameStart.Add(hookPane)
