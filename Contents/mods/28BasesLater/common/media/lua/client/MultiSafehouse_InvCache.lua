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
-- PUBLIC: Wipe everything — called on disconnect
-- so a reconnecting player starts fresh.
-- -----------------------------------------------
function MSI_Cache.clear()
    MSI_Cache.perBase       = {}
    MSI_Cache._merged       = nil
    MSI_Cache._mergedDirty  = true
    MSI_Cache.lastScanTime  = {}
    MSI_Cache.lastScanSig   = {}
end

print("[28 Bases Later] InvCache module loaded.")
