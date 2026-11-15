-- =============================================
-- 28 Bases Later — Player Picker Dialog
-- =============================================
-- Modal dialog allowing safehouse owners and admins to select an online
-- player and send them an invite to the active safehouse.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"

MultiSafehousePlayerPicker = ISCollapsableWindow:derive("MultiSafehousePlayerPicker")

function MultiSafehousePlayerPicker:initialise()
    ISCollapsableWindow.initialise(self)
    self:setTitle(getText("UI_MultiSafehouse_InviteTitle", "Invite Player to Safehouse"))
    self.resizable = false
end

function MultiSafehousePlayerPicker:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local pad = 10
    local btnH = 26
    local btnW = 90

    -- Header label
    local prompt = getText("UI_MultiSafehouse_SelectPlayerToInvite", "Select an online player to invite:")
    self.headerLabel = ISLabel:new(pad, th + pad, 20, prompt, 1, 1, 1, 1, UIFont.Small, true)
    self.headerLabel:initialise()
    self:addChild(self.headerLabel)

    local listTop = th + pad + 24
    local listBottomMargin = pad + btnH + pad

    -- Online Players list
    self.playerList = ISScrollingListBox:new(
        pad,
        listTop,
        self.width - pad * 2,
        self.height - listTop - listBottomMargin
    )
    self.playerList:initialise()
    self.playerList:instantiate()
    self.playerList.itemheight = 28
    self.playerList.drawBorder = true
    self.playerList.doDrawItem = MultiSafehousePlayerPicker.drawPlayerItem
    self.playerList.onMouseDown = function(list, x, y)
        local row = ISScrollingListBox.onMouseDown(list, x, y)
        local picker = list.parent
        if picker and picker.updateInviteButton then
            picker:updateInviteButton()
        end
        return row
    end
    self:addChild(self.playerList)

    -- Invite button
    self.inviteBtn = ISButton:new(
        pad,
        self.height - pad - btnH,
        btnW,
        btnH,
        getText("UI_MultiSafehouse_InviteBtn", "Invite"),
        self,
        MultiSafehousePlayerPicker.onInvite
    )
    self.inviteBtn:initialise()
    self.inviteBtn:instantiate()
    self.inviteBtn.enable = false
    self.inviteBtn.borderColor = {r=0.2, g=0.6, b=0.2, a=1}
    self:addChild(self.inviteBtn)

    -- Cancel button
    self.cancelBtn = ISButton:new(
        self.width - pad - btnW,
        self.height - pad - btnH,
        btnW,
        btnH,
        getText("UI_Cancel", "Cancel"),
        self,
        MultiSafehousePlayerPicker.onCancel
    )
    self.cancelBtn:initialise()
    self.cancelBtn:instantiate()
    self.cancelBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self:addChild(self.cancelBtn)

    self:onResize()
    self:populatePlayerList()
end

function MultiSafehousePlayerPicker:onResize()
    ISCollapsableWindow.onResize(self)

    local th = self:titleBarHeight()
    local pad = 10
    local btnH = 26
    local btnW = 90
    local listTop = th + pad + 24
    local listBottomMargin = pad + btnH + pad

    if self.headerLabel then
        self.headerLabel:setX(pad)
        self.headerLabel:setY(th + pad)
    end
    if self.playerList then
        self.playerList:setX(pad)
        self.playerList:setY(listTop)
        self.playerList:setWidth(self.width - pad * 2)
        self.playerList:setHeight(math.max(80, self.height - listTop - listBottomMargin))
    end
    if self.inviteBtn then
        self.inviteBtn:setX(pad)
        self.inviteBtn:setY(self.height - pad - btnH)
    end
    if self.cancelBtn then
        self.cancelBtn:setX(self.width - pad - btnW)
        self.cancelBtn:setY(self.height - pad - btnH)
    end
end

function MultiSafehousePlayerPicker:drawPlayerItem(y, item, alt)
    local isSelected = (self.selected == item.index)
    local itemW = (self.isVScrollBarVisible and self:isVScrollBarVisible()) and (self:getWidth() - 13) or self:getWidth()

    if isSelected then
        self:drawRect(0, y, itemW, item.height - 1, 0.4, 0.25, 0.6, 0.3)
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.8, 0.45, 1.0, 0.5)
    else
        self:drawRectBorder(0, y, itemW, item.height - 1, 0.15, 0.3, 0.3, 0.3)
    end

    local text = item.text or ""
    local fontHgt = getTextManager():getFontHeight(UIFont.Small)
    local textY = y + math.floor((item.height - fontHgt) / 2)
    self:drawText(text, 10, textY, 1, 1, 1, 1, UIFont.Small)

    return y + item.height
end

function MultiSafehousePlayerPicker:populatePlayerList()
    self.playerList:clear()

    local player = getPlayer()
    local myUsername = player and player:getUsername() or ""
    local base = self.targetBase

    local existingMembers = {}
    if base and base.members then
        for _, m in ipairs(base.members) do
            existingMembers[m] = true
        end
    end
    if base and base.owner then
        existingMembers[base.owner] = true
    end

    local count = 0
    local online = getOnlinePlayers and getOnlinePlayers() or nil
    if online then
        for i = 0, online:size() - 1 do
            local p = online:get(i)
            if p and p.getUsername then
                local u = tostring(p:getUsername())
                if u ~= "" and u ~= myUsername and not existingMembers[u] then
                    self.playerList:addItem(u, u)
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then
        self.playerList:addItem(getText("UI_MultiSafehouse_NoEligiblePlayers", "(No other players available to invite)"), nil)
        self.inviteBtn.enable = false
    else
        self.playerList.selected = 1
        self:updateInviteButton()
    end
end

function MultiSafehousePlayerPicker:updateInviteButton()
    local selectedIndex = self.playerList.selected
    local item = selectedIndex and self.playerList.items[selectedIndex]
    local target = item and item.item
    self.inviteBtn.enable = (target ~= nil and target ~= "")
end

function MultiSafehousePlayerPicker:onInvite()
    local selectedIndex = self.playerList.selected
    local item = selectedIndex and self.playerList.items[selectedIndex]
    local targetUsername = item and item.item

    if targetUsername and self.targetBase then
        local me = getPlayer()
        local myUsername = me and me:getUsername() or ""
        local bx = self.targetBase.x
        local by = self.targetBase.y

        -- 1. Native Build 42 safehouse invite
        local sh = MultiSafehouse.findClientSafehouse and MultiSafehouse.findClientSafehouse(bx, by)
        if sh and sendSafehouseInvite then
            pcall(function()
                sendSafehouseInvite(sh, myUsername, targetUsername)
            end)
        end

        -- 2. Mod server command
        if me then
            sendClientCommand(me, "MultiSafehouse", "inviteMember", {
                x = bx,
                y = by,
                targetUsername = targetUsername
            })
        end

        -- 3. Optimistic UI update: add member to targetBase.members & playerData
        self.targetBase.members = self.targetBase.members or {}
        local alreadyIn = false
        for _, m in ipairs(self.targetBase.members) do
            if m == targetUsername then
                alreadyIn = true
                break
            end
        end
        if not alreadyIn then
            table.insert(self.targetBase.members, targetUsername)
        end

        if myUsername ~= "" and MultiSafehouse.playerData and MultiSafehouse.playerData[myUsername] then
            for _, b in ipairs(MultiSafehouse.playerData[myUsername]) do
                if b.x == bx and b.y == by then
                    b.members = b.members or {}
                    local found = false
                    for _, m in ipairs(b.members) do
                        if m == targetUsername then found = true; break end
                    end
                    if not found then
                        table.insert(b.members, targetUsername)
                    end
                    break
                end
            end
        end

        if MultiSafehouse.uiWindow and MultiSafehouse.uiWindow:isVisible() then
            MultiSafehouse.uiWindow:onBaseSelected()
        end
    end

    self:close()
end

function MultiSafehousePlayerPicker:onCancel()
    self:close()
end

function MultiSafehousePlayerPicker:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

-- Global helper to summon the picker modal
MultiSafehouse = MultiSafehouse or {}
function MultiSafehouse.openPlayerPicker(baseObj)
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local w = 320
    local h = 280
    local x = (screenW - w) / 2
    local y = (screenH - h) / 2

    local picker = MultiSafehousePlayerPicker:new(x, y, w, h)
    picker.targetBase = baseObj
    picker:initialise()
    picker:addToUIManager()
    return picker
end

print("[28 Bases Later] Player picker module loaded.")
