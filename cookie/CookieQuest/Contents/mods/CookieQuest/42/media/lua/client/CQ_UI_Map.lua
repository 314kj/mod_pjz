-- Cookie Quest - world map / minimap overlay + admin "set checkpoint here" on the map
require "CQ_UI_Kit"
require "ISUI/Maps/ISWorldMap"

CQMap = CQMap or {}
local C = CQUI.C
local T = CQC.txt

CQMap.adminZones = CQMap.adminZones or nil   -- { {zone=, label=, cur=bool} } from the mission editor
CQMap.pick = CQMap.pick or nil               -- function(x, y) set by the editor when a step is selected

local function line(ui, x1, y1, x2, y2, c, a, w)
    local jo = ui.javaObject
    if jo and jo.DrawLine then
        pcall(function() jo:DrawLine(nil, x1, y1, x2, y2, w or 2, c[1], c[2], c[3], a) end)
    elseif ui.drawLine2 then
        pcall(function() ui:drawLine2(x1, y1, x2, y2, a, c[1], c[2], c[3]) end)
    end
end

local function drawZone(ui, api, zn, c, label, small)
    if not zn then return end
    local pts = { { zn.x1, zn.y1 }, { zn.x2 + 1, zn.y1 }, { zn.x2 + 1, zn.y2 + 1 }, { zn.x1, zn.y2 + 1 } }
    local sp = {}
    for i = 1, 4 do
        sp[i] = { api:worldToUIX(pts[i][1], pts[i][2]), api:worldToUIY(pts[i][1], pts[i][2]) }
    end
    for i = 1, 4 do
        local a, b = sp[i], sp[CQ.mod(i, 4) + 1]
        line(ui, a[1], a[2], b[1], b[2], c, 0.95, 2)
    end
    local cx, cy = CQ.zoneCenter(zn)
    local ux, uy = api:worldToUIX(cx + 0.5, cy + 0.5), api:worldToUIY(cx + 0.5, cy + 0.5)
    local s = small and 18 or 28
    if not CQUI.icon(ui, "cq_pin", ux - s / 2, uy - s, s, c) then
        ui:drawRect(ux - 4, uy - 4, 8, 8, 1, c[1], c[2], c[3])
    end
    if label and label ~= "" and not small then
        local fh = CQUI.fh(UIFont.Small)
        local text = CQUI.fit(label, UIFont.Small, 220)
        local tw = CQUI.tw(UIFont.Small, text) + 10
        CQUI.rbox(ui, ux - tw / 2, uy - s - fh - 6, tw, fh + 4, C.dark, 0.85, 4)
        CQUI.textC(ui, text, ux, uy - s - fh - 4, c)
    end
end

local function overlay(ui, small)
    local api = ui and ui.mapAPI
    if not api or not api.worldToUIX then return end
    local tgt = CQC.trackTarget()
    if tgt then drawZone(ui, api, tgt.zone, C.accent, (tgt.label and tgt.label ~= "") and tgt.label or tgt.title, small) end
    if CQMap.adminZones and CQC.isAdmin() then
        for i = 1, #CQMap.adminZones do
            local z = CQMap.adminZones[i]
            local col = z.cur and C.gold or (z.bad and C.bad or C.purple)
            drawZone(ui, api, z.zone, col, z.label, small)
        end
    end
end

-- world map
if ISWorldMap and not CQMap._hooked then
    CQMap._hooked = true
    local origRender = ISWorldMap.render
    ISWorldMap.render = function(self, ...)
        if origRender then origRender(self, ...) end
        local ok, err = pcall(overlay, self, false)
        if not ok then CQ.log("map overlay: " .. tostring(err)) end
    end
    local origRight = ISWorldMap.onRightMouseUp
    ISWorldMap.onRightMouseUp = function(self, x, y, ...)
        local r = nil
        if origRight then r = origRight(self, x, y, ...) end
        if CQMap.pick and CQC.isAdmin() and self.mapAPI then
            local wx = self.mapAPI:uiToWorldX(x, y)
            local wy = self.mapAPI:uiToWorldY(x, y)
            local ctx = getPlayerContextMenu and getPlayerContextMenu(0)
            local fresh = false
            if not ctx or not ctx:getIsVisible() or (ctx.numOptions or 0) <= 1 then
                ctx = ISContextMenu.get(0, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
                fresh = true
            end
            if ctx then
                ctx:addOption(T("IGUI_CQ_MapPick", math.floor(wx), math.floor(wy)), nil, function()
                    if CQMap.pick then CQMap.pick(math.floor(wx), math.floor(wy)) end
                end)
                if ctx.setAlwaysOnTop then ctx:setAlwaysOnTop(true) end
                if not fresh and ctx.bringToTop then ctx:bringToTop() end
            end
        end
        return r
    end
end

-- minimap (if present in this build)
local function hookMini()
    if CQMap._miniHooked or not ISMiniMapInner then return end
    CQMap._miniHooked = true
    local orig = ISMiniMapInner.render
    ISMiniMapInner.render = function(self, ...)
        if orig then orig(self, ...) end
        pcall(overlay, self, true)
    end
end
pcall(function() require "ISUI/Maps/ISMiniMap" end)
hookMini()
Events.OnGameStart.Add(hookMini)

return CQMap
