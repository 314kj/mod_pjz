-- Cookie Mission - Die or Die: squads fight Project A-Life soldiers at 5 fixed spots
-- (shared numbers; the server runs the matches, the client draws the screens)
require "CM_Shared"

CM.DOD = {
    MAX = 8,                    -- players in one team
    MIN = 2,                    -- players needed to deploy
    SIZES = { 2, 4, 6, 8 },     -- team sizes the leader can pick
    TEAM_LIFE = 30 * 60,        -- a team that never deploys closes after this
    WARP = 8,                   -- seconds of the insertion screen (the warp happens at its end)
    RECON = 120,                -- seconds to look around before the soldiers come
    SHIELD = 15,                -- seconds of god mode right after landing (late loaders)
    CLEAR = 30,                 -- tiles around the safe area cleared of zombies during recon
    GROUP = 8,                  -- A-Life takes at most 8 per request
    RETRY = 10,                 -- seconds between refused spawn requests
    TRIES = 6,                  -- refusals before a group is dropped from the target
    STUCK = 90,                 -- seconds a soldier may stay dormant / never show before it is retired
    WIN_HOLD = 8,               -- seconds every soldier must stay down before the win
    ASSIST = 15,                -- seconds a hit counts as an assist
    AREA = 80,                  -- tiles around the safe area that count as the match area
    -- guard / assault split in % (guard first), per tier
    GUARD = { 70, 50, 30 },
    TIER_TAG = { "RECRUIT", "VETERAN", "ELITE" },
    -- the 5 spots (fixed names and pictures; an admin sets the safe area and spawn points in game)
    LOCS = {
        { id = "bonne", n = "Bonne Street Area", tex = "dod_loc_bonne" },
        { id = "mansion", n = "Mansion", tex = "dod_loc_mansion" },
        { id = "tunnel", n = "Old Tunnel", tex = "dod_loc_tunnel" },
        { id = "farable", n = "F.ARABLE", tex = "dod_loc_farable" },
        { id = "mccoy", n = "McCoy Logging", tex = "dod_loc_mccoy" },
    },
    -- reward per winner: p = pool, r = rolls, c = chance %, cs = sandbox option that overrides c;
    -- MVP = extra lines for the top killer (the legendary chances are set in the sandbox)
    DROPS = {
        { { p = "guns", r = 1, c = 100, f = "melee" }, { p = "meds", r = 2, c = 100 }, { p = "legend", r = 1, c = 0, cs = "DodLegendEasy" } },
        { { p = "guns", r = 1, c = 100, f = "melee" }, { p = "medsplus", r = 1, c = 100 }, { p = "legend", r = 1, c = 10, cs = "DodLegendMedium" } },
        { { p = "guns", r = 2, c = 100, f = "melee" }, { p = "medsplus", r = 2, c = 100 }, { p = "legend", r = 1, c = 25, cs = "DodLegendHard" } },
    },
    MVP = { { { p = "legend", r = 1, c = 10, cs = "DodMvpEasy" } }, { { p = "legend", r = 1, c = 25, cs = "DodMvpMedium" } },
        { { p = "legend", r = 1, c = 50, cs = "DodMvpHard" } } },
}

CM.DOD.LOC = {}
for _, l in ipairs(CM.DOD.LOCS) do CM.DOD.LOC[l.id] = l end

function CM.dodOn() return CM.sv("DieOrDie") == true end

function CM.dodCount(tier)
    local n = CM.TIER_NAME[tier] or "Easy"
    return CM.int(CM.sv("Dod" .. n), 20, 1, 80)
end

-- week number (Monday based, server local time) for the weekly scoreboard
function CM.dodWeek(ts)
    local day = CM.dayKey(ts or CM.now())
    return math.floor((day + 3) / 7)
end

return CM
