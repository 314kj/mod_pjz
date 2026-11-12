-- Cookie Mission - Die or Die: a squad fights Project A-Life soldiers at a spot an admin saved in game
-- (shared numbers; the server runs the match, the client draws lobby / loading / HUD / tags)
require "CM_Shared"

CM.DOD = {
    MAX = 8,                    -- players in one lobby
    MIN = 2,                    -- players needed to start
    VOTE = 60,                  -- seconds of the place vote
    LOAD = 8,                   -- seconds of the loading screen before the warp
    READY = 90,                 -- seconds the ready check waits at most
    COUNT = 3,                  -- 3-2-1
    CLEAR = 30,                 -- tiles around the spot cleared of zombies while locked
    SPAWN_MIN = 25,             -- soldiers appear at least this far from every player
    SPAWN_MAX = 40,
    GROUP = 8,                  -- A-Life takes at most 8 per request
    RETRY = 10,                 -- seconds between refused spawn requests
    AREA = 70,                  -- tiles from the spot that count as the match area (send home rect)
    -- guard / assault split in % (guard first), per tier
    GUARD = { 70, 50, 30 },
    -- 8 team colours and 8 call signs (shown over the heads during a match)
    COLORS = {
        { 0.95, 0.30, 0.30 }, { 0.30, 0.60, 1.00 }, { 0.35, 0.90, 0.40 }, { 1.00, 0.85, 0.25 },
        { 0.80, 0.45, 1.00 }, { 1.00, 0.55, 0.15 }, { 0.30, 0.95, 0.95 }, { 1.00, 0.55, 0.80 },
    },
    SIGNS = { "ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL" },
    -- reward per surviving winner: p = pool, r = rolls, c = chance %; mvp = extra lines for the top killer
    DROPS = {
        { { p = "guns", r = 1, c = 100, f = "melee" }, { p = "meds", r = 2, c = 100 } },
        { { p = "guns", r = 1, c = 100, f = "melee" }, { p = "medsplus", r = 1, c = 100 }, { p = "legend", r = 1, c = 10 } },
        { { p = "guns", r = 2, c = 100, f = "melee" }, { p = "medsplus", r = 2, c = 100 }, { p = "legend", r = 1, c = 25 } },
    },
    MVP = { { p = "legend", r = 1, c = 10 }, { p = "legend", r = 1, c = 25 }, { p = "legend", r = 1, c = 50 } },
}

function CM.dodOn() return CM.sv("DieOrDie") == true end

function CM.dodCount(tier)
    local n = CM.TIER_NAME[tier] or "Easy"
    return CM.int(CM.sv("Dod" .. n), 20, 1, 80)
end

function CM.dodColor(i) return CM.DOD.COLORS[CM.int(i, 1, 1, 8)] end
function CM.dodSign(i) return CM.DOD.SIGNS[CM.int(i, 1, 1, 8)] end

return CM
