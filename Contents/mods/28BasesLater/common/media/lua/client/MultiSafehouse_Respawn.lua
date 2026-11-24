-- =============================================
-- 28 Bases Later — Respawn Handler (Client-Side)
-- =============================================
-- Hooks player creation to detect when a fresh character is made after dying.
-- Requests safehouse respawn coordinates from the server and performs the teleport.

local function onCreatePlayer(playerNum, player)
    local ticksWaited = 0

    local function onPlayerInitTick()
        ticksWaited = ticksWaited + 1

        local pObj = type(playerNum) == "number" and getSpecificPlayer(playerNum) or player

        -- 1. DATA HYDRATION: Request base names for ALL players (reconnecting or brand new)
        -- We wait 30 ticks (~0.5 sec) to give the network connection time to settle.
        if ticksWaited == 30 then
            if pObj then
                sendClientCommand(pObj, "MultiSafehouse", "requestData", { reason = "connect" })
            end
        end

        -- 2. RESPAWN TELEPORT: Only for fresh characters who just died and respawned
        -- We wait 120 ticks (~2 sec) so the map chunks have time to load around them.
        if ticksWaited >= 120 then
            if pObj and pObj.getHoursSurvived and pObj:getHoursSurvived() <= 0.01 then
                sendClientCommand(pObj, "MultiSafehouse", "checkRespawn", { reason = "newCharacter" })
            end

            -- Remove our timer once all checks are done
            Events.OnTick.Remove(onPlayerInitTick)
        end
    end

    Events.OnTick.Add(onPlayerInitTick)
end

Events.OnCreatePlayer.Add(onCreatePlayer)

-- -----------------------------------------------
-- TELEPORT LISTENER
-- -----------------------------------------------
-- Executes the physical survivor teleport once the server approves the respawn base.
local function onServerCommand(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    if command == "teleportToRespawn" and args.x and args.y then
        local player = getPlayer()
        if not player then return end

        local targetX = args.x + 0.5
        local targetY = args.y + 0.5
        local targetZ = args.z or 0

        -- Check if destination is an RV Interior pocket dimension
        local isRV = args.isRV or (args.x >= 22500 and args.y >= 12000)

        if isRV then
            -- 1. Hydrate RV modData if available so player has exit interaction
            if args.rvData then
                pcall(function()
                    local pmd = player:getModData()
                    if pmd then
                        if args.rvData.roomX and args.rvData.roomY then
                            pmd.projectRV_room = {
                                x = args.rvData.roomX,
                                y = args.rvData.roomY,
                                z = args.rvData.roomZ or 0
                            }
                        end
                        if args.rvData.vehicleId then
                            pmd.projectRV_vehicleId = tonumber(args.rvData.vehicleId) or args.rvData.vehicleId
                        end
                        if args.rvData.typeKey then
                            pmd.projectRV_typeKey = args.rvData.typeKey
                        end
                    end
                end)
            end

            -- 2. Stream chunk watcher: wait up to 60 ticks (~1 sec) for floor to instantiate
            local ticksWaited = 0
            local function onStreamRVTick()
                ticksWaited = ticksWaited + 1
                local cell = getCell()
                local floorExists = false
                if cell then
                    local sq = cell:getGridSquare(math.floor(targetX), math.floor(targetY), targetZ)
                    if sq and (sq:getFloor() ~= nil or (sq:getObjects() and sq:getObjects():size() > 0)) then
                        floorExists = true
                    end
                end

                if floorExists or ticksWaited >= 60 then
                    Events.OnTick.Remove(onStreamRVTick)

                    local ok = pcall(function()
                        player:teleportTo(targetX, targetY, targetZ)
                    end)
                    if not ok then
                        pcall(function()
                            player:setX(targetX)
                            player:setY(targetY)
                            player:setZ(targetZ)
                        end)
                    end

                    player:Say("Respawned at " .. (args.name or "RV Safehouse"))
                end
            end

            Events.OnTick.Add(onStreamRVTick)
            return
        end

        -- Standard base teleport
        local ok = pcall(function()
            player:teleportTo(targetX, targetY, targetZ)
        end)

        -- Fallback coordinate setter if teleportTo encounters an issue
        if not ok then
            pcall(function()
                player:setX(targetX)
                player:setY(targetY)
                player:setZ(targetZ)
            end)
        end

        player:Say("Respawned at " .. (args.name or "Base"))
    end
end

Events.OnServerCommand.Add(onServerCommand)

print("[28 Bases Later] Respawn handler initialized.")
