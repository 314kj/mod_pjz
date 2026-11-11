-- CookieServerPatch: The Only Cure+ (3818733381) Cyber arm Strength bonus, client half. Multiplayer only.
--
-- TOC+ client/TOC/Plus/CyberStrength.lua raises Strength on the client and sends it with SyncXp, which
-- gets every non-admin kicked ("PlayerXp: no capability"). In multiplayer the bonus is now given by the
-- server (server/CSP_TOCCyberStrength.lua), so TOC+'s client loop is turned off here: its OnPlayerUpdate
-- calls CyberStrength.Update through the module table, so replacing that one field is enough.
-- Single player keeps TOC+'s own version.
-- Installed after all Lua has loaded (OnGameBoot / OnGameStart) so require returns TOC+'s own table.

if isServer() or not isClient() then return end

local TAG = "[CookieServerPatch] toc-cyber-strength"
local installed = false

local function install()
    if installed then return end
    local ok, CS = pcall(require, "TOC/Plus/CyberStrength")
    if not ok or type(CS) ~= "table" or type(CS.Update) ~= "function" then return end
    CS.Update = function() end
    CS.CookieServerPatch = true
    installed = true
    print(TAG .. " client loop off (the server gives the bonus)")
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
