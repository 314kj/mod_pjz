--[[ ============================================================
  TOILEPORT  [MP]  --  station protection               KACHASIG
  Registered toilets must survive players: no combat smash, no
  sledgehammer, no wrench pickup/disassemble.
  Patterns verified against TraderVendingMachine:
    * setIsThumpable(false)               -> blocks combat smashing
    * ISDestroyCursor.canDestroy patch    -> blocks sledgehammer
    * ISDestroyStuffAction.isValid patch  -> blocks destroy action
    * ISMoveablesAction.isValid patch     -> blocks pickup / scrap
  Source of truth = the object's own modData flag (ToileportStation),
  which persists on save and is transmitted to clients on register.
  setIsThumpable is runtime-only, so it is re-applied on square load
  and after every config sync.
============================================================ ]]

require "Toileport_Shared"
pcall(require, "BuildingObjects/ISDestroyCursor")
pcall(require, "TimedActions/ISDestroyStuffAction")
pcall(require, "TimedActions/ISMoveablesAction")

local TP = Toileport

----------------------------------------------------------------
-- runtime re-apply (thumpable) -- modData flag is the truth
----------------------------------------------------------------
local function protectObject(obj)
    if TP.isProtectedObject(obj) then
        pcall(function() if obj.setIsThumpable then obj:setIsThumpable(false) end end)
    end
end

-- re-apply to any registered toilet whose square is currently loaded
function TP.applyProtectionToLoaded()
    local cfg = TP.getConfig()
    local cell = getCell()
    if not (cfg and cell) then return end
    for _, st in pairs(cfg.stations or {}) do
        local sq = cell:getGridSquare(st.x, st.y, st.z or 0)
        if sq then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do protectObject(objs:get(i)) end
        end
    end
end

-- squares stream in over time -> protect on load
Events.LoadGridsquare.Add(function(sq)
    if not sq then return end
    local objs = sq:getObjects()
    if not objs then return end
    for i = 0, objs:size() - 1 do protectObject(objs:get(i)) end
end)

----------------------------------------------------------------
-- destroy / pickup patches (install once; safe if classes absent)
----------------------------------------------------------------
local function installPatches()
    -- sledgehammer cursor
    if ISDestroyCursor and ISDestroyCursor.canDestroy and not ISDestroyCursor.Toileport_Patched then
        ISDestroyCursor.Toileport_Patched = true
        local old = ISDestroyCursor.canDestroy
        ISDestroyCursor.canDestroy = function(self, object)
            if TP.isProtectedObject(object) then return false end
            return old(self, object)
        end
    end
    -- destroy timed action
    if ISDestroyStuffAction and ISDestroyStuffAction.isValid and not ISDestroyStuffAction.Toileport_Patched then
        ISDestroyStuffAction.Toileport_Patched = true
        local old = ISDestroyStuffAction.isValid
        ISDestroyStuffAction.isValid = function(self)
            if self and self.item and TP.isProtectedObject(self.item) then return false end
            return old(self)
        end
    end
    -- moveables: block pickup / scrap (disassemble) of protected stations
    if ISMoveablesAction and ISMoveablesAction.isValid and not ISMoveablesAction.Toileport_Patched then
        ISMoveablesAction.Toileport_Patched = true
        local old = ISMoveablesAction.isValid
        ISMoveablesAction.isValid = function(self)
            if self and (self.mode == "pickup" or self.mode == "scrap")
                and TP.isProtectedObject(self.object) then
                return false
            end
            return old(self)
        end
    end
end

Events.OnGameStart.Add(function()
    installPatches()
    TP.applyProtectionToLoaded()
end)

print("[Toileport] protection loaded")
