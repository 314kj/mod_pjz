-- Cookie Slicer (client): picture looks. Only this player's screen changes:
--   colour fade  the game's own "desaturation" value, set again each frame after
--                the game works it out (it is used for drawing only)
--   darkness /   one see-through rectangle over the world, under all windows
--   tint / lift  (black = darker, a colour = tint, white = brighter)
-- Nothing the game simulates is touched (no light levels, no night value), nothing
-- is saved in the world or sent to the server. Cost: one rectangle per UI frame.
-- With the Cookie Slicer Helper running, the real shader (CookieSlicer_Shader.lua)
-- does the look instead and these layers stay off.
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
if isServer() then return end

local CS = CookieSlicer
if not CS then return end

-- desat: added to the game's colour fade (0..1)
-- dark:  black over the world (alpha); night: extra black times the night value (0..1)
-- tint:  {r, g, b, alpha}
CS.LOOKS = {
    { id = "natural", desat = 0,    dark = 0,    night = 0,    tint = nil,                        swatch = { 0.42, 0.55, 0.38 } },
    { id = "cinema",  desat = 0.15, dark = 0.07, night = 0.05, tint = { 1.00, 0.80, 0.58, 0.07 }, swatch = { 0.62, 0.50, 0.36 } },
    { id = "retro",   desat = 0.55, dark = 0.03, night = 0,    tint = { 0.82, 0.68, 0.46, 0.13 }, swatch = { 0.60, 0.55, 0.45 } },
    { id = "dark",    desat = 0.10, dark = 0.16, night = 0.32, tint = { 0.55, 0.62, 0.82, 0.05 }, swatch = { 0.16, 0.18, 0.24 } },
}
CS.BRIGHT_MIN, CS.BRIGHT_MAX = -5, 5

function CS.lookById(id)
    for _, l in ipairs(CS.LOOKS) do
        if l.id == id then return l end
    end
    return CS.LOOKS[1]
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- the three layers for the current look + brightness + night value
-- returns black alpha, tint (or nil), white alpha
function CS.layers(nightValue)
    local look = CS.lookById(CS.settings.look)
    local b = clamp(tonumber(CS.settings.bright) or 0, CS.BRIGHT_MIN, CS.BRIGHT_MAX)
    local black = look.dark + look.night * (nightValue or 0)
    local white = 0
    if b < 0 then black = black + (-b) * 0.05 else white = b * 0.022 end
    return clamp(black, 0, 0.6), look.tint, clamp(white, 0, 0.15)
end

-- what a colour on the world looks like through the layers (for the
-- brightness check squares in the window, which are drawn above the layers)
function CS.through(r, g, b, nightValue)
    local black, tint, white = CS.layers(nightValue)
    r, g, b = r * (1 - black), g * (1 - black), b * (1 - black)
    if tint then
        local a = tint[4]
        r, g, b = r + (tint[1] - r) * a, g + (tint[2] - g) * a, b + (tint[3] - b) * a
    end
    r, g, b = r + (1 - r) * white, g + (1 - g) * white, b + (1 - b) * white
    return r, g, b
end

local function nightNow()
    local ok, v = pcall(function() return getClimateManager():getNightStrength() end)
    if ok and type(v) == "number" then return v end
    return 0
end
CS.nightNow = nightNow

-- colour fade: after the game has worked out this frame's value (the climate
-- update runs before players update), before the drawing settings read it
local desatFloat = nil
local function onPlayerUpdate(player)
    if player ~= getPlayer() then return end
    if CS.shaderActive and CS.shaderActive() then return end -- the real shader does the look
    local look = CS.lookById(CS.settings.look)
    if look.desat <= 0 then return end
    pcall(function()
        if not desatFloat then desatFloat = getClimateManager():getClimateFloat(0) end -- FLOAT_DESATURATION
        local v = desatFloat:getFinalValue() + look.desat
        if v > 1 then v = 1 end
        desatFloat:setFinalValue(v)
    end)
end

local function onPreUIDraw()
    if not getPlayer() then return end
    if CS.shaderActive and CS.shaderActive() then return end
    local black, tint, white = CS.layers(nightNow())
    if black <= 0 and not tint and white <= 0 then return end
    local core = getCore()
    local w, h = core:getScreenWidth(), core:getScreenHeight()
    local rnd = getRenderer()
    if black > 0 then rnd:renderRect(0, 0, w, h, 0, 0, 0, black) end
    if tint then rnd:renderRect(0, 0, w, h, tint[1], tint[2], tint[3], tint[4]) end
    if white > 0 then rnd:renderRect(0, 0, w, h, 1, 1, 1, white) end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnPreUIDraw.Add(onPreUIDraw)
