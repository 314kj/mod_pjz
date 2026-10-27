--[[
================================================================================
  AKA MOD  --  Indestructible machine guard  (ผีตีตู้ไม่แตก)
  Copyright (c) 2026 AKA & Haftfull. All Rights Reserved.
  Created under the AKA brand. Made for Haftfull.
  Personal use only. No modify / no reupload without permission. See LICENSE.txt
--------------------------------------------------------------------------------
  SHARED, guarded singleton (first AKA mod to load defines it; the rest reuse).
  Every AKA mod registers a matcher fn(obj)->bool. Any object that matches is
  hardened on the AUTHORITY side only (dedicated server, OR true singleplayer):

      setIsThumpable(false)   <- zombies can no longer thump/break it
      setMaxHealth / setHealth = very high   (belt-and-suspenders)
      setCanBarricade(false)

  Re-applied whenever the object is added AND whenever its chunk loads, because
  the thumpable flag can reset on chunk reload. Pattern mirrors the working
  TraderVendingMachine durability stamp (setIsThumpable + setMaxHealth/setHealth).
================================================================================
]]--

AKA = AKA or {}

if not AKA.Indestructible then
    AKA.Indestructible = {}
    AKA.Indestructible.matchers = AKA.Indestructible.matchers or {}
    AKA.Indestructible.BIG = 300000

    -- mods call this once (idempotent-ish): register a predicate obj -> bool
    function AKA.Indestructible.register(fn)
        if type(fn) ~= "function" then return end
        for _, f in ipairs(AKA.Indestructible.matchers) do
            if f == fn then return end
        end
        table.insert(AKA.Indestructible.matchers, fn)
    end

    function AKA.Indestructible.isMachine(obj)
        if not obj then return false end
        for _, fn in ipairs(AKA.Indestructible.matchers) do
            local ok, res = pcall(fn, obj)
            if ok and res == true then return true end
        end
        return false
    end

    function AKA.Indestructible.harden(obj)
        if not obj then return false end
        local BIG = AKA.Indestructible.BIG
        if obj.setIsThumpable   then obj:setIsThumpable(false) end
        if obj.setCanBarricade  then obj:setCanBarricade(false) end
        if obj.setCanPassThrough then obj:setCanPassThrough(false) end
        if obj.setMaxHealth     then obj:setMaxHealth(BIG) end
        if obj.setHealth        then obj:setHealth(BIG) end
        if obj.getModData then
            local md = obj:getModData()
            if md then md.AKA_Indestructible = true end
        end
        return true
    end

    -- only the authority touches world objects (server in MP, or SP).
    local function isAuthority()
        local sv = isServer and isServer()
        local cl = isClient and isClient()
        if sv then return true end          -- dedicated / coop server
        if (not sv) and (not cl) then return true end  -- true singleplayer
        return false
    end

    local function onObjectAdded(obj)
        if not isAuthority() then return end
        if AKA.Indestructible.isMachine(obj) then
            AKA.Indestructible.harden(obj)
        end
    end

    local function onLoadGridsquare(sq)
        if not isAuthority() then return end
        if not sq or not sq.getObjects then return end
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if AKA.Indestructible.isMachine(o) then
                AKA.Indestructible.harden(o)
            end
        end
    end

    if Events then
        if Events.OnObjectAdded   then Events.OnObjectAdded.Add(onObjectAdded) end
        if Events.LoadGridsquare  then Events.LoadGridsquare.Add(onLoadGridsquare) end
    end
end
