-- =============================================
-- 28 Bases Later — Core Shared Module
-- =============================================
-- Loaded on both client and server before other scripts.
-- Provides the root namespace, configuration defaults, and shared state.

MultiSafehouse = MultiSafehouse or {}

MultiSafehouse.version = "1.0"

-- Maximum number of safehouses a single player may own simultaneously.
-- Set to 28 to match the mod theme, but easily adjustable for server balance.
MultiSafehouse.maxBasesPerPlayer = 28

-- Maximum building dimension (in tiles) that can be claimed as a single safehouse.
MultiSafehouse.maxDimension = 120

-- Local cache of the current player's safehouses for UI display.
-- Structure: MultiSafehouse.playerData[username] = { {x, y, w, h, name, isRespawn}, ... }
MultiSafehouse.playerData = MultiSafehouse.playerData or {}

-- Tracks whether authoritative safehouse data has been received from the server.
MultiSafehouse.isHydrated = false

print("[28 Bases Later] Core loaded (v" .. MultiSafehouse.version .. ")")
