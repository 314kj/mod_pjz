--[[===========================================================================
    Traka's place in the AKA family right-click menu.

    The family has exactly ONE menu helper: Kaandther's media/lua/shared/
    AKA_Menu.lua, global AKA, called as AKA.getGroup(context, "<mod name>").
    Kaandther, Toileport, Kacha, Dunka and Kuraya already file their tools
    under it, which is what puts them all behind one "AKA MOD" row.

    Traka 3.7.5 shipped a second helper of its own. It merged Traka
    with nothing, because nothing else called it - a second registry under a
    different global is the "every mod builds its own parent" bug moved into a
    new file. It is gone. Traka now asks the family helper, and only builds a
    parent of its own when no family mod is installed at all.

    The helper is looked up on every call, never cached: it may load after
    Traka, and PZ reuses one menu object per player with its rows cleared, so
    nothing about a previous right-click may be remembered.
============================================================================]]

AkaShopMenu = AkaShopMenu or {}

AkaShopMenu.GROUP = "Traka"

--- The menu Traka's server-wide admin tools go into.
---
--- Call it only when there is something to put in it. The family helper
--- builds the parent row the moment it is asked, so asking on behalf of a
--- player who has no tools to see hands them a row that opens onto nothing.
function AkaShopMenu.adminRoot(context)
    local aka = AKA
    if type(aka) == "table" and type(aka.getGroup) == "function" then
        local g = nil
        local ok = pcall(function() g = aka.getGroup(context, AkaShopMenu.GROUP) end)
        if ok and g then return g end
    end
    -- No family helper on this server (or it failed): a parent of our own,
    -- named so that the family helper adopts it if one turns up later -
    -- it treats any row reading "akamod" once spaces and case are gone as
    -- the shared parent.
    local root = context:addOptionOnTop("AKA Mod", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    return menu
end
