-- =============================================
-- 28 Bases Later — Safehouse Claim Validation
-- =============================================
-- Authoritative validation engine loaded on both client and server.
-- Evaluates whether a player is allowed to claim a specific building based on
-- room classifications, spawn point collision, survival time, quota limits,
-- and administrator privileges.

MultiSafehouse = MultiSafehouse or {}
MultiSafehouse.Validation = {}

-- Cached list of extracted spawn point coordinates: { {x = 10420, y = 9812}, ... }
local spawnPointsCache = nil

-- Recognized residential room names in Project Zomboid Build 42.
local RESIDENTIAL_ROOMS = {
    ["bathroom"] = true,
    ["bedroom"] = true,
    ["closet"] = true,
    ["fishingstorage"] = true,
    ["garage"] = true,
    ["hall"] = true,
    ["kidsbedroom"] = true,
    ["kitchen"] = true,
    ["laundry"] = true,
    ["livingroom"] = true,
    ["diningroom"] = true,
    ["sewingroom"] = true,
    ["office"] = true,
    ["emptyoutside"] = true,
    ["empty"] = true,
    ["shed"] = true,
    ["storage"] = true,
}

-- Blacklisted non-residential room types (commercial, municipal, industrial).
local COMMERCIAL_ROOMS = {
    ["policestation"] = true,
    ["prison"] = true,
    ["jail"] = true,
    ["firestation"] = true,
    ["gunstore"] = true,
    ["medical"] = true,
    ["hospital"] = true,
    ["pharmacy"] = true,
    ["clinic"] = true,
    ["grocerystore"] = true,
    ["supermarket"] = true,
    ["convenience"] = true,
    ["warehouse"] = true,
    ["factory"] = true,
    ["bank"] = true,
    ["restaurant"] = true,
    ["bar"] = true,
    ["diner"] = true,
    ["gasstation"] = true,
    ["postoffice"] = true,
    ["school"] = true,
    ["church"] = true,
    ["motel"] = true,
    ["hotel"] = true,
    ["office_building"] = true,
}

-- Staff/admin roles recognized by Project Zomboid Build 42.
-- Normal players ("user", "player", "none", or empty) are excluded.
local ADMIN_ROLES = {
    ["admin"] = true,
    ["moderator"] = true,
    ["overseer"] = true,
    ["gm"] = true,
    ["observer"] = true,
}

-- Checks whether a player has administrator privileges or is running in single-player/host mode.
function MultiSafehouse.Validation.isPlayerAdmin(playerObj)
    if not playerObj then return false end

    -- 1. Native engine global isAdmin() (Build 42 / Build 41 engine function)
    if isAdmin and type(isAdmin) == "function" then
        local ok, res = pcall(isAdmin)
        if ok and res == true then
            return true
        end
    end

    -- 2. Build 42 Role & Capability engine
    if playerObj.getRole then
        local ok, role = pcall(function() return playerObj:getRole() end)
        if ok and role then
            -- Capability check for safehouses
            if Capability and Capability.CanSetupSafehouses and role.hasCapability then
                local okCap, hasCap = pcall(function() return role:hasCapability(Capability.CanSetupSafehouses) end)
                if okCap and hasCap == true then return true end
            end
            -- Admin powers & tools
            if role.hasAdminPower then
                local okPow, hasPow = pcall(function() return role:hasAdminPower() end)
                if okPow and hasPow == true then return true end
            end
            if role.hasAdminTool then
                local okTool, hasTool = pcall(function() return role:hasAdminTool() end)
                if okTool and hasTool == true then return true end
            end
            -- Role name string check
            if role.getName then
                local okName, rName = pcall(function() return role:getName() end)
                if okName and rName then
                    local lowRole = string.lower(tostring(rName))
                    if ADMIN_ROLES[lowRole] then return true end
                end
            end
        end
    end

    -- 3. Access level on player object
    if playerObj.getAccessLevel then
        local ok, access = pcall(function() return playerObj:getAccessLevel() end)
        if ok and access then
            local lowAccess = string.lower(tostring(access))
            if ADMIN_ROLES[lowAccess] then
                return true
            end
        end
    end

    -- 4. Global getAccessLevel() function (PZ client connection state)
    if getAccessLevel and type(getAccessLevel) == "function" then
        local ok, access = pcall(getAccessLevel)
        if ok and access then
            local lowAccess = string.lower(tostring(access))
            if ADMIN_ROLES[lowAccess] then
                return true
            end
        end
    end

    -- 5. Native engine isAccessLevel method
    if playerObj.isAccessLevel then
        for role, _ in pairs(ADMIN_ROLES) do
            local ok, hasRole = pcall(function() return playerObj:isAccessLevel(role) end)
            if ok and hasRole == true then
                return true
            end
        end
    end

    -- 6. Debug mode (Host debug / -debug launch option)
    if getCore and getCore().getDebug and getCore():getDebug() then
        return true
    end
    if isDebugEnabled and isDebugEnabled() then
        return true
    end

    -- 7. Pure Single Player (solo offline games)
    local isMP = (isClient and isClient()) or (isServer and isServer())
    if not isMP then
        return true
    end

    return false
end

-- Extracts absolute tile coordinates from spawn point data tables.
local function extractPointCoords(pt)
    if not pt then return nil end
    local px = pt.posX or pt.x
    local py = pt.posY or pt.y
    if px and py then
        -- Handle chunk/cell relative offsets if present
        if pt.worldX and pt.posX and pt.posX < 300 then
            px = pt.worldX * 300 + pt.posX
        end
        if pt.worldY and pt.posY and pt.posY < 300 then
            py = pt.worldY * 300 + pt.posY
        end
        return { x = math.floor(px), y = math.floor(py) }
    end
    return nil
end

-- Aggregates and caches all map spawn points across all registered regions.
function MultiSafehouse.Validation.getSpawnPoints()
    if spawnPointsCache then
        return spawnPointsCache
    end

    spawnPointsCache = {}

    -- Approach A: Multiplayer server spawn regions
    local regions = nil
    if isClient and isClient() and GameClient and GameClient.instance and GameClient.instance.getServerSpawnRegions then
        pcall(function()
            regions = GameClient.instance:getServerSpawnRegions()
        end)
    end

    -- Approach B: Single-Player / World SpawnRegionMgr
    if not regions and SpawnRegionMgr and SpawnRegionMgr.getSpawnRegions then
        pcall(function()
            regions = SpawnRegionMgr.getSpawnRegions()
        end)
    end

    if regions then
        local regionCount = (regions.size and regions:size()) or #regions
        for i = 0, regionCount - 1 do
            local region = (regions.get and regions:get(i)) or regions[i + 1]
            if region then
                local points = region.points or (region.getPoints and region:getPoints())
                if points then
                    if type(points) == "table" then
                        for _, ptList in pairs(points) do
                            if type(ptList) == "table" then
                                for _, pt in pairs(ptList) do
                                    local coords = extractPointCoords(pt)
                                    if coords then
                                        table.insert(spawnPointsCache, coords)
                                    end
                                end
                            end
                        end
                    elseif points.size then
                        for pIdx = 0, points:size() - 1 do
                            local pt = points:get(pIdx)
                            local coords = extractPointCoords(pt)
                            if coords then
                                table.insert(spawnPointsCache, coords)
                            end
                        end
                    end
                end
            end
        end
    end

    return spawnPointsCache
end

-- Evaluates whether a building contains any map spawn point.
function MultiSafehouse.Validation.isSpawnBuilding(building)
    if not building then return false end
    local def = building:getDef()
    if not def then return false end

    local minX = def:getX()
    local minY = def:getY()
    local maxX = def:getX2()
    local maxY = def:getY2()

    local pts = MultiSafehouse.Validation.getSpawnPoints()
    if not pts or #pts == 0 then return false end

    for _, pt in ipairs(pts) do
        if pt.x >= minX and pt.x <= maxX and pt.y >= minY and pt.y <= maxY then
            return true
        end
    end

    return false
end

-- Evaluates whether a building qualifies as residential.
-- Requires at least one bedroom or livingroom, and no commercial/public rooms.
function MultiSafehouse.Validation.isResidentialBuilding(building)
    if not building then return false end

    local rooms = nil
    if building.getRooms then
        rooms = building:getRooms()
    elseif building.Rooms then
        rooms = building.Rooms
    elseif building.getDef and building:getDef() then
        local def = building:getDef()
        if def.getRooms then
            rooms = def:getRooms()
        elseif def.rooms then
            rooms = def.rooms
        end
    end

    if not rooms then return false end

    local count = 0
    if rooms.size then
        count = rooms:size()
    elseif type(rooms) == "table" then
        count = #rooms
    end

    if count == 0 then
        return false
    end

    local hasBedroomOrLiving = false
    local hasCommercialRoom = false

    for i = 0, count - 1 do
        local rm = (rooms.get and rooms:get(i)) or rooms[i + 1]
        if rm then
            local rName = nil
            if rm.getName then
                rName = rm:getName()
            elseif rm.name then
                rName = rm.name
            elseif rm.getRoomDef and rm:getRoomDef() and rm:getRoomDef().getName then
                rName = rm:getRoomDef():getName()
            end

            if rName and type(rName) == "string" then
                rName = string.lower(rName)
                if rName == "bedroom" or rName == "kidsbedroom" or rName == "livingroom" then
                    hasBedroomOrLiving = true
                end
                if COMMERCIAL_ROOMS[rName] then
                    hasCommercialRoom = true
                end
            end
        end
    end

    return hasBedroomOrLiving and not hasCommercialRoom
end

-- Master validator: checks if a player is permitted to claim a safehouse.
-- Returns: canClaim (boolean), reasons (table of strings/tokens), def (BuildingDef)
function MultiSafehouse.Validation.canClaimSafehouse(square, playerObj, currentBasesCount)
    if not square or not playerObj then
        return false, { "UI_28BL_Claim_MustBeInside" }, nil
    end

    local room = square:getRoom()
    if not room then
        return false, { "UI_28BL_Claim_MustBeInside" }, nil
    end

    local building = room:getBuilding()
    if not building then
        return false, { "UI_28BL_Claim_MustBeInside" }, nil
    end

    local def = building:getDef()
    if not def then
        return false, { "UI_28BL_Claim_MustBeInside" }, nil
    end

    -- 1. Player must be physically inside the building
    local pSquare = playerObj:getCurrentSquare()
    if not pSquare or pSquare:isOutside() or pSquare:getBuilding() ~= building then
        return false, { "UI_28BL_Claim_MustBeInside" }, def
    end

    -- 2. Size limit (MaxDimension)
    local w = def:getW()
    local h = def:getH()
    local maxDim = MultiSafehouse.getMaxDimension()
    if w > maxDim or h > maxDim then
        local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_BuildingTooLarge", tostring(maxDim)))
            or ("Building exceeds maximum allowed dimension (" .. maxDim .. " tiles).")
        return false, { errStr }, def
    end

    -- 3. Collision with an existing claimed safehouse
    if SafeHouse and SafeHouse.getSafehouseList then
        local list = SafeHouse.getSafehouseList()
        if list then
            local bX1 = def:getX()
            local bY1 = def:getY()
            local bX2 = def:getX2()
            local bY2 = def:getY2()

            for i = 0, list:size() - 1 do
                local sh = list:get(i)
                if sh then
                    local shX1 = sh:getX()
                    local shY1 = sh:getY()
                    local shX2 = shX1 + sh:getW()
                    local shY2 = shY1 + sh:getH()

                    -- 2D rectangle intersection check
                    if not (bX2 <= shX1 or bX1 >= shX2 or bY2 <= shY1 or bY1 >= shY2) then
                        local errStr = (getTextOrNull and getTextOrNull("IGUI_Safehouse_Intersects"))
                            or "Building intersects an existing safehouse."
                        return false, { errStr }, def
                    end
                end
            end
        end
    end

    -- 4. Admin bypass check
    local isAdminUser = MultiSafehouse.Validation.isPlayerAdmin(playerObj)
    local adminBypass = MultiSafehouse.isAdminBypassRestrictions()
    if isAdminUser and adminBypass then
        return true, { "UI_28BL_Claim_AdminBypassNotice" }, def
    end

    -- 5. Safehouse quota check (MaxBasesPerPlayer)
    local maxBases = MultiSafehouse.getMaxBasesPerPlayer()
    local currentCount = tonumber(currentBasesCount) or 0
    if maxBases > 0 and currentCount >= maxBases then
        local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_MaxBasesReached", tostring(maxBases)))
            or ("Maximum safehouse limit reached (" .. maxBases .. " bases).")
        return false, { errStr }, def
    end

    -- 6. Survival time requirement (DaysSurvivedToClaim) - 28BL is authoritative
    local requiredDays = MultiSafehouse.getDaysSurvivedToClaim()
    if requiredDays > 0 then
        local hoursSurvived = playerObj:getHoursSurvived() or 0
        local daysSurvived = hoursSurvived / 24
        if daysSurvived < requiredDays then
            local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_DaysRestricted", tostring(requiredDays)))
                or ("Must survive for " .. requiredDays .. " days before claiming a safehouse.")
            return false, { errStr }, def
        end
    end

    -- 7. Spawn building check - 28BL is authoritative
    local allowSpawn = MultiSafehouse.isAllowSpawnBuildings()
    if not allowSpawn then
        if MultiSafehouse.Validation.isSpawnBuilding(building) then
            local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_SpawnRestricted"))
                or "Spawn location. Cannot be claimed as a safehouse."
            return false, { errStr }, def
        end
    end

    -- 8. Non-Residential building check - 28BL is authoritative
    local allowNonRes = MultiSafehouse.isAllowNonResidential()
    if not allowNonRes then
        if not MultiSafehouse.Validation.isResidentialBuilding(building) then
            local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_NonResidentialRestricted"))
                or "Non-residential building. Cannot be claimed as a safehouse."
            return false, { errStr }, def
        end
    end

    -- 9. Vanilla engine check (supplementary check for multiplayer)
    local isMP = (isClient and isClient()) or (isServer and isServer())
    if isMP and SafeHouse and SafeHouse.canBeSafehouse then
        local ok, reason = pcall(function() return SafeHouse.canBeSafehouse(square, playerObj) end)
        if ok and reason and type(reason) == "string" and reason ~= "" then
            -- Check for zombies or other players inside building
            if string.find(reason, "SomeoneInside") then
                local errStr = (getTextOrNull and getTextOrNull("IGUI_Safehouse_SomeoneInside"))
                    or "Area must be clear of zombies and other players."
                return false, { errStr }, def
            end
            -- If vanilla flagged spawn point and 28BL forbids it
            if string.find(reason, "SpawnPoint") and not allowSpawn then
                local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_SpawnRestricted"))
                    or "Spawn location. Cannot be claimed as a safehouse."
                return false, { errStr }, def
            end
            -- If vanilla flagged commercial and 28BL forbids it
            if string.find(reason, "NotHouse") and not allowNonRes then
                local errStr = (getTextOrNull and getTextOrNull("UI_28BL_Claim_NonResidentialRestricted"))
                    or "Non-residential building. Cannot be claimed as a safehouse."
                return false, { errStr }, def
            end
        end
    end

    -- All checks passed!
    return true, {}, def
end
