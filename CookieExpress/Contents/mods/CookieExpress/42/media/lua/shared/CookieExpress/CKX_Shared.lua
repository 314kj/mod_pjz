-- Cookie Express : shared constants + transport (works in MP and single player)
require "CookieExpress/CKX_Codec"

CKX = CKX or {}
CKX.VERSION = "1.2.4"
CKX.BUILD = "ckx-261024-e1ff8a"
CKX.CREDIT = "Cookie Express - baked by lookchinnoi for CookieCheetah"
CKX.NET = "CookieExpress"
CKX.SLIP = "CookieExpress.VehicleSlip"

function CKX.log(msg)
    print("[CookieExpress] " .. tostring(msg))
end

function CKX.isSP()
    return (not isClient()) and (not isServer())
end

function CKX.nowMs()
    local ok, v = pcall(getTimestampMs)
    if ok and type(v) == "number" then return v end
    return os.time() * 1000
end

-- client -> server
function CKX.toServer(cmd, args)
    args = args or {}
    if CKX.isSP() then
        if CKX.S and CKX.S.onCommand then CKX.S.onCommand(getSpecificPlayer(0), cmd, args) end
        return
    end
    local p = getSpecificPlayer(0)
    if p then sendClientCommand(p, CKX.NET, cmd, args) end
end

-- server -> one client
function CKX.toClient(player, cmd, args)
    args = args or {}
    if CKX.isSP() then
        if CKX.Cl and CKX.Cl.onCommand then CKX.Cl.onCommand(cmd, args) end
        return
    end
    sendServerCommand(player, CKX.NET, cmd, args)
end
