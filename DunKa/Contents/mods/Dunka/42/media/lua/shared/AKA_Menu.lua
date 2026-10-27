--[[ ============================================================
     AKA MOD  -  shared right-click grouping helper
     Loaded (guarded) by every AKA mod. First mod to load defines
     AKA.getGroup; the rest reuse it. Produces ONE shared
        AKA MOD  >  Gacha / Dunka / ...  >  (that mod's options)
     parent in the world right-click menu.

     NOTE: PZ pools/reuses the world context menu and :clear()s its
     option list each right-click. So we must NOT cache anything on
     the context across builds (that caused the "flash then vanish"
     bug). Instead we scan the CURRENT build's option list, which PZ
     wipes every rebuild -> always build-local, never stale.
   ============================================================ ]]

AKA = AKA or {}

if not AKA.getGroup then
    require "ISUI/ISContextMenu"

    function AKA.getGroup(context, name)
        -- find an "AKA MOD" root already added in THIS build
        local rootSub
        if context.options then
            for _, o in ipairs(context.options) do
                if o._akaRoot then rootSub = o._akaSub; break end
            end
        end
        -- not there yet this build -> create it fresh
        if not rootSub then
            local rootOpt = context:addOptionOnTop("AKA MOD", nil, nil)
            rootSub = ISContextMenu:getNew(context)
            context:addSubMenu(rootOpt, rootSub)
            rootOpt._akaRoot   = true
            rootOpt._akaSub    = rootSub
            rootSub._akaGroups = {}
        end
        -- named child submenu (Gacha / Dunka / ...) under the root
        local groups = rootSub._akaGroups
        if groups[name] then return groups[name] end
        local opt = rootSub:addOption(name, nil, nil)
        local sub = ISContextMenu:getNew(rootSub)
        rootSub:addSubMenu(opt, sub)
        groups[name] = sub
        return sub
    end
end
