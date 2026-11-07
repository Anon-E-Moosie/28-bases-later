-- =============================================
-- 28 Bases Later — Claim Override (Client-Side)
-- =============================================
-- Modifies the world right-click context menu so players can claim
-- multiple safehouses without being blocked by the vanilla 1-base restriction.

require "ISUI/ISWorldObjectContextMenu"

-- Checks if a grid square is inside any registered safehouse in client memory
local function squareIsInSafehouse(square)
    if not square or not SafeHouse or not SafeHouse.getSafeHouse then return false end
    local ok, sh = pcall(function() return SafeHouse.getSafeHouse(square) end)
    return ok and sh ~= nil
end

-- Checks if the clicked location is valid for claiming (inside an unclaimed building)
local function isClaimableLocation(square)
    if not square then return false end

    -- Must be inside a recognized building room
    local ok, room = pcall(function() return square:getRoom() end)
    if not ok or not room then return false end

    -- Must NOT already be in an active safehouse
    if squareIsInSafehouse(square) then return false end

    return true
end

-- -----------------------------------------------
-- ACTION: Send claim command to server
-- -----------------------------------------------
-- Can be called from vanilla context menu (worldobjects, square, playerNum)
-- or custom options (worldobjects, playerObj).
local function doClaimBase(arg1, arg2, arg3)
    local ok, err = pcall(function()
        local playerObj = nil
        local square = nil

        -- Dynamically resolve player and square based on argument types
        if type(arg1) == "userdata" then
            if arg1.getSquare then playerObj = arg1
            elseif arg1.getRoom or arg1.getX then square = arg1 end
        end

        if type(arg2) == "userdata" then
            if arg2.getSquare then playerObj = arg2
            elseif arg2.getRoom or arg2.getX then square = arg2 end
        elseif type(arg2) == "number" then
            playerObj = getSpecificPlayer(arg2)
        end

        if type(arg3) == "number" and not playerObj then
            playerObj = getSpecificPlayer(arg3)
        elseif type(arg3) == "userdata" and not playerObj and arg3.getSquare then
            playerObj = arg3
        end

        if not playerObj then playerObj = getPlayer() end
        if not square and playerObj then square = playerObj:getSquare() end

        if not playerObj or not square then return end

        local room = square:getRoom()
        if not room then
            playerObj:Say("Must be inside a building to claim!")
            return
        end

        local building = room:getBuilding()
        if not building then return end

        local def = building:getDef()
        if not def then return end

        local x  = def:getX()
        local y  = def:getY()
        local w  = def:getX2() - def:getX()
        local h  = def:getY2() - def:getY()

        sendClientCommand(playerObj, "MultiSafehouse", "claimBase", {
            x = x, y = y, w = w, h = h
        })

        playerObj:Say("Claiming base...")
    end)

    if not ok then
        print("[28 Bases Later] doClaimBase error: " .. tostring(err))
    end
end

-- -----------------------------------------------
-- HOOK: Intercept vanilla onTakeSafeHouse
-- -----------------------------------------------
-- When a player clicks the vanilla "Claim Safehouse" option,
-- run our multi-base handler instead of the vanilla single-safehouse limit.
local original_onTakeSafeHouse = ISWorldObjectContextMenu.onTakeSafeHouse
ISWorldObjectContextMenu.onTakeSafeHouse = function(worldobjects, square, player)
    doClaimBase(worldobjects, square, player)
end

-- -----------------------------------------------
-- CONTEXT MENU: Unlock disabled button & add for 2nd+ base
-- -----------------------------------------------
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local ok, err = pcall(function()
        if test or not context then return end

        local player = getSpecificPlayer(playerNum)
        if not player or (player.isDead and player:isDead()) then return end

        local square = player:getSquare()
        if not square then return end

        -- If building is already claimed, hide all claim options
        if not isClaimableLocation(square) then return end

        -- Check if vanilla added a disabled "Claim Safehouse" option (due to 1-base limit)
        local foundVanilla = false
        if context.options then
            for _, opt in ipairs(context.options) do
                if opt and opt.onSelect == ISWorldObjectContextMenu.onTakeSafeHouse then
                    foundVanilla = true
                    -- Strip vanilla's red disabled lockout and tooltip
                    opt.notAvailable = false
                    opt.toolTip = nil
                    break
                end
            end
        end

        -- If vanilla did not add the option at all, add our own
        if not foundVanilla then
            context:addOption(
                "Claim Safehouse",
                worldobjects,
                ISWorldObjectContextMenu.onTakeSafeHouse,
                square,
                playerNum
            )
        end
    end)

    if not ok then
        print("[28 Bases Later] Context menu error: " .. tostring(err))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- -----------------------------------------------
-- SERVER PACKET LISTENERS (Client Replication)
-- -----------------------------------------------
local function onServerCommand(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    -- When server registers a safehouse, add it to local client engine
    if command == "safehouseAdded" then
        if SafeHouse and args.x and args.y and args.w and args.h then
            local fn = SafeHouse.addSafeHouse or SafeHouse.addSafehouse
            if fn then
                pcall(function() return fn(args.x, args.y, args.w, args.h, args.owner) end)
            end
        end

    -- When server removes a safehouse, remove it from local client engine
    elseif command == "safehouseRemoved" then
        if SafeHouse and SafeHouse.getSafehouseList and args.x and args.y then
            local list = SafeHouse.getSafehouseList()
            for i = list:size() - 1, 0, -1 do
                local sh = list:get(i)
                if sh and sh:getX() == args.x and sh:getY() == args.y then
                    if SafeHouse.removeSafeHouse then
                        pcall(function() SafeHouse.removeSafeHouse(sh) end)
                    elseif list.remove then
                        pcall(function() list:remove(sh) end)
                    end
                    break
                end
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

print("[28 Bases Later] Claim override initialized.")
