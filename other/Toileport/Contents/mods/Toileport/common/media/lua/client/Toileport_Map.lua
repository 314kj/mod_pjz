--[[ ============================================================
  TOILEPORT  [MP]  --  world map markers                KACHASIG
  Everyone sees registered toilet stations on the world map (a
  golden-plunger pin + the station name), so players know where the
  flush-points are. Admin can hide a station with the panel's
  "On Map" toggle (station.open=false).
  Renders by wrapping ISWorldMap.render and projecting world coords
  with mapAPI:worldToUIX/Y (verified against TraderVendingMachine).
============================================================ ]]

require "ISUI/Maps/ISWorldMap"
require "Toileport_Shared"

if isServer() then return end

local TP = Toileport
local installed = false

local MARKER = 22         -- base pin size (px) at full zoom
local MIN_MARKER = 10

local function markerSize(mapAPI)
    local zoom = mapAPI and mapAPI.getZoomF and mapAPI:getZoomF() or 18.0
    if zoom >= 20 then return MARKER end
    if zoom <= 13 then return MIN_MARKER end
    local t = (zoom - 13) / (20 - 13)
    return MIN_MARKER + (MARKER - MIN_MARKER) * t
end

local function getPinTexture()
    return getTexture("Item_Toileport_Ticket")
        or getTexture("media/textures/Item_Toileport_Ticket.png")
end

local function renderMarkers(map)
    local mapAPI = map and map.mapAPI or nil
    if not mapAPI or not mapAPI.worldToUIX then return end
    local cfg = TP.getConfig()
    if not cfg or not cfg.stations then return end

    local tex = getPinTexture()
    local size = markerSize(mapAPI)
    local half = size * 0.5

    for _, st in pairs(cfg.stations) do
        if st.open ~= false and st.x and st.y then
            local ux = mapAPI:worldToUIX(st.x + 0.5, st.y + 0.5)
            local uy = mapAPI:worldToUIY(st.x + 0.5, st.y + 0.5)
            if ux and uy then
                -- only draw if inside the visible map area
                if ux >= map:getX() and ux <= map:getX() + map:getWidth()
                    and uy >= map:getY() and uy <= map:getY() + map:getHeight() then
                    if tex then
                        map:drawTextureScaled(tex, ux - half, uy - half, size, size, 1.0, 1.0, 1.0, 1.0)
                    else
                        -- fallback pin: blue square + white border
                        map:drawRect(ux - half, uy - half, size, size, 1.0, 0.24, 0.50, 0.77)
                        map:drawRectBorder(ux - half, uy - half, size, size, 1.0, 1.0, 1.0, 1.0)
                    end
                    -- name label (small, above the pin)
                    local nm = tostring(st.name or "")
                    if nm ~= "" then
                        local tw = getTextManager():MeasureStringX(UIFont.Small, nm)
                        map:drawText(nm, ux - tw * 0.5, uy - half - 14, 1.0, 1.0, 1.0, 0.95, UIFont.Small)
                    end
                end
            end
        end
    end
end

local function install()
    if installed then return end
    if not (ISWorldMap and ISWorldMap.render) then return end
    local oldRender = ISWorldMap.render
    ISWorldMap.render = function(self, ...)
        oldRender(self, ...)
        pcall(function() renderMarkers(self) end)
    end
    installed = true
    print("[Toileport] map markers installed")
end

Events.OnGameStart.Add(install)
install()
