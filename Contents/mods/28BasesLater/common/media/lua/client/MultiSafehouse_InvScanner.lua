-- =============================================
-- 28 Bases Later — Safehouse Inventory Scanner
-- =============================================
-- Client-side only. Walks the tile grid inside each claimed safehouse
-- bounding box, counts items in every container (and nested containers
-- recursively up to MAX_DEPTH levels), and writes the results into MSI_Cache.
--
-- Scanning only happens when tile squares are actually loaded in client
-- memory (i.e., the player is nearby). If a safehouse's tiles are not
-- loaded, the previous cached count is preserved unchanged.
--
-- Throttle: a safehouse is never re-scanned more often than THROTTLE_MS
-- milliseconds, and only when the content fingerprint changes.
-- =============================================

MSI_Scanner = MSI_Scanner or {}

-- Minimum milliseconds between scans of the same safehouse.
MSI_Scanner.THROTTLE_MS = 1500

-- How many floors PZ buildings can span (ground = 0, top = 7 in B42).
-- We scan 0-7 to cover any building height; nil squares are skipped cheaply.
MSI_Scanner.Z_MIN = 0
MSI_Scanner.Z_MAX = 7

-- Maximum recursion depth for nested containers (bag-in-bag-in-crate etc.).
-- Prevents infinite loops on pathological save files.
MSI_Scanner.MAX_DEPTH = 5

-- -----------------------------------------------
-- INTERNAL: Returns the cache key for a safehouse entry.
-- Matches the convention used elsewhere in 28BL.
-- -----------------------------------------------
local function baseKey(base)
    return base.x .. "," .. base.y
end

-- -----------------------------------------------
-- INTERNAL: Recursively count items inside a container,
-- including items inside sub-containers (bags, etc.).
-- counts   = { [itemKey] = count }  (mutated in place)
-- depth    = current recursion level (starts at 0)
-- seen     = deduplication table for container objects
-- -----------------------------------------------
local function countContainerItems(container, counts, depth, seen)
    if not container then return end
    if depth > MSI_Scanner.MAX_DEPTH then return end

    local items = container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            -- Count the item using its specific identity key (fullType + title/name)
            local key = MSI_Cache.getItemKey and MSI_Cache.getItemKey(item)
            if not key then
                local ok, ft = pcall(function() return item:getFullType() end)
                if ok and ft then key = ft end
            end

            if key then
                counts[key] = (counts[key] or 0) + 1
            end

            -- If the item is itself a container (backpack, bag, crate-item etc.),
            -- recurse into it. Only recurse if it's genuinely a container category.
            local isContainerItem = false
            pcall(function()
                if item.getCategory and item:getCategory() == "Container" then
                    isContainerItem = true
                elseif item.IsInventoryContainer and item:IsInventoryContainer() then
                    isContainerItem = true
                end
            end)

            if isContainerItem then
                local innerContainer = nil
                local okInner = pcall(function()
                    if item.getItemContainer then
                        innerContainer = item:getItemContainer()
                    end
                end)

                if okInner and innerContainer and innerContainer ~= container then
                    if not seen or not seen[innerContainer] then
                        if seen then seen[innerContainer] = true end
                        countContainerItems(innerContainer, counts, depth + 1, seen)
                    end
                end
            end
        end
    end
end

-- -----------------------------------------------
-- INTERNAL: Scan a single safehouse and return a counts table.
-- Returns: counts { [itemKey]=count }, wasLoaded bool
--   wasLoaded = false means none of the safehouse's squares
--   were in memory, so we should NOT overwrite the cached data.
-- -----------------------------------------------
local function scanBase(base)
    local cell = getCell()
    if not cell then return {}, false end

    local counts  = {}
    local seen    = {}   -- deduplicate container references
    local wasLoaded = false

    local xMin = base.x
    local xMax = base.x + (base.w or 0) - 1
    local yMin = base.y
    local yMax = base.y + (base.h or 0) - 1

    for z = MSI_Scanner.Z_MIN, MSI_Scanner.Z_MAX do
        for x = xMin, xMax do
            for y = yMin, yMax do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    wasLoaded = true

                    -- Items on the floor (world objects with an attached item)
                    local wObjs = sq:getWorldObjects()
                    if wObjs then
                        for i = 0, wObjs:size() - 1 do
                            local wo = wObjs:get(i)
                            if wo then
                                local ok, floorItem = pcall(function() return wo:getItem() end)
                                if ok and floorItem then
                                    local key = MSI_Cache.getItemKey and MSI_Cache.getItemKey(floorItem)
                                    if not key then
                                        local ok2, ft = pcall(function() return floorItem:getFullType() end)
                                        if ok2 and ft then key = ft end
                                    end
                                    if key then
                                        counts[key] = (counts[key] or 0) + 1
                                    end
                                end
                            end
                        end
                    end

                    -- Items inside world containers (crates, fridges, cabinets, etc.)
                    local objs = sq:getObjects()
                    if objs then
                        for i = 0, objs:size() - 1 do
                            local obj = objs:get(i)
                            if obj then
                                -- Support objects with multiple container compartments (e.g. fridge + freezer)
                                local cCount = 1
                                if obj.getContainerCount then
                                    local okCount, countVal = pcall(function() return obj:getContainerCount() end)
                                    if okCount and type(countVal) == "number" and countVal > 0 then
                                        cCount = countVal
                                    end
                                end

                                for cIdx = 0, cCount - 1 do
                                    local cont = nil
                                    pcall(function()
                                        if cIdx == 0 then
                                            cont = obj:getContainer()
                                        elseif obj.getContainerByIndex then
                                            cont = obj:getContainerByIndex(cIdx)
                                        end
                                    end)

                                    if cont and not seen[cont] then
                                        seen[cont] = true
                                        -- Recursively count all items (including nested containers)
                                        countContainerItems(cont, counts, 0, seen)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return counts, wasLoaded
end

-- -----------------------------------------------
-- INTERNAL: Compute an order-independent fingerprint
-- of a counts table so we can detect when content changes.
-- -----------------------------------------------
local function signatureOf(counts)
    local keys = {}
    for ft in pairs(counts) do
        keys[#keys + 1] = ft
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        parts[i] = keys[i] .. "=" .. counts[keys[i]]
    end
    return table.concat(parts, ";")
end

-- -----------------------------------------------
-- PUBLIC: Scan a single safehouse entry and update MSI_Cache.
-- base = { x, y, w, h, name, ... }  (from MultiSafehouse.playerData)
-- -----------------------------------------------
function MSI_Scanner.updateBase(base)
    if not base or not base.x or not base.y then return end

    local key = baseKey(base)
    local now = getTimestampMs and getTimestampMs() or 0

    -- Throttle: skip if we scanned this safehouse very recently
    local lastScan = MSI_Cache.lastScanTime[key] or 0
    if now - lastScan < MSI_Scanner.THROTTLE_MS then return end
    MSI_Cache.lastScanTime[key] = now

    -- Scan the tiles
    local counts, wasLoaded = scanBase(base)

    -- If none of the safehouse squares are in memory, preserve the existing cache
    if not wasLoaded then return end

    -- Only update the cache if content has actually changed
    local sig = signatureOf(counts)
    if sig == MSI_Cache.lastScanSig[key] then return end
    MSI_Cache.lastScanSig[key] = sig

    -- Write the new counts into the per-base cache
    MSI_Cache.perBase[key] = {
        name   = base.name or ("Base at " .. key),
        counts = counts,
    }

    -- Invalidate the merged lookup so the next tooltip rebuilds it
    MSI_Cache.invalidate()

    -- Request a debounced save to disk so offline/reconnecting tooltips retain counts
    if MSI_Cache.requestSave then
        MSI_Cache.requestSave()
    end
end

-- -----------------------------------------------
-- PUBLIC: Scan all of the current player's safehouses.
-- Safe to call frequently — each base is internally throttled.
-- -----------------------------------------------
function MSI_Scanner.updateAll()
    -- Don't scan until the server has sent us the safehouse list
    if not MultiSafehouse or not MultiSafehouse.isHydrated then return end

    local player = getPlayer()
    if not player then return end

    local username = player:getUsername()
    if not username then return end

    local bases = MultiSafehouse.playerData and MultiSafehouse.playerData[username]
    if not bases or #bases == 0 then return end

    for _, base in ipairs(bases) do
        local ok, err = pcall(MSI_Scanner.updateBase, base)
        if not ok then
            print("[28 Bases Later] InvScanner error on base '" .. tostring(base.name) .. "': " .. tostring(err))
        end
    end
end

-- -----------------------------------------------
-- PUBLIC: Remove a single safehouse from the cache
-- (called when a safehouse is released/renamed).
-- -----------------------------------------------
function MSI_Scanner.removeBase(base)
    if not base or not base.x or not base.y then return end
    local key = baseKey(base)
    MSI_Cache.perBase[key]       = nil
    MSI_Cache.lastScanTime[key]  = nil
    MSI_Cache.lastScanSig[key]   = nil
    MSI_Cache.invalidate()
end

print("[28 Bases Later] InvScanner module loaded.")
