--[[===========================================================================
    Traka - the "emptying my bag" timed action.

    A player who clicks Sell everything with two hundred rings on them is asking
    for a job of work, and the game already has a language for a job of work: a
    progress bar over the character's head, the character standing still, and
    walking away to cancel. That is what reading a book looks like, and a player
    who has read a book knows what it means without being told.

    WHAT THIS DOES AND DOES NOT DO. It does not sell anything. The queue in
    AkaShop_Client.lua does the selling, on its own timer, and would finish
    perfectly well with this file deleted. This is the FACE of that queue: it
    shows how far along it is and gives the player somewhere to put their
    "actually, stop".

    That separation is the whole design. Timed actions are engine furniture -
    ISBaseTimedAction, the queue, the animation - and engine furniture moves
    between builds. If any of it is missing or throws on this build, selling
    still works; the player just does not get a bar. A cosmetic layer must never
    be able to break the thing it decorates.
============================================================================]]

AkaShopSellAction = nil

-- Guarded: on a build where the timed-action system is not what we expect, this
-- file quietly does nothing at all.
local ok = pcall(function() require "TimedActions/ISBaseTimedAction" end)
if not ok or not ISBaseTimedAction then
    print("[Traka] timed actions unavailable on this build - bulk sales will " ..
          "still work, without a progress bar.")
    return
end

AkaShopSellAction = ISBaseTimedAction:derive("AkaShopSellAction")

function AkaShopSellAction:isValid()
    -- The action lives exactly as long as the queue does. When the last batch
    -- lands, this goes false, the engine stops the action, and stop() below
    -- finds nothing left to cancel - which is how a finished sale ends without
    -- ever looking like an interruption.
    return AkaShopClient.sellBusy()
end

function AkaShopSellAction:waitToStart() return false end

function AkaShopSellAction:update()
    -- Keep the character busy-looking and stop them regenerating boredom as if
    -- they were idle. Everything else about the sale happens elsewhere.
    if self.character then
        pcall(function()
            self.character:setMetabolicTarget(Metabolics.LightDomestic)
        end)
    end
end

function AkaShopSellAction:start()
    self:setActionAnim("Loot")
    self:setOverrideHandModels(nil, nil)
end

function AkaShopSellAction:stop()
    -- Reached both when the player walks away and when the sale finishes. Only
    -- the first of those is a cancellation, and sellBusy is what tells them
    -- apart: a finished run has already emptied itself.
    if AkaShopClient.sellBusy() then
        AkaShopClient.cancelSell("Stopped. Everything already handed over is paid for.")
    end
    ISBaseTimedAction.stop(self)
end

function AkaShopSellAction:perform()
    ISBaseTimedAction.perform(self)
end

function AkaShopSellAction:new(character, seconds)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = true
    o.stopOnRun  = true
    -- maxTime is in engine ticks and the conversion has moved between builds,
    -- so it is deliberately an OVER-estimate: the action is meant to end when
    -- isValid() goes false, not when this runs out. Getting it roughly right
    -- only matters for how the bar fills.
    o.maxTime = math.max(60, math.floor((tonumber(seconds) or 5) * 30))
    return o
end

--- Put the character to work while a paced sale drains. Safe to call for a sale
--- that turns out not to need it - it simply ends on the next frame.
function AkaShopSellAction.begin(character, items)
    if not (character and AkaShopSellAction) then return end
    local rate = math.max(1, AkaShop.sellRate())
    local secs = math.max(1, math.ceil((tonumber(items) or 0) / rate))
    pcall(function()
        ISTimedActionQueue.add(AkaShopSellAction:new(character, secs))
    end)
end
