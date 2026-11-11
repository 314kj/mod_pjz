--[[ ============================================================
  PROJECT DUNKA  [MP]  -- server                    KACHASIG
  Receives "use" requests from clients, validates + fires the
  horde via the authoritative shared logic, replies with result.
  (In singleplayer the client calls DunKa.processUse directly,
   so this file is only needed for real MP servers.)
============================================================ ]]--

require "DunKa_Shared"

local function broadcastBoxes()
    sendServerCommand("DunKa", "boxList", { list = DunKa._boxList() })
end

local function onClientCommand(module, command, player, args)
    if module ~= "DunKa" then return end

    if command == "placeBox" then
        args = args or {}
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then
            print("[DunKa][SV] placeBox DENIED user="..tostring(player and player:getUsername()).." lvl="..lvl)
            sendServerCommand(player, "DunKa", "placeResult", { ok=false, reason="not_admin" })
            return
        end
        print("[DunKa][SV] placeBox recv from "..tostring(player and player:getUsername()))
        local ok, reason = DunKa.doPlaceBox(args.x, args.y, args.z)
        if ok then broadcastBoxes() end
        sendServerCommand(player, "DunKa", "placeResult", {
            ok     = ok and true or false,
            reason = reason,
            x = args.x, y = args.y, z = args.z,
        })
        return
    end

    if command == "helloBoxes" then
        sendServerCommand(player, "DunKa", "boxList", { list = DunKa._boxList() })
        return
    end

    if command == "use" then
        args = args or {}
        local ok, reason, remMs = DunKa.processUse(
            player, args.x, args.y, args.z, args.rank
        )
        if ok then DunKa.applyReward(player, args.rank) end   -- consume card + give slips on SERVER
        sendServerCommand(player, "DunKa", "useResult", {
            ok        = ok and true or false,
            reason    = reason,
            rank      = args.rank,
            remainingMs = remMs or 0,
        })
    end

    if command == "delBox" then
        args = args or {}
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        DunKa.unregisterBox(args.x, args.y, args.z)     -- stop regen
        broadcastBoxes()
        local cell = getCell() or (getWorld() and getWorld():getCell())
        local sq = cell and cell:getGridSquare(args.x, args.y, args.z)
        if sq then
            local objs = sq:getObjects()
            for i=objs:size()-1,0,-1 do
                local o = objs:get(i)
                local md = o.getModData and o:getModData()
                local spr = o.getSprite and o:getSprite()
                local nm = spr and spr.getName and spr:getName()
                if (md and md.DunKaCabinet) or (nm == DunKa.CABINET_SPRITE) then
                    if sq.transmitRemoveItemFromSquare then sq:transmitRemoveItemFromSquare(o)
                    else sq:RemoveTileObject(o) end
                end
            end
        end
        print("[DunKa][SV] delBox at "..tostring(args.x)..","..tostring(args.y))
    end

    if command == "getLog" then
        args = args or {}
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        sendServerCommand(player, "DunKa", "logData", {
            x = args.x, y = args.y, z = args.z,
            entries = DunKa.getLog(args.x, args.y, args.z),
        })
    end

    if command == "openSlip" then
        args = args or {}
        local ok, gained = DunKa.openSlip(player, args.color)
        sendServerCommand(player, "DunKa", "openResult", {
            color  = args.color,
            ok     = ok and true or false,
            gained = ok and gained or nil,
        })
    end

    if command == "getConfig" then
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        sendServerCommand(player, "DunKa", "configData", { slip = DunKa.getSlipConfig(), rank = DunKa.getRankConfig() })
    end

    if command == "getSlipCfg" then
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        sendServerCommand(player, "DunKa", "slipCfg", { cfg = DunKa.getSlipConfig() })
    end

    if command == "setSlipCfg" then
        args = args or {}
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        DunKa.setSlipColor(args.color, args.rolls, args.guaranteed, args.random)
        print("[DunKa][SV] slip config updated: "..tostring(args.color))
    end

    if command == "getRankCfg" then
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        sendServerCommand(player, "DunKa", "rankCfg", { cfg = DunKa.getRankConfig() })
    end

    if command == "setRankCfg" then
        args = args or {}
        local lvl = (player and player.getAccessLevel) and tostring(player:getAccessLevel()):lower() or ""
        if not (lvl=="admin" or lvl=="moderator" or lvl=="gm") then return end
        DunKa.setRankReward(args.rank, args.white, args.yellow, args.blue)
        print("[DunKa][SV] rank reward updated: "..tostring(args.rank))
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[DunKa] server command handler ready")
