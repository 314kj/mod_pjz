-- CookieWatch: admin chat switch for Cookie Slicer (the server's java agent).
--   !onslice   Cookie Slicer on
--   !offslice  Cookie Slicer off (the server runs the game's own way)
--   !slice     show its state and the last minute's numbers
-- Only for roles that may change server options (admins). For everyone else the text
-- goes to chat as usual. The server side is server/CookieWatch_SlicerServer.lua.
if isServer() then return end

local MODULE = "CookieSlicer"
local COMMANDS = { onslice = true, offslice = true, slice = true }

local function allowed()
    local ok, yes = pcall(function()
        local p = getPlayer()
        local r = p and p:getRole()
        return r ~= nil and r:hasCapability(Capability.ChangeAndReloadServerOptions)
    end)
    return ok and yes == true
end

local function hook()
    if not ISChat or ISChat.CookieSlicerHooked then return end
    ISChat.CookieSlicerHooked = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local chat = ISChat.instance
        local text = chat and chat.textEntry and chat.textEntry:getText() or ""
        local word = string.match(text, "^%s*!(%a+)%s*$")
        word = word and string.lower(word)
        if word and COMMANDS[word] and allowed() then
            chat:logChatCommand(text)
            chat:unfocus()
            sendClientCommand(getPlayer(), MODULE, word, {})
            doKeyPress(false)
            chat.timerTextEntry = 20
            return
        end
        return original(self)
    end
    -- the chat box may already exist (it keeps the function it was given)
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

local function show(text, box)
    local p = getPlayer()
    if not p or type(text) ~= "string" or text == "" then return end
    for line in string.gmatch(text, "[^\n]+") do
        print("[CookieSlicer] " .. line)
    end
    local first = string.match(text, "^[^\n]+") or text
    pcall(function() p:setHaloNote(first, 140, 230, 140, 600) end)
    if box then
        pcall(function() luautils.okModal(text, true, 560, 150) end)
    end
end

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "reply" or type(args) ~= "table" then return end
    show(args.text, args.box == true)
end

hook()
Events.OnGameStart.Add(hook)
Events.OnServerCommand.Add(onServerCommand)
