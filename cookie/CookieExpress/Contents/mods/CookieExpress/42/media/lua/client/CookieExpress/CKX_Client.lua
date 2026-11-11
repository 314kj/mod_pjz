-- Cookie Express : client glue (net, text, item info, slip context menu)
if isServer() then return end

require "CookieExpress/CKX_Shared"

CKX.Cl = CKX.Cl or {}
local Cl = CKX.Cl
Cl.entries = {}
Cl.count = 0
Cl.helloAt = nil

-- English fallback when a translation key is missing (Thai lives in Translate/TH/UI.json)
Cl.EN = {
    Subtitle = "Your delivery is here! Claim items one by one, or all at once.",
    Claim = "Claim",
    ClaimAll = "Claim all (%1)",
    Later = "Later",
    Waiting = "%1 waiting",
    Empty = "Nothing to deliver right now",
    Got = "Received: %1",
    GotMore = "Received: %1 +%2 more",
    Failed = "Delivery failed, please tell an admin",
    SlipPrefix = "Vehicle Slip: %1",
    SlipLine = "Vehicle slip: %1",
    UseSlip = "Call this vehicle",
    SlipDone = "Your %1 has arrived!",
    Slip_outside = "Go outside to an open ground-floor area first",
    Slip_nospace = "Not enough open space here, try a wider spot",
    Slip_invehicle = "Get out of the vehicle first",
    Slip_used = "This slip was already used",
    Slip_invalid = "This slip is not valid",
    Slip_failed = "Could not call the vehicle, please tell an admin",
    Tip = "Cookie Express",
    SplashTitle = "Your delivery is here!",
    SplashCount = "%1 item(s) waiting for you",
    SplashGo = "Open the box",
    SplashHint = "(click anywhere)",
}

local function replace1(s, token, value)
    local a = string.find(s, token, 1, true)
    if not a then return s end
    return string.sub(s, 1, a - 1) .. value .. string.sub(s, a + #token)
end

function Cl.txt(k, a1, a2)
    local key = "UI_CKX_" .. k
    local t
    if a2 ~= nil then t = getText(key, tostring(a1), tostring(a2))
    elseif a1 ~= nil then t = getText(key, tostring(a1))
    else t = getText(key) end
    if not t or t == key then
        t = Cl.EN[k] or k
        if a1 ~= nil then t = replace1(t, "%1", tostring(a1)) end
        if a2 ~= nil then t = replace1(t, "%2", tostring(a2)) end
    end
    return t
end

-- ------------------------------------------------------------------ item info
Cl.info = {}

local function vehicleName(fullName)
    local short = fullName
    local ok, script = pcall(function() return getScriptManager():getVehicle(fullName) end)
    if ok and script then short = script:getName() end
    local key = "IGUI_VehicleName" .. tostring(short)
    local t = getText(key)
    if t and t ~= key then return t end
    return short
end

function Cl.itemInfo(kind, ft)
    local k = kind .. ":" .. ft
    local inf = Cl.info[k]
    if inf then return inf end
    inf = { name = ft, tex = nil }
    if kind == "v" then
        inf.name = vehicleName(ft)
        inf.tex = CKX.T and CKX.T.tex("ckx_slip")
    else
        local si = getScriptManager():FindItem(ft)
        local ok, n = pcall(getItemNameFromFullType, ft)
        if ok and n and n ~= "" then inf.name = n
        elseif si then inf.name = si:getDisplayName() end
        if si then
            local okT, t = pcall(function() return si:getNormalTexture() end)
            if okT and t then inf.tex = t end
        end
        if not inf.tex then
            local okI, item = pcall(instanceItem, ft)
            if okI and item then
                local okT2, t2 = pcall(function() return item:getTex() end)
                if okT2 then inf.tex = t2 end
                if inf.name == ft then inf.name = item:getDisplayName() end
            end
        end
    end
    Cl.info[k] = inf
    return inf
end

-- ------------------------------------------------------------------ net
local function toArray(t)
    local keys, out = {}, {}
    if type(t) ~= "table" then return out end
    for k, _ in pairs(t) do
        if type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = t[k] end
    return out
end

function Cl.onCommand(cmd, args)
    args = args or {}
    if cmd == "list" then
        Cl.entries = toArray(args.items)
        Cl.count = #Cl.entries
        if CKX.UI then
            CKX.UI.refresh()
            if (args.reason == "arrive" or args.reason == "login") and Cl.count > 0 and args.autoPopup ~= false then
                if args.splash ~= false and CKX.UI.splash then
                    CKX.UI.splash(Cl.count)
                else
                    CKX.UI.open(args.reason == "arrive")
                end
            end
        end
    elseif cmd == "claimed" then
        if CKX.UI then CKX.UI.onClaimed(args.ok, toArray(args.got), args.fails or 0) end
    elseif cmd == "slip" then
        local known = { outside = 1, nospace = 1, invehicle = 1, used = 1, invalid = 1, failed = 1 }
        local key = "slip_done"
        if not args.ok then key = known[tostring(args.why)] and ("slip_" .. tostring(args.why)) or "slip_failed" end
        if CKX.UI and CKX.UI.toast then CKX.UI.toast("pink", { key }) end
        if args.ok then CKX.T.playSound("UIToggleTickBox") end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == CKX.NET then Cl.onCommand(command, args) end
end)

-- say hello a few seconds after entering the world (and after respawn)
local function scheduleHello()
    Cl.helloAt = CKX.nowMs() + 3000
end

Events.OnGameStart.Add(scheduleHello)
Events.OnCreatePlayer.Add(function(idx) if idx == 0 then scheduleHello() end end)
Events.OnTick.Add(function()
    if Cl.helloAt and CKX.nowMs() >= Cl.helloAt then
        Cl.helloAt = nil
        CKX.toServer("hello", {})
    end
end)

-- ------------------------------------------------------------------ vehicle slip context menu
function Cl.useSlip(item, player)
    if not item then return end
    CKX.toServer("useSlip", { id = item:getID() })
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local slip = nil
    for _, v in ipairs(items) do
        local it = v
        if not instanceof(v, "InventoryItem") and type(v) == "table" and v.items then it = v.items[1] end
        if it and instanceof(it, "InventoryItem") and it:getFullType() == CKX.SLIP then
            slip = it
            break
        end
    end
    if not slip then return end
    local player = getSpecificPlayer(playerNum)
    local opt = context:addOption(Cl.txt("UseSlip"), slip, Cl.useSlip, player)
    local md = slip:getModData()
    if md and md.ckx_v then
        local tip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip()
        if tip then
            tip.description = vehicleName(md.ckx_v)
            opt.toolTip = tip
        end
    end
end)
