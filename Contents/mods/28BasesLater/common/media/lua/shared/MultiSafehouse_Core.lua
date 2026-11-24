-- =============================================
-- 28 Bases Later — Core Shared Module
-- =============================================
-- Loaded on both client and server before other scripts.
-- Provides the root namespace, configuration defaults, and shared state.

MultiSafehouse = MultiSafehouse or {}

MultiSafehouse.version = "1.2.0"

-- Default fallback values (used if SandboxVars are not yet initialized)
MultiSafehouse.maxBasesPerPlayer = 28
MultiSafehouse.maxDimension = 120
MultiSafehouse.allowNonResidential = false
MultiSafehouse.allowSpawnBuildings = false
MultiSafehouse.daysSurvivedToClaim = 0
MultiSafehouse.adminBypassRestrictions = true

-- Resolves a configuration setting with live engine SandboxOptions as the top authority.
-- Hierarchy:
-- 1. Live getSandboxOptions():getOptionByName("MultiSafehouse." .. key) (Engine Authority, updates in real-time)
-- 2. Server network sync cache (MultiSafehouse["server_" .. key] or MultiSafehouse["server" .. key])
-- 3. Active SandboxVars.MultiSafehouse[key] (Engine startup copy)
-- 4. Legacy SandboxVars["28BasesLater"][key]
-- 5. Default constant
local function getSandboxEngineValue(key)
    if getSandboxOptions then
        local ok, opts = pcall(getSandboxOptions)
        if ok and opts and opts.getOptionByName then
            local ok2, opt = pcall(function() return opts:getOptionByName("MultiSafehouse." .. key) end)
            if ok2 and opt and opt.getValue then
                local ok3, val = pcall(function() return opt:getValue() end)
                if ok3 and val ~= nil then
                    return val
                end
            end
        end
    end
    return nil
end

local function getSetting(key, defaultVal)
    -- 1. Live Java engine option (updates dynamically when admin edits sandbox options in-game)
    local liveVal = getSandboxEngineValue(key)
    if liveVal ~= nil then
        return liveVal
    end

    -- 2. Server network sync cache
    if MultiSafehouse["server_" .. key] ~= nil then
        return MultiSafehouse["server_" .. key]
    end
    if MultiSafehouse["server" .. key] ~= nil then
        return MultiSafehouse["server" .. key]
    end

    -- 3. Active SandboxVars.MultiSafehouse
    if SandboxVars and SandboxVars.MultiSafehouse and SandboxVars.MultiSafehouse[key] ~= nil then
        return SandboxVars.MultiSafehouse[key]
    end

    -- 4. Legacy SandboxVars["28BasesLater"]
    if SandboxVars and SandboxVars["28BasesLater"] and SandboxVars["28BasesLater"][key] ~= nil then
        return SandboxVars["28BasesLater"][key]
    end

    return defaultVal
end

-- Resolves the current authoritative safehouse claim cap per player.
-- 0 = Unlimited claims
-- 1 - 100 = Custom claim ceiling
function MultiSafehouse.getMaxBasesPerPlayer()
    local val = tonumber(getSetting("MaxBasesPerPlayer", MultiSafehouse.maxBasesPerPlayer))
    if not val or type(val) ~= "number" or val ~= val then
        return 28
    end
    return math.max(0, math.min(100, math.floor(val)))
end

-- Resolves the maximum allowed building dimension (in tiles) for safehouse claims.
function MultiSafehouse.getMaxDimension()
    local val = tonumber(getSetting("MaxDimension", MultiSafehouse.maxDimension))
    if not val or type(val) ~= "number" or val ~= val then
        return 120
    end
    return math.max(10, math.min(300, math.floor(val)))
end

-- Resolves whether non-residential (commercial/industrial) buildings can be claimed.
function MultiSafehouse.isAllowNonResidential()
    local val = getSetting("AllowNonResidential", MultiSafehouse.allowNonResidential)
    return val == true or val == 1 or val == "true"
end

-- Resolves whether map spawn point buildings can be claimed.
function MultiSafehouse.isAllowSpawnBuildings()
    local val = getSetting("AllowSpawnBuildings", MultiSafehouse.allowSpawnBuildings)
    return val == true or val == 1 or val == "true"
end

-- Resolves the minimum days a player must survive before claiming is permitted (0 = disabled).
function MultiSafehouse.getDaysSurvivedToClaim()
    local val = tonumber(getSetting("DaysSurvivedToClaim", MultiSafehouse.daysSurvivedToClaim))
    if not val or type(val) ~= "number" or val ~= val then
        return 0
    end
    return math.max(0, math.min(365, math.floor(val)))
end

-- Resolves whether administrators bypass claiming restrictions.
function MultiSafehouse.isAdminBypassRestrictions()
    local val = getSetting("AdminBypassRestrictions", MultiSafehouse.adminBypassRestrictions)
    return val == true or val == 1 or val == "true"
end

-- Local cache of the current player's safehouses for UI display.
-- Structure: MultiSafehouse.playerData[username] = { {x, y, w, h, name, isRespawn}, ... }
MultiSafehouse.playerData = MultiSafehouse.playerData or {}

-- Tracks whether authoritative safehouse data has been received from the server.
MultiSafehouse.isHydrated = false

print("[28 Bases Later] Core loaded (v" .. MultiSafehouse.version .. ")")
