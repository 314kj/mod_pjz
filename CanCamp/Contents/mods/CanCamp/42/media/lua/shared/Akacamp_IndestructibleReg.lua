--[[ Akacamp - register tent matcher for AKA Indestructible guard (เต้นซอมบี้ตีไม่แตก)
     (c) 2026 AKA & Haftfull. See LICENSE.txt ]]
require "Akacamp_Util"
if AKA and AKA.Indestructible and AKA.Indestructible.register then
    AKA.Indestructible.register(function(o)
        return Akacamp.isTentObject(o) == true
    end)
end
