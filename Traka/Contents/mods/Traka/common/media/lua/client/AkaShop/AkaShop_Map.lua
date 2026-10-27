--[[===========================================================================
    AkaShop - draw every known shop on the world map.

    Markers are painted as an overlay on top of ISWorldMap rather than pushed
    into the vanilla symbols API, because vanilla symbols are saved into the
    player's map data: a shop that later closes or moves would leave a stale
    scribble behind forever. Drawing every frame from the live shop index means
    the map is always exactly as current as the index is.
============================================================================]]

AkaShopMap = AkaShopMap or {}

-- Kept as a kill switch only: the overlay sets it to false and stays quiet if
-- it ever throws, so a broken frame cannot spam the log or block the map. There
-- is no button and no sandbox option any more - shops are simply shown.
AkaShopMap.enabled  = true
AkaShopMap.MAX_DRAW = 120       -- never paint more than this many plates

local PLATE_A   = 0.88
local PIN       = 5             -- half-size of the marker square
local installed = false

--=============================================================== projection =

local function mapAPI(ui)
    local api
    if ui and ui.javaObject and pcall(function() api = ui.javaObject:getAPIv1() end) then
        return api
    end
    return nil
end

-- Which projection the running build actually offers is decided once, on the
-- first successful draw, and then reused. `worldToUIX` is the documented pair;
-- the manual fallback covers builds that only expose the centre + zoom.
local projector = nil

local function tryDirect(api, wx, wy)
    local sx, sy
    local ok = pcall(function()
        sx = api:worldToUIX(wx, wy)
        sy = api:worldToUIY(wx, wy)
    end)
    if ok and type(sx) == "number" and type(sy) == "number" then return sx, sy end
    return nil
end

local function tryManual(api, wx, wy, ui)
    local cx, cy, zoom
    local ok = pcall(function()
        cx   = api:getCenterWorldX()
        cy   = api:getCenterWorldY()
        zoom = api:getWorldScale()
    end)
    if not ok or type(cx) ~= "number" or type(zoom) ~= "number" or zoom == 0 then
        return nil
    end
    return (wx - cx) * zoom + ui:getWidth() / 2,
           (wy - cy) * zoom + ui:getHeight() / 2
end

--- World tile -> on-screen UI coordinates, or nil when the map cannot say.
local function project(api, wx, wy, ui)
    if projector == "direct" then return tryDirect(api, wx, wy) end
    if projector == "manual" then return tryManual(api, wx, wy, ui) end

    local sx, sy = tryDirect(api, wx, wy)
    if sx then projector = "direct"; print("[Traka] map projection: worldToUIX/Y")
        return sx, sy end
    sx, sy = tryManual(api, wx, wy, ui)
    if sx then projector = "manual"; print("[Traka] map projection: centre + scale")
        return sx, sy end
    return nil
end

--- Print what the map API on this build actually exposes, so an unexpected
--- signature can be identified from a single console line instead of guesswork.
local function reportAPI(api)
    local names = { "worldToUIX", "worldToUIY", "uiToWorldX", "uiToWorldY",
                    "getCenterWorldX", "getCenterWorldY", "getWorldScale",
                    "getZoom", "getAPIv1", "getSymbolsAPI" }
    local have = {}
    for i = 1, #names do
        local fn
        pcall(function() fn = api[names[i]] end)
        if fn then table.insert(have, names[i]) end
    end
    print("[Traka] map API offers: " ..
          (#have > 0 and table.concat(have, ", ") or "nothing recognised"))
end

--=================================================================== policy =
-- There is no policy any more, and that is the point. Every registered shop is
-- drawn, for everyone, always. The three-way sandbox option and the per-player
-- ON/OFF button are gone: a shop map that shows a different set of shops
-- depending on who is looking is a map players cannot trust or talk about.
-- One display, one meaning.

--==================================================================== paint =

function AkaShopMap.drawOn(ui)
    if not AkaShopMap.enabled then return end

    local index = AkaShopClient and AkaShopClient.index
    if not index then return end
    local api = mapAPI(ui)
    if not api then return end
    if not AkaShopMap.reported then
        AkaShopMap.reported = true
        pcall(reportAPI, api)
    end

    local C    = AkaShopUI.C
    local th   = AkaShopUI.THEME
    local font = UIFont.Small
    local tm   = getTextManager()
    local fh   = tm:getFontHeight(font)
    local w, h = ui:getWidth(), ui:getHeight()
    local me   = AkaShopClient.myName()
    local drawn = 0

    -- Depots are drawn from the same loop as shops so one MAX_DRAW budget
    -- covers both; a map full of depots must not be able to hide the shops.
    local all = {}
    for _, e in pairs(index) do table.insert(all, e) end
    for _, e in pairs(AkaShopClient.depots or {}) do
        table.insert(all, { x = e.x, y = e.y, z = e.z, name = e.name,
                            nameTH = e.nameTH, enabled = true, depot = true,
                            owner = "" })
    end

    for _, e in ipairs(all) do
        if drawn >= AkaShopMap.MAX_DRAW then return end
        do
            local sx, sy = project(api, e.x + 0.5, e.y + 0.5, ui)
            if sx and sx > -60 and sx < w + 60 and sy > -30 and sy < h + 30 then
                drawn = drawn + 1

                local mine  = (e.owner == me)
                local label = AkaShop.shopName(e)
                if e.depot then label = label .. "  (buying)" end
                if not e.enabled then label = label .. "  (closed)" end
                local tw = tm:MeasureStringX(font, label)

                local px = sx - tw / 2 - 7
                local py = sy - fh - 15

                -- dark grey name plate, same greys as the windows
                ui:drawRect(px, py, tw + 14, fh + 6,
                            PLATE_A, th.window.r, th.window.g, th.window.b)
                ui:drawRectBorder(px, py, tw + 14, fh + 6,
                                  0.95, th.border.r, th.border.g, th.border.b)

                local c = e.depot and C.good
                       or (e.enabled and (mine and C.money or C.text) or C.dim)
                ui:drawText(label, px + 7, py + 2, c[1], c[2], c[3], 1, font)

                -- the pin itself
                local pc = e.depot and C.who
                        or (e.enabled and (mine and C.money or C.good) or C.bad)
                ui:drawRect(sx - PIN, sy - PIN, PIN * 2, PIN * 2,
                            0.95, th.window.r, th.window.g, th.window.b)
                ui:drawRect(sx - PIN + 1, sy - PIN + 1, PIN * 2 - 2, PIN * 2 - 2,
                            1, pc[1], pc[2], pc[3])
                -- stalk from pin up to the plate
                ui:drawRect(sx - 1, py + fh + 6, 2, (sy - PIN) - (py + fh + 6),
                            0.8, th.border.r, th.border.g, th.border.b)
            end
        end
    end
end

--============================================================ map integration

function AkaShopMap.install()
    if installed then return end
    if type(ISWorldMap) ~= "table" then
        print("[Traka] ISWorldMap not found - map markers disabled")
        return
    end
    installed = true

    local origRender = ISWorldMap.render
    if type(origRender) == "function" then
        function ISWorldMap:render()
            origRender(self)
            local ok, err = pcall(AkaShopMap.drawOn, self)
            if not ok then
                print("[Traka] map overlay error: " .. tostring(err))
                AkaShopMap.enabled = false      -- fail once, then stay quiet
                if AkaShopClient and AkaShopClient.notify then
                    AkaShopClient.notify("Shop map markers turned themselves off - " ..
                        "see console.txt", true)
                end
            end
        end
    end

    print("[Traka] world map markers installed")
end

Events.OnGameStart.Add(function()
    pcall(AkaShopMap.install)
end)
