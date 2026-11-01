local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local GroupEdit, GroupPlan = ns.GroupEdit, ns.GroupPlan

-- Groups editor (issue #26): one layout of the plan as 8 groups of 5, next to the raid members and the bench who are
-- not in it. The dropdown picks the night's groups or an encounter: an encounter on the night's groups shows them
-- read-only until it gets its own groups (Create override); its own groups can be edited or deleted. Click a player,
-- then a slot, another player or a list (or drag) to move, swap or take out. Every change is a plan edit
-- (Modules/PlanImport.lua) that syncs, and saving the active encounter's groups sorts the raid. The layout changes go
-- through Modules/GroupEdit.lua.
local GroupEditor = UTRM:NewModule("GroupEditor", "AceEvent-3.0")
UTRM.GroupEditor = GroupEditor

-- Layout (1 px = 1 UI pixel at 100% scale): the note editor's dialog (AceGUI's Frame: dialog border, header, status
-- bar with the button beside it), its content 17 px in and 27 px from the top. Under the dropdown row an info line
-- (two lines) and the hint, then the groups like Blizzard's raid panel (two columns of four, the label above each
-- box), the two lists on the right, and Save / Undo under the groups.
local LEFT, TOP = 17, 27
local SLOT_WIDTH, SLOT_HEIGHT = 158, 14       -- the raid panel's name buttons
local BOX_PAD = 5                             -- the tooltip border is 4 px wide
local BOX_WIDTH, BOX_HEIGHT = SLOT_WIDTH + 2 * BOX_PAD, 5 * SLOT_HEIGHT + 2 * BOX_PAD
local LABEL = 16                              -- a label row above a box or pane
local GROUP_BLOCK = LABEL + BOX_HEIGHT
local ROW_GAP, COLUMN_GAP = 6, 8
local DROPDOWN, DROPDOWN_WIDTH = 26, 260      -- the plan window's encounter box (AceGUI's Dropdown height)
local INFO_TOP, HINT_TOP, GROUPS_TOP = 32, 60, 78
local GROUPS_WIDTH = 2 * BOX_WIDTH + COLUMN_GAP
local GROUPS_HEIGHT = 4 * GROUP_BLOCK + 3 * ROW_GAP
local LIST_LEFT, LIST_WIDTH = GROUPS_WIDTH + 16, 220
local LIST_GAP = 8
local PANE_HEIGHT = (GROUPS_HEIGHT - 2 * LABEL - LIST_GAP) / 2
local PANE_INSET = 8                          -- keeps the scroll bar's arrows off the pane's border
local SCROLLBAR = 22                          -- UIPanelScrollFrameTemplate's bar sits 6 px right of the frame, 16 wide
local BUTTON_WIDTH, BUTTON_HEIGHT = 140, 24   -- the note editor's buttons (AceGUI Button: UIPanelButtonTemplate)
local BUTTONS_TOP = GROUPS_TOP + GROUPS_HEIGHT + 10
local STATUS = 15 + 24                        -- the status bar's bottom inset and height
local CONTENT_WIDTH = LIST_LEFT + LIST_WIDTH
local WIDTH = CONTENT_WIDTH + 2 * LEFT
local HEIGHT = TOP + BUTTONS_TOP + BUTTON_HEIGHT + 8 + STATUS
local SLOTS, GROUP_SIZE = 40, 5

local FRAME_NAME = "UnityToolsRaidManagementGroupFrame"
local DELETE_POPUP = "UNITYTOOLSRAIDMANAGEMENT_DELETE_OVERRIDE"
local DISCARD_POPUP = "UNITYTOOLSRAIDMANAGEMENT_DISCARD_GROUPS"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local PANE_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

local function findEncounter(plan, key)
    for _, encounter in ipairs(plan and plan.encounters or {}) do
        if encounter.key == key then return encounter end
    end
    return nil
end

local function labels(encounters)
    local out = {}
    for i, encounter in ipairs(encounters) do out[i] = encounter.label end
    return table.concat(out, ", ")
end

-- The raid by GroupPlan.Key: { name = the raid's spelling, class = "WARRIOR" ... }, and the members in roster order.
-- The classes seen are kept (db.global.classes) to colour the names outside a raid too.
local function currentRoster()
    local byKey, members = {}, {}
    if not IsInRaid() then return byKey, members end
    local classes = UTRM.db.global.classes
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            local member = { name = name, class = class }
            byKey[GroupPlan.Key(name)] = member
            members[#members + 1] = member
            if class then classes[GroupPlan.Key(name)] = class end
        end
    end
    return byKey, members
end

-- A name's class: the raid's, else the plan's people (protocol 2), else the last one seen in a raid
local function classFinder(plan, byKey)
    local people = {}
    for name, person in pairs(plan.people or {}) do
        if person.class then people[GroupPlan.Key(name)] = person.class end
    end
    local classes = UTRM.db.global.classes
    return function(name)
        local key = GroupPlan.Key(name)
        return byKey[key] and byKey[key].class or people[key] or classes[key]
    end
end

-- Everybody the plan names: its people and the players of all its layouts (candidates for the bench)
local function plannedNames(plan)
    local names = {}
    for name in pairs(plan.people or {}) do names[#names + 1] = name end
    for _, layout in pairs(plan.layouts) do
        for slot = 1, SLOTS do names[#names + 1] = layout[slot] or "" end
    end
    return names
end

----------------------------------------------------------------------------------------------- editing ---

-- The selection is a target: { slot = 1..40 } in the groups, { name = "Name" } in a list, or { list = "raid" /
-- "bench" } (a list itself)
local function sameTarget(a, b)
    return a and b and a.slot == b.slot and a.name == b.name and a.list == b.list
end

function GroupEditor:IsChanged()
    return self.layout ~= nil and not GroupEdit.Equal(self.layout, self.original)
end

-- The second click (or the drop) with `target`: moves, swaps, fills a slot, or takes a player out to the lists
function GroupEditor:Pick(target)
    if self.readOnly then return end
    local selected, layout = self.selected, self.layout
    self.message = nil
    if not selected or sameTarget(selected, target) then
        -- First click: a player to move (an empty slot or a list itself have nothing to pick up)
        local hasPlayer = target.name or (target.slot and layout[target.slot] ~= "")
        self.selected = (not sameTarget(selected, target) and hasPlayer) and target or nil
    elseif selected.slot and target.slot then
        GroupEdit.Swap(layout, selected.slot, target.slot)
        self.selected = nil
    elseif selected.name and target.slot then
        GroupEdit.Place(layout, target.slot, selected.name)
        self.selected = nil
    elseif selected.slot then
        -- Onto a list or one of its names: out of the groups (into the raid list, or the bench outside the raid)
        GroupEdit.Remove(layout, selected.slot)
        self.selected = nil
    else
        -- From a list to a list: pick the other one instead
        self.selected = target.name and target or nil
    end
    self:Render()
end

-- Right-click on a slot: the player leaves the groups
function GroupEditor:Remove(slot)
    if self.readOnly then return end
    GroupEdit.Remove(self.layout, slot)
    self.selected, self.message = nil, nil
    self:Render()
end

function GroupEditor:Undo()
    self.layout = GroupEdit.Copy(self.original)
    self.selected, self.message = nil, nil
    self:Render()
end

-- Sorts the raid when the active encounter is on the layout `layoutKey`
local function sortIfActive(plan, layoutKey)
    local active = findEncounter(plan, plan.active)
    if active and active.layout == layoutKey then
        UTRM:GetModule("RaidGroups"):Apply(plan.layouts[layoutKey])
    end
end

-- One plan edit (PlanImport:Edit, so it gets a revision and syncs): `change(plan)` returns a result or nil and why.
-- Returns the result, or nil after showing why in the status bar (nothing when it was unchanged).
local function edit(change, gone)
    local result, why
    local ok, message = UTRM:GetModule("PlanImport"):Edit(function(plan)
        result, why = change(plan)
        return result ~= nil
    end)
    if ok then return result end
    if message or (why and why ~= "unchanged") then
        GroupEditor.message = "|cffff4040" .. (message or gone) .. "|r"
        GroupEditor:Render()
    end
    return nil
end

-- Saves the groups into the layout shown; every encounter on it changes
function GroupEditor:Save()
    if self.readOnly then return end
    local layoutKey, layout, encounterKey = self.layoutKey, self.layout, self.encounterKey
    local saved = edit(function(plan) return GroupEdit.Save(plan, layoutKey, layout) end,
        L["These groups are no longer in the raid plan."])
    if not saved then return end
    local plan = currentPlan()
    local encounter = findEncounter(plan, encounterKey)
    self.original = GroupEdit.Copy(layout)
    self.selected = nil
    self.message = encounter and format(L["Groups of %s saved."], encounter.label) or L["The night's groups saved."]
    self:Render()
    sortIfActive(plan, saved)
end

-- The encounter shown gets its own groups, a copy of the night's groups, and they can be edited
function GroupEditor:CreateOverride()
    local key = self.encounterKey
    local created = edit(function(plan) return GroupEdit.CreateOverride(plan, key) end,
        L["This encounter is no longer in the raid plan."])
    if not created then return end
    self:Load(key)
    self.message = format(L["%s has its own groups now."], findEncounter(currentPlan(), key).label)
    self:Render()
end

-- The encounter shown goes back to the night's groups (after the confirmation)
function GroupEditor:DeleteOverride()
    local key = self.encounterKey
    local deleted = edit(function(plan) return GroupEdit.DeleteOverride(plan, key) end,
        L["This encounter is no longer in the raid plan."])
    if not deleted then return end
    local plan = currentPlan()
    self:Load(key)
    self.message = format(L["%s uses the night's groups again."], findEncounter(plan, key).label)
    self:Render()
    if plan.active == key then sortIfActive(plan, "default") end
end

StaticPopupDialogs[DELETE_POPUP] = {
    button1 = YES,
    button2 = NO,
    OnAccept = function() GroupEditor:DeleteOverride() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs[DISCARD_POPUP] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        GroupEditor:Load(GroupEditor.pending)
        GroupEditor:Render()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function GroupEditor:ConfirmDelete()
    local plan = currentPlan()
    local encounter = findEncounter(plan, self.encounterKey)
    if not encounter or encounter.layout == "default" then return end
    local others = GroupEdit.UsersOf(plan, encounter.layout, encounter.key)
    if #others > 0 then
        StaticPopupDialogs[DELETE_POPUP].text = L["Use the night's groups for %s again? Its groups stay for: %s"]
        StaticPopup_Show(DELETE_POPUP, encounter.label, labels(others))
    else
        StaticPopupDialogs[DELETE_POPUP].text = L["Use the night's groups for %s again? Its own groups (%s) are deleted."]
        StaticPopup_Show(DELETE_POPUP, encounter.label, encounter.layout)
    end
end

-- The dropdown's choice: nil for the night's groups, or an encounter key. Unsaved changes are confirmed first.
function GroupEditor:Choose(encounterKey)
    if encounterKey == self.encounterKey then return end
    if self:IsChanged() then
        self.pending = encounterKey
        StaticPopupDialogs[DISCARD_POPUP].text = L["Discard your changes to the groups?"]
        StaticPopup_Show(DISCARD_POPUP)
        return
    end
    self:Load(encounterKey)
    self:Render()
end

-------------------------------------------------------------------------------------------- drag & drop ---

-- While dragging, the player's name follows the cursor
local function startDrag(button)
    local target = button.target
    if GroupEditor.readOnly or not target then return end
    if target.slot and GroupEditor.layout[target.slot] == "" then return end
    GroupEditor.selected = target
    GroupEditor:Render()
    frame.ghost.text:SetText(button.name:GetText())
    frame.ghost:Show()
end

-- Dropped: the slot, list name or list under the cursor is the second click
local function stopDrag()
    if not frame.ghost:IsShown() then return end
    frame.ghost:Hide()
    local drop
    for _, button in ipairs(frame.slots) do
        if button:IsMouseOver() then drop = button.target end
    end
    for _, pane in ipairs(frame.panes) do
        if pane:IsMouseOver() then
            drop = { list = pane.list }
            for _, button in ipairs(pane.buttons) do
                if button:IsShown() and button:IsMouseOver() then drop = button.target end
            end
        end
    end
    if drop and not sameTarget(drop, GroupEditor.selected) then
        GroupEditor:Pick(drop)
    else
        GroupEditor.selected = nil
        GroupEditor:Render()
    end
end

local function followCursor(ghost)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    ghost:ClearAllPoints()
    ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
end

------------------------------------------------------------------------------------------------ the frame ---

-- A name button like the raid panel's: class-coloured name, a marker on the right, highlight on hover, yellow when
-- picked. Left-click picks or drops, right-click on a slot takes the player out.
local function nameButton(parent, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, SLOT_HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT, "ADD")

    button.selected = button:CreateTexture(nil, "BACKGROUND")
    button.selected:SetTexture(HIGHLIGHT)
    button.selected:SetBlendMode("ADD")
    button.selected:SetVertexColor(1, 0.82, 0)
    button.selected:SetAllPoints()

    button.marker = button:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    button.marker:SetPoint("RIGHT", -2, 0)
    button.marker:SetJustifyH("RIGHT")

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("LEFT", 4, 0)
    button.name:SetPoint("RIGHT", button.marker, "LEFT", -4, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if self.target.slot then GroupEditor:Remove(self.target.slot) end
            return
        end
        GroupEditor:Pick(self.target)
    end)
    button:SetScript("OnDragStart", startDrag)
    button:SetScript("OnDragStop", stopDrag)
    return button
end

-- A panel button at least `width` wide, wider when its text needs it (the translations are longer)
local function fitText(button, width)
    button:SetWidth(math.max(width, button:GetFontString():GetStringWidth() + 24))
end

local function panelButton(parent, width, height, label)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(label)
    fitText(button, width)
    return button
end

local function pane(parent, x, y, width, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", x, -y)
    box:SetSize(width, height)
    box:SetBackdrop(PANE_BACKDROP)
    box:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4)
    return box
end

local function label(parent, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", x + 4, -y)
    text:SetSize(width - 4, LABEL)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    return text
end

-- The note editor's title: Blizzard's dialog header, as wide as the title
local function header(text)
    local titlebg = frame:CreateTexture(nil, "OVERLAY")
    titlebg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titlebg:SetTexCoord(0.31, 0.67, 0, 0.63)
    titlebg:SetPoint("TOP", 0, 12)
    titlebg:SetHeight(40)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", titlebg, "TOP", 0, -14)
    title:SetText(text)
    titlebg:SetWidth(title:GetStringWidth() + 10)

    local left = frame:CreateTexture(nil, "OVERLAY")
    left:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", titlebg, "LEFT")
    left:SetSize(30, 40)

    local right = frame:CreateTexture(nil, "OVERLAY")
    right:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", titlebg, "RIGHT")
    right:SetSize(30, 40)
end

-- The encounter box, set up like the plan window's (UI/PlanWindow.lua): Blizzard's UIDropDownMenuTemplate art around
-- `holder` (it reaches 15 px left and 17 px right of it), with our MenuUtil menu instead of Blizzard's list
local function dropdown(holder, onClick)
    local box = CreateFrame("Frame", FRAME_NAME .. "DropDown", holder, "UIDropDownMenuTemplate")
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", -15, 0)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 17, 0)
    box:SetScript("OnHide", nil)

    local name = box:GetName()
    local left, middle, right = _G[name .. "Left"], _G[name .. "Middle"], _G[name .. "Right"]
    middle:ClearAllPoints()
    right:ClearAllPoints()
    middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
    middle:SetPoint("RIGHT", right, "LEFT", 0, 0)
    right:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 17)

    local text = _G[name .. "Text"]
    text:ClearAllPoints()
    text:SetPoint("RIGHT", right, "RIGHT", -43, 2)
    text:SetPoint("LEFT", left, "LEFT", 25, 2)
    text:SetJustifyH("LEFT")

    holder.text = text
    local button = _G[name .. "Button"]
    button:SetScript("OnMouseDown", nil)
    local cover = CreateFrame("Button", nil, holder)
    cover:SetAllPoints(holder)
    for _, clickable in ipairs({ cover, button }) do
        clickable:SetScript("OnClick", onClick)
    end
end

local function openMenu(owner)
    local plan = currentPlan()
    if not plan then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(plan.event.title)
        root:CreateRadio(L["Night's groups"],
            function() return GroupEditor.encounterKey == nil end,
            function()
                GroupEditor:Choose(nil)
                return MenuResponse and MenuResponse.Close
            end)
        root:CreateDivider()
        for i, encounter in ipairs(plan.encounters) do
            local text = format("%d. %s", i, encounter.label)
            if encounter.layout ~= "default" then text = text .. "  |cff999999" .. encounter.layout .. "|r" end
            root:CreateRadio(text,
                function() return GroupEditor.encounterKey == encounter.key end,
                function()
                    GroupEditor:Choose(encounter.key)
                    return MenuResponse and MenuResponse.Close
                end)
        end
    end)
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    local s = UTRM.db.profile.groupEditor
    s.point, s.relativePoint, s.x, s.y = point, relativePoint, x, y
end

-- One of the two lists: a label, and a pane with a scroll list that is also a drop target
local function listPane(content, list, y)
    local box = pane(content, LIST_LEFT, y + LABEL, LIST_WIDTH, PANE_HEIGHT)
    box.label = label(content, LIST_LEFT, y, LIST_WIDTH)
    box.list = list
    box.buttons = {}

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", BOX_PAD, -PANE_INSET)
    scroll:SetPoint("BOTTOMRIGHT", -(PANE_INSET + SCROLLBAR), PANE_INSET)
    -- The scroll child is a button too, so a click anywhere on the list drops the picked player there
    box.child = CreateFrame("Button", nil, scroll)
    box.child:SetSize(LIST_WIDTH - BOX_PAD - PANE_INSET - SCROLLBAR, PANE_HEIGHT - 2 * PANE_INSET)
    box.child:SetScript("OnClick", function() GroupEditor:Pick({ list = list }) end)
    scroll:SetScrollChild(box.child)
    box.visible = PANE_HEIGHT - 2 * PANE_INSET

    box.empty = box.child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.empty:SetPoint("TOPLEFT", 4, -4)
    box.empty:SetPoint("TOPRIGHT", -4, -4)
    box.empty:SetJustifyH("LEFT")
    return box
end

local function create()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetScript("OnHide", function()
        frame.ghost:Hide()
        GroupEditor.layout = nil
    end)
    local s = UTRM.db.profile.groupEditor
    frame:SetPoint(s.point or "CENTER", UIParent, s.relativePoint or "CENTER", s.x or 0, s.y or 0)
    tinsert(UISpecialFrames, FRAME_NAME)   -- Escape closes it, as Cancel

    header(L["Edit groups"])

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", LEFT, -TOP)
    content:SetSize(CONTENT_WIDTH, HEIGHT - TOP - STATUS)

    -- The dropdown (the night's groups or an encounter), and Create / Delete override beside it
    frame.choice = CreateFrame("Frame", nil, content)
    frame.choice:SetPoint("TOPLEFT")
    frame.choice:SetSize(DROPDOWN_WIDTH, DROPDOWN)
    dropdown(frame.choice, function() openMenu(frame.choice) end)

    frame.override = panelButton(content, BUTTON_WIDTH, 22, L["Create override"])
    frame.override:SetPoint("LEFT", frame.choice, "RIGHT", 24, 0)
    frame.override:SetScript("OnClick", function()
        if GroupEditor.readOnly then GroupEditor:CreateOverride() else GroupEditor:ConfirmDelete() end
    end)

    -- What the groups shown are and who uses them (two lines), and how to edit
    frame.info = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.info:SetPoint("TOPLEFT", 0, -INFO_TOP)
    frame.info:SetSize(CONTENT_WIDTH, 24)
    frame.info:SetJustifyH("LEFT")
    frame.info:SetJustifyV("TOP")
    frame.info:SetMaxLines(2)

    frame.hint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", 0, -HINT_TOP)
    frame.hint:SetSize(CONTENT_WIDTH, 12)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(false)
    frame.hint:SetText(L["Click a player, then a slot, a player or a list, or drag. Right-click takes a player out."])

    -- 8 groups × 5 slots, each box with its label above it
    frame.slots, frame.boxes = {}, {}
    for group = 1, SLOTS / GROUP_SIZE do
        local column, row = (group - 1) % 2, math.floor((group - 1) / 2)
        local x, y = column * (BOX_WIDTH + COLUMN_GAP), GROUPS_TOP + row * (GROUP_BLOCK + ROW_GAP)
        label(content, x, y, BOX_WIDTH):SetText(format(L["Group %d"], group))
        local box = pane(content, x, y + LABEL, BOX_WIDTH, BOX_HEIGHT)
        frame.boxes[group] = box
        for position = 1, GROUP_SIZE do
            local button = nameButton(box, SLOT_WIDTH)
            button:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD - (position - 1) * SLOT_HEIGHT)
            local slot = (group - 1) * GROUP_SIZE + position
            button.target = { slot = slot }
            frame.slots[slot] = button
        end
    end

    -- The raid members not in the groups, and the bench: both are where players are dropped to leave the groups
    frame.raid = listPane(content, "raid", GROUPS_TOP)
    frame.bench = listPane(content, "bench", GROUPS_TOP + LABEL + PANE_HEIGHT + LIST_GAP)
    frame.panes = { frame.raid, frame.bench }

    -- Save and Undo under the groups; Cancel where the note editor has Close
    frame.save = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Save"])
    frame.save:SetPoint("TOPLEFT", 0, -BUTTONS_TOP)
    frame.save:SetScript("OnClick", function() GroupEditor:Save() end)
    frame.undo = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Undo changes"])
    frame.undo:SetPoint("LEFT", frame.save, "RIGHT", 4, 0)
    frame.undo:SetScript("OnClick", function() GroupEditor:Undo() end)

    local cancel = panelButton(frame, 100, 20, CANCEL)
    cancel:SetPoint("BOTTOMRIGHT", -27, 17)
    cancel:SetScript("OnClick", function() GroupEditor:Hide() end)

    local statusbg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusbg:SetPoint("BOTTOMLEFT", 15, 15)
    statusbg:SetPoint("BOTTOMRIGHT", -132, 15)
    statusbg:SetHeight(24)
    statusbg:SetBackdrop(PANE_BACKDROP)
    statusbg:SetBackdropColor(0.1, 0.1, 0.1)
    statusbg:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame.status = statusbg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.status:SetPoint("TOPLEFT", 7, -2)
    frame.status:SetPoint("BOTTOMRIGHT", -7, 2)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    -- The name under the cursor while dragging
    frame.ghost = CreateFrame("Frame", nil, UIParent)
    frame.ghost:SetFrameStrata("TOOLTIP")
    frame.ghost:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
    frame.ghost.text = frame.ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.ghost.text:SetPoint("LEFT")
    frame.ghost:SetScript("OnUpdate", followCursor)
    frame.ghost:Hide()
end

-- Shows a name (or "Empty") on a button in its class colour; `absent` marks a planned player who is not in the raid
local function showName(button, name, class, absent)
    button.marker:SetText(absent and L["not in raid"] or "")
    if name == "" then
        button.name:SetText(EMPTY)
        button.name:SetTextColor(0.5, 0.5, 0.5)
        return
    end
    button.name:SetText(name)
    local color = class and RAID_CLASS_COLORS[class]
    if color then
        button.name:SetTextColor(color.r, color.g, color.b)
    else
        button.name:SetTextColor(1, 1, 1)
    end
end

-- Fills a list pane with `names`; `empty` is shown when there are none
local function fillList(box, names, classOf, empty)
    local selected = GroupEditor.selected
    local width = box.child:GetWidth()
    for i, name in ipairs(names) do
        local button = box.buttons[i]
        if not button then
            button = nameButton(box.child, width)
            button:SetPoint("TOPLEFT", 0, -(i - 1) * SLOT_HEIGHT)
            box.buttons[i] = button
        end
        button.target = { name = name }
        showName(button, name, classOf(name), false)
        button.selected:SetShown(selected ~= nil and selected.name == name)
        button:EnableMouse(not GroupEditor.readOnly)
        button:Show()
    end
    for i = #names + 1, #box.buttons do
        box.buttons[i]:Hide()
    end
    box.child:SetHeight(math.max(box.visible, #names * SLOT_HEIGHT))
    box.child:EnableMouse(not GroupEditor.readOnly)
    box.empty:SetText(empty)
    box.empty:SetShown(#names == 0)
    box:SetAlpha(GroupEditor.readOnly and 0.5 or 1)
end

-- What the groups shown are, and who else uses them
local function infoText(plan, encounter, layoutKey)
    if not encounter then
        local users = GroupEdit.UsersOf(plan, "default")
        return #users > 0 and format(L["The night's groups, used by: %s"], labels(users))
            or L["The night's groups: no encounter uses them."]
    end
    if layoutKey == "default" then
        return format(L["%s uses the night's groups. Create an override to give this fight its own groups."],
            encounter.label)
    end
    local text = format(L["%s has its own groups (%s)."], encounter.label, layoutKey)
    local others = GroupEdit.UsersOf(plan, layoutKey, encounter.key)
    if #others > 0 then text = text .. " " .. format(L["Also used by: %s"], labels(others)) end
    return text
end

function GroupEditor:Render()
    if not frame or not self.layout then return end
    local plan = currentPlan()
    if not plan then return end
    local encounter = findEncounter(plan, self.encounterKey)
    local layout, selected, readOnly = self.layout, self.selected, self.readOnly
    local byKey, members = currentRoster()
    local inRaid = IsInRaid()
    local classOf = classFinder(plan, byKey)

    -- The dropdown's text, the override button and the info line
    if encounter then
        local index
        for i, candidate in ipairs(plan.encounters) do
            if candidate == encounter then index = i end
        end
        frame.choice.text:SetText(format("|cff999999%d/%d|r  %s", index, #plan.encounters, encounter.label))
    else
        frame.choice.text:SetText(L["Night's groups"])
    end
    frame.override:SetShown(encounter ~= nil)
    frame.override:SetText(readOnly and L["Create override"] or L["Delete override"])
    fitText(frame.override, BUTTON_WIDTH)
    frame.info:SetText(infoText(plan, encounter, self.layoutKey))

    -- The groups; planned players who are not in the raid are marked
    local missing = {}
    for slot = 1, SLOTS do
        local button, name = frame.slots[slot], layout[slot]
        local absent = inRaid and name ~= "" and not byKey[GroupPlan.Key(name)]
        showName(button, name, name ~= "" and classOf(name), absent)
        button.selected:SetShown(selected ~= nil and selected.slot == slot)
        button:EnableMouse(not readOnly)
        if absent then missing[#missing + 1] = name end
    end
    for _, box in ipairs(frame.boxes) do
        box:SetAlpha(readOnly and 0.5 or 1)
    end

    -- The raid members who are not in the groups, by name; then the bench
    local unplaced = {}
    for _, member in ipairs(members) do
        if not GroupEdit.Find(layout, member.name) then unplaced[#unplaced + 1] = member.name end
    end
    table.sort(unplaced, function(a, b) return a:lower() < b:lower() end)
    frame.raid.label:SetText(format(L["In the raid, not in groups (%d)"], #unplaced))
    fillList(frame.raid, unplaced, classOf,
        inRaid and L["Drop a player here to take them out of the groups."] or L["Not in a raid"])

    local bench = GroupEdit.Bench(plannedNames(plan), layout, function(name) return byKey[GroupPlan.Key(name)] end)
    frame.bench.label:SetText(format(L["Bench (%d)"], #bench))
    fillList(frame.bench, bench, classOf, L["Drop a player here to take them out of the groups."])

    local changed = self:IsChanged()
    frame.save:SetEnabled(changed)
    frame.undo:SetEnabled(changed)
    if self.message then
        frame.status:SetText(self.message)
    elseif #missing > 0 then
        frame.status:SetText(format(L["Planned but not in the raid: %s"], table.concat(missing, ", ")))
    else
        frame.status:SetText("")
    end
end

-- Shows the night's groups (`encounterKey` nil, or an encounter no longer in the plan) or an encounter's groups
function GroupEditor:Load(encounterKey)
    local plan = currentPlan()
    local encounter = findEncounter(plan, encounterKey)
    self.encounterKey = encounter and encounter.key
    self.layoutKey = encounter and encounter.layout or "default"
    self.readOnly = encounter ~= nil and encounter.layout == "default"
    self.original = GroupEdit.Copy(plan.layouts[self.layoutKey])
    self.layout = GroupEdit.Copy(self.original)
    self.selected, self.message, self.pending = nil, nil, nil
end

-- Opens the editor on the active encounter's groups (the night's groups when no encounter is active)
function GroupEditor:Open()
    local plan = currentPlan()
    if not plan then
        UTRM:Print(L["No raid plan imported yet."])
        return
    end
    if not frame then create() end
    self:Load(plan.active)
    frame:Show()
    self:Render()
end

function GroupEditor:Hide()
    if frame then frame:Hide() end
end

function GroupEditor:IsShown()
    return frame ~= nil and frame:IsShown()
end

function GroupEditor:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if self:IsShown() then self:Render() end
    end)
    -- Somebody else's plan or edit arrived: show it, but close when it changed the groups being edited under unsaved
    -- changes
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function()
        if not self:IsShown() then return end
        local plan = currentPlan()
        local encounter = findEncounter(plan, self.encounterKey)
        local layoutKey = encounter and encounter.layout or "default"
        local same = layoutKey == self.layoutKey and (self.encounterKey == nil or encounter ~= nil)
            and GroupEdit.Equal(plan.layouts[layoutKey], self.original)
        if same then
            self:Render()
        elseif self:IsChanged() then
            self:Hide()
            UTRM:Print(L["The raid plan changed, so the groups editor was closed."])
        else
            self:Load(self.encounterKey)
            self:Render()
        end
    end)
    self:RegisterMessage("UTRM_PLAN_CLEARED", function() self:Hide() end)
end
