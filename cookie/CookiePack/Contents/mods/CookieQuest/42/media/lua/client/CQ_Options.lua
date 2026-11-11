-- Cookie Quest - Options > Mods: hotkey to open the window (for players who cannot see the icon)
require "CQ_Client"

CQOpt = CQOpt or {}

local function init()
    if CQOpt.o or not (PZAPI and PZAPI.ModOptions) then return end
    local ok, o = pcall(function() return PZAPI.ModOptions:create("CookieQuest", "Cookie Quest") end)
    if not ok or not o then return end
    pcall(function() o:addKeyBind("openKey", getText("IGUI_CQ_Opt_Key"), 0, getText("IGUI_CQ_Opt_KeyTip")) end)
    CQOpt.o = o
end

function CQOpt.key()
    if not CQOpt.o then return 0 end
    local ok, v = pcall(function() return CQOpt.o:getOption("openKey"):getValue() end)
    if ok and type(v) == "number" then return v end
    return 0
end

Events.OnCreateUI.Add(init)
Events.OnKeyPressed.Add(function(key)
    local k = CQOpt.key()
    if k ~= 0 and key == k and CQBoard and CQBoard.toggle then CQBoard.toggle() end
end)

return CQOpt
