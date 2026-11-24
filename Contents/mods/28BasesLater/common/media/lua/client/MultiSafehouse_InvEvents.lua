-- =============================================
-- 28 Bases Later — Safehouse Inventory Event Wiring
-- =============================================
-- Client-side only. Connects MSI_Scanner to the game's event system.
-- No scanning logic lives here — this file is purely the "glue".
--
-- Events wired:
--   OnServerCommand        — triggers a full re-scan after each syncData packet
--                            (covers initial connect, renames, and releases)
--   OnRefreshInventoryWindowContainers
--                          — scans when the player opens or transfers in a loot window
--   OnContainerUpdate      — invalidates merged cache when any container changes
--   EveryTenMinutes        — periodic safety-net scan
--   OnDisconnect           — wipes cache on disconnect so a reconnect starts fresh
-- =============================================

-- -----------------------------------------------
-- Hook 1: Respond to 28BL server packets.
-- "syncData" is sent on connect, rename, release, and admin config change.
-- We hydrate from disk, reconcile against active bases, and scan loaded chunks.
-- -----------------------------------------------
local function onServerCommand_InvSync(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    if command == "syncData" and args.safehouses then
        -- 1. Load persisted item counts from local disk
        if MSI_Cache.load then
            MSI_Cache.load()
        end

        -- 2. Reconcile with active server safehouses (retains counts for distant/RV bases)
        if MSI_Cache.reconcile then
            MSI_Cache.reconcile(args.safehouses)
        end

        -- 3. Scan whatever squares are currently loaded around the player
        MSI_Scanner.updateAll()
    end
end

Events.OnServerCommand.Add(onServerCommand_InvSync)

-- -----------------------------------------------
-- Hook 2: Scan when a loot / inventory window opens or refreshes.
-- state == "begin" fires at the start of a refresh, before the UI redraws.
-- -----------------------------------------------
Events.OnRefreshInventoryWindowContainers.Add(function(invSelf, state)
    if state ~= "begin" then return end
    MSI_Scanner.updateAll()
end)

-- -----------------------------------------------
-- Hook 3: Invalidate the merged cache any time a container's
-- contents change (item added, removed, moved).
-- We don't scan here — the next refresh or timer will trigger that.
-- -----------------------------------------------
Events.OnContainerUpdate.Add(function(container)
    -- nil-safe: the event passes a container object; we just need to know *something* changed
    MSI_Cache.invalidate()
end)

-- -----------------------------------------------
-- Hook 4: Periodic background scan every 10 minutes.
-- Catches changes made by other players in a shared safehouse.
-- -----------------------------------------------
Events.EveryTenMinutes.Add(function()
    MSI_Scanner.updateAll()
end)

-- -----------------------------------------------
-- Hook 5: Flush disk writes and clear on disconnect.
-- Persists latest counts so reconnecting can restore them.
-- -----------------------------------------------
Events.OnDisconnect.Add(function()
    if MSI_Cache.save then
        pcall(MSI_Cache.save)
    end
    MSI_Cache.clear()
end)

-- -----------------------------------------------
-- Hook 6: Initial scan on game start (single-player).
-- In single-player there is no server syncData packet,
-- so we trigger disk load and first scan after playerData populates.
-- -----------------------------------------------
local _spScanDone = false
Events.OnTick.Add(function()
    if _spScanDone then return end
    -- Only run this in single-player (isClient() and isServer() both false)
    if isClient() or isServer() then
        _spScanDone = true  -- not SP — the syncData hook handles it
        return
    end
    -- Wait for hydration flag (set when OnSafehousesChanged fires in SP)
    if not MultiSafehouse or not MultiSafehouse.isHydrated then return end
    _spScanDone = true

    if MSI_Cache.load then
        MSI_Cache.load()
    end
    local player = getPlayer()
    local uName = player and player:getUsername()
    if uName and MultiSafehouse.playerData and MultiSafehouse.playerData[uName] and MSI_Cache.reconcile then
        MSI_Cache.reconcile(MultiSafehouse.playerData[uName])
    end
    MSI_Scanner.updateAll()
end)

-- -----------------------------------------------
-- Hook 7: Debounced disk save ticker & settling scan scheduler
-- -----------------------------------------------
local _pendingScanTicks = -1
local _tickCounter = 0

Events.OnTick.Add(function()
    _tickCounter = _tickCounter + 1

    -- Periodic check for debounced cache save (every 60 ticks = ~1 second)
    if _tickCounter % 60 == 0 and MSI_Cache.checkDebouncedSave then
        MSI_Cache.checkDebouncedSave()
    end

    -- Delayed scan countdown for settling chunks after entering an RV or teleporting
    if _pendingScanTicks > 0 then
        _pendingScanTicks = _pendingScanTicks - 1
    elseif _pendingScanTicks == 0 then
        _pendingScanTicks = -1
        MSI_Scanner.updateAll()
    end
end)

-- -----------------------------------------------
-- Hook 8: Coordinate Jump Detector (Universal RV Enter/Exit & Teleport Handler)
-- Detects when a character teleports across dimensions (>200 tiles in 1 tick)
-- -----------------------------------------------
local _lastPlayerX = nil
local _lastPlayerY = nil

local function onPlayerMoveCheck(player)
    if not player or not player.isLocalPlayer or not player:isLocalPlayer() then return end

    local curX = player:getX()
    local curY = player:getY()

    if _lastPlayerX ~= nil and _lastPlayerY ~= nil then
        local dx = math.abs(curX - _lastPlayerX)
        local dy = math.abs(curY - _lastPlayerY)

        -- If player moved more than 200 tiles in a single movement update,
        -- they entered an RV interior, exited to the world, or were teleported.
        if dx > 200 or dy > 200 then
            -- Immediately flush previous location's cache before old chunks unload
            if MSI_Cache.save then
                pcall(MSI_Cache.save)
            end
            -- Schedule a scan in 30 ticks (~0.5s) to allow destination chunks to load
            _pendingScanTicks = 30
        end
    end

    _lastPlayerX = curX
    _lastPlayerY = curY
end

if Events.OnPlayerMove then
    Events.OnPlayerMove.Add(onPlayerMoveCheck)
end

-- -----------------------------------------------
-- Hook 9: Direct RVHooks integration (if Project RV Interior mod is active)
-- -----------------------------------------------
if RVHooks and type(RVHooks.register) == "function" then
    pcall(function()
        RVHooks.register("postEnter", function()
            _pendingScanTicks = 30
        end)
        RVHooks.register("postExit", function()
            if MSI_Cache.save then pcall(MSI_Cache.save) end
            _pendingScanTicks = 30
        end)
    end)
end

print("[28 Bases Later] InvEvents wiring loaded.")
