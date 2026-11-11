-- =============================================
-- 28 Bases Later — Server Handler
-- =============================================
-- Server-authoritative logic. Validates all player commands, manages
-- safehouse registration, persists data to ModData, and broadcasts state.

local function getModData()
    return ModData.getOrCreate("28BasesLater")
end

local function isPlayerAdmin(player)
    if not player then return false end
    if player.getAccessLevel then
        local access = player:getAccessLevel()
        if access and access ~= "" and access ~= "none" then
            return true
        end
    end
    if player.isAdmin and player:isAdmin() then
        return true
    end
    if not isClient() and not isServer() then
        return true
    end
    return false
end

local function onInitGlobalModData(isNewGame)
    ModData.getOrCreate("28BasesLater")
    local config = ModData.getOrCreate("28BasesLater_Config")
    if config.maxBasesPerPlayer ~= nil then
        MultiSafehouse.serverMaxBases = config.maxBasesPerPlayer
    end
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)

-- Finds the native Java SafeHouse object at given coordinates
local function findNativeSafehouse(x, y)
    if not SafeHouse or not SafeHouse.getSafehouseList then return nil end
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh and sh:getX() == x and sh:getY() == y then
            return sh
        end
    end
    return nil
end

-- Reconciles 28BL stored bases against the authoritative in-game SafeHouse list.
-- Removes phantom/released bases, syncs native titles, and guarantees no duplicates.
local function reconcilePlayerSafehouses(username)
    local data = getModData()
    data[username] = data[username] or {}
    local stored = data[username]

    if not SafeHouse or not SafeHouse.getSafehouseList then
        return stored
    end

    local list = SafeHouse.getSafehouseList()
    local realMap = {}
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh and sh:getOwner() == username then
            local key = sh:getX() .. "," .. sh:getY()
            realMap[key] = sh
        end
    end

    local reconciled = {}
    local hadRespawn = false

    -- 1. Keep only bases that genuinely still exist in the world
    for _, base in ipairs(stored) do
        local key = base.x .. "," .. base.y
        local sh = realMap[key]
        if sh then
            local nativeTitle = sh:getTitle()
            if nativeTitle and nativeTitle ~= "" then
                base.name = nativeTitle
            end
            base.w = sh:getW()
            base.h = sh:getH()
            if sh.isRespawnInSafehouse then
                base.isRespawn = (sh:isRespawnInSafehouse(username) == true)
            end
            if base.isRespawn then
                hadRespawn = true
            end
            table.insert(reconciled, base)
            realMap[key] = nil
        end
    end

    -- 2. Add any bases claimed outside 28BL (e.g. via vanilla menu)
    for key, sh in pairs(realMap) do
        local baseName = sh:getTitle()
        if not baseName or baseName == "" then
            baseName = "Base #" .. (#reconciled + 1)
            sh:setTitle(baseName)
            if sh.syncSafehouse then sh:syncSafehouse() end
        end
        local isResp = false
        if sh.isRespawnInSafehouse then
            isResp = (sh:isRespawnInSafehouse(username) == true)
        end
        if not hadRespawn and #reconciled == 0 then
            isResp = true
            if sh.setRespawnInSafehouse then
                pcall(function() sh:setRespawnInSafehouse(true, username) end)
            end
        end
        if isResp then hadRespawn = true end

        table.insert(reconciled, {
            x = sh:getX(),
            y = sh:getY(),
            w = sh:getW(),
            h = sh:getH(),
            name = baseName,
            isRespawn = isResp
        })
    end

    -- 3. Ensure player has a designated respawn if they own bases
    if #reconciled > 0 and not hadRespawn then
        reconciled[1].isRespawn = true
        local firstSh = findNativeSafehouse(reconciled[1].x, reconciled[1].y)
        if firstSh and firstSh.setRespawnInSafehouse then
            pcall(function() firstSh:setRespawnInSafehouse(true, username) end)
        end
    end

    data[username] = reconciled
    return reconciled
end

-- Checks if two 2D rectangles overlap.
-- Used to prevent duplicate claims and colliding safehouses.
local function rectsOverlap(x1, y1, w1, h1, x2, y2, w2, h2)
    return not (x1 + w1 <= x2 or x1 >= x2 + w2 or y1 + h1 <= y2 or y1 >= y2 + h2)
end

-- Verifies whether an area already belongs to any registered safehouse.
local function isAreaAlreadyClaimed(x, y, w, h)
    if not SafeHouse or not SafeHouse.getSafehouseList then return false end
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh then
            local sx = sh:getX()
            local sy = sh:getY()
            local sw = sh:getW()
            local shH = sh:getH()
            if rectsOverlap(x, y, w, h, sx, sy, sw, shH) then
                return true
            end
        end
    end
    return false
end

-- Broadcasts newly created safehouse to all online clients so their local
-- engines immediately register anti-trespass and update the world map.
local function broadcastSafehouseAdded(x, y, w, h, owner, name)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return end

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            sendServerCommand(p, "MultiSafehouse", "safehouseAdded", {
                x = x, y = y, w = w, h = h,
                owner = owner,
                name = name
            })
        end
    end
end

-- Broadcasts safehouse removal so all clients dereference it locally.
local function broadcastSafehouseRemoved(x, y, w, h)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return end

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            sendServerCommand(p, "MultiSafehouse", "safehouseRemoved", {
                x = x, y = y, w = w, h = h
            })
        end
    end
end

-- Sanitizes player-provided text strings (prevents UI overflow and save bloat).
local function sanitizeName(input, defaultName)
    if type(input) ~= "string" then return defaultName end
    -- Remove control characters, trim whitespace
    local clean = input:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if not clean or clean == "" then return defaultName end
    -- Enforce maximum of 32 characters
    if #clean > 32 then
        clean = string.sub(clean, 1, 32)
    end
    return clean
end

-- -----------------------------------------------
-- MAIN COMMAND ROUTER
-- -----------------------------------------------
local function onClientCommand(module, command, player, args)
    if module ~= "MultiSafehouse" or not player then return end
    args = args or {}

    local username = player:getUsername()
    local playerSafehouses = reconcilePlayerSafehouses(username)
    local data = getModData()

    -- -------------------------------------------
    -- COMMAND: "claimBase"
    -- -------------------------------------------
    if command == "claimBase" then
        local x = math.floor(tonumber(args.x) or 0)
        local y = math.floor(tonumber(args.y) or 0)
        local w = math.floor(tonumber(args.w) or 0)
        local h = math.floor(tonumber(args.h) or 0)

        -- SECURITY 1: Validate positive dimensions within allowable limits
        local maxDim = MultiSafehouse.getMaxDimension()
        if w <= 0 or h <= 0 or w > maxDim or h > maxDim then
            print("[28 Bases Later] Security: Invalid dimensions requested by " .. username)
            return
        end

        -- SECURITY 2: Distance check (Player must be in/near the building to claim it)
        local px = player:getX()
        local py = player:getY()
        local padding = 6 -- Allow up to 6 tiles outside building bounds
        if px < (x - padding) or px > (x + w + padding) or py < (y - padding) or py > (y + h + padding) then
            print("[28 Bases Later] Security: Remote claim blocked for " .. username .. " (out of range)")
            return
        end

        -- SECURITY 3: Enforce maximum bases per player (0 = unlimited)
        local maxBases = MultiSafehouse.getMaxBasesPerPlayer()
        if maxBases > 0 and #playerSafehouses >= maxBases then
            player:Say("Max safehouse limit reached (" .. maxBases .. ")!")
            return
        end

        -- SECURITY 4: Overlap check (Building must not already be claimed)
        if isAreaAlreadyClaimed(x, y, w, h) then
            player:Say("This building is already claimed!")
            return
        end

        local fn = SafeHouse.addSafeHouse or SafeHouse.addSafehouse
        if not fn then
            print("[28 Bases Later] Error: SafeHouse.addSafeHouse function missing!")
            return
        end

        local ok, result = pcall(function()
            return fn(x, y, w, h, username)
        end)

        if not ok then
            print("[28 Bases Later] addSafeHouse error: " .. tostring(result))
            return
        end

        local baseCount = #playerSafehouses + 1
        local baseName = "Base #" .. baseCount

        -- Set the native title on the newly created safehouse
        local sh = (type(result) == "userdata" and result) or findNativeSafehouse(x, y)
        if sh then
            if sh.setTitle then sh:setTitle(baseName) end
            if sh.syncSafehouse then sh:syncSafehouse() end
        end

        -- Deduplicate: check if this (x, y) already exists
        local alreadyExists = false
        for _, existing in ipairs(playerSafehouses) do
            if existing.x == x and existing.y == y then
                alreadyExists = true
                existing.w = w
                existing.h = h
                existing.name = baseName
                break
            end
        end

        if not alreadyExists then
            local isResp = (baseCount == 1)
            table.insert(playerSafehouses, {
                x = x,
                y = y,
                w = w,
                h = h,
                name = baseName,
                isRespawn = isResp
            })
            if isResp and sh and sh.setRespawnInSafehouse then
                pcall(function() sh:setRespawnInSafehouse(true, username) end)
            end
        end

        data[username] = playerSafehouses

        -- Notify all clients to register safehouse locally
        broadcastSafehouseAdded(x, y, w, h, username, baseName)

        -- Send updated list back to claiming player
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

        print("[28 Bases Later] " .. username .. " claimed base #" .. baseCount .. " (" .. x .. "," .. y .. ")")

    -- -------------------------------------------
    -- COMMAND: "releaseBase"
    -- -------------------------------------------
    elseif command == "releaseBase" then
        local index = math.floor(tonumber(args.index) or 0)
        if index < 1 or index > #playerSafehouses then return end

        local base = playerSafehouses[index]

        -- Remove from server's vanilla SafeHouse list (verifying ownership)
        if SafeHouse and SafeHouse.getSafehouseList then
            local list = SafeHouse.getSafehouseList()
            for i = list:size() - 1, 0, -1 do
                local sh = list:get(i)
                if sh and sh:getX() == base.x and sh:getY() == base.y then
                    if sh:getOwner() == username then
                        if SafeHouse.removeSafeHouse then
                            pcall(function() SafeHouse.removeSafeHouse(sh) end)
                        elseif list.remove then
                            pcall(function() list:remove(sh) end)
                        end
                    end
                    break
                end
            end
        end

        broadcastSafehouseRemoved(base.x, base.y, base.w, base.h)

        local wasRespawn = base.isRespawn
        table.remove(playerSafehouses, index)

        -- Fallback: If player released their respawn base, assign remaining first base
        if wasRespawn and #playerSafehouses > 0 then
            playerSafehouses[1].isRespawn = true
        end

        data[username] = playerSafehouses

        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

        print("[28 Bases Later] " .. username .. " released base #" .. index)

    -- -------------------------------------------
    -- COMMAND: "renameBase"
    -- -------------------------------------------
    elseif command == "renameBase" then
        local index = math.floor(tonumber(args.index) or 0)
        if index < 1 or index > #playerSafehouses then return end

        local cleanName = sanitizeName(args.newName, "Base #" .. index)
        local base = playerSafehouses[index]

        -- Update native engine safehouse so Vanilla and Better Safehouse see the new title
        local sh = findNativeSafehouse(base.x, base.y)
        if sh then
            sh:setTitle(cleanName)
            if sh.syncSafehouse then
                sh:syncSafehouse()
            end
        end

        base.name = cleanName
        data[username] = playerSafehouses

        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

    -- -------------------------------------------
    -- COMMAND: "setRespawn"
    -- -------------------------------------------
    elseif command == "setRespawn" then
        local index = math.floor(tonumber(args.index) or 0)
        if index < 1 or index > #playerSafehouses then return end

        for i, base in ipairs(playerSafehouses) do
            local isTarget = (i == index)
            base.isRespawn = isTarget
            local sh = findNativeSafehouse(base.x, base.y)
            if sh and sh.setRespawnInSafehouse then
                pcall(function()
                    sh:setRespawnInSafehouse(isTarget, username)
                    if sh.syncSafehouse then sh:syncSafehouse() end
                end)
            end
        end

        data[username] = playerSafehouses

        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

    -- -------------------------------------------
    -- COMMAND: "checkRespawn"
    -- -------------------------------------------
    elseif command == "checkRespawn" then
        for _, base in ipairs(playerSafehouses) do
            if base.isRespawn then
                local spawnX = math.floor(base.x + (base.w / 2))
                local spawnY = math.floor(base.y + (base.h / 2))

                sendServerCommand(player, "MultiSafehouse", "teleportToRespawn", {
                    x = spawnX,
                    y = spawnY,
                    z = 0,
                    name = base.name
                })
                return
            end
        end

    -- -------------------------------------------
    -- COMMAND: "requestData"
    -- -------------------------------------------
    elseif command == "requestData" then
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

    -- -------------------------------------------
    -- COMMAND: "setAdminConfig"
    -- -------------------------------------------
    elseif command == "setAdminConfig" then
        if not isPlayerAdmin(player) then
            print("[28 Bases Later] Security: Non-admin " .. username .. " attempted to modify server config.")
            return
        end

        local requestedCap = tonumber(args.maxBases)
        if requestedCap ~= nil then
            local sanitizedCap = math.max(0, math.min(100, math.floor(requestedCap)))
            MultiSafehouse.serverMaxBases = sanitizedCap

            local configData = ModData.getOrCreate("28BasesLater_Config")
            configData.maxBasesPerPlayer = sanitizedCap

            local players = getOnlinePlayers and getOnlinePlayers() or nil
            if players then
                for i = 0, players:size() - 1 do
                    local p = players:get(i)
                    if p then
                        sendServerCommand(p, "MultiSafehouse", "syncAdminConfig", {
                            maxBases = sanitizedCap
                        })
                    end
                end
            end

            print("[28 Bases Later] Admin " .. username .. " updated max safehouses to: " .. sanitizedCap)
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[28 Bases Later] Server handler initialized.")
