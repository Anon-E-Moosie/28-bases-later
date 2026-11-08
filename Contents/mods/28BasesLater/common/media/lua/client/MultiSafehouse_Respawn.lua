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

        -- Native PZ engine teleport (handles chunk streaming, camera centering, and physics)
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
