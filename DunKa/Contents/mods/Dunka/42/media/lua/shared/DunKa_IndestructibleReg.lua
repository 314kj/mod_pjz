--[[ PROJECT DUNKA [MP] - register horde box matcher for AKA Indestructible guard.
     (c) 2026 AKA & Haftfull. See LICENSE.txt ]]
DunKa = DunKa or {}
if AKA and AKA.Indestructible and AKA.Indestructible.register then
    AKA.Indestructible.register(function(o)
        if not o then return false end
        local md = o.getModData and o:getModData()
        if md and md.DunKaCabinet then return true end
        local spr = o.getSprite and o:getSprite()
        local nm  = spr and spr.getName and spr:getName()
        return nm == (DunKa.CABINET_SPRITE or "horde_aka_0")
    end)
end
