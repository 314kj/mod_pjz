--[[ Kacha B42 [MP] - register machine matcher for AKA Indestructible guard.
     (c) 2026 AKA & Haftfull. See LICENSE.txt ]]
Kacha = Kacha or {}
if AKA and AKA.Indestructible and AKA.Indestructible.register then
    AKA.Indestructible.register(function(o)
        if Kacha.isKacha and Kacha.isKacha(o) then return true end
        local spr = o and o.getSprite and o:getSprite()
        local nm  = spr and spr.getName and spr:getName()
        return nm ~= nil and string.find(nm, "set_aka_") ~= nil
    end)
end
if Kacha.__mark then Kacha.__mark("indestruct") end
