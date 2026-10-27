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

    function AKA.getGroup(context, name)
        -- ISContextMenu is client-only. Require lazily INSIDE the function so
        -- it always runs in a client call-stack (this function is never called
        -- on the server), avoiding the shared-context ISUI path problem.
        if not ISContextMenu then
            require "ISUI/ISContextMenu"
        end

        -- find an "AKA MOD" root already added in THIS build.
        -- B42 uses context.items; B41 used context.options. Try both.
        local rootSub
        local items = context.items or context.options
        if items then
            for _, o in ipairs(items) do
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

        -- named child submenu (Toileport / Gacha / ...) under the root
        local groups = rootSub._akaGroups
        if groups[name] then return groups[name] end
        local opt = rootSub:addOption(name, nil, nil)
        local sub = ISContextMenu:getNew(rootSub)
        rootSub:addSubMenu(opt, sub)
        groups[name] = sub
        return sub
    end

end
