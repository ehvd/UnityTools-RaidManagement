local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local GroupEdit, GroupPlan = ns.GroupEdit, ns.GroupPlan

-- Groups editor (issue #26), the Groups section of the Raid Plan window (UI/RaidPlanWindow.lua): one layout of the
-- plan as 8 groups of 5, next to the raid members and the bench who are not in it. Layouts are shared (issue #55):
-- the dropdown picks a layout (Default, the night's groups, or a named one such as "MC Default") or an encounter (it
-- never changes the active one). A named layout can be deleted (its encounters go back to Default); an encounter
-- picks the layout it uses (Groups) or gets a new one copied from it (New override), and editing its groups edits
-- that layout for every encounter on it. Click a player, then a slot, another player or a list (or drag) to move,
-- swap or take out. Players can be added to the plan (on the bench) or taken out of it (× on the bench, issue #52).
-- All of it is one draft of every layout (Save / Undo changes); Save is one plan edit (Modules/PlanImport.lua) that
-- syncs, and sorts the raid when the active encounter's groups changed. The layout changes go through
-- Modules/GroupEdit.lua.
local GroupEditor = UTRM:NewModule("GroupEditor", "AceEvent-3.0")
UTRM.GroupEditor = GroupEditor

-- Layout (1 px = 1 UI pixel at 100% scale), inside the Raid Plan window's section: the dropdown row (for an
-- encounter also Groups and New override), then the groups like Blizzard's raid panel (two columns of four, the label
-- above each box), the two lists on the right with Add a player under them, and Save / Undo under the groups; last,
-- under a divider, Export raid. The window's status bar shows the messages.
local SLOT_WIDTH, SLOT_HEIGHT = 158, 14       -- the raid panel's name buttons
local BOX_PAD = 5                             -- the tooltip border is 4 px wide
local BOX_WIDTH, BOX_HEIGHT = SLOT_WIDTH + 2 * BOX_PAD, 5 * SLOT_HEIGHT + 2 * BOX_PAD
local LABEL = 16                              -- a label row above a box or pane
local GROUP_BLOCK = LABEL + BOX_HEIGHT
local ROW_GAP, COLUMN_GAP = 6, 8
local DROPDOWN, DROPDOWN_WIDTH = 26, 260      -- the plan window's encounter box (AceGUI's Dropdown height)
local GROUPS_TOP = DROPDOWN + 6
local LAYOUT_LEFT, NEW_WIDTH = 344, 84        -- an encounter's Groups box (its art starts 15 px left) and New override
local GROUPS_WIDTH = 2 * BOX_WIDTH + COLUMN_GAP
local GROUPS_HEIGHT = 4 * GROUP_BLOCK + 3 * ROW_GAP
local LIST_LEFT, LIST_WIDTH = GROUPS_WIDTH + 16, 220
local LIST_GAP = 8
local BUTTON_WIDTH, BUTTON_HEIGHT = 140, 24   -- the note editor's buttons (AceGUI Button: UIPanelButtonTemplate)
local BUTTONS_TOP = GROUPS_TOP + GROUPS_HEIGHT + 10
-- Add a player (issue #52), under the lists: a label, the name box (InputBoxTemplate, 20 high, its art reaches 5 px
-- left of it), then the class box and Add on Save's row
local INPUT_HEIGHT, INPUT_ART = 20, 6
local ADD_WIDTH = 70
local NAME_TOP = BUTTONS_TOP - 4 - INPUT_HEIGHT
local ADD_LABEL_TOP = NAME_TOP - LABEL
local PANE_HEIGHT = (ADD_LABEL_TOP - LIST_GAP - GROUPS_TOP - 2 * LABEL - LIST_GAP) / 2
local PANE_INSET = 8                          -- keeps the scroll bar's arrows off the pane's border
local SCROLLBAR = 22                          -- UIPanelScrollFrameTemplate's bar sits 6 px right of the frame, 16 wide
local REMOVE_SIZE = 18                        -- the close button's art on a bench row (the red square is ~11 px)
local CLOSE_ART = "Interface\\Buttons\\UI-Panel-MinimizeButton-"
local CONTENT_WIDTH = LIST_LEFT + LIST_WIDTH
-- Export raid (issue #47) on its own row under everything else, a divider above it
local DIVIDER_TOP, DIVIDER_HEIGHT = BUTTONS_TOP + BUTTON_HEIGHT + 8, 8
local EXPORT_TOP = DIVIDER_TOP + DIVIDER_HEIGHT + 4
local CONTENT_HEIGHT = EXPORT_TOP + BUTTON_HEIGHT
GroupEditor.WIDTH, GroupEditor.HEIGHT = CONTENT_WIDTH, CONTENT_HEIGHT   -- what the Raid Plan window must fit
local SLOTS, GROUP_SIZE = 40, 5

local FRAME_NAME = "UnityToolsRaidManagementGroupFrame"
local DELETE_POPUP = "UNITYTOOLSRAIDMANAGEMENT_DELETE_OVERRIDE"
local NEW_POPUP = "UNITYTOOLSRAIDMANAGEMENT_NEW_OVERRIDE"
local REMOVE_POPUP = "UNITYTOOLSRAIDMANAGEMENT_REMOVE_PLAYER"
local GREY, OVERRIDE = "|cff999999", "|cff40d8e8"    -- Default and the named layouts in the menus
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

-- A layout's name as shown: "Default" for the night's groups
local function layoutName(key)
    return key == "default" and L["Default"] or key
end

-- A layout's name in its menu colour: Default grey, a named layout (an override) highlighted
local function coloredLayout(key)
    return (key == "default" and GREY or OVERRIDE) .. layoutName(key) .. "|r"
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

-- A name's class: the raid's, else the players added in the draft and the plan's people (protocol 2), else the last
-- one seen in a raid
local function classFinder(plan, byKey, added)
    local people = {}
    for name, person in pairs(plan.people or {}) do
        if person.class then people[GroupPlan.Key(name)] = person.class end
    end
    for _, person in ipairs(added) do people[GroupPlan.Key(person.name)] = person.class end
    local classes = UTRM.db.global.classes
    return function(name)
        local key = GroupPlan.Key(name)
        return byKey[key] and byKey[key].class or people[key] or classes[key]
    end
end

local function keySet(names)
    local set = {}
    for _, name in ipairs(names) do set[GroupPlan.Key(name)] = true end
    return set
end

-- Everybody the plan names: its people and the players of all the draft's layouts (candidates for the bench), but
-- the players `removed` in the draft, and with the ones `added` in it
local function plannedNames(plan, draft, added, removed)
    local names, gone = {}, keySet(removed)
    local function keep(name)
        if name ~= "" and not gone[GroupPlan.Key(name)] then names[#names + 1] = name end
    end
    for name in pairs(plan.people or {}) do keep(name) end
    for _, layout in pairs(draft.layouts) do
        for slot = 1, SLOTS do keep(layout[slot] or "") end
    end
    for _, person in ipairs(added) do names[#names + 1] = person.name end
    return names
end

-- A class name in its class colour
local function className(class)
    local text = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
    local color = RAID_CLASS_COLORS[class]
    if not color then return text end
    local function byte(value) return math.floor(value * 255 + 0.5) end
    return format("|cff%02x%02x%02x%s|r", byte(color.r), byte(color.g), byte(color.b), text)
end

----------------------------------------------------------------------------------------------- editing ---

-- The selection is a target: { slot = 1..40 } in the groups, { name = "Name" } in a list, or { list = "raid" /
-- "bench" } (a list itself)
local function sameTarget(a, b)
    return a and b and a.slot == b.slot and a.name == b.name and a.list == b.list
end

-- The draft: every layout and which one each encounter uses (GroupEdit.NewDraft), and the players added to the plan
-- ({ name, class }) and removed from it (names). `base` is the plan's as loaded.
function GroupEditor:IsChanged()
    return self.draft ~= nil
        and (not GroupEdit.SameDraft(self.draft, self.base) or #self.added > 0 or #self.removed > 0)
end

-- What is shown: `view` is { layout = key } or { encounter = key }; `layoutKey` and `layout` are the draft layout
-- shown (an encounter's is the one it uses), edited in place
function GroupEditor:Point()
    local draft, view = self.draft, self.view
    if view.encounter then
        self.layoutKey = GroupEdit.LayoutOf(draft, view.encounter)
    else
        self.layoutKey = draft.layouts[view.layout] and view.layout or "default"
        view.layout = self.layoutKey
    end
    self.layout = draft.layouts[self.layoutKey]
end

-- The second click (or the drop) with `target`: moves, swaps, fills a slot, or takes a player out to the lists
function GroupEditor:Pick(target)
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
    GroupEdit.Remove(self.layout, slot)
    self.selected, self.message = nil, nil
    self:Render()
end

-- Add: the name typed and the class chosen join the plan's people in the draft, on the bench
function GroupEditor:AddPlayer(text)
    local name = GroupEdit.CleanName(text)
    local plan = currentPlan()
    local byKey = currentRoster()
    local gone, added = keySet(self.removed), {}
    for _, person in ipairs(self.added) do added[GroupPlan.Key(person.name)] = true end
    local why = GroupEdit.CheckNewName(name, function(candidate)
        local key = GroupPlan.Key(candidate)
        return byKey[key] or added[key] or (not gone[key] and GroupEdit.InPlan(plan, candidate))
    end)
    if not why and not self.addClass then why = "class" end
    if why then
        local messages = {
            empty = L["Type the player's name first."],
            taken = format(L["%s is already in the raid plan or the raid."], name),
            class = L["Choose the player's class first."],
        }
        self.message = "|cffff4040" .. messages[why] .. "|r"
        self:Render()
        return false
    end
    self.added[#self.added + 1] = { name = name, class = self.addClass }
    self.selected = nil
    self.message = format(L["%s is on the bench. Save to keep them in the plan."], name)
    self:Render()
    return true
end

-- The player leaves the plan in the draft: a player added in the draft is just forgotten
function GroupEditor:RemovePlayer(name)
    local key, wasAdded = GroupPlan.Key(name), false
    for i, person in ipairs(self.added) do
        if GroupPlan.Key(person.name) == key then
            table.remove(self.added, i)
            wasAdded = true
            break
        end
    end
    if not wasAdded then self.removed[#self.removed + 1] = name end
    self.selected = nil
    self.message = wasAdded and format(L["%s is no longer added."], name)
        or format(L["%s is out of the raid plan. Save to keep it so."], name)
    self:Render()
end

StaticPopupDialogs[REMOVE_POPUP] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, name) GroupEditor:RemovePlayer(name) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- × on a bench row: asks first when the draft uses the player elsewhere (other groups, assignments)
function GroupEditor:ConfirmRemovePlayer(name)
    local uses = GroupEdit.UsesOf(currentPlan(), self.draft, name, self.layoutKey)
    local lines = {}
    if uses.night then lines[#lines + 1] = L["In Default, which no encounter uses."] end
    if #uses.groups > 0 then lines[#lines + 1] = format(L["In the groups of: %s"], labels(uses.groups)) end
    if #uses.holds > 0 then
        lines[#lines + 1] = format(L["Assigned in: %s (the assignments stay; change them in Assignments)"],
            labels(uses.holds))
    end
    if #lines == 0 then
        self:RemovePlayer(name)
        return
    end
    StaticPopupDialogs[REMOVE_POPUP].text = L["Take %s out of the raid plan?"] .. "\n\n%s"
    StaticPopup_Show(REMOVE_POPUP, name, table.concat(lines, "\n"), name)
end

function GroupEditor:Undo()
    self.draft = GroupEdit.CopyDraft(self.base)
    self.added, self.removed = {}, {}
    self.selected, self.message = nil, nil
    self:Point()
    self:Render()
end

-- The groups of the plan's active encounter (nil when none is active)
local function activeGroups(plan)
    local active = findEncounter(plan, plan.active)
    return active and (plan.layouts[active.layout] or plan.layouts.default)
end

-- Saves the whole draft in one plan edit (PlanImport:Edit, so it gets a revision and syncs); sorts the raid when the
-- active encounter's groups changed
function GroupEditor:Save()
    local draft, added, removed = self.draft, self.added, self.removed
    local before = activeGroups(currentPlan())
    before = before and GroupEdit.Copy(before)
    local ok, message = UTRM:GetModule("PlanImport"):Edit(function(plan)
        return GroupEdit.SaveDraft(plan, draft, added, removed) ~= nil
    end)
    if not ok then
        if message then
            self.message = "|cffff4040" .. message .. "|r"
            self:Render()
        end
        return
    end
    local plan = currentPlan()
    self:Load(self.view)
    self.message = L["Groups saved."]
    self:Render()
    local after = activeGroups(plan)
    if after and not (before and GroupEdit.Equal(before, after)) then
        UTRM:GetModule("RaidGroups"):Apply(after)
    end
end

-- Groups (an encounter's layout): the encounter shown uses the layout `layoutKey` in the draft
function GroupEditor:UseLayout(layoutKey)
    local encounter = findEncounter(currentPlan(), self.view.encounter)
    if not encounter or not GroupEdit.UseLayout(self.draft, encounter.key, layoutKey) then return end
    self:Point()
    self.selected = nil
    self.message = format(L["%s uses %s now. Save to keep it so."], encounter.label, layoutName(layoutKey))
    self:Render()
end

-- New override: a new layout `name` for the encounter shown, a copy of the one it uses. Returns whether it was made.
function GroupEditor:NewLayout(name)
    local encounter = findEncounter(currentPlan(), self.view.encounter)
    local key, why = GroupEdit.NewLayout(self.draft, encounter and encounter.key, name)
    if not key then
        local messages = {
            empty = L["Type a name for the groups first."],
            taken = format(L["Groups named %s exist already."], (name or ""):match("^%s*(.-)%s*$")),
            encounter = L["This encounter is no longer in the raid plan."],
        }
        self.message = "|cffff4040" .. messages[why] .. "|r"
        self:Render()
        return false
    end
    self:Point()
    self.selected = nil
    self.message = format(L["%s has new groups: %s. Save to keep them."], encounter.label, key)
    self:Render()
    return true
end

-- Delete override (after the confirmation): the layout shown is deleted in the draft, its encounters use Default
function GroupEditor:DeleteLayout()
    local key = self.view.layout
    local moved = key and GroupEdit.DeleteLayout(self.draft, key)
    if not moved then return end
    self.view = { layout = "default" }
    self:Point()
    self.selected = nil
    self.message = format(L["%s deleted: %d encounters go back to Default. Save to keep it so."], key, moved)
    self:Render()
end

local function editBoxOf(dialog)
    return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function button1Of(dialog)
    return dialog.button1 or (dialog.GetButton1 and dialog:GetButton1())
end

-- Create is only clickable with a name no layout has
local function updateCreate(dialog)
    local button, box = button1Of(dialog), editBoxOf(dialog)
    if button and box then
        button:SetEnabled(GroupEdit.CheckLayoutName(GroupEditor.draft, box:GetText()) == nil)
    end
end

StaticPopupDialogs[NEW_POPUP] = {
    text = "",
    button1 = L["Create"],
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 200,
    maxLetters = 48,
    OnShow = function(dialog, name)
        local box = editBoxOf(dialog)
        box:SetText(name or dialog.data or "")
        box:HighlightText()
        box:SetFocus()
        updateCreate(dialog)
    end,
    OnAccept = function(dialog) GroupEditor:NewLayout(editBoxOf(dialog):GetText()) end,
    EditBoxOnTextChanged = function(box) updateCreate(box:GetParent()) end,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        if GroupEdit.CheckLayoutName(GroupEditor.draft, box:GetText()) == nil then
            GroupEditor:NewLayout(box:GetText())
            dialog:Hide()
        end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- New override: asks the name, starting with the encounter's (made unique)
function GroupEditor:ConfirmNewLayout()
    local encounter = findEncounter(currentPlan(), self.view.encounter)
    if not encounter then return end
    StaticPopupDialogs[NEW_POPUP].text = L["New groups for %s, starting as a copy of %s."] .. "\n\n" .. L["Name:"]
    StaticPopup_Show(NEW_POPUP, encounter.label, layoutName(self.layoutKey),
        GroupEdit.NewKey(self.draft.layouts, encounter.label))
end

StaticPopupDialogs[DELETE_POPUP] = {
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function() GroupEditor:DeleteLayout() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Delete override: names the encounters that go back to Default
function GroupEditor:ConfirmDelete()
    local key = self.view.layout
    if not key or key == "default" then return end
    local users = GroupEdit.UsersOf(currentPlan(), self.draft, key)
    local text = L["Delete the groups %s?"] .. "\n\n"
    if #users > 0 then
        StaticPopupDialogs[DELETE_POPUP].text = text .. L["These encounters go back to Default: %s"]
        StaticPopup_Show(DELETE_POPUP, key, labels(users))
    else
        StaticPopupDialogs[DELETE_POPUP].text = text .. L["No encounter uses them."]
        StaticPopup_Show(DELETE_POPUP, key)
    end
end

-- The dropdown's choice: { layout = key } or { encounter = key }. The draft covers every layout, so nothing is lost.
function GroupEditor:Choose(view)
    self.view = view
    self.selected, self.message = nil, nil
    self:Point()
    self:Render()
end

-------------------------------------------------------------------------------------------- drag & drop ---

-- While dragging, the player's name follows the cursor
local function startDrag(button)
    local target = button.target
    if not target then return end
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

-- A dropdown box, set up like the plan window's (UI/PlanWindow.lua): Blizzard's UIDropDownMenuTemplate art around
-- `holder` (it reaches 15 px left and 17 px right of it), with our MenuUtil menu instead of Blizzard's list
local function dropdown(holder, suffix, onClick)
    local box = CreateFrame("Frame", FRAME_NAME .. suffix, holder, "UIDropDownMenuTemplate")
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
    holder.clickables = { cover, button }
    for _, clickable in ipairs(holder.clickables) do
        clickable:SetScript("OnClick", onClick)
    end
end

-- The class of the player to add: the nine classes in their colours
local function openClassMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, class in ipairs(GroupEdit.CLASSES) do
            root:CreateRadio(className(class),
                function() return GroupEditor.addClass == class end,
                function()
                    GroupEditor.addClass = class
                    owner.text:SetText(className(class))
                    return MenuResponse and MenuResponse.Close
                end)
        end
    end)
end

-- A menu entry with `right` at its right edge (the entries' widths are the widest one's, so these line up). Without
-- AttachFontString the text just follows the name.
local function withRight(description, right)
    description:AddInitializer(function(button)
        if not button.AttachFontString then
            button.fontString:SetText(button.fontString:GetText() .. "  " .. right)
            return
        end
        local text = button:AttachFontString()
        text:ClearAllPoints()
        text:SetPoint("RIGHT")
        text:SetJustifyH("RIGHT")
        text:SetText(right)
        return button.fontString:GetUnboundedStringWidth() + 16 + text:GetUnboundedStringWidth() + 24, 20
    end)
end

local function encounterCount(count)
    return count == 1 and L["1 encounter"] or format(L["%d encounters"], count)
end

-- The section's dropdown: Default and the named layouts (how many encounters use them on the right), then the
-- encounters (the layout each uses on the right)
local function openMenu(owner)
    local plan = currentPlan()
    local draft = GroupEditor.draft
    if not plan or not draft then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(plan.event.title)
        local keys = GroupEdit.LayoutKeys(draft)
        table.insert(keys, 1, "default")
        for _, key in ipairs(keys) do
            local count = #GroupEdit.UsersOf(plan, draft, key)
            local radio = root:CreateRadio(layoutName(key),
                function() return GroupEditor.view.layout == key end,
                function()
                    GroupEditor:Choose({ layout = key })
                    return MenuResponse and MenuResponse.Close
                end)
            withRight(radio, GREY .. encounterCount(count) .. "|r")
        end
        root:CreateDivider()
        for i, encounter in ipairs(plan.encounters) do
            local radio = root:CreateRadio(format("%d. %s", i, encounter.label),
                function() return GroupEditor.view.encounter == encounter.key end,
                function()
                    GroupEditor:Choose({ encounter = encounter.key })
                    return MenuResponse and MenuResponse.Close
                end)
            withRight(radio, coloredLayout(GroupEdit.LayoutOf(draft, encounter.key)))
        end
    end)
end

-- Groups (an encounter shown): the layout it uses, Default or a named one
local function openLayoutMenu(owner)
    local encounter = findEncounter(currentPlan(), GroupEditor.view.encounter)
    local draft = GroupEditor.draft
    if not encounter or not draft then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(format(L["Groups of %s"], encounter.label))
        local keys = GroupEdit.LayoutKeys(draft)
        table.insert(keys, 1, "default")
        for _, key in ipairs(keys) do
            root:CreateRadio(layoutName(key),
                function() return GroupEditor.layoutKey == key end,
                function()
                    GroupEditor:UseLayout(key)
                    return MenuResponse and MenuResponse.Close
                end)
        end
    end)
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
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    frame:SetScript("OnHide", function() frame.ghost:Hide() end)
    local content = frame

    -- The dropdown (a layout or an encounter); for a named layout Delete override beside it, for an encounter the
    -- layout it uses (Groups) and New override
    frame.choice = CreateFrame("Frame", nil, content)
    frame.choice:SetPoint("TOPLEFT")
    frame.choice:SetSize(DROPDOWN_WIDTH, DROPDOWN)
    dropdown(frame.choice, "DropDown", function() openMenu(frame.choice) end)

    frame.delete = panelButton(content, BUTTON_WIDTH, 22, L["Delete override"])
    frame.delete:SetPoint("LEFT", frame.choice, "RIGHT", 24, 0)
    frame.delete:SetScript("OnClick", function() GroupEditor:ConfirmDelete() end)

    frame.new = panelButton(content, NEW_WIDTH, 22, L["New override"])
    frame.new:SetPoint("RIGHT", content, "TOPLEFT", CONTENT_WIDTH, -DROPDOWN / 2)
    frame.new:SetScript("OnClick", function() GroupEditor:ConfirmNewLayout() end)

    frame.groupsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.groupsLabel:SetPoint("LEFT", frame.choice, "RIGHT", 24, 0)
    frame.groupsLabel:SetText(L["Groups"])

    -- The Groups box fills the row up to New override (its art reaches 17 px right of the holder)
    frame.layoutChoice = CreateFrame("Frame", nil, content)
    frame.layoutChoice:SetPoint("TOPLEFT", LAYOUT_LEFT, 0)
    frame.layoutChoice:SetSize(CONTENT_WIDTH - frame.new:GetWidth() - 4 - 17 - LAYOUT_LEFT, DROPDOWN)
    dropdown(frame.layoutChoice, "Layout", function() openLayoutMenu(frame.layoutChoice) end)

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

    -- Add a player: the name, then the class and Add on Save's row
    label(content, LIST_LEFT, ADD_LABEL_TOP, LIST_WIDTH):SetText(L["Add a player"])
    frame.addName = CreateFrame("EditBox", FRAME_NAME .. "AddName", content, "InputBoxTemplate")
    frame.addName:SetPoint("TOPLEFT", LIST_LEFT + INPUT_ART, -NAME_TOP)
    frame.addName:SetSize(LIST_WIDTH - INPUT_ART, INPUT_HEIGHT)
    frame.addName:SetAutoFocus(false)
    frame.addName:SetMaxLetters(48)
    frame.addName:SetScript("OnEnterPressed", function(box)
        if GroupEditor:AddPlayer(box:GetText()) then box:SetText("") end
    end)
    frame.addName:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

    frame.add = panelButton(content, ADD_WIDTH, 22, L["Add"])
    frame.add:SetPoint("RIGHT", content, "TOPLEFT", LIST_LEFT + LIST_WIDTH, -(BUTTONS_TOP + BUTTON_HEIGHT / 2))
    frame.add:SetScript("OnClick", function()
        if GroupEditor:AddPlayer(frame.addName:GetText()) then frame.addName:SetText("") end
        frame.addName:ClearFocus()
    end)

    -- The class box fills the row up to Add (its art reaches 17 px right of the holder)
    frame.addClass = CreateFrame("Frame", nil, content)
    frame.addClass:SetPoint("LEFT", content, "TOPLEFT", LIST_LEFT, -(BUTTONS_TOP + BUTTON_HEIGHT / 2))
    frame.addClass:SetSize(LIST_WIDTH - 17 - 4 - frame.add:GetWidth(), DROPDOWN)
    dropdown(frame.addClass, "AddClass", function() openClassMenu(frame.addClass) end)

    -- Save and Undo under the groups
    frame.save = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Save"])
    frame.save:SetPoint("TOPLEFT", 0, -BUTTONS_TOP)
    frame.save:SetScript("OnClick", function() GroupEditor:Save() end)
    frame.undo = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Undo changes"])
    frame.undo:SetPoint("LEFT", frame.save, "RIGHT", 4, 0)
    frame.undo:SetScript("OnClick", function() GroupEditor:Undo() end)

    -- Below everything, under a divider (AceGUI's Heading line): Export raid (issue #47, UI/RosterDialog.lua)
    local divider = content:CreateTexture(nil, "BACKGROUND")
    divider:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    divider:SetTexCoord(0.81, 0.94, 0.5, 1)
    divider:SetPoint("TOPLEFT", 0, -DIVIDER_TOP)
    divider:SetSize(CONTENT_WIDTH, DIVIDER_HEIGHT)
    frame.export = panelButton(content, BUTTON_WIDTH, BUTTON_HEIGHT, L["Export raid"])
    frame.export:SetPoint("TOPLEFT", 0, -EXPORT_TOP)
    frame.export:SetScript("OnClick", function() UTRM.RosterDialog:Open() end)

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

-- The × on a bench row (the close button's art): takes the player out of the plan
local function removeButton(button)
    local remove = CreateFrame("Button", nil, button)
    remove:SetSize(REMOVE_SIZE, REMOVE_SIZE)
    remove:SetPoint("RIGHT", 2, 0)
    remove:SetNormalTexture(CLOSE_ART .. "Up")
    remove:SetPushedTexture(CLOSE_ART .. "Down")
    remove:SetHighlightTexture(CLOSE_ART .. "Highlight", "ADD")
    remove:SetScript("OnClick", function() GroupEditor:ConfirmRemovePlayer(button.target.name) end)
    remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Take out of the raid plan"])
        GameTooltip:Show()
    end)
    remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button.marker:ClearAllPoints()
    button.marker:SetPoint("RIGHT", remove, "LEFT", 0, 0)
    button.remove = remove
end

-- Fills a list pane with `names`; `empty` is shown when there are none. The bench's rows have a ×.
local function fillList(box, names, classOf, empty)
    local selected = GroupEditor.selected
    local width = box.child:GetWidth()
    for i, name in ipairs(names) do
        local button = box.buttons[i]
        if not button then
            button = nameButton(box.child, width)
            button:SetPoint("TOPLEFT", 0, -(i - 1) * SLOT_HEIGHT)
            if box.list == "bench" then removeButton(button) end
            box.buttons[i] = button
        end
        button.target = { name = name }
        showName(button, name, classOf(name), false)
        button.selected:SetShown(selected ~= nil and selected.name == name)
        button:Show()
    end
    for i = #names + 1, #box.buttons do
        box.buttons[i]:Hide()
    end
    box.child:SetHeight(math.max(box.visible, #names * SLOT_HEIGHT))
    box.empty:SetText(empty)
    box.empty:SetShown(#names == 0)
end

function GroupEditor:Render()
    if not frame or not self.draft then return end
    local plan = currentPlan()
    if not plan then return end
    local encounter = findEncounter(plan, self.view.encounter)
    local layout, selected = self.layout, self.selected
    local byKey, members = currentRoster()
    local inRaid = IsInRaid()
    local classOf = classFinder(plan, byKey, self.added)

    -- The top row: a layout (Delete override when it is a named one), or an encounter (Groups, New override)
    if encounter then
        local index
        for i, candidate in ipairs(plan.encounters) do
            if candidate == encounter then index = i end
        end
        frame.choice.text:SetText(format("%s%d/%d|r  %s", GREY, index, #plan.encounters, encounter.label))
        frame.layoutChoice.text:SetText(coloredLayout(self.layoutKey))
    else
        frame.choice.text:SetText(layoutName(self.layoutKey))
    end
    frame.delete:SetShown(not encounter and self.layoutKey ~= "default")
    frame.groupsLabel:SetShown(encounter ~= nil)
    frame.layoutChoice:SetShown(encounter ~= nil)
    frame.new:SetShown(encounter ~= nil)

    -- The groups; planned players who are not in the raid are marked
    local missing = {}
    for slot = 1, SLOTS do
        local button, name = frame.slots[slot], layout[slot]
        local absent = inRaid and name ~= "" and not byKey[GroupPlan.Key(name)]
        showName(button, name, name ~= "" and classOf(name), absent)
        button.selected:SetShown(selected ~= nil and selected.slot == slot)
        if absent then missing[#missing + 1] = name end
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

    local bench = GroupEdit.Bench(plannedNames(plan, self.draft, self.added, self.removed), layout,
        function(name) return byKey[GroupPlan.Key(name)] end)
    frame.bench.label:SetText(format(L["Bench (%d)"], #bench))
    fillList(frame.bench, bench, classOf, L["Drop a player here to take them out of the groups."])

    frame.addClass.text:SetText(self.addClass and className(self.addClass) or L["Class"])

    local changed = self:IsChanged()
    frame.save:SetEnabled(changed)
    frame.undo:SetEnabled(changed)
    if self.message then
        self.host:SetStatus(self.message)
    elseif #missing > 0 then
        self.host:SetStatus(format(L["Planned but not in the raid: %s"], table.concat(missing, ", ")))
    else
        self.host:SetStatus("")
    end
    self.host:UpdateTree()
end

-- A new draft from the plan, showing `view` ({ layout = key } or { encounter = key }); an encounter no longer in the
-- plan shows Default
function GroupEditor:Load(view)
    local plan = currentPlan()
    if view.encounter and not findEncounter(plan, view.encounter) then view = { layout = "default" } end
    self.view = view
    self.base = GroupEdit.NewDraft(plan)
    self.draft = GroupEdit.CopyDraft(self.base)
    self.added, self.removed = {}, {}
    self.selected, self.message = nil, nil
    self:Point()
end

-- Shows the section in the Raid Plan window (`host`, UI/RaidPlanWindow.lua), on what it showed last, else the
-- active encounter (Default when no encounter is active)
function GroupEditor:Attach(host)
    local plan = currentPlan()
    if not plan then return end
    if not frame then create() end
    self.host = host
    local parent = host.content
    frame:SetParent(parent)
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT")
    if not self.draft then
        self:Load(plan.active and { encounter = plan.active } or { layout = "default" })
    elseif self.view.encounter and not findEncounter(plan, self.view.encounter) then
        self.view = { layout = "default" }
        self:Point()
    end
    frame:Show()
    self:Render()
end

function GroupEditor:Detach()
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
end

function GroupEditor:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Unsaved changes are dropped (the Raid Plan window asked first)
function GroupEditor:Discard()
    if self.draft then self:Undo() end
end

function GroupEditor:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if self:IsShown() then self:Render() end
    end)
    -- Somebody else's plan or edit arrived: show it; when it changed the layouts, the draft starts again from it
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function()
        if not self.draft then return end
        local plan = currentPlan()
        if GroupEdit.SameDraft(GroupEdit.NewDraft(plan), self.base) then
            if self.view.encounter and not findEncounter(plan, self.view.encounter) then
                self.view = { layout = "default" }
                self:Point()
            end
            if self:IsShown() then self:Render() end
            return
        end
        local dropped = self:IsChanged()
        self:Load(self.view)
        if dropped then
            self.message = "|cffffa040" .. L["The raid plan changed: your changes to these groups were dropped."] .. "|r"
        end
        if self:IsShown() then self:Render() end
    end)
    self:RegisterMessage("UTRM_PLAN_CLEARED", function() self.draft = nil end)
end
