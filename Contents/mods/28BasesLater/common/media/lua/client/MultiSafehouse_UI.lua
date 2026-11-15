-- =============================================
-- 28 Bases Later — Management UI (Client-Side)
-- =============================================
-- The base management window (F7).
-- Features a two-column layout:
-- Left Column:  List of claimed and shared safehouses with owner/member tags.
-- Right Column: Base details, active member roster, and member management controls.
-- Bottom Row:   Active respawn designation, renaming, releasing, and refreshing.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"
require "ISUI/ISLabel"

MultiSafehouseWindow = ISCollapsableWindow:derive("MultiSafehouseWindow")

function MultiSafehouseWindow:initialise()
    ISCollapsableWindow.initialise(self)
    self:setTitle(getText("UI_MultiSafehouse_WindowTitle", "28 Bases Later"))
    self.minimumWidth = 580
    self.minimumHeight = 360
end

function MultiSafehouseWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local pad = 10
    local btnH = 26
    local btnW = 85

    -- =========================================================
    -- 1. LEFT COLUMN: Base List
    -- =========================================================
    self.baseList = ISScrollingListBox:new(pad, th + pad, 250, 260)
    self.baseList:initialise()
    self.baseList:instantiate()
    self.baseList.itemheight = 36
    self.baseList.drawBorder = true
    self.baseList.doDrawItem = MultiSafehouseWindow.drawBaseItem
    self.baseList.onMouseDown = function(list, x, y)
        local row = ISScrollingListBox.onMouseDown(list, x, y)
        local win = list.parent
        if win and win.onBaseSelected then
            win:onBaseSelected()
        end
        return row
    end
    self:addChild(self.baseList)

    -- =========================================================
    -- 2. RIGHT COLUMN: Base Details & Member Roster
    -- =========================================================
    self.baseNameLabel = ISLabel:new(270, th + pad, 22, "Select a safehouse", 1, 1, 1, 1, UIFont.Medium, true)
    self.baseNameLabel:initialise()
    self:addChild(self.baseNameLabel)

    self.baseOwnerLabel = ISLabel:new(270, th + pad + 24, 18, "Owner: -", 0.85, 0.85, 0.85, 1, UIFont.Small, true)
    self.baseOwnerLabel:initialise()
    self:addChild(self.baseOwnerLabel)

    self.baseCoordsLabel = ISLabel:new(270, th + pad + 42, 18, "Dimensions: -", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self.baseCoordsLabel:initialise()
    self:addChild(self.baseCoordsLabel)

    self.baseRespawnLabel = ISLabel:new(270, th + pad + 60, 18, "Personal Respawn: Inactive", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self.baseRespawnLabel:initialise()
    self:addChild(self.baseRespawnLabel)

    self.membersHeaderLabel = ISLabel:new(270, th + pad + 82, 18, getText("UI_MultiSafehouse_MembersHeader", "Whitelisted Members:"), 1, 0.85, 0.4, 1, UIFont.Small, true)
    self.membersHeaderLabel:initialise()
    self:addChild(self.membersHeaderLabel)

    self.memberList = ISScrollingListBox:new(270, th + pad + 104, 340, 160)
    self.memberList:initialise()
    self.memberList:instantiate()
    self.memberList.itemheight = 28
    self.memberList.drawBorder = true
    self.memberList.doDrawItem = MultiSafehouseWindow.drawMemberItem
    self.memberList.onMouseDown = function(list, x, y)
        local row = ISScrollingListBox.onMouseDown(list, x, y)
        local win = list.parent
        if win and win.updatePermissionControls then
            win:updatePermissionControls()
        end
        return row
    end
    self:addChild(self.memberList)

    -- Member Action Buttons
    self.addMemberBtn = ISButton:new(
        270,
        280,
        120,
        btnH,
        getText("UI_MultiSafehouse_AddMember", "+ Add Member"),
        self,
        MultiSafehouseWindow.onAddMember
    )
    self.addMemberBtn:initialise()
    self.addMemberBtn:instantiate()
    self.addMemberBtn.borderColor = {r=0.2, g=0.5, b=0.2, a=1}
    self:addChild(self.addMemberBtn)

    self.kickMemberBtn = ISButton:new(
        400,
        280,
        120,
        btnH,
        getText("UI_MultiSafehouse_KickMember", "- Kick Member"),
        self,
        MultiSafehouseWindow.onKickMember
    )
    self.kickMemberBtn:initialise()
    self.kickMemberBtn:instantiate()
    self.kickMemberBtn.borderColor = {r=0.6, g=0.2, b=0.2, a=1}
    self:addChild(self.kickMemberBtn)

    self.leaveBaseBtn = ISButton:new(
        530,
        280,
        110,
        btnH,
        getText("UI_MultiSafehouse_LeaveBase", "Leave Base"),
        self,
        MultiSafehouseWindow.onLeaveBase
    )
    self.leaveBaseBtn:initialise()
    self.leaveBaseBtn:instantiate()
    self.leaveBaseBtn.borderColor = {r=0.5, g=0.3, b=0.1, a=1}
    self:addChild(self.leaveBaseBtn)

    -- =========================================================
    -- 3. BOTTOM ROW: Global Actions
    -- =========================================================
    self.respawnBtn = ISButton:new(
        pad,
        self.height - pad - btnH,
        btnW + 15,
        btnH,
        getText("UI_MultiSafehouse_SetRespawn", "Set Respawn"),
        self,
        MultiSafehouseWindow.onSetRespawn
    )
    self.respawnBtn:initialise()
    self.respawnBtn:instantiate()
    self.respawnBtn.borderColor = {r=0.3, g=0.5, b=0.3, a=1}
    self:addChild(self.respawnBtn)

    self.renameBtn = ISButton:new(
        self.respawnBtn:getRight() + 8,
        self.height - pad - btnH,
        btnW - 5,
        btnH,
        getText("UI_MultiSafehouse_Rename", "Rename"),
        self,
        MultiSafehouseWindow.onRename
    )
    self.renameBtn:initialise()
    self.renameBtn:instantiate()
    self.renameBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self:addChild(self.renameBtn)

    self.releaseBtn = ISButton:new(
        self.renameBtn:getRight() + 8,
        self.height - pad - btnH,
        btnW - 5,
        btnH,
        getText("UI_MultiSafehouse_Release", "Release"),
        self,
        MultiSafehouseWindow.onRelease
    )
    self.releaseBtn:initialise()
    self.releaseBtn:instantiate()
    self.releaseBtn.borderColor = {r=0.6, g=0.2, b=0.2, a=1}
    self:addChild(self.releaseBtn)

    self.refreshBtn = ISButton:new(
        self.width - pad - btnW,
        self.height - pad - btnH,
        btnW,
        btnH,
        getText("UI_MultiSafehouse_Refresh", "Refresh"),
        self,
        MultiSafehouseWindow.onRefresh
    )
    self.refreshBtn:initialise()
    self.refreshBtn:instantiate()
    self.refreshBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self:addChild(self.refreshBtn)

    -- Trigger initial proportional layout
    self:onResize()
end

-- Recalculates proportional layout dynamically on window resize
function MultiSafehouseWindow:onResize()
    ISCollapsableWindow.onResize(self)

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight() or 16
    local pad = 10
    local btnH = 26
    local btnW = 85

    local bottomOffset = rh + 10
    local bottomRowY = self.height - bottomOffset - btnH

    -- Proportional Two-Column Allocation
    local col1W = math.max(240, math.floor(self.width * 0.38))
    local col2X = pad + col1W + pad
    local col2W = math.max(260, self.width - col2X - pad)

    local listBottomMargin = bottomOffset + btnH + 10

    -- 1. Resize baseList
    if self.baseList then
        self.baseList:setX(pad)
        self.baseList:setY(th + pad)
        self.baseList:setWidth(col1W)
        self.baseList:setHeight(math.max(100, self.height - th - pad - listBottomMargin))
    end

    -- 2. Reposition right column labels
    local curY = th + pad
    if self.baseNameLabel then
        self.baseNameLabel:setX(col2X)
        self.baseNameLabel:setY(curY)
    end
    curY = curY + 24
    if self.baseOwnerLabel then
        self.baseOwnerLabel:setX(col2X)
        self.baseOwnerLabel:setY(curY)
    end
    curY = curY + 18
    if self.baseCoordsLabel then
        self.baseCoordsLabel:setX(col2X)
        self.baseCoordsLabel:setY(curY)
    end
    curY = curY + 18
    if self.baseRespawnLabel then
        self.baseRespawnLabel:setX(col2X)
        self.baseRespawnLabel:setY(curY)
    end
    curY = curY + 22
    if self.membersHeaderLabel then
        self.membersHeaderLabel:setX(col2X)
        self.membersHeaderLabel:setY(curY)
    end
    curY = curY + 20

    -- 3. Calculate dynamic height for memberList and position member buttons
    local memberBtnsH = 26
    local memberBtnsY = bottomRowY - 12 - memberBtnsH
    local memberListH = math.max(80, memberBtnsY - 8 - curY)

    if self.memberList then
        self.memberList:setX(col2X)
        self.memberList:setY(curY)
        self.memberList:setWidth(col2W)
        self.memberList:setHeight(memberListH)
    end

    local memberBtnW = math.max(110, math.min(135, math.floor((col2W - 20) / 3)))
    if self.addMemberBtn then
        self.addMemberBtn:setX(col2X)
        self.addMemberBtn:setY(memberBtnsY)
        self.addMemberBtn:setWidth(memberBtnW)
        self.addMemberBtn:setHeight(memberBtnsH)
    end
    if self.kickMemberBtn then
        self.kickMemberBtn:setX(col2X + memberBtnW + 10)
        self.kickMemberBtn:setY(memberBtnsY)
        self.kickMemberBtn:setWidth(memberBtnW)
        self.kickMemberBtn:setHeight(memberBtnsH)
    end
    if self.leaveBaseBtn then
        self.leaveBaseBtn:setX(col2X + col2W - memberBtnW)
        self.leaveBaseBtn:setY(memberBtnsY)
        self.leaveBaseBtn:setWidth(memberBtnW)
        self.leaveBaseBtn:setHeight(memberBtnsH)
    end

    -- 4. Position bottom row global buttons
    if self.respawnBtn then
        self.respawnBtn:setX(pad)
        self.respawnBtn:setY(bottomRowY)
    end
    if self.renameBtn then
        self.renameBtn:setX(self.respawnBtn:getRight() + 8)
        self.renameBtn:setY(bottomRowY)
    end
    if self.releaseBtn then
        self.releaseBtn:setX(self.renameBtn:getRight() + 8)
        self.releaseBtn:setY(bottomRowY)
    end
    if self.refreshBtn then
        self.refreshBtn:setX(self.width - pad - btnW)
        self.refreshBtn:setY(bottomRowY)
    end
end

-- Renders each safehouse in the left list with ownership tag and respawn marker
function MultiSafehouseWindow:drawBaseItem(y, item, alt)
    local isSelected = (self.selected == item.index)
    local itemW = (self.isVScrollBarVisible and self:isVScrollBarVisible()) and (self:getWidth() - 13) or self:getWidth()

    if isSelected then
        self:drawRect(0, y, itemW, item.height - 1, 0.45, 0.75, 0.45, 0.15)
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.8, 1.0, 0.7, 0.2)
    else
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.2, 0.4, 0.4, 0.4)
    end

    local base = item.item
    local tag = ""
    local r, g, b = 1, 1, 1

    if base then
        if base.isOwner == false then
            tag = "[MEMBER] "
            r, g, b = 0.65, 0.85, 1.0 -- Soft cyan for member bases
        else
            tag = "[OWNER] "
            r, g, b = 1.0, 1.0, 1.0
        end
    end

    local text = tag .. (item.text or "")
    local fontHgt = getTextManager():getFontHeight(UIFont.Small)
    local textY = y + math.floor((item.height - fontHgt) / 2)
    self:drawText(text, 10, textY, r, g, b, 1, UIFont.Small)

    return y + item.height
end

-- Renders each member in the right member roster
function MultiSafehouseWindow:drawMemberItem(y, item, alt)
    local isSelected = (self.selected == item.index)
    local itemW = (self.isVScrollBarVisible and self:isVScrollBarVisible()) and (self:getWidth() - 13) or self:getWidth()

    if isSelected then
        self:drawRect(0, y, itemW, item.height - 1, 0.35, 0.2, 0.6, 0.3)
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.7, 0.4, 1.0, 0.5)
    else
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.15, 0.3, 0.3, 0.3)
    end

    local text = item.text or ""
    local isOwner = string.find(text, "%[Owner%]") ~= nil
    local r, g, b = 0.9, 0.9, 0.9
    if isOwner then
        r, g, b = 1.0, 0.85, 0.3 -- Gold for owner
    end

    local fontHgt = getTextManager():getFontHeight(UIFont.Small)
    local textY = y + math.floor((item.height - fontHgt) / 2)
    self:drawText(text, 10, textY, r, g, b, 1, UIFont.Small)

    return y + item.height
end

local function findClientSafehouse(x, y)
    if not SafeHouse or not SafeHouse.getSafehouseList then return nil end
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh and sh:getX() == x and sh:getY() == y then
            return sh
        end
    end
    return nil
end

local function extractSafehouseMembersClient(sh, ownerUsername)
    local members = {}
    if not sh or not sh.getPlayers then return members end
    local ok, players = pcall(function() return sh:getPlayers() end)
    if not ok or not players then return members end
    local okSize, n = pcall(function() return players:size() end)
    if not okSize or type(n) ~= "number" then return members end
    for i = 0, n - 1 do
        local okGet, u = pcall(function() return players:get(i) end)
        if okGet and u then
            local uName = tostring(u)
            if uName ~= "" and uName ~= ownerUsername then
                table.insert(members, uName)
            end
        end
    end
    return members
end

-- Rebuilds list items from cached data, preserving selected row
function MultiSafehouseWindow:refreshList()
    local prevSelected = self.baseList.selected or 1
    self.baseList:clear()

    local player = getPlayer()
    if not player then return end

    local username = player:getUsername()
    local safehouses = MultiSafehouse.playerData[username] or {}

    if not MultiSafehouse.isHydrated then
        self.baseList:addItem("Fetching bases from server...", nil)
        self:onBaseSelected()
        return
    end

    if #safehouses == 0 then
        self.baseList:addItem("No bases claimed yet. Right-click inside a building!", nil)
    else
        for i, base in ipairs(safehouses) do
            local sh = findClientSafehouse(base.x, base.y)
            if sh then
                if sh.getTitle then
                    local nativeTitle = sh:getTitle()
                    if nativeTitle and nativeTitle ~= "" then
                        base.name = nativeTitle
                    end
                end
                if sh.isRespawnInSafehouse then
                    base.isRespawn = (sh:isRespawnInSafehouse(username) == true)
                end
                base.owner = sh:getOwner() or base.owner
                base.isOwner = (base.owner == username)
                base.members = extractSafehouseMembersClient(sh, base.owner)
            end

            local label = base.name or ("Base #" .. i)
            if base.isRespawn then
                label = label .. "   [RESPAWN]"
            end
            self.baseList:addItem(label, base)
        end
    end

    if #safehouses > 0 then
        self.baseList.selected = math.max(1, math.min(prevSelected, #safehouses))
    end

    self:onBaseSelected()
end

-- Handles base selection: refreshes right panel labels, members, and permissions
function MultiSafehouseWindow:onBaseSelected()
    local selectedIndex = self.baseList.selected
    local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
    local base = selectedItem and selectedItem.item or nil

    local player = getPlayer()
    local myUsername = player and player:getUsername() or ""

    if not base then
        self.baseNameLabel:setName("No base selected")
        self.baseOwnerLabel:setName("Owner: -")
        self.baseCoordsLabel:setName("Dimensions: -")
        self.baseRespawnLabel:setName("Personal Respawn: -")
        self.memberList:clear()
        self:updatePermissionControls()
        return
    end

    local baseTitle = base.name or "Safehouse"
    self.baseNameLabel:setName(baseTitle)

    local ownerStr = base.owner or myUsername
    if ownerStr == myUsername then
        self.baseOwnerLabel:setName("Owner: " .. ownerStr .. " (You)")
    else
        self.baseOwnerLabel:setName("Owner: " .. ownerStr)
    end

    local dimStr = string.format("Dimensions: %dx%d (X: %d, Y: %d)", base.w or 0, base.h or 0, base.x or 0, base.y or 0)
    self.baseCoordsLabel:setName(dimStr)

    if base.isRespawn then
        self.baseRespawnLabel:setName("Personal Respawn: ACTIVE")
    else
        self.baseRespawnLabel:setName("Personal Respawn: Inactive")
    end

    -- Populate member roster
    self.memberList:clear()
    local ownerName = base.owner or myUsername
    self.memberList:addItem(ownerName .. "  [Owner]", ownerName)

    if base.members and #base.members > 0 then
        for _, memberName in ipairs(base.members) do
            if memberName ~= ownerName then
                self.memberList:addItem(memberName .. "  [Member]", memberName)
            end
        end
    end

    self:updatePermissionControls()
end

-- Evaluates role permissions for active player and adjusts UI controls accordingly
function MultiSafehouseWindow:updatePermissionControls()
    local selectedIndex = self.baseList.selected
    local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
    local base = selectedItem and selectedItem.item or nil

    local player = getPlayer()
    local myUsername = player and player:getUsername() or ""
    local isAdmin = MultiSafehouse.Validation and MultiSafehouse.Validation.isPlayerAdmin and MultiSafehouse.Validation.isPlayerAdmin(player)

    if not base then
        self.respawnBtn:setEnable(false)
        self.renameBtn:setEnable(false)
        self.releaseBtn:setEnable(false)
        self.addMemberBtn:setEnable(false)
        self.kickMemberBtn:setEnable(false)
        self.leaveBaseBtn:setEnable(false)
        return
    end

    local isOwner = (base.isOwner == true) or (base.owner == myUsername)
    local canManage = isOwner or isAdmin

    -- Set Respawn: Allowed for both Owner and Member
    self.respawnBtn:setEnable(true)
    self.respawnBtn:setTooltip(nil)

    -- Rename & Release: Allowed for Owner & Admin only
    self.renameBtn:setEnable(canManage)
    if not canManage then
        self.renameBtn:setTooltip("Only the safehouse owner can rename this base.")
    else
        self.renameBtn:setTooltip(nil)
    end

    self.releaseBtn:setEnable(canManage)
    if not canManage then
        self.releaseBtn:setTooltip("Only the safehouse owner can release this base. Use 'Leave Base' to depart.")
    else
        self.releaseBtn:setTooltip(nil)
    end

    local isMultiplayer = isClient() or isServer()

    if not isMultiplayer then
        self.addMemberBtn:setEnable(false)
        self.kickMemberBtn:setEnable(false)
        self.leaveBaseBtn:setEnable(false)
        self.addMemberBtn:setTooltip("Multiplayer only.")
        self.kickMemberBtn:setTooltip("Multiplayer only.")
        self.leaveBaseBtn:setTooltip("Multiplayer only.")
    else
        -- Add Member: Allowed for Owner & Admin
        self.addMemberBtn:setEnable(canManage)
        if not canManage then
            self.addMemberBtn:setTooltip("Only the safehouse owner can invite members.")
        else
            self.addMemberBtn:setTooltip("Invite an online player to this safehouse.")
        end

        -- Kick Member: Allowed for Owner & Admin when a non-owner member is selected
        local selectedMemberIndex = self.memberList.selected
        local selectedMemberItem = selectedMemberIndex and self.memberList.items[selectedMemberIndex]
        local memberUsername = selectedMemberItem and selectedMemberItem.item or nil

        local canKickSelected = canManage and memberUsername and (memberUsername ~= base.owner)
        self.kickMemberBtn:setEnable(canKickSelected == true)
        if not canManage then
            self.kickMemberBtn:setTooltip("Only the safehouse owner can remove members.")
        elseif not memberUsername then
            self.kickMemberBtn:setTooltip("Select a member from the list to remove.")
        elseif memberUsername == base.owner then
            self.kickMemberBtn:setTooltip("Cannot remove the safehouse owner.")
        else
            self.kickMemberBtn:setTooltip("Remove " .. memberUsername .. " from this safehouse.")
        end

        -- Leave Base: Allowed for Members only
        local canLeave = (not isOwner) and (not isAdmin or base.owner ~= myUsername)
        self.leaveBaseBtn:setEnable(canLeave)
        if isOwner then
            self.leaveBaseBtn:setTooltip("The owner cannot leave their own safehouse. Use 'Release' to abandon.")
        else
            self.leaveBaseBtn:setTooltip("Leave this safehouse and revoke your membership.")
        end
    end
end

-- Requests the freshest safehouse list from server
function MultiSafehouseWindow:onRefresh()
    local player = getPlayer()
    if player then
        sendClientCommand(player, "MultiSafehouse", "requestData", { reason = "manualRefresh" })
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
                local selectedItem = self.baseList.items[self.renameIndex]
                local baseObj = selectedItem and selectedItem.item or nil

                if baseObj and baseObj.x and baseObj.y then
                    local sh = findClientSafehouse(baseObj.x, baseObj.y)
                    if sh then
                        pcall(function() sh:setTitle(newName) end)
                        if sendSafehouseChangeTitle then
                            pcall(function() sendSafehouseChangeTitle(sh, newName) end)
                        end
                    end
                end

                sendClientCommand(player, "MultiSafehouse", "renameBase", {
                    index = self.renameIndex,
                    x = baseObj and baseObj.x or nil,
                    y = baseObj and baseObj.y or nil,
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

    local baseObj = selectedItem.item
    local baseName = baseObj.name or ("Base #" .. selectedIndex)

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        (screenW - 350) / 2,
        (screenH - 120) / 2,
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
        local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
        local baseObj = selectedItem and selectedItem.item
        if baseObj then
            local player = getPlayer()
            if player then
                sendClientCommand(player, "MultiSafehouse", "releaseBase", {
                    index = selectedIndex,
                    x = baseObj.x,
                    y = baseObj.y
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

    local baseObj = selectedItem.item
    local player = getPlayer()
    if player then
        sendClientCommand(player, "MultiSafehouse", "setRespawn", {
            index = selectedIndex,
            x = baseObj.x,
            y = baseObj.y
        })
    end
end

-- Add Member button clicked: opens player picker dialog
function MultiSafehouseWindow:onAddMember()
    local selectedIndex = self.baseList.selected
    local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
    local baseObj = selectedItem and selectedItem.item
    if baseObj and MultiSafehouse.openPlayerPicker then
        MultiSafehouse.openPlayerPicker(baseObj)
    end
end

-- Kick Member button clicked: confirms removal of selected member
function MultiSafehouseWindow:onKickMember()
    local selectedIndex = self.baseList.selected
    local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
    local baseObj = selectedItem and selectedItem.item
    if not baseObj then return end

    local memberIndex = self.memberList.selected
    local memberItem = memberIndex and self.memberList.items[memberIndex]
    local targetUsername = memberItem and memberItem.item

    if not targetUsername or targetUsername == baseObj.owner then return end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        (screenW - 350) / 2,
        (screenH - 120) / 2,
        "Remove '" .. targetUsername .. "' from safehouse '" .. (baseObj.name or "Base") .. "'?",
        true,
        self,
        MultiSafehouseWindow.onKickMemberConfirm
    )
    modal:initialise()
    modal:addToUIManager()
    self.pendingKickTarget = targetUsername
    self.pendingKickBase = baseObj
end

function MultiSafehouseWindow:onKickMemberConfirm(button)
    if button.internal == "YES" and self.pendingKickTarget and self.pendingKickBase then
        local player = getPlayer()
        if player then
            sendClientCommand(player, "MultiSafehouse", "kickMember", {
                x = self.pendingKickBase.x,
                y = self.pendingKickBase.y,
                targetUsername = self.pendingKickTarget
            })
        end
    end
    self.pendingKickTarget = nil
    self.pendingKickBase = nil
end

-- Leave Base button clicked: confirms departure from member safehouse
function MultiSafehouseWindow:onLeaveBase()
    local selectedIndex = self.baseList.selected
    local selectedItem = selectedIndex and self.baseList.items[selectedIndex]
    local baseObj = selectedItem and selectedItem.item
    if not baseObj then return end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        (screenW - 350) / 2,
        (screenH - 120) / 2,
        "Leave safehouse '" .. (baseObj.name or "Base") .. "'?\nYou will lose access to this safehouse.",
        true,
        self,
        MultiSafehouseWindow.onLeaveBaseConfirm
    )
    modal:initialise()
    modal:addToUIManager()
    self.pendingLeaveBase = baseObj
end

function MultiSafehouseWindow:onLeaveBaseConfirm(button)
    if button.internal == "YES" and self.pendingLeaveBase then
        local player = getPlayer()
        if player then
            sendClientCommand(player, "MultiSafehouse", "leaveBase", {
                x = self.pendingLeaveBase.x,
                y = self.pendingLeaveBase.y
            })
        end
    end
    self.pendingLeaveBase = nil
end

-- =============================================
-- Global Window Management & Networking
-- =============================================

function MultiSafehouse.toggleUI()
    local player = getPlayer()
    if not player then return end

    local username = player:getUsername()

    if not MultiSafehouse.uiWindow then
        local screenW = getCore():getScreenWidth()
        local screenH = getCore():getScreenHeight()
        local winW = 660
        local winH = 420
        local winX = (screenW - winW) / 2
        local winY = (screenH - winH) / 2

        MultiSafehouse.uiWindow = MultiSafehouseWindow:new(winX, winY, winW, winH)
        MultiSafehouse.uiWindow:initialise()
        MultiSafehouse.uiWindow:addToUIManager()
    else
        MultiSafehouse.uiWindow:setVisible(not MultiSafehouse.uiWindow:isVisible())
    end

    if MultiSafehouse.uiWindow:isVisible() then
        if not MultiSafehouse.isHydrated then
            sendClientCommand(player, "MultiSafehouse", "requestData", { reason = "initialLoad" })
        end
        MultiSafehouse.uiWindow:refreshList()
    end
end

local function onServerCommand(module, command, args)
    if module ~= "MultiSafehouse" or not args then return end

    if command == "syncData" and args.safehouses then
        local player = getPlayer()
        if player then
            MultiSafehouse.playerData[player:getUsername()] = args.safehouses
            MultiSafehouse.isHydrated = true
        end

        if MultiSafehouse.uiWindow and MultiSafehouse.uiWindow:isVisible() then
            MultiSafehouse.uiWindow:refreshList()
        end
    elseif command == "syncAdminConfig" then
        if args.maxBases ~= nil then
            local val = tonumber(args.maxBases)
            MultiSafehouse.serverMaxBases = val
            MultiSafehouse.server_MaxBasesPerPlayer = val
        end
        if args.allowNonResidential ~= nil then
            local val = (args.allowNonResidential == true)
            MultiSafehouse.serverAllowNonResidential = val
            MultiSafehouse.server_AllowNonResidential = val
        end
        if args.allowSpawnBuildings ~= nil then
            local val = (args.allowSpawnBuildings == true)
            MultiSafehouse.serverAllowSpawnBuildings = val
            MultiSafehouse.server_AllowSpawnBuildings = val
        end
        if args.daysSurvivedToClaim ~= nil then
            local val = tonumber(args.daysSurvivedToClaim)
            MultiSafehouse.serverDaysSurvivedToClaim = val
            MultiSafehouse.server_DaysSurvivedToClaim = val
        end
        if args.adminBypassRestrictions ~= nil then
            local val = (args.adminBypassRestrictions == true)
            MultiSafehouse.serverAdminBypassRestrictions = val
            MultiSafehouse.server_AdminBypassRestrictions = val
        end
    elseif command == "memberNotice" and args.msg then
        local player = getPlayer()
        if player and player.Say then
            player:Say(args.msg)
        end
    end
end

-- Listens to native engine event when any safehouse is claimed, released, or renamed
local function onSafehousesChanged()
    local player = getPlayer()
    if not player then return end
    local username = player:getUsername()

    if MultiSafehouse.playerData[username] and SafeHouse and SafeHouse.getSafehouseList then
        local list = SafeHouse.getSafehouseList()
        local activeCoords = {}
        for i = 0, list:size() - 1 do
            local sh = list:get(i)
            if sh then
                local isOwner = (sh:getOwner() == username)
                local isMember = (sh.getPlayers and sh:getPlayers():contains(username))
                if isOwner or isMember then
                    activeCoords[sh:getX() .. "," .. sh:getY()] = sh
                end
            end
        end

        local updated = {}
        for _, base in ipairs(MultiSafehouse.playerData[username]) do
            local key = base.x .. "," .. base.y
            local sh = activeCoords[key]
            if sh then
                local nativeTitle = sh:getTitle()
                if nativeTitle and nativeTitle ~= "" then
                    base.name = nativeTitle
                end
                base.w = sh:getW()
                base.h = sh:getH()
                base.owner = sh:getOwner()
                base.isOwner = (sh:getOwner() == username)
                if sh.isRespawnInSafehouse then
                    base.isRespawn = (sh:isRespawnInSafehouse(username) == true)
                end
                base.members = extractSafehouseMembersClient(sh, sh:getOwner())
                table.insert(updated, base)
                activeCoords[key] = nil
            end
        end

        for key, sh in pairs(activeCoords) do
            local isOwner = (sh:getOwner() == username)
            local baseName = sh:getTitle()
            if not baseName or baseName == "" then
                baseName = isOwner and ("Base #" .. (#updated + 1)) or "Shared Safehouse"
            end
            local isResp = false
            if sh.isRespawnInSafehouse then
                isResp = (sh:isRespawnInSafehouse(username) == true)
            end
            table.insert(updated, {
                x = sh:getX(),
                y = sh:getY(),
                w = sh:getW(),
                h = sh:getH(),
                name = baseName,
                owner = sh:getOwner(),
                isOwner = isOwner,
                isRespawn = isResp,
                members = extractSafehouseMembersClient(sh, sh:getOwner())
            })
        end

        MultiSafehouse.playerData[username] = updated
    end

    if MultiSafehouse.uiWindow and MultiSafehouse.uiWindow:isVisible() then
        MultiSafehouse.uiWindow:refreshList()
    end
end

if Events and Events.OnSafehousesChanged then
    Events.OnSafehousesChanged.Add(onSafehousesChanged)
end

Events.OnServerCommand.Add(onServerCommand)

local function onKeyPressed(key)
    if key == Keyboard.KEY_F7 then
        MultiSafehouse.toggleUI()
    end
end

Events.OnKeyPressed.Add(onKeyPressed)

print("[28 Bases Later] Management UI initialized with responsive layout.")
