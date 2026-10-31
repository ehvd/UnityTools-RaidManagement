local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local GroupEdit, GroupPlan = ns.GroupEdit, ns.GroupPlan

-- Groups editor (issue #26): the active encounter's layout as 8 groups of 5, and the raid members not in it. Click a
-- player, then a slot or another player (or drag) to move or swap; Save is a plan edit (Modules/PlanImport.lua) that
-- syncs, and sorts the raid when the encounter is active. The layout changes go through Modules/GroupEdit.lua.
local GroupEditor = UTRM:NewModule("GroupEditor", "AceEvent-3.0")
UTRM.GroupEditor = GroupEditor

-- Composition from the Figma wireframe (1 px = 1 UI pixel at 100% scale): the dialog of the note editor (AceGUI's
-- Frame: dialog border, header, status bar and the button beside it) with its content area 17 px in, 27 px from the
-- top and 40 px from the bottom; the groups laid out like Blizzard's raid panel, two columns of four.
local WIDTH, HEIGHT = 552, 523
local LEFT, TOP, BOTTOM = 17, 27, 40
local CONTENT_WIDTH = WIDTH - 2 * LEFT
local SLOT_WIDTH, SLOT_HEIGHT = 158, 14       -- the raid panel's name buttons
local GROUP_WIDTH, GROUP_HEIGHT = 165, 86     -- a label row and five name buttons
local GROUP_GAP = 6
local GROUPS_TOP = 58
local LIST_LEFT = 2 * GROUP_WIDTH + GROUP_GAP + 12
local LIST_WIDTH = CONTENT_WIDTH - LIST_LEFT
local LIST_HEIGHT = 4 * GROUP_HEIGHT + 3 * GROUP_GAP - 16
local SCROLLBAR = 24                          -- UIPanelScrollFrameTemplate's bar sits 6 px right of the frame, 16 wide
local BUTTON_WIDTH, BUTTON_HEIGHT = 140, 24   -- the note editor's buttons (AceGUI Button: UIPanelButtonTemplate)
local SLOTS, GROUP_SIZE = 40, 5

local FRAME_NAME = "UnityToolsRaidManagementGroupFrame"
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

-- The raid by GroupPlan.Key: { name = the raid's spelling, class = "WARRIOR" ... }, and the members in roster order
local function currentRoster()
    local byKey, members = {}, {}
    if not IsInRaid() then return byKey, members end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            local member = { name = name, class = class }
            byKey[GroupPlan.Key(name)] = member
            members[#members + 1] = member
        end
    end
    return byKey, members
end

----------------------------------------------------------------------------------------------- editing ---

-- The selection is a target: { slot = 1..40 } in the groups, { name = "Name" } in the list, or { list = true }
local function sameTarget(a, b)
    return a and b and a.slot == b.slot and a.name == b.name and a.list == b.list
end

-- The second click (or the drop) with `target`: moves, swaps, fills or empties a slot (Modules/GroupEdit.lua)
function GroupEditor:Pick(target)
    local selected, layout = self.selected, self.layout
    if not selected or sameTarget(selected, target) then
        -- First click: a player to move (an empty slot or the list itself have nothing to pick up)
        local hasPlayer = target.name or (target.slot and layout[target.slot] ~= "")
        self.selected = (not sameTarget(selected, target) and hasPlayer) and target or nil
    elseif selected.slot and target.slot then
        GroupEdit.Swap(layout, selected.slot, target.slot)
        self.selected = nil
    elseif selected.name and target.slot then
        GroupEdit.Place(layout, target.slot, selected.name)
        self.selected = nil
    elseif selected.slot and target.name then
        GroupEdit.Place(layout, selected.slot, target.name)
        self.selected = nil
    elseif selected.slot and target.list then
        GroupEdit.Remove(layout, selected.slot)
        self.selected = nil
    else
        -- From the list to the list: pick the other one instead
        self.selected = target.name and target or nil
    end
    self:Render()
end

-- Right-click on a slot: the player leaves the groups
function GroupEditor:Remove(slot)
    GroupEdit.Remove(self.layout, slot)
    self.selected = nil
    self:Render()
end

function GroupEditor:Undo()
    self.layout = GroupEdit.Copy(self.original)
    self.selected = nil
    self:Render()
end

-- Saves through PlanImport:Edit, so the change gets a revision and syncs; the active encounter's groups are sorted
function GroupEditor:Save()
    local key, layout, onlyThis = self.encounterKey, self.layout, self.onlyThis
    local savedKey, why
    local PlanImport = UTRM:GetModule("PlanImport")
    local ok, message = PlanImport:Edit(function(plan)
        savedKey, why = GroupEdit.Save(plan, key, layout, onlyThis)
        return savedKey ~= nil
    end)
    if not ok and (message or why == "encounter") then
        frame.status:SetText("|cffff4040" .. (message or L["This encounter is no longer in the raid plan."]) .. "|r")
        return
    end
    self:Hide()
    if not ok then return end   -- nothing changed

    local plan = PlanImport:GetPlan()
    local encounter = findEncounter(plan, key)
    UTRM.PlanWindow:ShowResult(true, format(L["Groups of %s saved."], encounter.label))
    if plan.active == key then
        UTRM:GetModule("RaidGroups"):Apply(plan.layouts[savedKey])
    end
end

-------------------------------------------------------------------------------------------- drag & drop ---

-- While dragging, the player's name follows the cursor
local function startDrag(button)
    if not button.target then return end
    local target = button.target
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
    for _, button in ipairs(frame.listButtons) do
        if button:IsShown() and button:IsMouseOver() then drop = button.target end
    end
    if not drop and frame.list:IsMouseOver() then drop = { list = true } end
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

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("LEFT", 4, 0)
    button.name:SetPoint("RIGHT", -60, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    button.marker = button:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    button.marker:SetPoint("RIGHT", -2, 0)
    button.marker:SetJustifyH("RIGHT")

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

local function panelButton(parent, width, height, label)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(label)
    return button
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

-- One of the two scope choices: a radio button with its text (the text is clickable too)
local function radio(parent, x, onClick)
    local button = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    button:SetSize(16, 16)
    button:SetPoint("LEFT", x, 0)
    button.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    button:SetScript("OnClick", onClick)
    return button
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    local s = UTRM.db.profile.groupEditor
    s.point, s.relativePoint, s.x, s.y = point, relativePoint, x, y
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
        GroupEditor.encounterKey = nil
    end)
    local s = UTRM.db.profile.groupEditor
    frame:SetPoint(s.point or "CENTER", UIParent, s.relativePoint or "CENTER", s.x or 0, s.y or 0)
    tinsert(UISpecialFrames, FRAME_NAME)   -- Escape closes it, as Cancel

    header(L["Edit groups"])

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", LEFT, -TOP)
    content:SetPoint("BOTTOMRIGHT", -LEFT, BOTTOM)

    -- Rows above the groups: the encounter and its layout, how to edit, and the scope
    frame.encounter = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.encounter:SetPoint("TOPLEFT")
    frame.encounter:SetSize(CONTENT_WIDTH, 18)
    frame.encounter:SetJustifyH("LEFT")

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, -18)
    hint:SetSize(CONTENT_WIDTH, 14)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Click a player, then a slot or another player, or drag. Right-click takes a player out."])

    -- Night's groups or only this fight: shown when the encounter uses the night's groups
    frame.scope = CreateFrame("Frame", nil, content)
    frame.scope:SetPoint("TOPLEFT", 0, -34)
    frame.scope:SetSize(CONTENT_WIDTH, 18)
    local scopeLabel = frame.scope:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scopeLabel:SetPoint("LEFT")
    scopeLabel:SetText(L["Change for:"])
    frame.every = radio(frame.scope, 72, function()
        GroupEditor.onlyThis = false
        GroupEditor:Render()
    end)
    frame.every.label:SetText(L["Every fight on the night's groups"])
    frame.only = radio(frame.scope, 290, function()
        GroupEditor.onlyThis = true
        GroupEditor:Render()
    end)
    -- A named layout used by other encounters too: say which change with it
    frame.shared = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.shared:SetPoint("TOPLEFT", 0, -34)
    frame.shared:SetSize(CONTENT_WIDTH, 18)
    frame.shared:SetJustifyH("LEFT")
    frame.shared:SetWordWrap(false)

    -- 8 groups × 5 slots
    frame.slots = {}
    for group = 1, SLOTS / GROUP_SIZE do
        local column, row = (group - 1) % 2, math.floor((group - 1) / 2)
        local box = CreateFrame("Frame", nil, content, "BackdropTemplate")
        box:SetSize(GROUP_WIDTH, GROUP_HEIGHT)
        box:SetPoint("TOPLEFT", column * (GROUP_WIDTH + GROUP_GAP), -(GROUPS_TOP + row * (GROUP_HEIGHT + GROUP_GAP)))
        box:SetBackdrop(PANE_BACKDROP)
        box:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        box:SetBackdropBorderColor(0.4, 0.4, 0.4)
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 4, 0)
        label:SetHeight(SLOT_HEIGHT)
        label:SetText(format(L["Group %d"], group))
        for position = 1, GROUP_SIZE do
            local button = nameButton(box, SLOT_WIDTH)
            button:SetPoint("TOPLEFT", 4, -position * SLOT_HEIGHT)
            local slot = (group - 1) * GROUP_SIZE + position
            button.target = { slot = slot }
            frame.slots[slot] = button
        end
    end

    -- The raid members not in the layout: a scroll list that is also where players are dropped to leave the groups
    frame.listLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.listLabel:SetPoint("TOPLEFT", LIST_LEFT, -GROUPS_TOP)
    frame.listLabel:SetSize(LIST_WIDTH, SLOT_HEIGHT)
    frame.listLabel:SetJustifyH("LEFT")

    frame.list = CreateFrame("Button", nil, content, "BackdropTemplate")
    frame.list:SetPoint("TOPLEFT", LIST_LEFT, -(GROUPS_TOP + 16))
    frame.list:SetSize(LIST_WIDTH, LIST_HEIGHT)
    frame.list:SetBackdrop(PANE_BACKDROP)
    frame.list:SetBackdropColor(0, 0, 0, 1)
    frame.list:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame.list:SetScript("OnClick", function() GroupEditor:Pick({ list = true }) end)

    local scroll = CreateFrame("ScrollFrame", nil, frame.list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4 - SCROLLBAR, 4)
    frame.listChild = CreateFrame("Frame", nil, scroll)
    frame.listChild:SetSize(LIST_WIDTH - 8 - SCROLLBAR, LIST_HEIGHT - 8)
    scroll:SetScrollChild(frame.listChild)
    frame.listButtons = {}

    local listHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHint:SetPoint("TOPLEFT", frame.list, "BOTTOMLEFT", 0, -2)
    listHint:SetSize(LIST_WIDTH, SLOT_HEIGHT)
    listHint:SetJustifyH("LEFT")
    listHint:SetText(L["Drop a player here to empty the slot"])

    -- Save and Undo under the groups; Cancel where the note editor has Close
    frame.save = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Save"])
    frame.save:SetPoint("BOTTOMLEFT")
    frame.save:SetScript("OnClick", function() GroupEditor:Save() end)
    frame.undo = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Undo changes"])
    frame.undo:SetPoint("LEFT", frame.save, "RIGHT")
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

-- Shows a name (or "Empty") on a button, class-coloured when the player is in the raid
local function showName(button, name, member, inRaid)
    button.marker:SetText("")
    if name == "" then
        button.name:SetText(EMPTY)
        button.name:SetTextColor(0.5, 0.5, 0.5)
        return
    end
    button.name:SetText(name)
    local color = member and RAID_CLASS_COLORS[member.class]
    if color then
        button.name:SetTextColor(color.r, color.g, color.b)
    elseif inRaid and not member then
        button.name:SetTextColor(0.5, 0.5, 0.5)
        button.marker:SetText(L["not in raid"])
    else
        button.name:SetTextColor(1, 1, 1)
    end
end

function GroupEditor:Render()
    if not frame then return end
    local plan = currentPlan()
    local encounter = findEncounter(plan, self.encounterKey)
    if not encounter then return end
    local layout, selected = self.layout, self.selected
    local byKey, members = currentRoster()
    local inRaid = IsInRaid()

    frame.encounter:SetText(encounter.label .. "  |cff999999" .. (encounter.layout == "default"
        and L["The night's groups"] or format(L["Groups: %s"], encounter.layout)) .. "|r")

    -- The scope choice, or which other encounters share the layout
    local others = {}
    for _, other in ipairs(plan.encounters) do
        if other.layout == encounter.layout and other.key ~= encounter.key then others[#others + 1] = other.label end
    end
    frame.scope:SetShown(encounter.layout == "default")
    frame.every:SetChecked(not self.onlyThis)
    frame.only:SetChecked(self.onlyThis)
    frame.only.label:SetText(format(L["Only %s"], encounter.label))
    frame.every:SetHitRectInsets(0, -frame.every.label:GetStringWidth() - 2, 0, 0)
    frame.only:SetHitRectInsets(0, -frame.only.label:GetStringWidth() - 2, 0, 0)
    frame.shared:SetShown(encounter.layout ~= "default" and #others > 0)
    frame.shared:SetText(format(L["Also changes the groups of: %s"], table.concat(others, ", ")))

    -- The groups; planned players who are not in the raid are marked
    local missing = {}
    for slot = 1, SLOTS do
        local button, name = frame.slots[slot], layout[slot]
        local member = name ~= "" and byKey[GroupPlan.Key(name)]
        showName(button, name, member, inRaid)
        button.selected:SetShown(selected ~= nil and selected.slot == slot)
        if inRaid and name ~= "" and not member then missing[#missing + 1] = name end
    end

    -- The raid members who are not in the layout, by name
    local unplaced = {}
    for _, member in ipairs(members) do
        if not GroupEdit.Find(layout, member.name) then unplaced[#unplaced + 1] = member end
    end
    table.sort(unplaced, function(a, b) return a.name < b.name end)
    frame.listLabel:SetText(format(L["In the raid, not in groups (%d)"], #unplaced))
    local listWidth = frame.listChild:GetWidth()
    for i, member in ipairs(unplaced) do
        local button = frame.listButtons[i]
        if not button then
            button = nameButton(frame.listChild, listWidth)
            button:SetPoint("TOPLEFT", 0, -(i - 1) * SLOT_HEIGHT)
            frame.listButtons[i] = button
        end
        button.target = { name = member.name }
        showName(button, member.name, member, inRaid)
        button.selected:SetShown(selected ~= nil and selected.name == member.name)
        button:Show()
    end
    for i = #unplaced + 1, #frame.listButtons do
        frame.listButtons[i]:Hide()
    end
    frame.listChild:SetHeight(math.max(1, #unplaced * SLOT_HEIGHT))

    local changed = not GroupEdit.Equal(layout, self.original)
    frame.save:SetEnabled(changed)
    frame.undo:SetEnabled(changed)
    if #missing > 0 then
        frame.status:SetText(format(L["Planned but not in the raid: %s"], table.concat(missing, ", ")))
    elseif not inRaid then
        frame.status:SetText(L["Not in a raid: no class colours, and the list is empty."])
    else
        frame.status:SetText("")
    end
end

-- Opens the editor on the active encounter's groups
function GroupEditor:Open()
    local plan = currentPlan()
    local encounter = plan and findEncounter(plan, plan.active)
    if not encounter then
        UTRM:Print(L["Choose the encounter first."])
        return
    end
    if not frame then create() end
    self.encounterKey = encounter.key
    self.original = GroupEdit.Copy(plan.layouts[encounter.layout])
    self.layout = GroupEdit.Copy(self.original)
    self.selected, self.onlyThis = nil, false
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
    -- Somebody else's plan or edit arrived: close when the groups being edited changed under the editor
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function()
        if not self:IsShown() then return end
        local plan = currentPlan()
        local encounter = findEncounter(plan, self.encounterKey)
        if not encounter or not GroupEdit.Equal(plan.layouts[encounter.layout], self.original) then
            self:Hide()
            UTRM:Print(L["The raid plan changed, so the groups editor was closed."])
        end
    end)
    self:RegisterMessage("UTRM_PLAN_CLEARED", function() self:Hide() end)
end
