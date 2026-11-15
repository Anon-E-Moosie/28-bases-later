-- =============================================
-- 28 Bases Later — Safehouse Inventory Tooltip Hook
-- =============================================
-- Client-side only. Wraps ISToolTipInv:render() to append a
-- "At Your Bases: N" stock breakdown below the normal item tooltip
-- whenever the hovered item type is stored in one or more of the
-- player's claimed 28BL safehouses.
--
-- Safety guarantees:
--   • The original tooltip is ALWAYS drawn first (we wrap, not replace).
--   • Every code path is wrapped in pcall so a crash here cannot break
--     the game or any other tooltip mod.
--   • Multiple nil guards prevent errors from non-item tooltips or
--     modded items that return nil from getFullType().
--
-- Load order: this file must load AFTER InvCache and InvScanner
-- (alphabetically T > S > E > C, so this is last — correct).
-- =============================================

MSI_Tooltip = MSI_Tooltip or {}

-- Max number of base lines shown before "+N more..." truncation
MSI_Tooltip.MAX_LINES = 6

-- -----------------------------------------------
-- Colour constants (RGBA)
-- -----------------------------------------------
local COL = {
    bg       = { r = 0.09, g = 0.09, b = 0.09, a = 0.90 },
    border   = { r = 0.40, g = 0.55, b = 0.45, a = 0.75 },
    title    = { r = 0.70, g = 1.00, b = 0.75, a = 1.00 },  -- soft green-white
    line     = { r = 0.78, g = 0.78, b = 0.78, a = 1.00 },  -- soft grey
    more     = { r = 0.55, g = 0.55, b = 0.55, a = 1.00 },  -- dimmer grey for "+N more"
}

-- -----------------------------------------------
-- INTERNAL: The actual drawing logic.
-- Called inside a pcall from the render hook below.
-- self = the ISToolTipInv instance being rendered.
-- -----------------------------------------------
local function drawTooltipExtra(self)
    -- Guard 1: safehouse list not received from server yet
    if not MultiSafehouse or not MultiSafehouse.isHydrated then return end

    -- Guard 2: not an item tooltip (could be a world-object tooltip)
    local item = self.item
    if not item then return end

    -- Guard 3: safely get the item's identity key (fullType + name/issue)
    local itemKey = MSI_Cache.getItemKey and MSI_Cache.getItemKey(item)
    if not itemKey then
        local ok, fullType = pcall(function() return item:getFullType() end)
        if ok and fullType then itemKey = fullType end
    end
    if not itemKey then return end

    -- Guard 4: look up the cache — returns nil if not stored at any base
    local info = MSI_Cache.getInfo(itemKey)
    if not info or info.total <= 0 then return end

    -- ---- Build display lines ----
    -- Sort bases by count descending so the most-stocked base is first
    local sortedBases = {}
    for _, b in ipairs(info.bases) do
        sortedBases[#sortedBases + 1] = b
    end
    table.sort(sortedBases, function(a, b) return (a.count or 0) > (b.count or 0) end)

    local titleBase = (getTextOrNull and getTextOrNull("UI_28BL_InvTrack_Title")) or "At Your Bases"
    local titleStr  = titleBase .. ": " .. info.total
    local lines     = {}
    local cap       = math.min(#sortedBases, MSI_Tooltip.MAX_LINES)
    for i = 1, cap do
        local b = sortedBases[i]
        lines[#lines + 1] = { text = "  " .. (b.name or "?") .. ": " .. (b.count or 0), col = COL.line }
    end
    local extra = #sortedBases - cap
    if extra > 0 then
        local moreBase = (getTextOrNull and getTextOrNull("UI_28BL_InvTrack_More")) or "more..."
        lines[#lines + 1] = { text = "  +" .. extra .. " " .. moreBase, col = COL.more }
    end

    -- ---- Measure the box ----
    local font  = UIFont.Small
    local tm    = getTextManager()
    local fh    = tm:getFontHeight(font)
    local pad   = 6

    local boxW = tm:MeasureStringX(font, titleStr)
    for _, l in ipairs(lines) do
        local lw = tm:MeasureStringX(font, l.text)
        if lw > boxW then boxW = lw end
    end
    boxW = boxW + pad * 2

    local boxH = fh * (1 + #lines) + pad * 2   -- 1 title + N lines

    -- ---- Position below the existing tooltip ----
    -- If it would clip off the bottom of the screen, flip it above.
    local x       = 0
    local y       = self:getHeight() + 4
    local screenH = getCore():getScreenHeight()
    if self:getAbsoluteY() + y + boxH > screenH then
        y = -(boxH + 4)
    end

    -- ---- Draw ----
    self:drawRect(x, y, boxW, boxH, COL.bg.a, COL.bg.r, COL.bg.g, COL.bg.b)
    self:drawRectBorder(x, y, boxW, boxH, COL.border.a, COL.border.r, COL.border.g, COL.border.b)

    local ty = y + pad
    self:drawText(titleStr, x + pad, ty, COL.title.r, COL.title.g, COL.title.b, COL.title.a, font)
    ty = ty + fh

    for _, l in ipairs(lines) do
        self:drawText(l.text, x + pad, ty, l.col.r, l.col.g, l.col.b, l.col.a, font)
        ty = ty + fh
    end
end

-- -----------------------------------------------
-- HOOK: Wrap ISToolTipInv:render() — the standard
-- safe pattern used by all well-behaved PZ tooltip mods.
-- -----------------------------------------------
local orig_ISToolTipInv_render = ISToolTipInv.render

function ISToolTipInv:render()
    -- Step 1: always draw the original tooltip first
    orig_ISToolTipInv_render(self)

    -- Step 2: try to draw our extra section; catch any crash silently
    local ok, err = pcall(drawTooltipExtra, self)
    if not ok then
        -- Print once — the error message is useful but we don't want per-frame spam.
        -- Subsequent frames will simply call pcall again; if it still fails, it prints again.
        -- A production hardening option would be to set a flag here and stop trying.
        print("[28 Bases Later] InvTooltip draw error: " .. tostring(err))
    end
end

print("[28 Bases Later] InvTooltip hook installed.")
