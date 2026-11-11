-- =============================================
-- 28 Bases Later — Core Shared Module
-- =============================================
-- Loaded on both client and server before other scripts.
-- Provides the root namespace, configuration defaults, and shared state.

MultiSafehouse = MultiSafehouse or {}

MultiSafehouse.version = "1.1.0"

-- Default fallback values (used if SandboxVars are not yet initialized)
MultiSafehouse.maxBasesPerPlayer = 28
MultiSafehouse.maxDimension = 120

-- Resolves the current authoritative safehouse claim cap per player.
-- 0 = Unlimited claims
-- 1 - 100 = Custom claim ceiling
function MultiSafehouse.getMaxBasesPerPlayer()
    local val = nil

    -- 1. Check native engine SandboxVars (server-authoritative)
    if SandboxVars and SandboxVars.MultiSafehouse and SandboxVars.MultiSafehouse.MaxBasesPerPlayer ~= nil then
        val = tonumber(SandboxVars.MultiSafehouse.MaxBasesPerPlayer)
    elseif SandboxVars and SandboxVars["28BasesLater"] and SandboxVars["28BasesLater"].MaxBasesPerPlayer ~= nil then
        val = tonumber(SandboxVars["28BasesLater"].MaxBasesPerPlayer)
    -- 2. Check live server-synced override
    elseif MultiSafehouse.serverMaxBases ~= nil then
        val = tonumber(MultiSafehouse.serverMaxBases)
    -- 3. Default constant
    else
        val = MultiSafehouse.maxBasesPerPlayer
    end

    -- Sanitize: must be an integer between 0 and 100 (defaults to 28 if invalid)
    if not val or type(val) ~= "number" or val ~= val then
        return 28
    end
    return math.max(0, math.min(100, math.floor(val)))
end

-- Resolves the maximum allowed building dimension (in tiles) for safehouse claims.
function MultiSafehouse.getMaxDimension()
    local val = nil

    if SandboxVars and SandboxVars.MultiSafehouse and SandboxVars.MultiSafehouse.MaxDimension ~= nil then
        val = tonumber(SandboxVars.MultiSafehouse.MaxDimension)
    elseif SandboxVars and SandboxVars["28BasesLater"] and SandboxVars["28BasesLater"].MaxDimension ~= nil then
        val = tonumber(SandboxVars["28BasesLater"].MaxDimension)
    elseif MultiSafehouse.serverMaxDimension ~= nil then
        val = tonumber(MultiSafehouse.serverMaxDimension)
    else
        val = MultiSafehouse.maxDimension
    end

    if not val or type(val) ~= "number" or val ~= val then
        return 120
    end
    return math.max(10, math.min(300, math.floor(val)))
end

-- Local cache of the current player's safehouses for UI display.
-- Structure: MultiSafehouse.playerData[username] = { {x, y, w, h, name, isRespawn}, ... }
MultiSafehouse.playerData = MultiSafehouse.playerData or {}

-- Tracks whether authoritative safehouse data has been received from the server.
MultiSafehouse.isHydrated = false

print("[28 Bases Later] Core loaded (v" .. MultiSafehouse.version .. ")")
