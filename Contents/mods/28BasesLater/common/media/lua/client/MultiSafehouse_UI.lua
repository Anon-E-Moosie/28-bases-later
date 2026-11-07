-- =============================================
-- 28 Bases Later — Management UI (Client-Side)
-- =============================================
-- The base management window (F7).
-- Allows viewing owned safehouses, renaming them, setting active respawn,
-- and releasing unwanted safehouses.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"

MultiSafehouseWindow = ISCollapsableWindow:derive("MultiSafehouseWindow")

function MultiSafehouseWindow:initialise()
    ISCollapsableWindow.initialise(self)
    self:setTitle("28 Bases Later")
end

function MultiSafehouseWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight() or 16
    local pad = 10
    local btnH = 26
    local btnW = 85

    -- Clearance from the bottom edge so buttons never overlap the resize handle
    local bottomOffset = rh + 10
    local listBottomMargin = bottomOffset + btnH + 10

    -- 1. Scrollable Base List (Anchored to all 4 edges to resize smoothly)
    self.baseList = ISScrollingListBox:new(
        pad,
        th + pad,
        self.width - pad * 2,
        self.height - th - pad - listBottomMargin
    )
    self.baseList:initialise()
    self.baseList:instantiate()
    self.baseList.itemheight = 36
    self.baseList.drawBorder = true
    self.baseList.doDrawItem = MultiSafehouseWindow.drawBaseItem
    self.baseList:setAnchorLeft(true)
    self.baseList:setAnchorRight(true)
    self.baseList:setAnchorTop(true)
    self.baseList:setAnchorBottom(true)
    self:addChild(self.baseList)

    -- 2. "Set Respawn" Button
    self.respawnBtn = ISButton:new(
        pad,
        self.height - bottomOffset - btnH,
        btnW + 15,
        btnH,
        "Set Respawn",
        self,
        MultiSafehouseWindow.onSetRespawn
    )
    self.respawnBtn:initialise()
    self.respawnBtn:instantiate()
    self.respawnBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self.respawnBtn:setAnchorLeft(true)
    self.respawnBtn:setAnchorBottom(true)
    self.respawnBtn:setAnchorTop(false)
    self:addChild(self.respawnBtn)

    -- 3. "Rename" Button
    self.renameBtn = ISButton:new(
        self.respawnBtn:getRight() + 8,
        self.height - bottomOffset - btnH,
        btnW - 5,
        btnH,
        "Rename",
        self,
        MultiSafehouseWindow.onRename
    )
    self.renameBtn:initialise()
    self.renameBtn:instantiate()
    self.renameBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self.renameBtn:setAnchorLeft(true)
    self.renameBtn:setAnchorBottom(true)
    self.renameBtn:setAnchorTop(false)
    self:addChild(self.renameBtn)

    -- 4. "Release" (Delete) Button
    self.releaseBtn = ISButton:new(
        self.renameBtn:getRight() + 8,
        self.height - bottomOffset - btnH,
        btnW - 5,
        btnH,
        "Release",
        self,
        MultiSafehouseWindow.onRelease
    )
    self.releaseBtn:initialise()
    self.releaseBtn:instantiate()
    self.releaseBtn.borderColor = {r=0.6, g=0.2, b=0.2, a=1}
    self.releaseBtn:setAnchorLeft(true)
    self.releaseBtn:setAnchorBottom(true)
    self.releaseBtn:setAnchorTop(false)
    self:addChild(self.releaseBtn)

    -- 5. "Refresh" Button (Anchored to right edge)
    self.refreshBtn = ISButton:new(
        self.width - pad - btnW,
        self.height - bottomOffset - btnH,
        btnW,
        btnH,
        "Refresh",
        self,
        MultiSafehouseWindow.onRefresh
    )
    self.refreshBtn:initialise()
    self.refreshBtn:instantiate()
    self.refreshBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self.refreshBtn:setAnchorLeft(false)
    self.refreshBtn:setAnchorRight(true)
    self.refreshBtn:setAnchorBottom(true)
    self.refreshBtn:setAnchorTop(false)
    self:addChild(self.refreshBtn)
end

-- Renders each item in the scrollable list with selection highlight
function MultiSafehouseWindow:drawBaseItem(y, item, alt)
    local isSelected = (self.selected == item.index)

    if isSelected then
        -- Gold/orange highlight for selected entry
        self:drawRect(0, y, self:getWidth(), item.height - 1, 0.45, 0.75, 0.45, 0.15)
        self:drawRectBorder(0, y, self:getWidth(), item.height - 1, 0.8, 1.0, 0.7, 0.2)
    else
        self:drawRectBorder(0, y, self:getWidth(), item.height - 1, 0.2, 0.4, 0.4, 0.4)
    end

    local text = item.text or ""
    self:drawText(text, 14, y + 8, 1, 1, 1, 1, UIFont.Small)

    return y + item.height
end

-- Rebuilds list items from cached data, preserving selected row
function MultiSafehouseWindow:refreshList()
    local prevSelected = self.baseList.selected or 1
    self.baseList:clear()

    local player = getPlayer()
    if not player then return end

    local username = player:getUsername()
    local safehouses = MultiSafehouse.playerData[username] or {}

    -- Fallback to vanilla SafeHouse list if player data has not arrived yet
    if #safehouses == 0 and SafeHouse and SafeHouse.getSafehouseList then
        local vanillaList = SafeHouse.getSafehouseList()
        for i = 0, vanillaList:size() - 1 do
            local sh = vanillaList:get(i)
            if sh and sh:getOwner() == username then
                table.insert(safehouses, {
                    x = sh:getX(), y = sh:getY(),
                    w = sh:getW(), h = sh:getH(),
                    name = "Base #" .. (#safehouses + 1),
                    isRespawn = (#safehouses == 0)
                })
            end
        end
        MultiSafehouse.playerData[username] = safehouses
    end

    if #safehouses == 0 then
        self.baseList:addItem("No bases claimed yet. Right-click inside a building!", nil)
    else
        for i, base in ipairs(safehouses) do
            local label = base.name
            if base.isRespawn then
                label = label .. "   [RESPAWN]"
            end
            self.baseList:addItem(label, base)
        end
    end

    -- Maintain row selection within valid item count
    if #safehouses > 0 then
        self.baseList.selected = math.max(1, math.min(prevSelected, #safehouses))
    end
end

-- Requests the freshest safehouse list from server
function MultiSafehouseWindow:onRefresh()
    local player = getPlayer()
    if player then
        sendClientCommand(player, "MultiSafehouse", "requestData", {})
    end
end

-- Rename dialog
function MultiSafehouseWindow:onRename()
    local selectedIndex = self.baseList.selected
    if not selectedIndex or selectedIndex < 1 then return end

    local selectedItem = self.baseList.items[selectedIndex]
    if not selectedItem or not selectedItem.item then return end

    self.renameIndex = selectedIndex
    local currentName = selectedItem.item.name or ""

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISTextBox:new(
        (screenW - 300) / 2,
        (screenH - 100) / 2,
        300, 100,
        "Enter new name (max 32 chars):",
        currentName,
        self,
        MultiSafehouseWindow.onRenameConfirm
    )
    modal:initialise()
    modal:addToUIManager()
end

function MultiSafehouseWindow:onRenameConfirm(button)
    if button.internal == "OK" then
        local newName = button.parent.entry:getText()
        if newName and newName ~= "" then
            local player = getPlayer()
            if player then
                sendClientCommand(player, "MultiSafehouse", "renameBase", {
                    index = self.renameIndex,
                    newName = newName
                })
            end
        end
    end
    self.renameIndex = nil
end

-- Release confirmation dialog
function MultiSafehouseWindow:onRelease()
    local selectedIndex = self.baseList.selected
    if not selectedIndex or selectedIndex < 1 then return end

    local selectedItem = self.baseList.items[selectedIndex]
    if not selectedItem or not selectedItem.item then return end

    local baseName = selectedItem.item.name or ("Base #" .. selectedIndex)

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        (screenW - 350) / 2,
        (screenH - 120) / 2,
        350, 120,
        "Release safehouse '" .. baseName .. "'?",
        true,
        self,
        MultiSafehouseWindow.onReleaseConfirm
    )
    modal:initialise()
    modal:addToUIManager()
end

function MultiSafehouseWindow:onReleaseConfirm(button)
    if button.internal == "YES" then
        local selectedIndex = self.baseList.selected
        if selectedIndex and selectedIndex >= 1 then
            local player = getPlayer()
            if player then
                sendClientCommand(player, "MultiSafehouse", "releaseBase", {
                    index = selectedIndex
                })
            end
        end
    end
end

-- Set respawn on selected base
function MultiSafehouseWindow:onSetRespawn()
    local selectedIndex = self.baseList.selected
    if not selectedIndex or selectedIndex < 1 then return end

    local selectedItem = self.baseList.items[selectedIndex]
    if not selectedItem or not selectedItem.item then return end

    local player = getPlayer()
    if player then
        sendClientCommand(player, "MultiSafehouse", "setRespawn", {
            index = selectedIndex
        })
    end
end

function MultiSafehouseWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    return o
end

-- -----------------------------------------------
-- WINDOW TOGGLE & NETWORKING
-- -----------------------------------------------
function MultiSafehouse.toggleUI()
    if MultiSafehouse.uiWindow and MultiSafehouse.uiWindow:isVisible() then
        MultiSafehouse.uiWindow:setVisible(false)
        return
    end

    if not MultiSafehouse.uiWindow then
        local screenW = getCore():getScreenWidth()
        local screenH = getCore():getScreenHeight()
        local winW = 460
        local winH = 340
        local x = (screenW - winW) / 2
        local y = (screenH - winH) / 2

        local window = MultiSafehouseWindow:new(x, y, winW, winH)
        window:initialise()
        window:addToUIManager()

        MultiSafehouse.uiWindow = window
    end

    MultiSafehouse.uiWindow:setVisible(true)
    MultiSafehouse.uiWindow:refreshList()

    local player = getPlayer()
    if player then
        sendClientCommand(player, "MultiSafehouse", "requestData", {})
    end
end

-- Updates client cache and refreshes UI when server sends updated list
local function onServerCommand(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    if command == "syncData" and args.safehouses then
        local player = getPlayer()
        if player then
            MultiSafehouse.playerData[player:getUsername()] = args.safehouses
        end

        if MultiSafehouse.uiWindow and MultiSafehouse.uiWindow:isVisible() then
            MultiSafehouse.uiWindow:refreshList()
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

local function onKeyPressed(key)
    if key == Keyboard.KEY_F7 then
        MultiSafehouse.toggleUI()
    end
end

Events.OnKeyPressed.Add(onKeyPressed)

print("[28 Bases Later] Management UI initialized.")
