-- Cookie Mastery - client: XP capture, networking, context menus, repair action
if isServer() and not isClient() then return end

require "CMM_Shared"
require "CM_Client"
require "TimedActions/ISBaseTimedAction"

CMMC = CMMC or {}
local MOD = CMM.MOD
CMMC.listeners = CMMC.listeners or {}

local function ms()
    if getTimestampMs then return getTimestampMs() end
    return CM.now() * 1000
end
CMMC.ms = ms

-- seconds since a snapshot arrived
function CMMC.age(at)
    if not at then return 0 end
    return math.max(0, (ms() - at) / 1000)
end

function CMMC.player() return getSpecificPlayer(0) end

function CMMC.send(cmd, args)
    local p = CMMC.player()
    if not p then return end
    sendClientCommand(p, MOD, cmd, args or {})
end

function CMMC.on(fn) CMMC.listeners[#CMMC.listeners + 1] = fn end
function CMMC.emit(what)
    for i = 1, #CMMC.listeners do
        local ok, err = pcall(CMMC.listeners[i], what)
        if not ok then CMM.log("listener error: " .. tostring(err)) end
    end
end

function CMMC.txt(key, a, b, c)
    if a == nil then return getText(key) end
    if b == nil then return getText(key, tostring(a)) end
    if c == nil then return getText(key, tostring(a), tostring(b)) end
    return getText(key, tostring(a), tostring(b), tostring(c))
end
local T = CMMC.txt

function CMMC.brName(bid) return T("IGUI_CMM_Br_" .. tostring(bid or "none")) end
function CMMC.sideName(sid) return T("IGUI_CMM_Side_" .. tostring(sid)) end

-- seconds -> "3 days 4 h" / "2 h 10 min" / "5 min"
function CMMC.dur(sec)
    sec = math.max(0, math.floor(CM.num(sec, 0)))
    local d = math.floor(sec / 86400)
    local h = math.floor(CM.mod(sec, 86400) / 3600)
    local m = math.floor(CM.mod(sec, 3600) / 60)
    if d > 0 then return T("IGUI_CMM_DurD", d, h) end
    if h > 0 then return T("IGUI_CMM_DurH", h, m) end
    return T("IGUI_CMM_DurM", math.max(1, m))
end

-- whole number with thousands separators (ASCII)
function CMMC.num(n)
    n = math.floor(CM.num(n, 0) + 0.5)
    local neg = n < 0
    if neg then n = -n end
    local s = tostring(n)
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, #s - 2) .. out
        s = string.sub(s, 1, #s - 3)
    end
    out = s .. out
    if neg then out = "-" .. out end
    return out
end

function CMMC.toast(text, color, sec)
    if CMC and CMC.toast then CMC.toast(text, color, sec); return end
    local p = CMMC.player()
    if p and HaloTextHelper then pcall(function() HaloTextHelper.addText(p, text) end) end
end

-- the local snapshot: CMMC.me (server answer) and the age it was received at
function CMMC.lv()
    if not CMMC.me then return 0 end
    return (CMM.level(CMMC.me.pts))
end

function CMMC.has(bid, tier) return CMMC.me ~= nil and CMM.has(CMMC.me, bid, tier) end

-- branches this player may pick; an admin in test mode may pick any (client display only:
-- the server decides, and a host's test mode must not change what other players may pick)
function CMMC.eligible()
    if CMMC.me and CMMC.me.test then
        local all = {}
        for bid in pairs(CMM.BRANCH) do all[bid] = true end
        return all
    end
    return CMM.eligible(CMMC.player())
end

function CMMC.isAdmin()
    if CM.isSP() then return true end
    return CMMC.me ~= nil and CMMC.me.admin == true
end

-- ===================================================================== XP
-- XP is counted on the server (CMM_Server "XP capture"): in B42 the AddXP event never fires on an MP
-- client, and a perk that is full at level 10 gets no event anywhere
local function flushXp() end
CMMC.flushXp = flushXp

-- ===================================================================== server -> client
local TOAST_COLOR = { locked = "bad", notready = "bad", nobody = "bad", swapwait = "dim", bookwait = "dim",
    declined = "dim", nohammer = "bad", nomats = "bad", lvup = "good", tier = "good", picked = "good",
    newappr = "good", newmentor = "good", bookdone = "good", bookread = "good", repaired = "good", apprlv = "good",
    lastbook = "good", ann10 = "good", annhof = "good", teston = "good", testoff = "good", seal = "good" }
local DUR_ARG = { swapwait = true, bookwait = true }
local BR_ARG = { canpick = 1, locked = 1, notready = 1, picked = 1, invited = 2, bookdone = 1, bookread = 2, ann10 = 2, annhof = 2 }

local function onServerCommand(module, command, args)
    if module ~= MOD then return end
    args = args or {}
    if command == "hi" then
        CMMC.helloOk = true
    elseif command == "me" then
        CMMC.me = args
        CMMC.meAt = ms()
        CMMC.emit("me")
    elseif command == "board" then
        CMMC.board = args
        CMMC.boardAt = ms()
        CMMC.emit("board")
    elseif command == "toast" then
        local k = tostring(args.k or "")
        local a = args.a or {}
        if DUR_ARG[k] then a[1] = CMMC.dur(a[1]) end
        local bi = BR_ARG[k]
        if bi and a[bi] then a[bi] = CMMC.brName(a[bi]) end
        CMMC.toast(T("IGUI_CMM_T_" .. k, a[1], a[2], a[3]), TOAST_COLOR[k] or "text", 7)
        CMMC.emit("toast")
    end
end
Events.OnServerCommand.Add(onServerCommand)
CMMC.onServerCommand = onServerCommand

-- ===================================================================== builder T10 (local mirror)
local function fixLocalBones()
    if not CMMC.has("build", 10) then return end
    local p = CMMC.player()
    if not p then return end
    local bd = CM.call(p, "getBodyDamage")
    local parts = bd and CM.call(bd, "getBodyParts")
    if not parts then return end
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if CM.num(CM.call(bp, "getFractureTime"), 0) > 0 then
            pcall(function() bp:setFractureTime(0) end)
            pcall(function() bp:setSplintFactor(0) end)
        end
    end
end

if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function(p)
    if p == CMMC.player() then CMMC.send("dead", {}) end
end) end

-- ===================================================================== builder T5: repair action
CMMRepairAction = ISBaseTimedAction:derive("CMMRepairAction")

function CMMRepairAction:isValid()
    if not self.obj or not CM.call(self.obj, "getSquare") then return false end
    local h, m = CMM.hp(self.obj)
    return h < m
end

function CMMRepairAction:waitToStart()
    pcall(function() self.character:faceThisObject(self.obj) end)
    return CM.call(self.character, "shouldBeTurning") == true
end

function CMMRepairAction:update()
    pcall(function() self.character:faceThisObject(self.obj) end)
end

function CMMRepairAction:start()
    pcall(function() self:setActionAnim("Build") end)
    pcall(function() self.sound = self.character:playSound("Hammering") end)
end

function CMMRepairAction:stop()
    if self.sound then pcall(function() self.character:stopOrTriggerSound(self.sound) end) end
    ISBaseTimedAction.stop(self)
end

function CMMRepairAction:perform()
    if self.sound then pcall(function() self.character:stopOrTriggerSound(self.sound) end) end
    local sq = self.obj:getSquare()
    CMMC.send("repair", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), i = CMM.objIndex(self.obj) })
    ISBaseTimedAction.perform(self)
end

function CMMRepairAction:getDuration() return self.maxTime end

function CMMRepairAction:new(character, obj, time)
    local o = ISBaseTimedAction.new(self, character)
    o.obj = obj
    o.maxTime = time
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

local function hasHammer(p)
    local inv = p:getInventory()
    if CM.call(inv, "containsTagRecurse", "Hammer") == true then return true end
    local list = { "Base.Hammer", "Base.HammerStone", "Base.BallPeenHammer", "Base.ClubHammer", "Base.WoodenMallet" }
    for i = 1, #list do
        if CM.call(inv, "getFirstTypeRecurse", list[i]) then return true end
    end
    return false
end

local function startRepair(p, o)
    if luautils and luautils.walkAdj then
        local sq = o:getSquare()
        if not luautils.walkAdj(p, sq, true) then return end
    end
    local h, m = CMM.hp(o)
    local frac = m > 0 and (m - h) / m or 0
    ISTimedActionQueue.add(CMMRepairAction:new(p, o, math.floor(120 + 360 * frac)))
end

-- ===================================================================== world context menu
local function thumpsIn(worldobjects)
    local out, seen = {}, {}
    for i = 1, #worldobjects do
        local o = worldobjects[i]
        local sq = CM.call(o, "getSquare")
        local list = sq and CM.call(sq, "getObjects")
        if list then
            for j = 0, list:size() - 1 do
                local x = list:get(j)
                if CMM.isThump(x) and not seen[x] then
                    seen[x] = true
                    out[#out + 1] = x
                end
            end
        end
    end
    return out
end

local function onWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local p = getSpecificPlayer(playerNum)
    if not p or p ~= CMMC.player() then return end
    local list = thumpsIn(worldobjects)
    if #list == 0 then return end
    local inspect = CMMC.has("build", 5)
    local o = nil
    for i = 1, #list do
        local md = CM.call(list[i], "getModData")
        if (md and md.cmmBy) or inspect then o = list[i]; break end
    end
    if not o then return end
    local md = CM.call(o, "getModData") or {}
    local h, m = CMM.hp(o)
    local root = context:addOption(T("IGUI_CMM_Ctx"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    if md.cmmBy then
        local opt = sub:addOption(T("IGUI_CMM_CtxBy", md.cmmBy, CM.num(md.cmmLv, 1)), nil, nil)
        opt.notAvailable = true
    end
    if inspect then
        local opt = sub:addOption(T("IGUI_CMM_CtxHp", math.floor(h), math.floor(m)), nil, nil)
        opt.notAvailable = true
        if m > 0 and h < m then
            local planks, nails = CMM.repairCost((m - h) / m)
            local r = sub:addOption(T("IGUI_CMM_CtxRepair", planks, nails), p, startRepair, o)
            local inv = p:getInventory()
            local okMats = CM.num(CM.call(inv, "getCountTypeRecurse", "Base.Plank"), 0) >= planks
                and CM.num(CM.call(inv, "getCountTypeRecurse", "Base.Nails"), 0) >= nails
            if not hasHammer(p) or not okMats then
                r.notAvailable = true
                local tip = ISToolTip:new()
                tip:initialise()
                tip:setVisible(false)
                tip.description = T("IGUI_CMM_CtxRepairNeed", planks, nails)
                r.toolTip = tip
            end
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local ok, err = pcall(onWorldMenu, playerNum, context, worldobjects, test)
    if not ok then CMM.log("world menu error: " .. tostring(err)) end
end)

-- ===================================================================== master book (inventory menu)
local function onReadBook(item)
    CMMC.send("read", { id = item:getID() })
end

local function onInvMenu(playerNum, context, items)
    local p = getSpecificPlayer(playerNum)
    if not p then return end
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and it.items then it = it.items[1] end
        if it and CM.call(it, "getFullType") == CMM.BOOK_TYPE then
            local md = it:getModData()
            local opt = context:addOption(T("IGUI_CMM_ReadBook"), it, onReadBook)
            local tip = ISToolTip:new()
            tip:initialise()
            tip:setVisible(false)
            tip.description = T("IGUI_CMM_BookTip", md.cmmBy or "?", CMMC.brName(md.cmmBr),
                CMMC.dur(CM.num(md.cmmH, CMM.sv("BookHours")) * 3600))
            opt.toolTip = tip
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local ok, err = pcall(onInvMenu, playerNum, context, items)
    if not ok then CMM.log("inventory menu error: " .. tostring(err)) end
end)

-- ===================================================================== ticking / hello
local helloAt, helloTries, lastBones = 0, 0, 0
local function onTick()
    local t = ms()
    if not CMMC.helloOk and helloAt > 0 and t >= helloAt and helloTries < 10 and CMMC.player() then
        helloTries = helloTries + 1
        helloAt = t + 5000
        CMMC.send("hello", {})
    end
    if t - lastBones >= 1000 then
        lastBones = t
        pcall(fixLocalBones)
    end
end
Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    helloAt = ms() + 2000
    helloTries = 0
    CMMC.helloOk = false
end)

return CMMC
