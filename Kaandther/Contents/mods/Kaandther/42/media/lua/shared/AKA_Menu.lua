--[[ ============================================================
     AKA MOD  -  shared right-click grouping helper  (v2)
     ------------------------------------------------------------
     Ship this IDENTICAL file in EVERY AKA mod at
        media/lua/shared/AKA_Menu.lua
     and have each mod call:
        local g = AKA.getGroup(context, "YourModName")
        g:addOption("...", ...)
     to place its options under ONE shared:
        AKA MOD  >  Kaandther / Toileport / Kacha / Dunka / ...

     v2: version-guarded (highest version wins regardless of load
     order) and it will ADOPT an existing "AKA MOD"/"AKA Mod" root
     made by any other implementation, so mods merge even if their
     spelling/casing differs.

     NOTE: PZ pools/reuses the world context menu and clears its
     option list each right-click, so we scan the CURRENT build's
     list every time and never cache across builds.
   ============================================================ ]]

AKA = AKA or {}

if (AKA._ver or 0) < 2 then
    AKA._ver = 2

    local function norm(s) return tostring(s or ""):lower():gsub("%s+", "") end
    local function isAkaName(s) local k = norm(s); return k == "akamod" or k == "akamods" end
    local function subOf(context, o)
        if o._akaSub then return o._akaSub end
        local so = o.subOption
        if type(so) == "table" then return so end
        if type(so) == "number" and context.getSubMenu then return context:getSubMenu(so) end
        return nil
    end

    function AKA.getGroup(context, name)
        if not ISContextMenu then require "ISUI/ISContextMenu" end
        local items = context.items or context.options   -- B42 items / B41 options
        local rootOpt, rootSub

        if items then
            -- 1) a root previously created by THIS helper (marker)
            for _, o in ipairs(items) do
                if o._akaRoot then rootOpt = o; rootSub = o._akaSub; break end
            end
            -- 2) OR any existing "AKA MOD"/"AKA Mod" from another mod -> adopt it
            if not rootSub then
                for _, o in ipairs(items) do
                    if isAkaName(o.name) then
                        local s = subOf(context, o)
                        if s then
                            rootOpt = o; rootSub = s
                            o._akaRoot = true; o._akaSub = s
                            s._akaGroups = s._akaGroups or {}
                            break
                        end
                    end
                end
            end
        end

        -- 3) none this build -> create the shared root
        if not rootSub then
            rootOpt = context:addOptionOnTop("AKA MOD", nil, nil)
            rootSub = ISContextMenu:getNew(context)
            context:addSubMenu(rootOpt, rootSub)
            rootOpt._akaRoot = true
            rootOpt._akaSub = rootSub
            rootSub._akaGroups = {}
        end

        local groups = rootSub._akaGroups or {}
        rootSub._akaGroups = groups
        if groups[name] then return groups[name] end
        local opt = rootSub:addOption(name, nil, nil)
        local sub = ISContextMenu:getNew(rootSub)
        rootSub:addSubMenu(opt, sub)
        groups[name] = sub
        return sub
    end
end
