-- =============================================
-- 28 Bases Later — Respawn Handler (Client-Side)
-- =============================================
-- Hooks player creation to detect when a fresh character is made after dying.
-- Requests safehouse respawn coordinates from the server and performs the teleport.

local function onCreatePlayer(playerNum, player)
    local p = type(playerNum) == "number" and getSpecificPlayer(playerNum) or player

    -- Guard: Existing survivors reconnecting to the server already have survived > 0 hours.
    -- We exit immediately so their in-game location is never modified.
    if p and p.getHoursSurvived and p:getHoursSurvived() > 0 then
        return
    end

    -- Wait ~2 seconds (120 ticks) for the initial world chunks to stream in
    local ticksWaited = 0

    local function waitThenRequest()
        ticksWaited = ticksWaited + 1

        if ticksWaited >= 120 then
            local pObj = getSpecificPlayer(playerNum)
            if pObj and pObj.getHoursSurvived and pObj:getHoursSurvived() <= 0.01 then
                sendClientCommand(pObj, "MultiSafehouse", "checkRespawn", {})
                sendClientCommand(pObj, "MultiSafehouse", "requestData", {})
            end

            Events.OnTick.Remove(waitThenRequest)
        end
    end

    Events.OnTick.Add(waitThenRequest)
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
