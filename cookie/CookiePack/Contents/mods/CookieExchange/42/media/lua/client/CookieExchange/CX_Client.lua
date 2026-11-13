-- Cookie Exchange : client side
-- Shows the balance on the character screen (Info tab) with an Open wallet button, the small
-- wallet window (send / withdraw), the "Take money" menu and the background auto-convert scan.
-- The client never changes a balance: it only asks, and shows what the server sends back.

require "CookieExchange/CX_Const"
require "ISUI/ISPanel"

CX.bal = nil            -- cents, nil until the server answers hello
CX.players = {}         -- online names for the send list
CX.status = nil         -- last result line in the wallet window

local AUTO_MS = 3000
local WANT_MS = 1500
local WANT_TRIES = 4
local HELLO_RETRY_MS = 10000

local want = {}         -- id -> tries: items the player asked to take (may still be moving into the bag)
local autoSent = {}     -- id -> time sent by the scan, so one item is not sent twice while in flight
local autoSkip = {}     -- ids the server said are withdrawn bills: the scan never sends them again
local lastAuto, lastWant, helloAt = 0, 0, nil

local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return os.time() * 1000
end

local function T(key, ...) return getText(key, ...) end

local function send(cmd, args)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, CX.MOD, cmd, args or {})
end

local function halo(text, good)
    local p = getPlayer()
    if not p or type(HaloTextHelper) ~= "table" then return end
    local fn = good and HaloTextHelper.addGoodText or HaloTextHelper.addBadText
    if type(fn) == "function" then pcall(fn, p, text) end
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------------------------
-- server answers
-- ------------------------------------------------------------------------------
local R = {}

function R.wallet(a)
    CX.bal = tonumber(a.c) or 0
end

function R.earn(a)
    CX.bal = tonumber(a.c) or CX.bal
    halo("+" .. CX.money((tonumber(a.d) or 0) * 100), true)
end

function R.took(a)
    if type(a.ids) == "table" then
        for _, id in pairs(a.ids) do
            want[id] = nil
            autoSent[id] = nil
        end
    end
    if type(a.skip) == "table" then
        for _, id in pairs(a.skip) do autoSkip[id] = true end
    end
    if a.c then CX.bal = tonumber(a.c) end
    local d = tonumber(a.d) or 0
    if d > 0 then halo("+" .. CX.money(d), true) end
end

function R.got(a)
    halo(T("IGUI_CX_Got", CX.money(a.d), tostring(a.who)), true)
end

function R.players(a)
    CX.players = type(a.list) == "table" and a.list or {}
    if CX.window then CX.window:fillPlayers() end
end

function R.result(a)
    local key = tostring(a.key)
    if key == "Sent" then
        CX.status = T("IGUI_CX_Res_Sent", CX.money(a.d), tostring(a.who))
    elseif key == "Withdrawn" then
        CX.status = T("IGUI_CX_Res_Withdrawn", CX.money(a.d))
    else
        CX.status = T("IGUI_CX_Res_" .. key)
    end
    CX.statusOk = a.ok == true
    if not CX.window or not CX.window:isVisible() then halo(CX.status, CX.statusOk) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CX.MOD then return end
    local fn = R[command]
    if fn then pcall(fn, args or {}) end
end)

-- ------------------------------------------------------------------------------
-- take money
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

local function wantId(id)
    want[id] = 0
end

local function flushWant()
    local ids = {}
    for id, tries in pairs(want) do
        if tries >= WANT_TRIES then
            want[id] = nil
        else
            want[id] = tries + 1
            ids[#ids + 1] = id
            if #ids >= CX.MAX_TAKE then break end
        end
    end
    if #ids > 0 then send("take", { ids = ids }) end
end

function CX.takeItems(p, items)
    for _, item in ipairs(items) do
        local id = item:getID()
        if inMyBags(p, item) then
            wantId(id)
        else
            local src = item:getContainer()
            if src then
                local act = ISInventoryTransferAction:new(p, item, src, p:getInventory())
                if type(act.setOnComplete) == "function" then
                    act:setOnComplete(wantId, id)
                end
                ISTimedActionQueue.add(act)
            end
        end
    end
    flushWant()
    lastWant = nowMs()
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local p = getSpecificPlayer(playerNum)
    if not p or not items then return end
    local picked, seenIds, cents = {}, {}, 0
    for _, v in ipairs(items) do
        local list = (type(v) == "table" and v.items) or { v }
        for _, it in ipairs(list) do
            if it and type(it.getFullType) == "function" then
                local id = it:getID()
                local c = CX.cents(it:getFullType())
                if c and not seenIds[id] then
                    seenIds[id] = true
                    picked[#picked + 1] = it
                    cents = cents + c
                end
            end
        end
    end
    if #picked == 0 then return end
    context:addOption(T("IGUI_CX_TakeMoney") .. " (" .. CX.money(cents) .. ")", p, CX.takeItems, picked)
end)

-- background scan: vanilla cash (from loot or another mod) in the player's bags goes into the
-- wallet. Bills that came out of a wallet carry CX.FLAG and stay as cash.
local function autoScan()
    if not CX.opt("AutoConvert") or CX.bal == nil then return end
    local p = getPlayer()
    if not p or p:isDead() then return end
    local inv = p:getInventory()
    if not inv then return end
    local t = nowMs()
    for id, at in pairs(autoSent) do
        if t - at > 8000 then autoSent[id] = nil end
    end
    local ids = {}
    for _, ft in ipairs(CX.cashTypes()) do
        local ok, list = pcall(inv.getAllTypeRecurse, inv, ft)
        if ok and list then
            for i = 0, list:size() - 1 do
                local it = list:get(i)
                local id = it:getID()
                if not autoSent[id] and not autoSkip[id] and it:getModData()[CX.FLAG] ~= true then
                    ids[#ids + 1] = id
                    autoSent[id] = t
                    if #ids >= CX.MAX_TAKE then break end
                end
            end
        end
        if #ids >= CX.MAX_TAKE then break end
    end
    if #ids > 0 then send("take", { ids = ids, auto = true }) end
end

Events.OnTick.Add(function()
    local t = nowMs()
    if helloAt and CX.bal == nil and t - helloAt > HELLO_RETRY_MS then
        helloAt = t
        send("hello")
    end
    if t - lastAuto >= AUTO_MS then
        lastAuto = t
        pcall(autoScan)
    end
    if t - lastWant >= WANT_MS and count(want) > 0 then
        lastWant = t
        flushWant()
    end
end)

Events.OnGameStart.Add(function()
    helloAt = nowMs()
    send("hello")
end)

-- ------------------------------------------------------------------------------
-- character screen: two lines under "Survived for" (Wallet : $x, then the Open wallet button)
-- ------------------------------------------------------------------------------
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6

local function drawWallet(self)
    if self.char ~= getPlayer() then return end
    local z = self:getHeight()
    local text = T("IGUI_CX_Wallet") .. " : " .. (CX.bal and CX.money(CX.bal) or "...")
    self:drawText(text, 20, z, 1, 0.85, 0.4, 1, UIFont.Small)
    if not self.cxButton then
        local b = ISButton:new(0, 0, 110, BUTTON_HGT, T("IGUI_CX_OpenWallet"), self, function() CX.toggleWallet() end)
        b:initialise()
        b:instantiate()
        b.borderColor = { r = 1, g = 1, b = 1, a = 0.3 }
        self:addChild(b)
        self.cxButton = b
    end
    if not self.cxShopButton and CX.toggleShop then
        local b = ISButton:new(0, 0, 110, BUTTON_HGT, T("IGUI_CX_OpenShop"), self, function() CX.toggleShop() end)
        b:initialise()
        b:instantiate()
        b.borderColor = { r = 1, g = 0.85, b = 0.4, a = 0.5 }
        self:addChild(b)
        self.cxShopButton = b
    end
    z = z + FONT_HGT_SMALL + 6
    self.cxButton:setX(20)
    self.cxButton:setY(z)
    if self.cxShopButton then
        self.cxShopButton:setX(20 + 110 + 8)
        self.cxShopButton:setY(z)
    end
    self:setHeightAndParentHeight(z + BUTTON_HGT + 10)
end

-- hooked at game start, after every file has loaded (wrap, so other mods can wrap too)
local hooked = false
local function hookCharacterScreen()
    if hooked or not (ISCharacterScreen and ISCharacterScreen.render) then return end
    hooked = true
    local orig = ISCharacterScreen.render
    function ISCharacterScreen:render()
        orig(self)
        local ok, err = pcall(drawWallet, self)
        if not ok and not CX.drawErr then
            CX.drawErr = true
            CX.log("character screen error: " .. tostring(err))
        end
    end
end

Events.OnGameStart.Add(hookCharacterScreen)
