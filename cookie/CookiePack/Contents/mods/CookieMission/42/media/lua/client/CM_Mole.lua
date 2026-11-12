-- Cookie Mission - mole on the client: cookie dolls pop up on floor squares of the building (drawn here,
-- never items), right-click one within reach to whack it; the server checks reach and that the doll is still up
require "CM_Client"
require "TimedActions/ISBaseTimedAction"

CMMole = CMMole or {}
local T = CMC.txt

local GOLD = { 1.00, 0.78, 0.30 }
local RED = { 1.00, 0.25, 0.25 }

function CMMole.run()
    local run = CMC.run()
    if run and run.phase == "live" and run.type == "mole" then return run end
    return nil
end

local function dist(p, o)
    local dx, dy = p:getX() - (o.x + 0.5), p:getY() - (o.y + 0.5)
    return math.sqrt(dx * dx + dy * dy)
end

function CMMole.nearest(run)
    local p = CMC.player()
    if not p or not run or not run.moles then return nil end
    local pz = math.floor(p:getZ())
    local best, bestD = nil, 999999
    for _, o in ipairs(run.moles) do
        if not o.red then
            local d = dist(p, o) + math.abs(o.z - pz) * 12
            if d < bestD then best, bestD = o, d end
        end
    end
    return best, bestD
end

-- ===================================================================== drawing (every frame, like the CookieHelper marks)
local function drawLabel(x, y, s, c)
    local tm = getTextManager()
    tm:DrawStringCentre(UIFont.Medium, x + 1, y + 1, s, 0, 0, 0, 0.85)
    tm:DrawStringCentre(UIFont.Medium, x, y, s, c[1], c[2], c[3], 1)
end

local function overlay()
    local run = CMMole.run()
    if not run or not run.moles or #run.moles == 0 then return end
    local p = CMC.player()
    if not p then return end
    local pz = math.floor(p:getZ())
    local zoom = getCore():getZoom(0)
    local pulse = 0.35 + 0.25 * math.abs(math.sin(CMC.ms() / 260))
    for _, o in ipairs(run.moles) do
        if o.z == pz and dist(p, o) < 45 then
            local c = o.red and RED or GOLD
            addAreaHighlight(o.x, o.y, o.x + 1, o.y + 1, o.z, c[1], c[2], c[3], pulse)
            local sx = isoToScreenX(0, o.x + 0.5, o.y + 0.5, o.z)
            local sy = isoToScreenY(0, o.x + 0.5, o.y + 0.5, o.z)
            local key = o.red and "IGUI_CM_Mole_red" or "IGUI_CM_Mole_doll"
            drawLabel(sx, sy - 70 / zoom, T(key), c)
        end
    end
end

Events.OnPreUIDraw.Add(function()
    local ok, err = pcall(overlay)
    if not ok then CM.log("mole overlay error: " .. tostring(err)) end
end)

-- ===================================================================== whack: walk next to it, then tell the server
CMMoleStep = ISBaseTimedAction:derive("CMMoleStep")

function CMMoleStep:isValid() return CMMole.run() ~= nil end
function CMMoleStep:update() end
function CMMoleStep:start()
    pcall(function() self:setActionAnim("Loot") end)
    pcall(function() self.character:SetVariable("LootPosition", "Low") end)
end
function CMMoleStep:stop() ISBaseTimedAction.stop(self) end
function CMMoleStep:perform()
    local run = CMMole.run()
    if run then CMC.send("whack", { run = run.id, i = self.i }) end
    ISBaseTimedAction.perform(self)
end
function CMMoleStep:new(character, i)
    local o = ISBaseTimedAction.new(self, character)
    o.i = i
    o.maxTime = 12
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function CMMole.whack(o)
    local p = CMC.player()
    if not p or not o then return end
    local reach = CM.gameVal("mole", "reach") or 2
    if dist(p, o) > reach + 0.3 or math.floor(p:getZ()) ~= o.z then
        local sq = getCell() and getCell():getGridSquare(o.x, o.y, o.z)
        local walked = false
        if sq and luautils and luautils.walkAdj then
            local ok, r = pcall(luautils.walkAdj, p, sq, false)
            walked = ok and r == true
        end
        if not walked then CMC.toast(T("IGUI_CM_T_tnoreach"), "bad", 4); return end
    else
        pcall(function() ISTimedActionQueue.clear(p) end)
    end
    ISTimedActionQueue.add(CMMoleStep:new(p, o.i))
end

local function onFillWorld(playerNum, context, worldobjects, test)
    if test then return end
    local run = CMMole.run()
    if not run or not run.moles or #run.moles == 0 then return end
    local hit = nil
    for _, wo in ipairs(worldobjects or {}) do
        local sq = CM.call(wo, "getSquare")
        if sq then
            local x, y, z = CM.call(sq, "getX"), CM.call(sq, "getY"), CM.call(sq, "getZ")
            for _, o in ipairs(run.moles) do
                if o.z == z and math.abs(o.x - x) <= 1 and math.abs(o.y - y) <= 1 then
                    if not hit or (o.x == x and o.y == y) then hit = o end
                end
            end
        end
    end
    if not hit then return end
    local fn = function() CMMole.whack(hit) end
    local label = T("IGUI_CM_Mole_whack")
    local ok = pcall(function() context:addOptionOnTop(label, nil, fn) end)
    if not ok then pcall(function() context:addOption(label, nil, fn) end) end
end
if Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
        local ok, err = pcall(onFillWorld, playerNum, context, worldobjects, test)
        if not ok then CM.log("mole context error: " .. tostring(err)) end
    end)
end

-- the server took the doll: drop it here at once instead of waiting for the next tracker update
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CM.MOD or command ~= "mpop" then return end
    local run = CMMole.run()
    if not run or not run.moles then return end
    local i = CM.int((args or {}).i, 0)
    for n = #run.moles, 1, -1 do
        if run.moles[n].i == i then table.remove(run.moles, n) end
    end
    pcall(function() getSoundManager():playUISound((args or {}).red and "UIActivateMainMenuItem" or "UIActivateButton") end)
end)

-- ===================================================================== HUD line (called from the tracker)
function CMMole.drawHud(win, x, y, w, run)
    local S = CMUI.S
    local C = CMUI.C
    local lh = CMUI.fh(UIFont.Small) + S(4)
    local p = CMC.player()
    if not p then return y end
    local o = CMMole.nearest(run)
    if not o then
        CMUI.text(win, CMUI.fit(T("IGUI_CM_Mole_wait"), UIFont.Small, w), x, y, C.dim)
        return y + lh
    end
    local d = dist(p, o)
    local s = T("IGUI_CM_Mole_next", T("IGUI_CM_Dir_" .. CMHud.dirOf(o.x + 0.5 - p:getX(), o.y + 0.5 - p:getY())), math.floor(d))
    local pz = math.floor(p:getZ())
    if o.z ~= pz then s = s .. T("IGUI_CM_Task_floor", o.z + 1) end
    CMUI.text(win, CMUI.fit(s, UIFont.Small, w), x, y, GOLD)
    y = y + lh
    CMUI.text(win, CMUI.fit(T("IGUI_CM_Mole_hint"), UIFont.Small, w), x, y, C.faint)
    return y + lh
end

return CMMole
