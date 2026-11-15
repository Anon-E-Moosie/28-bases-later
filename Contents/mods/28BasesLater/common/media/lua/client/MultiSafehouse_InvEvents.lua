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
-- We use it as the trigger for a fresh scan of all safehouse bases.
-- -----------------------------------------------
local function onServerCommand_InvSync(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    if command == "syncData" then
        -- The player's safehouse list (names, bounds) just updated from the server.
        -- Wipe the entire cache so old base names or stale counts don't linger.
        MSI_Cache.clear()
        -- Attempt an immediate scan (will only pick up loaded squares).
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
-- Hook 5: Wipe cache on disconnect.
-- Prevents stale data from a previous session appearing briefly after reconnect.
-- -----------------------------------------------
Events.OnDisconnect.Add(function()
    MSI_Cache.clear()
end)

-- -----------------------------------------------
-- Hook 6: Initial scan on game start (single-player).
-- In single-player there is no server syncData packet,
-- so we trigger the first scan 60 ticks after game start
-- to give playerData time to populate via OnSafehousesChanged.
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
    MSI_Scanner.updateAll()
end)

print("[28 Bases Later] InvEvents wiring loaded.")
