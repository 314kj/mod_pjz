-- CookieServerPatch: stop Kentucky Cannabis from checking every item on every
-- square that loads. Server and players (shared).
--
-- Why: KC_FoodDoses adds KentuckyCannabis.FoodDoses.restoreSquare to
-- LoadGridsquare. For every square that loads it goes through every container
-- on the square and every item inside, and inside bags inside those, to put
-- back the eat/cook hooks of cannabis food. Driving into a town loads
-- thousands of squares, so this runs over every item in the town, on the
-- server and on the driver's game. 2 Nov 07:52-08:04 the server fell to
-- 4-6 FPS while two players drove at the same time (normal is 10).
--
-- What is kept: KC still puts the hooks back right before someone eats
-- (its ISEatFoodAction hook), every 30 ticks for items that are cooking
-- (its OnTick pass over the cell's process items), and on a player's own
-- inventory when they spawn. Only the pass over every square is removed.
-- Possible side effect (rare): a cannabis meal cooked again before KC sees it
-- may lose its effect. Eating works as before.
--
-- Log: "[CookieServerPatch] kc-lite on" when the pass was removed,
-- "kc-lite: Kentucky Cannabis not found" when KC is not loaded.
-- To undo: remove this file.

local TAG = "[CookieServerPatch] kc-lite"
local done = false

local function handler()
    local kc = KentuckyCannabis
    local f = kc and kc.FoodDoses
    local h = f and f.restoreSquare
    if type(h) == "function" then return h end
    return nil
end

local function removePass(when, last)
    if done then return end
    local h = handler()
    if not h then
        if last then print(TAG .. ": Kentucky Cannabis not found (" .. when .. "), nothing to do") end
        return
    end
    local ok, err = pcall(function() Events.LoadGridsquare.Remove(h) end)
    done = true
    if ok then
        print(TAG .. " on (removed the per-square item pass, " .. when .. ")")
    else
        print(TAG .. ": could not remove the per-square item pass: " .. tostring(err))
    end
end

removePass("file load", false)
Events.OnGameBoot.Add(function() removePass("OnGameBoot", true) end)
