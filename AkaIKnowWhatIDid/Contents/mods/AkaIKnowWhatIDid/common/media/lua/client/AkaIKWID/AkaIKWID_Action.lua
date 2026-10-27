--[[
    "Sit down and actually write in it."

    Pressing either sticker closes the book and queues this timed action. Only
    when it finishes does the record get written or the XP handed back; walking
    away cancels it and nothing happens.

    Duration comes from the real clock, not from maxTime: the tick rate of a B42
    timed action is not documented, so maxTime is deliberately set far too long
    and forceComplete() ends the action on the exact second.
]]

require "TimedActions/ISBaseTimedAction"
require "AkaIKWID/AkaIKWID_Shared"

AkaIKWID_Action = ISBaseTimedAction:derive("AkaIKWID_Action")

local safe = AkaIKWID.safe

function AkaIKWID_Action:isValid()
    if not self.item then return false end
    local inv = safe(function() return self.character:getInventory() end, nil)
    if not inv then return false end
    return safe(function() return inv:contains(self.item) end, true) ~= false
end

function AkaIKWID_Action:waitToStart()
    return false
end

function AkaIKWID_Action:buildLines()
    local src = (self.kind == "record") and AkaIKWID.earned(self.character)
                                        or (AkaIKWID.book and AkaIKWID.book.skills)
    local out = AkaIKWID.rowsFromSkills(src)
    while #out > 6 do table.remove(out) end
    return out
end

function AkaIKWID_Action:tickLines(elapsed)
    if not self.lines or #self.lines == 0 then return end
    local step = self.seconds / (#self.lines + 1)
    local want = math.floor(elapsed / step)
    if want > #self.lines then want = #self.lines end
    while (self.shown or 0) < want do
        self.shown = (self.shown or 0) + 1
        local verb = (self.kind == "record")
            and AkaIKWID.T("IGUI_AkaIKWID_Writing", "writing down")
            or  AkaIKWID.T("IGUI_AkaIKWID_Recalling", "remembering")
        AkaIKWID.haloPlain(self.character, verb .. ": " .. self.lines[self.shown].name)
    end
end

function AkaIKWID_Action:update()
    safe(function() self.character:setMetabolicTarget(Metabolics.LightDomestic) end, nil)

    local elapsed = (AkaIKWID.nowMs() - (self.startedMs or 0)) / 1000
    safe(function() self:tickLines(elapsed) end, nil)

    -- keep the vanilla "reading" look alive: progress on the item itself
    local p = elapsed / self.seconds
    if p > 1 then p = 1 end
    safe(function() self.item:setJobDelta(p) end, nil)

    if elapsed >= self.seconds and not self.done then
        self.done = true
        local ok = safe(function() self:forceComplete() return true end, false)
        if ok ~= true then self.maxTime = 1 end
    end
end

function AkaIKWID_Action:start()
    self.startedMs = AkaIKWID.nowMs()
    self.done  = false
    self.shown = 0
    self.lines = safe(function() return self:buildLines() end, {}) or {}

    -- The reading animation only plays with the book actually in hand, so put
    -- it there and give the old item back when we are done.
    -- (character:setReadItem does NOT exist in B42 - calling it threw on every
    --  single start and filled console.txt. Test before calling, never pcall.)
    safe(function() self.item:setJobType(AkaIKWID.T("ContextMenu_Read", "Reading")) end, nil)
    safe(function() self.item:setJobDelta(0.0) end, nil)

    self.prevPrimary = safe(function() return self.character:getPrimaryHandItem() end, nil)
    if self.prevPrimary ~= self.item then
        safe(function() self.character:setPrimaryHandItem(self.item) end, nil)
    end

    if AkaIKWID.has(self.character, "setReadItem") then
        safe(function() self.character:setReadItem(self.item) end, nil)
    end

    safe(function() self:setActionAnim("Read") end, nil)
    safe(function() self:setOverrideHandModels(self.item, nil) end, nil)
end

function AkaIKWID_Action:restoreHands()
    safe(function() self.item:setJobDelta(0.0) end, nil)
    if AkaIKWID.has(self.character, "setReadItem") then
        safe(function() self.character:setReadItem(nil) end, nil)
    end
    if self.prevPrimary ~= self.item then
        safe(function() self.character:setPrimaryHandItem(self.prevPrimary) end, nil)
    end
end

function AkaIKWID_Action:stop()
    self:restoreHands()
    ISBaseTimedAction.stop(self)
end

function AkaIKWID_Action:perform()
    self:restoreHands()
    ISBaseTimedAction.perform(self)

    local ok, err = pcall(function() AkaIKWID.runAction(self.character, self.item, self.kind) end)
    if not ok then AkaIKWID.log("action error: " .. tostring(err)) end
end

function AkaIKWID_Action:new(character, item, kind, seconds)
    local o = ISBaseTimedAction.new(self, character)
    o.item       = item
    o.kind       = kind
    o.seconds    = seconds or 60
    o.maxTime    = (o.seconds * 200) + 200
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.caloriesModifier = 1
    return o
end

function AkaIKWID.runAction(player, item, kind)
    if not (player and item) then return end
    AkaIKWID.lastItem = item
    if kind == "record" then
        AkaIKWID.requestRecord(player)
    elseif kind == "restore" then
        AkaIKWID.requestRestore(player)
    end
end

function AkaIKWID.startAction(player, item, kind)
    AkaIKWID.lastItem = item

    local secs = AkaIKWID.opt("WriteSeconds")
    if type(secs) ~= "number" then secs = 60 end
    if secs <= 0 then
        AkaIKWID.runAction(player, item, kind)
        return
    end

    local ok = safe(function()
        ISTimedActionQueue.add(AkaIKWID_Action:new(player, item, kind, secs))
        return true
    end, false)

    if ok ~= true then
        AkaIKWID.log("timed action unavailable - doing it immediately")
        AkaIKWID.runAction(player, item, kind)
    end
end
