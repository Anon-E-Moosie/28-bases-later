-- =============================================
-- 28 Bases Later — Safehouse Inventory Cache
-- =============================================
-- Client-side only. Holds the in-RAM item-count cache for all of the
-- player's claimed safehouses. No network traffic, no ModData writes.
--
-- Data model (plain English):
--   MSI_Cache.perBase[key]  = { name="Main Base", counts={ ["Base.Hammer"]=2, ... } }
--   MSI_Cache._merged       = { ["Base.Hammer"]={ total=3, bases={{name,count},...} }, ... }
--
-- The key for a safehouse is always the string "x,y" (e.g. "100,200"),
-- matching the existing 28BL convention in ServerHandler and UI.
-- =============================================

MSI_Cache = MSI_Cache or {}

-- Per-safehouse count tables.  Populated by MSI_Scanner.
-- [safehouseKey] = { name = string, counts = { [fullType] = count } }
MSI_Cache.perBase = MSI_Cache.perBase or {}

-- Merged lookup rebuilt lazily from perBase.
-- [fullType] = { total = number, bases = { {name, count}, ... } }
MSI_Cache._merged = nil
MSI_Cache._mergedDirty = true

-- Throttle timestamps: [safehouseKey] = millisecond timestamp of last scan
MSI_Cache.lastScanTime = MSI_Cache.lastScanTime or {}

-- Content signatures: [safehouseKey] = "fingerprint" string to detect changes
MSI_Cache.lastScanSig = MSI_Cache.lastScanSig or {}

-- -----------------------------------------------
-- Rebuild the merged lookup from perBase tables.
-- Called lazily the first time getInfo() is used after a dirty flag.
-- -----------------------------------------------
local function rebuildMerged()
    local merged = {}
    for _, baseData in pairs(MSI_Cache.perBase) do
        local baseName = baseData.name or "?"
        for fullType, count in pairs(baseData.counts or {}) do
            if count and count > 0 then
                local entry = merged[fullType]
                if not entry then
                    entry = { total = 0, bases = {} }
                    merged[fullType] = entry
                end
                entry.total = entry.total + count
                entry.bases[#entry.bases + 1] = { name = baseName, count = count }
            end
        end
    end
    MSI_Cache._merged = merged
    MSI_Cache._mergedDirty = false
end

-- -----------------------------------------------
-- PUBLIC: Resolves the unique cache key for an item.
-- In Build 42, procedural literature (magazines, books, comics)
-- and media items (VHS tapes, CDs) share identical fullTypes
-- (e.g. Base.Book_Fiction) while having unique issue/title names.
-- Combining fullType with item:getName() guarantees that distinct
-- books and issues are not conflated into a single count.
-- -----------------------------------------------
function MSI_Cache.getItemKey(item)
    if not item then return nil end
    local ft = nil
    local ok1 = pcall(function() ft = item:getFullType() end)
    if not ok1 or not ft then return nil end

    local name = nil
    local ok2 = pcall(function() name = item:getName() end)

    if ok2 and name and name ~= "" then
        return ft .. "::" .. name
    end
    return ft
end

-- -----------------------------------------------
-- PUBLIC: Look up a single itemKey or fullType.
-- Returns { total, bases = {{name, count}, ...} } or nil.
-- -----------------------------------------------
function MSI_Cache.getInfo(itemKey)
    if not itemKey then return nil end
    if MSI_Cache._mergedDirty or not MSI_Cache._merged then
        rebuildMerged()
    end
    local e = MSI_Cache._merged[itemKey]
    if not e or e.total <= 0 then return nil end
    return e
end

-- -----------------------------------------------
-- PUBLIC: Mark the merged lookup as needing a rebuild.
-- Call this whenever perBase contents change.
-- -----------------------------------------------
function MSI_Cache.invalidate()
    MSI_Cache._mergedDirty = true
end

-- -----------------------------------------------
-- PUBLIC: Wipe everything — called when resetting cache.
-- -----------------------------------------------
function MSI_Cache.clear()
    MSI_Cache.perBase       = {}
    MSI_Cache._merged       = nil
    MSI_Cache._mergedDirty  = true
    MSI_Cache.lastScanTime  = {}
    MSI_Cache.lastScanSig   = {}
    MSI_Cache._dirty        = false
end

-- -----------------------------------------------
-- PERSISTENCE: Storage filename resolution
-- -----------------------------------------------
function MSI_Cache.getStorageFileName()
    local isMP = (isClient and isClient()) or (isServer and isServer())
    local player = getPlayer()
    local uName = (player and player.getUsername and player:getUsername()) or "Player"
    uName = string.gsub(tostring(uName), "[^%w_%-]", "_")

    if isMP then
        local sName = (getServerName and getServerName()) or "MP_Server"
        if sName == "" then sName = "MP_Server" end
        sName = string.gsub(tostring(sName), "[^%w_%-]", "_")
        return "28BL_InvCache_" .. sName .. "_" .. uName .. ".ini"
    else
        local worldName = "SP_World"
        if getWorld and getWorld() and getWorld().getWorld then
            pcall(function() worldName = getWorld():getWorld() end)
        end
        if not worldName or worldName == "" then worldName = "SP_World" end
        worldName = string.gsub(tostring(worldName), "[^%w_%-]", "_")
        return "28BL_InvCache_SP_" .. worldName .. "_" .. uName .. ".ini"
    end
end

-- -----------------------------------------------
-- PERSISTENCE: Save perBase counts to local disk
-- -----------------------------------------------
MSI_Cache._dirty = false
MSI_Cache._lastDirtyTime = 0
MSI_Cache.DEBOUNCE_DELAY_MS = 5000

function MSI_Cache.requestSave()
    MSI_Cache._dirty = true
    local now = (getTimestampMs and getTimestampMs()) or (os and os.time and os.time() * 1000) or 0
    MSI_Cache._lastDirtyTime = now
end

function MSI_Cache.checkDebouncedSave()
    if not MSI_Cache._dirty then return end
    local now = (getTimestampMs and getTimestampMs()) or (os and os.time and os.time() * 1000) or 0
    if (now - MSI_Cache._lastDirtyTime) >= MSI_Cache.DEBOUNCE_DELAY_MS then
        MSI_Cache.save()
    end
end

function MSI_Cache.save()
    local fn = MSI_Cache.getStorageFileName()
    if not fn or fn == "" then return false end
    MSI_Cache._dirty = false

    if not getFileWriter then return false end

    local ok, err = pcall(function()
        local file = getFileWriter(fn, true, false)
        if not file then return end
        for key, baseData in pairs(MSI_Cache.perBase) do
            if baseData and baseData.counts then
                file:write("[base:" .. tostring(key) .. "]\r\n")
                if baseData.name then
                    file:write("__name=" .. tostring(baseData.name) .. "\r\n")
                end
                for itemKey, count in pairs(baseData.counts) do
                    if count and count > 0 then
                        file:write(tostring(itemKey) .. "=" .. tostring(count) .. "\r\n")
                    end
                end
            end
        end
        file:close()
    end)

    if not ok then
        print("[28 Bases Later] InvCache save error: " .. tostring(err))
        return false
    end
    return true
end

-- -----------------------------------------------
-- PERSISTENCE: Load perBase counts from local disk
-- -----------------------------------------------
function MSI_Cache.load()
    local fn = MSI_Cache.getStorageFileName()
    if not fn or fn == "" then return false end

    if not getFileReader then return false end

    local ok, err = pcall(function()
        local file = getFileReader(fn, false)
        if not file then return end

        local currentKey = nil
        local currentBase = nil

        while true do
            local line = file:readLine()
            if not line then break end
            line = line:gsub("^%s*(.-)%s*$", "%1")

            if line ~= "" and line:sub(1, 1) ~= ";" and line:sub(1, 1) ~= "#" then
                local sectionKey = line:match("^%[base:([^%]]+)%]$")
                if sectionKey then
                    currentKey = sectionKey
                    currentBase = MSI_Cache.perBase[currentKey] or { counts = {} }
                    MSI_Cache.perBase[currentKey] = currentBase
                elseif currentBase and currentKey then
                    local k, v = line:match("^(.-)=(.*)$")
                    if k and v then
                        if k == "__name" then
                            currentBase.name = v
                        else
                            local num = tonumber(v)
                            if num and num > 0 then
                                currentBase.counts[k] = num
                            end
                        end
                    end
                end
            end
        end
        file:close()
    end)

    if not ok then
        print("[28 Bases Later] InvCache load error: " .. tostring(err))
        return false
    end

    MSI_Cache.invalidate()
    return true
end

-- -----------------------------------------------
-- PERSISTENCE: Reconcile loaded disk cache with active safehouses
-- -----------------------------------------------
function MSI_Cache.reconcile(activeBases)
    if not activeBases or #activeBases == 0 then return end
    local activeKeys = {}
    for _, b in ipairs(activeBases) do
        if b.x and b.y then
            local k = b.x .. "," .. b.y
            activeKeys[k] = b
            if MSI_Cache.perBase[k] and b.name then
                MSI_Cache.perBase[k].name = b.name
            end
        end
    end

    local changed = false
    for k in pairs(MSI_Cache.perBase) do
        if not activeKeys[k] then
            MSI_Cache.perBase[k] = nil
            MSI_Cache.lastScanTime[k] = nil
            MSI_Cache.lastScanSig[k] = nil
            changed = true
        end
    end

    if changed then
        MSI_Cache.invalidate()
        MSI_Cache.requestSave()
    end
end

print("[28 Bases Later] InvCache module loaded.")
