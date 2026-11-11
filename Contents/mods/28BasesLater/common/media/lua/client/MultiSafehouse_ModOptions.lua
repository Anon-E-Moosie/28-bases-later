-- =============================================
-- 28 Bases Later — ModOptions Integration Bridge
-- =============================================
-- Native Build 42 PZAPI.ModOptions bridge with legacy fallback.
-- Exposes a numeric text entry field in Escape -> Options -> Mods for server admins.

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

local function initModOptions()
    if MultiSafehouse and MultiSafehouse._modOptionsInitialized then
        return
    end

    local defaultCap = "28"
    if MultiSafehouse and MultiSafehouse.getMaxBasesPerPlayer then
        defaultCap = tostring(MultiSafehouse.getMaxBasesPerPlayer())
    end

    -- 1. BUILD 42 NATIVE ENGINE API
    if PZAPI and PZAPI.ModOptions then
        local options = PZAPI.ModOptions:create("28baseslater", "28 Bases Later")

        local capOption = options:addTextEntry(
            "MaxBasesPerPlayer",
            "Max Bases Per Player",
            defaultCap,
            "Maximum number of safehouses a single player may own simultaneously (0-100). Enter 0 for unlimited. Default is 28."
        )

        -- Build 42 calls options:apply() when the player clicks Apply in Options
        function options:apply()
            local player = getPlayer()
            if not player or not isPlayerAdmin(player) then return end

            local rawVal = capOption:getValue()
            local numVal = tonumber(rawVal)

            if numVal ~= nil then
                local sanitized = math.max(0, math.min(100, math.floor(numVal)))
                sendClientCommand(player, "MultiSafehouse", "setAdminConfig", {
                    maxBases = sanitized
                })
            end
        end

        if MultiSafehouse then MultiSafehouse._modOptionsInitialized = true end
        print("[28 Bases Later] PZAPI.ModOptions initialized.")

    -- 2. LEGACY BUILD 41 FALLBACK (Community Framework)
    elseif ModOptions and ModOptions.getInstance then
        local options = ModOptions:getInstance({
            name = "28BasesLater",
            id = "28baseslater"
        })

        local capOption = options:addTextEntry(
            "MaxBasesPerPlayer",
            "Max Bases Per Player",
            defaultCap,
            "Maximum number of safehouses a single player may own simultaneously (0-100). Enter 0 for unlimited. Default is 28."
        )

        function options:onApply()
            local player = getPlayer()
            if not player or not isPlayerAdmin(player) then return end

            local rawVal = capOption:getValue()
            local numVal = tonumber(rawVal)

            if numVal ~= nil then
                local sanitized = math.max(0, math.min(100, math.floor(numVal)))
                sendClientCommand(player, "MultiSafehouse", "setAdminConfig", {
                    maxBases = sanitized
                })
            end
        end

        if MultiSafehouse then MultiSafehouse._modOptionsInitialized = true end
        print("[28 Bases Later] Community ModOptions initialized.")
    end
end

-- Execute immediately on file load so #PZAPI.ModOptions.Data is populated
-- BEFORE MainOptions:create() builds the options tabs.
initModOptions()

-- Also hook early boot event as backup if PZAPI was loaded asynchronously
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(initModOptions)
end
