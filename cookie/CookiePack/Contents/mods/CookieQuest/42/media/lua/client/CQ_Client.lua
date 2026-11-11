-- Cookie Quest - client core: sync, commands, radio, reporters, navigation markers
require "CQ_Shared"
require "CQ_XP"

CQC = CQC or {}
local MOD = CQ.MOD

CQC.pub = CQC.pub or nil
CQC.me = CQC.me or nil
CQC.adm = CQC.adm or nil
CQC.skew = CQC.skew or 0
CQC.toasts = CQC.toasts or {}
CQC.radioLog = CQC.radioLog or {}
CQC.listeners = CQC.listeners or {}
CQC.cfg = CQC.cfg or {}
CQC.adminOk = CQC.adminOk or false

-- ===================================================================== small helpers
function CQC.player() return getSpecificPlayer(0) end

function CQC.send(cmd, args)
    local p = CQC.player()
    if not p then return end
    sendClientCommand(p, MOD, cmd, args or {})
end

function CQC.on(fn) CQC.listeners[#CQC.listeners + 1] = fn end

function CQC.emit(what)
    for i = 1, #CQC.listeners do
        local ok, err = pcall(CQC.listeners[i], what)
        if not ok then CQ.log("listener error: " .. tostring(err)) end
    end
end

function CQC.now() return CQ.now() + (CQC.skew or 0) end

function CQC.utc()
    return (CQC.pub and CQC.pub.utc) or (CQC.adm and CQC.adm.cfg and CQC.adm.cfg.utc) or 7
end

function CQC.txt(key, a, b, c, d)
    if a == nil then return getText(key) end
    if b == nil then return getText(key, tostring(a)) end
    if c == nil then return getText(key, tostring(a), tostring(b)) end
    if d == nil then return getText(key, tostring(a), tostring(b), tostring(c)) end
    return getText(key, tostring(a), tostring(b), tostring(c), tostring(d))
end
local T = CQC.txt

-- the server decides who is staff (role admin tool); the client only mirrors its answer
function CQC.isAdmin()
    if CQ.isSP() then return true end
    return CQC.adminOk == true
end

local itemNameCache = {}
function CQC.itemName(ft)
    if not ft or ft == "" then return "?" end
    local c = itemNameCache[ft]
    if c then return c end
    local name = ft
    local ok, it = pcall(function() return getScriptManager():FindItem(ft) end)
    if ok and it then
        local okn, dn = pcall(function() return it:getDisplayName() end)
        if okn and dn and dn ~= "" then name = dn end
    end
    itemNameCache[ft] = name
    return name
end

function CQC.itemValid(ft)
    if not ft or ft == "" then return false end
    local ok, it = pcall(function() return getScriptManager():FindItem(ft) end)
    return ok and it ~= nil
end

function CQC.itemTexture(ft)
    local ok, tex = pcall(function()
        local it = getScriptManager():FindItem(ft)
        return it and it:getNormalTexture()
    end)
    if ok then return tex end
    return nil
end

local skillCache = nil
function CQC.skills()
    if skillCache then return skillCache end
    local out = {}
    local ok = pcall(function()
        local list = PerkFactory.PerkList
        for i = 0, list:size() - 1 do
            local perk = list:get(i)
            local id = perk:getId()
            local parent = perk:getParent()
            local pid = parent and parent:getId() or "None"
            if id and id ~= "None" and pid ~= "None" then
                out[#out + 1] = { id = tostring(id), name = tostring(perk:getName() or id) }
            end
        end
    end)
    if not ok or #out == 0 then
        local fallback = { "Woodwork", "Cooking", "Farming", "Doctor", "Electricity", "MetalWelding", "Mechanics",
            "Tailoring", "Aiming", "Reloading", "Fishing", "Trapping", "PlantScavenging", "Axe", "Blunt",
            "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance", "Sprinting", "Lightfoot", "Nimble",
            "Sneak", "Fitness", "Strength" }
        out = {}
        for i = 1, #fallback do out[#out + 1] = { id = fallback[i], name = fallback[i] } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    skillCache = out
    return out
end

function CQC.skillName(id)
    for _, s in ipairs(CQC.skills()) do if string.lower(s.id) == string.lower(id) then return s.name end end
    return id
end

-- ===================================================================== client config file
local CFG_FILE = "CookieQuest_ui.txt"

function CQC.loadCfg()
    CQC.cfg = {}
    local ok = pcall(function()
        local r = getFileReader(CFG_FILE, false)
        if not r then return end
        local line = r:readLine()
        while line do
            local k, v = string.match(line, "^([%w_]+)=(.*)$")
            if k then CQC.cfg[k] = v end
            line = r:readLine()
        end
        r:close()
    end)
    if not ok then CQC.cfg = {} end
end

function CQC.saveCfg()
    pcall(function()
        local w = getFileWriter(CFG_FILE, true, false)
        if not w then return end
        for _, k in ipairs(CQ.sortedKeys(CQC.cfg)) do
            w:write(k .. "=" .. tostring(CQC.cfg[k]) .. "\n")
        end
        w:close()
    end)
end

function CQC.cfgNum(k, def) return CQ.num(CQC.cfg[k], def) end
function CQC.cfgSet(k, v) CQC.cfg[k] = v; CQC.saveCfg() end

-- ===================================================================== toasts
function CQC.toastText(kind, a)
    a = a or {}
    if kind == "err" then return T("IGUI_CQ_Err_" .. tostring(a[1] or "x")) end
    if kind == "items" then
        local why = T("IGUI_CQ_Why_" .. tostring(a[1] or "kit"))
        return T("IGUI_CQ_T_items", why, a[2] or "0")
    end
    if kind == "cp" then
        local label = a[2]
        if not label or label == "" then label = T("IGUI_CQ_StepT_" .. tostring(a[5] or "reach")) end
        return T("IGUI_CQ_T_cp", label, a[3] or "?", a[4] or "?")
    end
    if kind == "phase" or kind == "myphase" then
        local nm = (a[2] and a[2] ~= "") and (" - " .. a[2]) or ""
        return T("IGUI_CQ_T_" .. kind, a[1] or "?", nm)
    end
    return T("IGUI_CQ_T_" .. tostring(kind), a[1] or "", a[2] or "", a[3] or "", a[4] or "")
end

local TOAST_STYLE = {
    cp = "good", mdone = "gold", mnew = "accent", mglobal = "accent", evstart = "accent", evend = "dim",
    evopen = "accent", items = "good", pen = "bad", penclear = "good", err = "bad", joined = "good",
    left = "dim", mfail = "bad", buffon = "gold", sheet = "dim", radio = "radio", phase = "gold", myphase = "accent", mcancel = "dim",
}

function CQC.pushToast(kind, text, sub)
    table.insert(CQC.toasts, { kind = kind, style = TOAST_STYLE[kind] or "accent", text = text, sub = sub, ms = getTimestampMs() })
    while #CQC.toasts > 5 do table.remove(CQC.toasts, 1) end
    if kind == "mdone" or kind == "evstart" or kind == "phase" or kind == "myphase" then
        pcall(function() getSoundManager():playUISound("UIActivateButton") end)
    end
end

-- ===================================================================== server commands
local function onServerCommand(module, command, args)
    if module ~= MOD then return end
    args = args or {}
    if command == "pub" then
        CQC.pub = args
        if args.now then CQC.skew = args.now - CQ.now() end
        CQC.emit("pub")
    elseif command == "me" then
        CQC.me = args
        if args.now then CQC.skew = args.now - CQ.now() end
        CQC.autoTrack()
        CQC.emit("me")
    elseif command == "adm" then
        CQC.adm = args
        CQC.adminOk = true
        CQC.emit("adm")
    elseif command == "isadm" then
        CQC.adminOk = args.ok == true
        if not CQC.adminOk then
            CQC.adm = nil
            if CQAdmin and CQAdmin.win then pcall(function() CQAdmin.win:close() end) end
        end
        CQC.emit("isadm")
    elseif command == "toast" then
        local text = CQC.toastText(args.k, args.a)
        local sub = nil
        if args.k == "cp" then sub = args.a and args.a[1] end
        if args.k == "mdone" and args.a and args.a[2] and args.a[2] ~= "" then sub = args.a[2] end
        CQC.pushToast(args.k, text, sub)
        CQC.emit("toast")
    elseif command == "saved" then
        CQC.emit("saved:" .. tostring(args.kind) .. ":" .. tostring(args.id))
    elseif command == "sheet" then
        CQC.sheetView = args
        CQC.emit("sheet")
    elseif command == "srvxp" then
        CQ.XP.setServerHandled()
    elseif command == "xpn" then
        CQC.pushXpNote(args)
    end
end
Events.OnServerCommand.Add(onServerCommand)
CQC.onServerCommand = onServerCommand

-- ===================================================================== missions helpers
function CQC.activeInst()
    local out = {}
    if not CQC.me or not CQC.me.inst then return out end
    for _, v in ipairs(CQC.me.inst) do if v.status == "active" then out[#out + 1] = v end end
    return out
end

function CQC.instById(iid)
    if not CQC.me or not CQC.me.inst then return nil end
    for _, v in ipairs(CQC.me.inst) do if v.id == iid then return v end end
    return nil
end

function CQC.curStep(inst)
    if not inst or not inst.steps then return nil end
    return inst.steps[inst.step]
end

function CQC.autoTrack()
    local cur = CQC.cfg.track
    local inst = cur and CQC.instById(cur)
    if inst and inst.status == "active" then return end
    local act = CQC.activeInst()
    if CQC.cfg.trackOff == "1" then return end
    if #act > 0 then
        CQC.cfg.track = act[1].id
    else
        CQC.cfg.track = nil
    end
end

function CQC.setTrack(iid)
    if iid then CQC.cfg.trackOff = nil else CQC.cfg.trackOff = "1" end
    CQC.cfg.track = iid
    CQC.saveCfg()
    CQC.emit("track")
end

-- world target {x,y,z,w,h,label,title} for the tracked mission, or nil
function CQC.trackTarget()
    local inst = CQC.cfg.track and CQC.instById(CQC.cfg.track)
    if not inst or inst.status ~= "active" then return nil end
    local st = CQC.curStep(inst)
    if not st or not st.zone then return nil end
    local cx, cy = CQ.zoneCenter(st.zone)
    return { x = cx, y = cy, z = st.zone.z or 0, w = CQ.zoneW(st.zone), h = CQ.zoneH(st.zone), zone = st.zone,
        label = st.label, title = inst.title, t = st.t, iid = inst.id }
end

-- ===================================================================== navigation markers (vanilla WorldMarkers)
local MK = { homing = nil, ground = nil, key = nil, retry = 0 }

local function clearMarkers()
    if MK.homing then pcall(function() MK.homing:remove() end) end
    if MK.ground then pcall(function() MK.ground:remove() end) end
    MK.homing, MK.ground = nil, nil
end
CQC.clearMarkers = clearMarkers

local function worldMarkers()
    if getWorldMarkers then
        local ok, wm = pcall(getWorldMarkers)
        if ok and wm then return wm end
    end
    return nil
end

function CQC.updateMarkers()
    local p = CQC.player()
    local tgt = (CQC.cfg.navOff ~= "1") and CQC.trackTarget() or nil
    if not p or p:isDead() then tgt = nil end
    local key = tgt and (tostring(tgt.x) .. "," .. tostring(tgt.y) .. "," .. tostring(tgt.z) .. "," .. tostring(tgt.w) .. "," .. tostring(tgt.h)) or nil
    if key ~= MK.key then
        clearMarkers()
        MK.key = key
        MK.retry = 0
        if tgt then
            local wm = worldMarkers()
            if wm then
                local ok, hp = pcall(function() return wm:addPlayerHomingPoint(p, tgt.x, tgt.y, 1.0, 0.62, 0.24, 1.0) end)
                if ok then MK.homing = hp end
            end
            if CQC.cfg.track and CQC.navigatorReady() and p:getVehicle() then CQC.routeWithNavigator(true) end
        end
    end
    if tgt and not MK.ground then
        MK.retry = MK.retry - 1
        if MK.retry <= 0 then
            MK.retry = 5
            local wm = worldMarkers()
            local sq = getCell() and getCell():getGridSquare(tgt.x, tgt.y, tgt.z)
            if wm and sq then
                local size = math.max(1, math.min(12, math.max(tgt.w, tgt.h) * 0.55))
                local ok, gm = pcall(function() return wm:addGridSquareMarker(sq, 1.0, 0.62, 0.24, true, size) end)
                if ok then MK.ground = gm end
            end
        end
    end
end

-- optional: route in the "Navigator" car GPS mod when it is installed
function CQC.navigatorReady()
    if CQC._nav == nil then
        CQC._nav = false
        local active = false
        pcall(function()
            local mods = getActivatedMods()
            active = mods:contains("Navigator") or mods:contains("\\Navigator")
        end)
        if active then
            local ok, api = pcall(require, "Navigator/API/RouteAPI")
            if ok and type(api) == "table" and type(api.SetDestination) == "function" then CQC._nav = api end
        end
    end
    return CQC._nav ~= false and CQC._nav ~= nil
end

function CQC.routeWithNavigator(silent)
    if not CQC.navigatorReady() then
        if not silent then CQC.pushToast("err", T("IGUI_CQ_NavMissing")) end
        return false
    end
    local tgt = CQC.trackTarget()
    if not tgt then return false end
    local ok, route = pcall(CQC._nav.SetDestination, tgt.x, tgt.y)
    if not silent then
        if ok and route then CQC.pushToast("joined", T("IGUI_CQ_NavRouted")) else CQC.pushToast("err", T("IGUI_CQ_NavNoRoute")) end
    end
    return ok and route ~= nil
end

-- ===================================================================== radio
local function deviceTuned(dd, out)
    if not dd then return end
    local ok, on = pcall(function() return dd:getIsTurnedOn() end)
    if ok and on then
        local okc, ch = pcall(function() return dd:getChannel() end)
        if okc and type(ch) == "number" then out[#out + 1] = ch end
    end
end

function CQC.tunedChannels(p)
    local out = {}
    if not p then return out end
    local function fromItem(it)
        if it and it.getDeviceData then
            local ok, dd = pcall(function() return it:getDeviceData() end)
            if ok then deviceTuned(dd, out) end
        end
    end
    fromItem(p:getPrimaryHandItem())
    fromItem(p:getSecondaryHandItem())
    pcall(function()
        local items = p:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if instanceof(it, "Radio") then fromItem(it) end
        end
    end)
    pcall(function()
        local v = p:getVehicle()
        if v then
            local part = v:getPartById("Radio")
            if part then deviceTuned(part:getDeviceData(), out) end
        end
    end)
    pcall(function()
        local cell = getCell()
        local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        for dx = -3, 3 do
            for dy = -3, 3 do
                local sq = cell:getGridSquare(x + dx, y + dy, z)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local o = objs:get(i)
                        if o and o.getDeviceData then
                            local ok, dd = pcall(function() return o:getDeviceData() end)
                            if ok then deviceTuned(dd, out) end
                        end
                    end
                end
            end
        end
    end)
    return out
end

local radioSlots = {}
local radioReported = {}

local function radioTick()
    local p = CQC.player()
    if not p or p:isDead() then return end
    local tuned = CQC.tunedChannels(p)
    CQC.lastTuned = tuned
    local sig = table.concat(tuned, ",")
    if sig ~= CQC.lastTunedSig then
        CQC.lastTunedSig = sig
        CQ.log("radio tuned: " .. (sig ~= "" and sig or "none"))
    end
    if #tuned == 0 then return end
    local t = CQC.now()
    -- broadcast lines
    local chans = (CQC.pub and CQC.pub.radio) or {}
    for _, r in ipairs(chans) do
        for _, ch in ipairs(tuned) do
            if math.abs(ch - r.ch) <= 100 then
                local idx, line, slot = CQ.radioLine(r, t)
                if line and radioSlots[r.id] ~= slot then
                    radioSlots[r.id] = slot
                    local c = CQ.RADIO_COLORS[r.color or 1] or CQ.RADIO_COLORS[1]
                    -- over the head like a vanilla broadcast; a screen toast only if the build cannot project
                    if CQRT and CQRT.available and CQRT.available() then
                        CQRT.ensure()
                        CQRT.add(line, c)
                    else
                        CQC.pushToast("radio", line, CQ.chText(r.ch) .. " MHz")
                    end
                    table.insert(CQC.radioLog, 1, { ch = r.ch, text = line, t = t, color = r.color })
                    while #CQC.radioLog > 12 do table.remove(CQC.radioLog) end
                    CQC.emit("radio")
                end
                break
            end
        end
    end
    -- radio steps
    for _, inst in ipairs(CQC.activeInst()) do
        local st = CQC.curStep(inst)
        if st and st.t == "radio" and st.ch then
            for _, ch in ipairs(tuned) do
                if math.abs(ch - st.ch) <= 100 then
                    local last = radioReported[inst.id .. ":" .. tostring(inst.step)]
                    if not last or t - last > 8 then
                        radioReported[inst.id .. ":" .. tostring(inst.step)] = t
                        CQC.send("radio", { ch = ch })
                    end
                end
            end
        end
    end
end

-- ===================================================================== collect reporter
local collectSent = {}

local function collectTick()
    local p = CQC.player()
    if not p or p:isDead() then return end
    for _, inst in ipairs(CQC.activeInst()) do
        local st = CQC.curStep(inst)
        if st and st.t == "collect" and st.item and st.item ~= "" then
            local n = 0
            pcall(function() n = p:getInventory():getCountTypeRecurse(st.item) or 0 end)
            local key = inst.id .. ":" .. tostring(inst.step)
            if collectSent[key] ~= n then
                collectSent[key] = n
                CQC.send("collect", { iid = inst.id, n = n })
            end
        end
    end
end

-- ===================================================================== XP notes (admin self-check)
CQC.xpNotes = CQC.xpNotes or {}
function CQC.pushXpNote(n)
    if type(n) ~= "table" then return end
    table.insert(CQC.xpNotes, 1, { pid = n.pid, base = n.base, bonus = n.bonus, mult = n.mult, side = n.side, t = CQC.now() })
    while #CQC.xpNotes > 5 do table.remove(CQC.xpNotes) end
    CQC.emit("xpn")
end

-- ===================================================================== XP provider (client fallback)
if not CQ.isSP() then
    CQ.XP.onNote = function(p, n) CQC.pushXpNote(n) end
end

CQ.XP.provider = function(p, pid)
    local t = CQC.now()
    local buffs = CQC.pub and CQC.pub.buffs or {}
    local pen = CQC.me and CQC.me.pen or nil
    return CQ.multFor(pid, buffs, pen, t)
end

-- ===================================================================== ticking / lifecycle
local helloAt, helloTries, tickN = 0, 0, 0
local lastRadio, lastCollect, lastMarker = 0, 0, 0

local function onTick()
    local p = CQC.player()
    if not p then return end
    local ms = getTimestampMs()
    if ms < lastMarker then lastRadio, lastCollect, lastMarker = 0, 0, 0 end
    if not CQC.pub and ms >= helloAt and helloTries < 8 then
        helloTries = helloTries + 1
        helloAt = ms + 5000
        CQC.send("hello", {})
    end
    if ms - lastRadio >= 2000 then
        lastRadio = ms
        local ok, err = pcall(radioTick)
        if not ok then CQ.log("radio error: " .. tostring(err)) end
    end
    if ms - lastCollect >= 3000 then
        lastCollect = ms
        local ok, err = pcall(collectTick)
        if not ok then CQ.log("collect error: " .. tostring(err)) end
    end
    if ms - lastMarker >= 1000 then
        lastMarker = ms
        local ok, err = pcall(CQC.updateMarkers)
        if not ok then CQ.log("marker error: " .. tostring(err)) end
    end
end

local function onGameStart()
    CQC.loadCfg()
    helloAt = getTimestampMs() + 1500
    helloTries = 0
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(p)
        if p and p == CQC.player() then
            CQC.send("died", {})
            clearMarkers()
            MK.key = nil
        end
    end)
end

CQC.loadCfg()

return CQC
