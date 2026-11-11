-- Cookie Killer Board - client: asks the server for the board, keeps the last answer per tab
if isServer() and not isClient() then return end

require "CKB_Shared"
require "CM_Client"

CKBC = CKBC or {}
CKBC.data = CKBC.data or {}     -- tab -> { rows, me, n, adm, at }
local MOD = CKB.MOD

local function ms()
    if getTimestampMs then return getTimestampMs() end
    return CM.now() * 1000
end
CKBC.ms = ms

function CKBC.player() return getSpecificPlayer(0) end

function CKBC.send(cmd, args)
    local p = CKBC.player()
    if not p then return end
    sendClientCommand(p, MOD, cmd, args or {})
end

function CKBC.txt(key, a, b, c)
    if a == nil then return getText(key) end
    if b == nil then return getText(key, tostring(a)) end
    if c == nil then return getText(key, tostring(a), tostring(b)) end
    return getText(key, tostring(a), tostring(b), tostring(c))
end

function CKBC.isAdmin()
    if CM.isSP() then return true end
    return CMC and CMC.isAdmin and CMC.isAdmin() or false
end

CKBC.askedAt = {}
function CKBC.ask(tab)
    tab = tab == "all" and "all" or "life"
    CKBC.askedAt[tab] = ms()
    -- staff also get the players they took off the board (marked), so they can put them back
    local adm = nil
    if CKBC.isAdmin() then adm = true end
    CKBC.send("board", { tab = tab, adm = adm })
end

-- rows arrive as a table with 1..n keys; copy into a plain array
local function arr(t)
    local out = {}
    if type(t) ~= "table" then return out end
    local i = 1
    while t[i] ~= nil do
        out[#out + 1] = t[i]
        i = i + 1
    end
    return out
end

local function onServerCommand(module, command, args)
    if module ~= MOD then return end
    args = args or {}
    if command == "board" then
        local tab = args.tab == "all" and "all" or "life"
        CKBC.data[tab] = { rows = arr(args.rows), me = args.me, n = CM.num(args.n, 0), adm = args.adm, at = ms() }
    elseif command == "adm" then
        local key = args.op == "reset" and "IGUI_CKB_T_reset" or (args.hide and "IGUI_CKB_T_hidden" or "IGUI_CKB_T_shown")
        if CMC and CMC.toast then CMC.toast(CKBC.txt(key, args.n), "good") end
        CKBC.askedAt = {}
    end
end
CKBC.onServerCommand = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

-- the server also hears deaths itself; this is the fallback
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function(p)
    if p == CKBC.player() then CKBC.send("dead", {}) end
end) end

-- ===================================================================== weapon icons
local texCache = {}
function CKBC.tex(name)
    local t = texCache[name]
    if t == nil then
        t = getTexture("media/textures/CookieKillerBoard/" .. name .. ".png") or false
        texCache[name] = t
    end
    return t or nil
end

local wCache = {}
function CKBC.weaponTex(ft)
    if not ft or ft == "" then return nil end
    if ft == CKB.FIST then return CKBC.tex("kb_fist") end
    if ft == CKB.CAR then return CKBC.tex("kb_car") end
    local t = wCache[ft]
    if t == nil then
        t = false
        pcall(function()
            local it = getScriptManager():FindItem(ft)
            if it then t = it:getNormalTexture() or false end
        end)
        wCache[ft] = t
    end
    return t or nil
end

function CKBC.weaponName(ft)
    if not ft or ft == "" then return nil end
    if ft == CKB.FIST then return CKBC.txt("IGUI_CKB_Fist") end
    if ft == CKB.CAR then return CKBC.txt("IGUI_CKB_Car") end
    if CMC and CMC.itemName then return CMC.itemName(ft) end
    return ft
end

return CKBC
