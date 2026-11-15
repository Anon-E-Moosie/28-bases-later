-- =============================================
-- 28 Bases Later — Server Handler
-- =============================================
-- Server-authoritative logic. Validates all player commands, manages
-- safehouse registration, persists data to ModData, enforces permissions,
-- and synchronizes state with connected clients.

local function getModData()
    return ModData.getOrCreate("28BasesLater")
end

-- Staff/admin roles recognized by Project Zomboid Build 42
local ADMIN_ROLES = {
    ["admin"] = true,
    ["moderator"] = true,
    ["overseer"] = true,
    ["gm"] = true,
    ["observer"] = true,
}

local function isPlayerAdmin(player)
    if MultiSafehouse.Validation and MultiSafehouse.Validation.isPlayerAdmin then
        return MultiSafehouse.Validation.isPlayerAdmin(player)
    end
    if not player then return false end
    if isAdmin and type(isAdmin) == "function" then
        local ok, res = pcall(isAdmin)
        if ok and res == true then return true end
    end
    if player.getRole then
        local ok, role = pcall(function() return player:getRole() end)
        if ok and role then
            if role.hasAdminPower and role:hasAdminPower() then return true end
            if role.getName and ADMIN_ROLES[string.lower(tostring(role:getName()))] then return true end
        end
    end
    if player.getAccessLevel then
        local access = string.lower(player:getAccessLevel() or "")
        if ADMIN_ROLES[access] then return true end
    end
    if not isClient() and not isServer() then return true end
    return false
end

local function onInitGlobalModData(isNewGame)
    ModData.getOrCreate("28BasesLater")
    local config = ModData.getOrCreate("28BasesLater_Config")
    if config.maxBasesPerPlayer ~= nil then
        MultiSafehouse.serverMaxBases = config.maxBasesPerPlayer
        MultiSafehouse.server_MaxBasesPerPlayer = config.maxBasesPerPlayer
    end
    if config.allowNonResidential ~= nil then
        MultiSafehouse.serverAllowNonResidential = config.allowNonResidential
        MultiSafehouse.server_AllowNonResidential = config.allowNonResidential
    end
    if config.allowSpawnBuildings ~= nil then
        MultiSafehouse.serverAllowSpawnBuildings = config.allowSpawnBuildings
        MultiSafehouse.server_AllowSpawnBuildings = config.allowSpawnBuildings
    end
    if config.daysSurvivedToClaim ~= nil then
        MultiSafehouse.serverDaysSurvivedToClaim = config.daysSurvivedToClaim
        MultiSafehouse.server_DaysSurvivedToClaim = config.daysSurvivedToClaim
    end
    if config.adminBypassRestrictions ~= nil then
        MultiSafehouse.serverAdminBypassRestrictions = config.adminBypassRestrictions
        MultiSafehouse.server_AdminBypassRestrictions = config.adminBypassRestrictions
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

-- Extracts a table of member usernames from a Java SafeHouse, excluding the owner
local function extractSafehouseMembers(sh, ownerUsername)
    local members = {}
    if not sh or not sh.getPlayers then return members end
    local ok, players = pcall(function() return sh:getPlayers() end)
    if not ok or not players then return members end
    local okSize, n = pcall(function() return players:size() end)
    if not okSize or type(n) ~= "number" then return members end
    for i = 0, n - 1 do
        local okGet, u = pcall(function() return players:get(i) end)
        if okGet and u then
            local uName = tostring(u)
            if uName ~= "" and uName ~= ownerUsername then
                table.insert(members, uName)
            end
        end
    end
    return members
end

-- Resolves an online player by username
local function findOnlinePlayer(username)
    if not username or username == "" then return nil end
    if getPlayerFromUsername then
        local ok, p = pcall(function() return getPlayerFromUsername(username) end)
        if ok and p then return p end
    end
    if getOnlinePlayers then
        local ok, list = pcall(getOnlinePlayers)
        if ok and list and list.size then
            for i = 0, list:size() - 1 do
                local p = list:get(i)
                if p and p.getUsername and tostring(p:getUsername()) == username then
                    return p
                end
            end
        end
    end
    return nil
end

-- Locates a safehouse in ModData across all owners by coordinate
local function findSafehouseRecord(x, y)
    local data = getModData()
    for ownerName, bases in pairs(data) do
        if type(bases) == "table" then
            for idx, base in ipairs(bases) do
                if base.x == x and base.y == y then
                    return base, idx, ownerName
                end
            end
        end
    end
    return nil, nil, nil
end

-- Reconciles 28BL stored bases against the authoritative in-game SafeHouse list.
-- Aggregates both owned bases and member bases into a unified accessible list.
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

    local reconciledOwned = {}
    local hadRespawn = false

    -- 1. Keep only owned bases that genuinely still exist in the world
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
            base.owner = username
            base.isOwner = true
            if sh.isRespawnInSafehouse then
                base.isRespawn = (sh:isRespawnInSafehouse(username) == true)
            end
            if base.isRespawn then
                hadRespawn = true
            end
            base.members = extractSafehouseMembers(sh, username)
            table.insert(reconciledOwned, base)
            realMap[key] = nil
        end
    end

    -- 2. Add any bases claimed outside 28BL (e.g. via vanilla menu) where player is owner
    for key, sh in pairs(realMap) do
        local baseName = sh:getTitle()
        if not baseName or baseName == "" then
            baseName = "Base #" .. (#reconciledOwned + 1)
            sh:setTitle(baseName)
            if sh.syncSafehouse then sh:syncSafehouse() end
        end
        local isResp = false
        if sh.isRespawnInSafehouse then
            isResp = (sh:isRespawnInSafehouse(username) == true)
        end
        if not hadRespawn and #reconciledOwned == 0 then
            isResp = true
            if sh.setRespawnInSafehouse then
                pcall(function() sh:setRespawnInSafehouse(true, username) end)
            end
        end
        if isResp then hadRespawn = true end

        table.insert(reconciledOwned, {
            x = sh:getX(),
            y = sh:getY(),
            w = sh:getW(),
            h = sh:getH(),
            name = baseName,
            owner = username,
            isOwner = true,
            isRespawn = isResp,
            members = extractSafehouseMembers(sh, username)
        })
    end

    -- 3. Ensure player has a designated respawn if they own bases
    if #reconciledOwned > 0 and not hadRespawn then
        reconciledOwned[1].isRespawn = true
        local firstSh = findNativeSafehouse(reconciledOwned[1].x, reconciledOwned[1].y)
        if firstSh and firstSh.setRespawnInSafehouse then
            pcall(function() firstSh:setRespawnInSafehouse(true, username) end)
        end
    end

    -- Persist authoritative owned bases back to ModData[username]
    data[username] = reconciledOwned

    -- 4. Aggregate member bases (bases owned by someone else where username is in players list)
    local allAccessibleBases = {}
    for _, b in ipairs(reconciledOwned) do
        table.insert(allAccessibleBases, b)
    end

    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh and sh:getOwner() ~= username then
            local players = sh:getPlayers()
            if players and players:contains(username) then
                local isResp = false
                if sh.isRespawnInSafehouse then
                    isResp = (sh:isRespawnInSafehouse(username) == true)
                end
                local baseTitle = sh:getTitle()
                if not baseTitle or baseTitle == "" then
                    baseTitle = "Shared Safehouse"
                end
                local memberBase = {
                    x = sh:getX(),
                    y = sh:getY(),
                    w = sh:getW(),
                    h = sh:getH(),
                    name = baseTitle,
                    owner = sh:getOwner(),
                    isOwner = false,
                    isRespawn = isResp,
                    members = extractSafehouseMembers(sh, sh:getOwner())
                }
                table.insert(allAccessibleBases, memberBase)
            end
        end
    end

    return allAccessibleBases
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
    local clean = input:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if not clean or clean == "" then return defaultName end
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
        local padding = 6
        if px < (x - padding) or px > (x + w + padding) or py < (y - padding) or py > (y + h + padding) then
            print("[28 Bases Later] Security: Remote claim blocked for " .. username .. " (out of range)")
            return
        end

        -- Calculate owned bases count (quota applies only to owned bases)
        local ownedCount = 0
        for _, b in ipairs(playerSafehouses) do
            if b.isOwner ~= false and (b.owner == nil or b.owner == username) then
                ownedCount = ownedCount + 1
            end
        end

        -- SECURITY 3: Run authoritative claim validation engine
        local square = player:getSquare()
        if not square then
            square = getSquare(x + math.floor(w / 2), y + math.floor(h / 2), 0)
        end

        if MultiSafehouse.Validation and MultiSafehouse.Validation.canClaimSafehouse then
            local canClaim, reasons = MultiSafehouse.Validation.canClaimSafehouse(square, player, ownedCount)
            if not canClaim then
                local firstReason = (reasons and reasons[1]) or "Cannot claim safehouse!"
                local displayMsg = (getTextOrNull and getTextOrNull(firstReason)) or firstReason
                player:Say(displayMsg)
                print("[28 Bases Later] Server rejected claim by " .. username .. ": " .. tostring(firstReason))
                return
            end
        end

        -- SECURITY 4: Enforce maximum bases per player (0 = unlimited)
        local maxBases = MultiSafehouse.getMaxBasesPerPlayer()
        if maxBases > 0 and ownedCount >= maxBases then
            player:Say("Max safehouse limit reached (" .. maxBases .. ")!")
            return
        end

        -- SECURITY 5: Overlap check (Building must not already be claimed)
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

        local ownedData = data[username] or {}
        local baseCount = #ownedData + 1
        local baseName = "Base #" .. baseCount

        -- Set the native title on the newly created safehouse
        local sh = (type(result) == "userdata" and result) or findNativeSafehouse(x, y)
        if not sh then
            print("[28 Bases Later] Error: Engine refused to create SafeHouse at (" .. x .. "," .. y .. ")")
            player:Say("Cannot claim safehouse (Building claim refused).")
            return
        end

        if sh.setTitle then sh:setTitle(baseName) end
        if sh.syncSafehouse then sh:syncSafehouse() end

        local isResp = (baseCount == 1)
        table.insert(ownedData, {
            x = x,
            y = y,
            w = w,
            h = h,
            name = baseName,
            owner = username,
            isOwner = true,
            isRespawn = isResp,
            members = {}
        })
        if isResp and sh and sh.setRespawnInSafehouse then
            pcall(function() sh:setRespawnInSafehouse(true, username) end)
        end

        data[username] = ownedData

        -- Notify all clients to register safehouse locally
        broadcastSafehouseAdded(x, y, w, h, username, baseName)

        -- Reconcile and send full updated list to claiming player
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

        print("[28 Bases Later] " .. username .. " claimed base #" .. baseCount .. " (" .. x .. "," .. y .. ")")

    -- -------------------------------------------
    -- COMMAND: "releaseBase"
    -- -------------------------------------------
    elseif command == "releaseBase" then
        local x = args.x and math.floor(tonumber(args.x) or 0) or nil
        local y = args.y and math.floor(tonumber(args.y) or 0) or nil
        local index = math.floor(tonumber(args.index) or 0)

        local targetBase = nil
        if x and y then
            for _, b in ipairs(playerSafehouses) do
                if b.x == x and b.y == y then
                    targetBase = b
                    break
                end
            end
        end
        if not targetBase and index >= 1 and index <= #playerSafehouses then
            targetBase = playerSafehouses[index]
        end

        if not targetBase then return end

        local bx = targetBase.x
        local by = targetBase.y
        local bw = targetBase.w
        local bh = targetBase.h

        local baseRecord, baseIdx, baseOwner = findSafehouseRecord(bx, by)
        local isOwner = (baseOwner == username) or (targetBase.owner == username)
        local isAdmin = isPlayerAdmin(player)

        if not (isOwner or isAdmin) then
            print("[28 Bases Later] Security: Non-owner " .. username .. " attempted to release base at (" .. bx .. "," .. by .. ")")
            player:Say("Only the safehouse owner can release this base.")
            return
        end

        local actualOwner = baseOwner or targetBase.owner or username
        local membersToNotify = {}
        if baseRecord and baseRecord.members then
            for _, m in ipairs(baseRecord.members) do
                table.insert(membersToNotify, m)
            end
        end

        -- Remove from server's vanilla SafeHouse list
        if SafeHouse and SafeHouse.getSafehouseList then
            local list = SafeHouse.getSafehouseList()
            for i = list:size() - 1, 0, -1 do
                local sh = list:get(i)
                if sh and sh:getX() == bx and sh:getY() == by then
                    if SafeHouse.removeSafeHouse then
                        pcall(function() SafeHouse.removeSafeHouse(sh) end)
                    elseif list.remove then
                        pcall(function() list:remove(sh) end)
                    end
                    break
                end
            end
        end

        broadcastSafehouseRemoved(bx, by, bw, bh)

        -- Remove from ModData[actualOwner]
        if data[actualOwner] and baseIdx then
            table.remove(data[actualOwner], baseIdx)
        end

        -- Send updated list back to releasing player
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

        -- Notify and sync online members so base disappears from their UI
        for _, memberName in ipairs(membersToNotify) do
            local mp = findOnlinePlayer(memberName)
            if mp and memberName ~= username then
                sendServerCommand(mp, "MultiSafehouse", "syncData", {
                    safehouses = reconcilePlayerSafehouses(memberName)
                })
            end
        end

        print("[28 Bases Later] " .. username .. " released base at (" .. bx .. "," .. by .. ") owned by " .. tostring(actualOwner))

    -- -------------------------------------------
    -- COMMAND: "renameBase"
    -- -------------------------------------------
    elseif command == "renameBase" then
        local x = args.x and math.floor(tonumber(args.x) or 0) or nil
        local y = args.y and math.floor(tonumber(args.y) or 0) or nil
        local index = math.floor(tonumber(args.index) or 0)

        local targetBase = nil
        if x and y then
            for _, b in ipairs(playerSafehouses) do
                if b.x == x and b.y == y then
                    targetBase = b
                    break
                end
            end
        end
        if not targetBase and index >= 1 and index <= #playerSafehouses then
            targetBase = playerSafehouses[index]
        end

        if not targetBase then return end

        local bx = targetBase.x
        local by = targetBase.y

        local baseRecord, baseIdx, baseOwner = findSafehouseRecord(bx, by)
        local isOwner = (baseOwner == username) or (targetBase.owner == username)
        local isAdmin = isPlayerAdmin(player)

        if not (isOwner or isAdmin) then
            print("[28 Bases Later] Security: Non-owner " .. username .. " attempted to rename base at (" .. bx .. "," .. by .. ")")
            player:Say("Only the safehouse owner can rename this base.")
            return
        end

        local cleanName = sanitizeName(args.newName, targetBase.name or "Base")

        -- Update native engine safehouse on server
        local sh = findNativeSafehouse(bx, by)
        if sh then
            sh:setTitle(cleanName)
            if sh.syncSafehouse then sh:syncSafehouse() end
        end

        if baseRecord then
            baseRecord.name = cleanName
        end

        local actualOwner = baseOwner or targetBase.owner or username
        local membersToNotify = (baseRecord and baseRecord.members) or {}

        -- Sync caller
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

        -- Sync owner if caller was admin
        if actualOwner ~= username then
            local op = findOnlinePlayer(actualOwner)
            if op then
                sendServerCommand(op, "MultiSafehouse", "syncData", {
                    safehouses = reconcilePlayerSafehouses(actualOwner)
                })
            end
        end

        -- Sync online members
        for _, memberName in ipairs(membersToNotify) do
            local mp = findOnlinePlayer(memberName)
            if mp and memberName ~= username then
                sendServerCommand(mp, "MultiSafehouse", "syncData", {
                    safehouses = reconcilePlayerSafehouses(memberName)
                })
            end
        end

    -- -------------------------------------------
    -- COMMAND: "setRespawn"
    -- -------------------------------------------
    elseif command == "setRespawn" then
        local x = args.x and math.floor(tonumber(args.x) or 0) or nil
        local y = args.y and math.floor(tonumber(args.y) or 0) or nil
        local index = math.floor(tonumber(args.index) or 0)

        local targetBase = nil
        if x and y then
            for _, b in ipairs(playerSafehouses) do
                if b.x == x and b.y == y then
                    targetBase = b
                    break
                end
            end
        end
        if not targetBase and index >= 1 and index <= #playerSafehouses then
            targetBase = playerSafehouses[index]
        end

        if not targetBase then return end

        for _, base in ipairs(playerSafehouses) do
            local isTarget = (base.x == targetBase.x and base.y == targetBase.y)
            base.isRespawn = isTarget
            local sh = findNativeSafehouse(base.x, base.y)
            if sh and sh.setRespawnInSafehouse then
                pcall(function()
                    sh:setRespawnInSafehouse(isTarget, username)
                    if sh.syncSafehouse then sh:syncSafehouse() end
                end)
            end
        end

        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })

    -- -------------------------------------------
    -- COMMAND: "inviteMember"
    -- -------------------------------------------
    elseif command == "inviteMember" then
        local x = math.floor(tonumber(args.x) or 0)
        local y = math.floor(tonumber(args.y) or 0)
        local target = sanitizeName(args.targetUsername, "")
        if target == "" or target == username then return end

        local sh = findNativeSafehouse(x, y)
        if not sh then
            player:Say("Safehouse not found.")
            return
        end

        local baseRecord, baseIdx, baseOwner = findSafehouseRecord(x, y)
        local actualOwner = (sh.getOwner and sh:getOwner()) or baseOwner or username
        local isOwner = (actualOwner == username)
        local isAdmin = isPlayerAdmin(player)

        if not (isOwner or isAdmin) then
            print("[28 Bases Later] Security: Non-owner " .. username .. " attempted to invite to safehouse at (" .. x .. "," .. y .. ")")
            player:Say("Only the safehouse owner can invite members.")
            return
        end

        -- Check if target is online
        local targetPlayer = findOnlinePlayer(target)
        if not targetPlayer then
            player:Say("Player '" .. target .. "' is not online.")
            return
        end

        -- Check if target is already in the safehouse whitelist
        local players = sh:getPlayers()
        if players and players:contains(target) then
            player:Say("'" .. target .. "' is already a member of this safehouse.")
            return
        end

        -- Whitelist target in native Java engine SafeHouse
        if sh.addPlayer then
            pcall(function() sh:addPlayer(target) end)
        end
        if sh.syncSafehouse then
            pcall(function() sh:syncSafehouse() end)
        end

        -- Update ModData record if present
        if baseRecord then
            baseRecord.members = baseRecord.members or {}
            local exists = false
            for _, m in ipairs(baseRecord.members) do
                if m == target then exists = true; break end
            end
            if not exists then
                table.insert(baseRecord.members, target)
            end
        end

        local baseName = sh:getTitle() or (baseRecord and baseRecord.name) or "Safehouse"

        -- Sync caller
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })
        player:Say("Invited " .. target .. " to safehouse '" .. baseName .. "'.")

        -- Sync target player
        sendServerCommand(targetPlayer, "MultiSafehouse", "syncData", {
            safehouses = reconcilePlayerSafehouses(target)
        })
        targetPlayer:Say("Added to safehouse '" .. baseName .. "' by " .. username .. "!")

        print("[28 Bases Later] " .. username .. " added " .. target .. " to safehouse '" .. baseName .. "' (" .. x .. "," .. y .. ")")

    -- -------------------------------------------
    -- COMMAND: "kickMember"
    -- -------------------------------------------
    elseif command == "kickMember" then
        local x = math.floor(tonumber(args.x) or 0)
        local y = math.floor(tonumber(args.y) or 0)
        local target = sanitizeName(args.targetUsername, "")
        if target == "" then return end

        local sh = findNativeSafehouse(x, y)
        if not sh then
            player:Say("Safehouse not found.")
            return
        end

        local baseRecord, baseIdx, baseOwner = findSafehouseRecord(x, y)
        local actualOwner = (sh.getOwner and sh:getOwner()) or baseOwner or username
        local isOwner = (actualOwner == username)
        local isAdmin = isPlayerAdmin(player)

        if not (isOwner or isAdmin) then
            print("[28 Bases Later] Security: Non-owner " .. username .. " attempted to kick member from (" .. x .. "," .. y .. ")")
            player:Say("Only the safehouse owner can remove members.")
            return
        end

        if target == actualOwner then
            player:Say("Cannot remove the safehouse owner.")
            return
        end

        -- Check if target is actually in safehouse whitelist
        local players = sh:getPlayers()
        if not players or not players:contains(target) then
            player:Say("'" .. target .. "' is not a member of this safehouse.")
            return
        end

        -- Evict player using Build 42 native engine kick (removes from list & ejects from bounds)
        if SafeHouse.kickUserFromSafehouse then
            pcall(function() SafeHouse.kickUserFromSafehouse(sh, target) end)
        elseif sh.removePlayer then
            pcall(function() sh:removePlayer(target) end)
        end

        if sh.syncSafehouse then
            pcall(function() sh:syncSafehouse() end)
        end

        -- Clear any respawn point target had at this safehouse
        if sh.setRespawnInSafehouse then
            pcall(function() sh:setRespawnInSafehouse(false, target) end)
        end

        -- Update ModData record if present
        if baseRecord and baseRecord.members then
            for idx = #baseRecord.members, 1, -1 do
                if baseRecord.members[idx] == target then
                    table.remove(baseRecord.members, idx)
                end
            end
        end

        local baseName = sh:getTitle() or (baseRecord and baseRecord.name) or "Safehouse"

        -- Sync caller
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })
        player:Say("Removed " .. target .. " from safehouse '" .. baseName .. "'.")

        -- Sync target player if online
        local targetPlayer = findOnlinePlayer(target)
        if targetPlayer then
            sendServerCommand(targetPlayer, "MultiSafehouse", "syncData", {
                safehouses = reconcilePlayerSafehouses(target)
            })
            targetPlayer:Say("Removed from safehouse '" .. baseName .. "'.")
        end

        print("[28 Bases Later] " .. username .. " kicked " .. target .. " from safehouse '" .. baseName .. "' (" .. x .. "," .. y .. ")")

    -- -------------------------------------------
    -- COMMAND: "leaveBase"
    -- -------------------------------------------
    elseif command == "leaveBase" then
        local x = math.floor(tonumber(args.x) or 0)
        local y = math.floor(tonumber(args.y) or 0)

        local sh = findNativeSafehouse(x, y)
        if not sh then
            player:Say("Safehouse not found.")
            return
        end

        local baseRecord, baseIdx, baseOwner = findSafehouseRecord(x, y)
        local actualOwner = (sh.getOwner and sh:getOwner()) or baseOwner

        if actualOwner == username then
            player:Say("Safehouse owner cannot leave their own safehouse. Use 'Release' to abandon.")
            return
        end

        -- Check if player is currently in safehouse whitelist
        local players = sh:getPlayers()
        if not players or not players:contains(username) then
            player:Say("You are not a member of this safehouse.")
            return
        end

        -- Evict caller using native kick/remove
        if SafeHouse.kickUserFromSafehouse then
            pcall(function() SafeHouse.kickUserFromSafehouse(sh, username) end)
        elseif sh.removePlayer then
            pcall(function() sh:removePlayer(username) end)
        end

        if sh.syncSafehouse then
            pcall(function() sh:syncSafehouse() end)
        end

        -- Clear respawn point
        if sh.setRespawnInSafehouse then
            pcall(function() sh:setRespawnInSafehouse(false, username) end)
        end

        -- Update ModData record if present
        if baseRecord and baseRecord.members then
            for idx = #baseRecord.members, 1, -1 do
                if baseRecord.members[idx] == username then
                    table.remove(baseRecord.members, idx)
                end
            end
        end

        local baseName = sh:getTitle() or (baseRecord and baseRecord.name) or "Safehouse"

        -- Sync caller
        playerSafehouses = reconcilePlayerSafehouses(username)
        sendServerCommand(player, "MultiSafehouse", "syncData", {
            safehouses = playerSafehouses
        })
        player:Say("Left safehouse '" .. baseName .. "'.")

        -- Sync owner if online
        if actualOwner then
            local ownerPlayer = findOnlinePlayer(actualOwner)
            if ownerPlayer then
                sendServerCommand(ownerPlayer, "MultiSafehouse", "syncData", {
                    safehouses = reconcilePlayerSafehouses(actualOwner)
                })
            end
        end

        print("[28 Bases Later] " .. username .. " left safehouse '" .. baseName .. "' (" .. x .. "," .. y .. ") owned by " .. tostring(actualOwner))

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
        -- Synchronize authoritative server settings to client
        sendServerCommand(player, "MultiSafehouse", "syncAdminConfig", {
            maxBases = MultiSafehouse.getMaxBasesPerPlayer(),
            allowNonResidential = MultiSafehouse.isAllowNonResidential(),
            allowSpawnBuildings = MultiSafehouse.isAllowSpawnBuildings(),
            daysSurvivedToClaim = MultiSafehouse.getDaysSurvivedToClaim(),
            adminBypassRestrictions = MultiSafehouse.isAdminBypassRestrictions()
        })

    -- -------------------------------------------
    -- COMMAND: "setAdminConfig"
    -- -------------------------------------------
    elseif command == "setAdminConfig" then
        if not isPlayerAdmin(player) then
            print("[28 Bases Later] Security: Non-admin " .. username .. " attempted to modify server config.")
            return
        end

        local configData = ModData.getOrCreate("28BasesLater_Config")
        local broadcastPayload = {}

        if args.maxBases ~= nil then
            local sanitizedCap = math.max(0, math.min(100, math.floor(tonumber(args.maxBases) or 28)))
            MultiSafehouse.serverMaxBases = sanitizedCap
            MultiSafehouse.server_MaxBasesPerPlayer = sanitizedCap
            configData.maxBasesPerPlayer = sanitizedCap
            broadcastPayload.maxBases = sanitizedCap
            if SandboxVars and SandboxVars.MultiSafehouse then
                SandboxVars.MultiSafehouse.MaxBasesPerPlayer = sanitizedCap
            end
        end

        if args.allowNonResidential ~= nil then
            local val = (args.allowNonResidential == true)
            MultiSafehouse.serverAllowNonResidential = val
            MultiSafehouse.server_AllowNonResidential = val
            configData.allowNonResidential = val
            broadcastPayload.allowNonResidential = val
            if SandboxVars and SandboxVars.MultiSafehouse then
                SandboxVars.MultiSafehouse.AllowNonResidential = val
            end
        end

        if args.allowSpawnBuildings ~= nil then
            local val = (args.allowSpawnBuildings == true)
            MultiSafehouse.serverAllowSpawnBuildings = val
            MultiSafehouse.server_AllowSpawnBuildings = val
            configData.allowSpawnBuildings = val
            broadcastPayload.allowSpawnBuildings = val
            if SandboxVars and SandboxVars.MultiSafehouse then
                SandboxVars.MultiSafehouse.AllowSpawnBuildings = val
            end
        end

        if args.daysSurvivedToClaim ~= nil then
            local days = math.max(0, math.min(365, math.floor(tonumber(args.daysSurvivedToClaim) or 0)))
            MultiSafehouse.serverDaysSurvivedToClaim = days
            MultiSafehouse.server_DaysSurvivedToClaim = days
            configData.daysSurvivedToClaim = days
            broadcastPayload.daysSurvivedToClaim = days
            if SandboxVars and SandboxVars.MultiSafehouse then
                SandboxVars.MultiSafehouse.DaysSurvivedToClaim = days
            end
        end

        if args.adminBypassRestrictions ~= nil then
            local val = (args.adminBypassRestrictions == true)
            MultiSafehouse.serverAdminBypassRestrictions = val
            MultiSafehouse.server_AdminBypassRestrictions = val
            configData.adminBypassRestrictions = val
            broadcastPayload.adminBypassRestrictions = val
            if SandboxVars and SandboxVars.MultiSafehouse then
                SandboxVars.MultiSafehouse.AdminBypassRestrictions = val
            end
        end

        -- Synchronize into native engine SandboxOptions if available
        if getSandboxOptions then
            pcall(function()
                local opts = getSandboxOptions()
                if opts and opts.set then
                    if broadcastPayload.maxBases ~= nil then
                        opts:set("MultiSafehouse.MaxBasesPerPlayer", broadcastPayload.maxBases)
                    end
                    if broadcastPayload.allowNonResidential ~= nil then
                        opts:set("MultiSafehouse.AllowNonResidential", broadcastPayload.allowNonResidential)
                    end
                    if broadcastPayload.allowSpawnBuildings ~= nil then
                        opts:set("MultiSafehouse.AllowSpawnBuildings", broadcastPayload.allowSpawnBuildings)
                    end
                    if broadcastPayload.daysSurvivedToClaim ~= nil then
                        opts:set("MultiSafehouse.DaysSurvivedToClaim", broadcastPayload.daysSurvivedToClaim)
                    end
                    if broadcastPayload.adminBypassRestrictions ~= nil then
                        opts:set("MultiSafehouse.AdminBypassRestrictions", broadcastPayload.adminBypassRestrictions)
                    end
                    if opts.toLua then opts:toLua() end
                end
            end)
        end

        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then
                    sendServerCommand(p, "MultiSafehouse", "syncAdminConfig", broadcastPayload)
                end
            end
        end

        print("[28 Bases Later] Admin " .. username .. " updated server configuration settings.")
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[28 Bases Later] Server handler initialized with membership support.")
