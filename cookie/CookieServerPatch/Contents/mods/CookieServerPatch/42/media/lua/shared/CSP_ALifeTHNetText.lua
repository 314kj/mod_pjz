-- CookieServerPatch: Project A-Life Thai translation (3806340371, ProjectALifeNPCs_TH 1.4.6) — NPC lines
-- arrive as "àà¸ à¸à¸¡àà¸..." in multiplayer. Server side.
--
-- 9 Nov 2026 screenshots: menu options are proper Thai (they come from the player's own translation files),
-- but every line an NPC says (sent by the server) shows as Latin-1 junk.
-- ZZ_ProjectALife_TH_NetText.lua wraps sendServerCommand on the server and, for A-Life, Jimmy and its radio,
-- turns every Thai character into its UTF-8 bytes, one character per byte. It was written for a server that
-- wrote only the low 8 bits of each character. B42.21 (4a0e9546ec, the current build here) writes and reads
-- server-command strings as real UTF-8 (GameWindow.StringUTF / ByteBufferReader.getUTF), so those byte
-- characters now arrive unchanged and are drawn one by one: Thai "ก" (U+0E01) -> "à¸" + an invisible control.
--
-- Fix: make that encoder hand strings back unchanged (its encodeValue looks Net.encode up at call time), so
-- Thai goes out as Thai and the game's own UTF-8 carries it. The mod's client decoder only acts on its old
-- "@TH@" form, so it stays harmless. Nothing else in the translation mod is touched.
-- If a later game build goes back to 8-bit strings, the old "D!H" junk would return: remove this file then.

if not isServer() then return end

local TAG = "[CookieServerPatch] alife-th-net"
local done = false

local function apply()
    if done then return end
    local Net = ProjectALifeTH and ProjectALifeTH.NetText
    if type(Net) ~= "table" or type(Net.encode) ~= "function" then return end
    Net.encode = function(s) return s end
    Net.CookieServerPatch = true
    done = true
    print(TAG .. " on: Thai in A-Life server commands is sent as is (B42.21 sends UTF-8)")
end

apply()
if not done then
    Events.OnGameBoot.Add(apply)
    if Events.OnServerStarted then Events.OnServerStarted.Add(apply) end
end
