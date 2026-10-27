--[[ ============================================================
  TOILEPORT  [MP]  --  Admin Panel UI                   KACHASIG
  Dark-gray clean theme, blue + red accents. Replaces the nested
  right-click admin submenus with one window:
    * STATIONS list  : rename / delete / pick which tickets it accepts
    * TICKETS list   : bind each ticket -> a destination station / clear
    * Register nearest toilet (scans around the admin)
  All edits go through the existing TP.admin* senders (SP direct /
  MP server-validated + broadcast). On syncConfig the panel refreshes.
============================================================ ]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
require "Toileport_Shared"

local TP = Toileport

ToileportPanel = ISCollapsableWindow:derive("ToileportPanel")
ToileportPanel.instance = nil

-- palette --------------------------------------------------------
local C = {
    bg       = { r = 0.086, g = 0.098, b = 0.110, a = 1.0 },  -- #16191d
    panel    = { r = 0.118, g = 0.133, b = 0.153, a = 1.0 },  -- #1e2228
    row      = { r = 0.137, g = 0.157, b = 0.184, a = 1.0 },
    rowAlt   = { r = 0.106, g = 0.122, b = 0.145, a = 1.0 },
    sel      = { r = 0.184, g = 0.369, b = 0.549, a = 1.0 },  -- blue
    border   = { r = 0.227, g = 0.251, b = 0.282, a = 1.0 },
    text     = { r = 0.847, g = 0.867, b = 0.890, a = 1.0 },
    dim      = { r = 0.486, g = 0.533, b = 0.588, a = 1.0 },
    blue     = { r = 0.239, g = 0.498, b = 0.769, a = 1.0 },  -- #3d7fc4
    red      = { r = 0.753, g = 0.271, b = 0.231, a = 1.0 },  -- #c0453b
}

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------
local function styleButton(btn, accent)
    btn.backgroundColor          = { r = 0.16, g = 0.18, b = 0.21, a = 1.0 }
    btn.backgroundColorMouseOver = { r = accent.r, g = accent.g, b = accent.b, a = 0.55 }
    btn.textColor                = { r = C.text.r, g = C.text.g, b = C.text.b, a = 1.0 }
    btn.borderColor              = { r = accent.r, g = accent.g, b = accent.b, a = 0.85 }
    return btn
end

----------------------------------------------------------------
function ToileportPanel:new(player)
    local w, h = 560, 460
    local x = getCore():getScreenWidth() * 0.5 - w * 0.5
    local y = getCore():getScreenHeight() * 0.5 - h * 0.5
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.title = "Toileport  Admin"
    o.resizable = false
    o.backgroundColor = { r = C.bg.r, g = C.bg.g, b = C.bg.b, a = 0.97 }
    o.borderColor = { r = C.border.r, g = C.border.g, b = C.border.b, a = 1.0 }
    o.selStationKey = nil
    o.selTicket = nil
    o.acceptBtns = {}
    return o
end

----------------------------------------------------------------
function ToileportPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = 12
    local top = 26
    local colW = (self.width - pad * 3) / 2
    local listH = 210

    -- STATIONS list (left)
    self.stationList = ISScrollingListBox:new(pad, top + 18, colW, listH)
    self.stationList:initialise()
    self.stationList:instantiate()
    self.stationList.itemheight = 24
    self.stationList.font = UIFont.Small
    self.stationList.drawBorder = true
    self.stationList.backgroundColor = C.panel
    self.stationList.borderColor = C.border
    self.stationList.doDrawItem = function(list, yy, item, alt) return self:drawStationRow(list, yy, item, alt) end
    self.stationList:setOnMouseDownFunction(self, self.onStationClick)
    self:addChild(self.stationList)

    -- TICKETS list (right)
    self.ticketList = ISScrollingListBox:new(pad * 2 + colW, top + 18, colW, listH)
    self.ticketList:initialise()
    self.ticketList:instantiate()
    self.ticketList.itemheight = 24
    self.ticketList.font = UIFont.Small
    self.ticketList.drawBorder = true
    self.ticketList.backgroundColor = C.panel
    self.ticketList.borderColor = C.border
    self.ticketList.doDrawItem = function(list, yy, item, alt) return self:drawTicketRow(list, yy, item, alt) end
    self.ticketList:setOnMouseDownFunction(self, self.onTicketClick)
    self:addChild(self.ticketList)

    -- station action buttons (Rename / Map toggle / Delete)
    local by = top + 18 + listH + 6
    local bw, bh = (colW - 6) / 2, 22
    local bw3 = (colW - 12) / 3
    self.btnRename = ISButton:new(pad, by, bw3, bh, "Rename", self, self.onRename)
    self.btnRename:initialise(); styleButton(self.btnRename, C.blue); self:addChild(self.btnRename)
    self.btnMap = ISButton:new(pad + bw3 + 6, by, bw3, bh, "Map", self, self.onToggleMap)
    self.btnMap:initialise(); styleButton(self.btnMap, C.blue); self:addChild(self.btnMap)
    self.btnDelete = ISButton:new(pad + (bw3 + 6) * 2, by, bw3, bh, "Delete", self, self.onDelete)
    self.btnDelete:initialise(); styleButton(self.btnDelete, C.red); self:addChild(self.btnDelete)

    -- ticket action buttons
    self.btnBind = ISButton:new(pad * 2 + colW, by, bw, bh, "Bind  ->  station", self, self.onBind)
    self.btnBind:initialise(); styleButton(self.btnBind, C.blue); self:addChild(self.btnBind)
    self.btnClear = ISButton:new(pad * 2 + colW + bw + 6, by, bw, bh, "Clear dest", self, self.onClear)
    self.btnClear:initialise(); styleButton(self.btnClear, C.red); self:addChild(self.btnClear)

    -- accept toggle row (12 small buttons)
    self.acceptY = by + bh + 24
    local cell = (self.width - pad * 2 - 5 * 6) / 6   -- 6 per row
    for i = 1, TP.TICKET_COUNT do
        local col = (i - 1) % 6
        local rowN = math.floor((i - 1) / 6)
        local bx = pad + col * (cell + 6)
        local byy = self.acceptY + rowN * (bh + 4)
        local b = ISButton:new(bx, byy, cell, bh, string.format("%02d", i), self, self.onToggleAccept)
        b:initialise(); styleButton(b, C.blue)
        b.ticketIndex = i
        self:addChild(b)
        self.acceptBtns[i] = b
    end

    -- bottom buttons
    local boty = self.height - 34
    self.btnRegister = ISButton:new(pad, boty, 180, 24, "Register nearest toilet", self, self.onRegisterNearest)
    self.btnRegister:initialise(); styleButton(self.btnRegister, C.blue); self:addChild(self.btnRegister)
    self.btnClose = ISButton:new(self.width - pad - 90, boty, 90, 24, "Close", self, self.close)
    self.btnClose:initialise(); styleButton(self.btnClose, C.red); self:addChild(self.btnClose)

    self:refresh()
end

----------------------------------------------------------------
-- row drawing
----------------------------------------------------------------
function ToileportPanel:drawStationRow(list, yy, item, alt)
    local st = item.item
    local h = list.itemheight
    local selected = (self.selStationKey == st.key)
    local bg = selected and C.sel or (alt and C.rowAlt or C.row)
    list:drawRect(0, yy, list.width, h - 1, bg.a, bg.r, bg.g, bg.b)
    list:drawText(st.name or st.key, 8, yy + 4, C.text.r, C.text.g, C.text.b, 1.0, UIFont.Small)
    local coord = "(" .. st.x .. "," .. st.y .. ")"
    local tw = getTextManager():MeasureStringX(UIFont.Small, coord)
    list:drawText(coord, list.width - tw - 8, yy + 4, C.dim.r, C.dim.g, C.dim.b, 1.0, UIFont.Small)
    return yy + h
end

function ToileportPanel:drawTicketRow(list, yy, item, alt)
    local t = item.item
    local h = list.itemheight
    local selected = (self.selTicket == t.index)
    local bg = selected and C.sel or (alt and C.rowAlt or C.row)
    list:drawRect(0, yy, list.width, h - 1, bg.a, bg.r, bg.g, bg.b)
    list:drawText(string.format("%02d", t.index), 8, yy + 4, C.text.r, C.text.g, C.text.b, 1.0, UIFont.Small)
    local destTxt, dc = "(none)", C.red
    if t.destName and t.destName ~= "" then destTxt = t.destName; dc = C.blue end
    list:drawText("->  " .. destTxt, 40, yy + 4, dc.r, dc.g, dc.b, 1.0, UIFont.Small)
    return yy + h
end

----------------------------------------------------------------
-- titlebar accent strip
----------------------------------------------------------------
function ToileportPanel:render()
    ISCollapsableWindow.render(self)
    -- thin blue/red accent under the title bar
    self:drawRect(0, 24, self.width * 0.5, 2, 1.0, C.blue.r, C.blue.g, C.blue.b)
    self:drawRect(self.width * 0.5, 24, self.width * 0.5, 2, 1.0, C.red.r, C.red.g, C.red.b)
    local pad = 12
    self:drawText("STATIONS", pad, 30, C.dim.r, C.dim.g, C.dim.b, 1.0, UIFont.Small)
    self:drawText("TICKETS", pad * 2 + (self.width - pad * 3) / 2, 30, C.dim.r, C.dim.g, C.dim.b, 1.0, UIFont.Small)
    self:drawText("Accepted tickets at selected station:", pad, self.acceptY - 18, C.dim.r, C.dim.g, C.dim.b, 1.0, UIFont.Small)
end

----------------------------------------------------------------
-- data refresh
----------------------------------------------------------------
function ToileportPanel:refresh()
    local cfg = TP.getConfig()

    -- stations
    self.stationList:clear()
    local arr = {}
    for key, st in pairs(cfg.stations or {}) do
        arr[#arr + 1] = { key = key, name = st.name, x = st.x, y = st.y, z = st.z, accepts = st.accepts }
    end
    table.sort(arr, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
    for _, st in ipairs(arr) do self.stationList:addItem(st.name or st.key, st) end

    -- tickets
    self.ticketList:clear()
    for i = 1, TP.TICKET_COUNT do
        local ft = TP.ticketFullType(i)
        local tdef = (cfg.tickets or {})[ft]
        local destName = ""
        if tdef and tdef.destKey then
            local dst = (cfg.stations or {})[tdef.destKey]
            destName = (dst and dst.name) or tdef.destKey
        end
        self.ticketList:addItem(string.format("%02d", i), { index = i, ft = ft, destName = destName })
    end

    self:refreshAcceptButtons()
end

function ToileportPanel:selectedStation()
    if not self.selStationKey then return nil end
    return TP.getStationByKey(self.selStationKey)
end

function ToileportPanel:refreshAcceptButtons()
    local st = self:selectedStation()
    if self.btnMap then
        if st then
            self.btnMap.title = (st.open ~= false) and "Map: ON" or "Map: OFF"
        else
            self.btnMap.title = "Map"
        end
    end
    for i, b in ipairs(self.acceptBtns) do
        if st then
            local ft = TP.ticketFullType(i)
            local on = TP.stationAccepts(st, ft)
            b:setEnable(true)
            local a = on and C.blue or C.dim
            b.backgroundColor = { r = a.r, g = a.g, b = a.b, a = on and 0.5 or 0.12 }
            b.borderColor     = { r = a.r, g = a.g, b = a.b, a = 0.85 }
        else
            b:setEnable(false)
            b.backgroundColor = { r = 0.12, g = 0.13, b = 0.15, a = 1.0 }
        end
    end
end

----------------------------------------------------------------
-- callbacks
----------------------------------------------------------------
-- In SP nothing broadcasts back, so refresh now; in MP the syncConfig
-- reply will call refreshIfOpen for us.
function ToileportPanel:afterEdit()
    if TP.isSP() then pcall(function() self:refresh() end) end
end

function ToileportPanel:onStationClick(item)
    if item then self.selStationKey = item.key end
    self:refreshAcceptButtons()
end

function ToileportPanel:onTicketClick(item)
    if item then self.selTicket = item.index end
end

function ToileportPanel:onBind()
    local st = self:selectedStation()
    if not (st and self.selTicket) then return end
    TP.adminSetTicketDest(self.player, TP.ticketFullType(self.selTicket), self.selStationKey, st.name)
    self:afterEdit()
end

function ToileportPanel:onClear()
    if not self.selTicket then return end
    TP.adminClearTicket(self.player, TP.ticketFullType(self.selTicket))
    self:afterEdit()
end

function ToileportPanel:onToggleAccept(button)
    local st = self:selectedStation()
    if not st then return end
    TP.adminToggleAccept(self.player, self.selStationKey, TP.ticketFullType(button.ticketIndex))
    self:afterEdit()
end

function ToileportPanel:onRename()
    local st = self:selectedStation()
    if not st then return end
    local key = self.selStationKey
    local modal = ISTextBox:new(0, 0, 280, 150, "Station name", st.name or "", nil,
        function(_, btn)
            if btn.internal == "OK" then
                TP.adminSetStationName(self.player, key, btn.parent.entry:getText())
                self:afterEdit()
            end
        end, self.player:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

function ToileportPanel:onDelete()
    if not self.selStationKey then return end
    TP.adminUnregister(self.player, self.selStationKey)
    self.selStationKey = nil
    self:afterEdit()
end

function ToileportPanel:onToggleMap()
    if not self.selStationKey then return end
    TP.adminToggleMap(self.player, self.selStationKey)
    self:afterEdit()
end

-- find a toilet on or near the admin, register it
function ToileportPanel:onRegisterNearest()
    local p = self.player
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell and cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local spr = o and o.getSprite and o:getSprite()
                    local sn = spr and spr.getName and spr:getName() or nil
                    if TP.isToiletSprite(sn) then
                        TP.adminRegister(p, sq)
                        self:afterEdit()
                        return
                    end
                end
            end
        end
    end
    if p.Say then p:Say("Toileport: no toilet within reach") end
end

function ToileportPanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ToileportPanel.instance = nil
end

----------------------------------------------------------------
-- module entry points
----------------------------------------------------------------
function ToileportPanel.open(player)
    if ToileportPanel.instance then
        ToileportPanel.instance:close()
    end
    local o = ToileportPanel:new(player)
    o:initialise()
    o:addToUIManager()
    ToileportPanel.instance = o
end

function ToileportPanel.refreshIfOpen()
    if ToileportPanel.instance and ToileportPanel.instance:getIsVisible() then
        pcall(function() ToileportPanel.instance:refresh() end)
    end
end
