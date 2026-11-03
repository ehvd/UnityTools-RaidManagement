local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")
local Assignments = ns.Assignments

-- The Assignments section of the Raid Plan window (UI/RaidPlanWindow.lua): who fills an encounter's assignments
-- (export protocol 2). The encounter dropdown picks the encounter to change (it never changes the active one), then
-- one row per job with a dropdown of its candidates, a preview of the rebuilt note, Save. Saving is a plan edit
-- (PlanImport:Edit), so it syncs like one, and the note goes to Method Raid Tools when the encounter is the active one.
-- Default (issue #59), above the encounters in the dropdown, changes a job on every encounter that follows the
-- default (Modules/Assignments.lua); on an encounter, a job with other holders is an override, its key in cyan.
-- Layout from the Figma wireframe "Assignments", every control at its own size.
local AssignmentsWindow = UTRM:NewModule("AssignmentsWindow", "AceEvent-3.0")
UTRM.AssignmentsWindow = AssignmentsWindow

-- The jobs list and the preview share the section's height (the Raid Plan window's, UTRM.GroupEditor.HEIGHT):
-- the list gets what its rows need, the preview the rest, each at least its minimum (FitHeight)
local ROW_HEIGHT = 29                   -- a job's row: a 26 tall dropdown and the Flow layout's 3 px gap
local MIN_ROWS_HEIGHT = 3 * ROW_HEIGHT
local MIN_PREVIEW_HEIGHT = 150
local LABEL_WIDTH = 110
local DROPDOWN_WIDTH = 400              -- wide enough that the next label starts a new row
local ENCOUNTER_WIDTH = 260             -- the other sections' encounter box (UI/RaidPlanWindow.lua)
local MENU_HEIGHT = 400                 -- a menu of a whole raid scrolls past this
local GREY = "|cff808080"
local OVERRIDE = "|cff40d8e8"           -- the Groups section's colour for a layout of its own
local DEFAULT_TEXT = DEFAULT or "Default"

local ROLES = { tank = L["Tank"], healer = L["Healer"], melee = L["Melee"], ranged = L["Ranged"] }

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

local function findEncounter(plan, key)
    for i, encounter in ipairs(plan and plan.encounters or {}) do
        if encounter.key == key then return encounter, i end
    end
    return nil
end

-- The raid's members by GroupPlan.Key, or nil outside a raid (then nobody is marked as missing)
local function raidMembers()
    if not IsInRaid() then return nil end
    local members = {}
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then members[ns.GroupPlan.Key(name)] = true end
    end
    return members
end

------------------------------------------------------------------------------------------------- texts ---

function AssignmentsWindow:InRaid(name)
    return not self.raid or self.raid[ns.GroupPlan.Key(name)] == true
end

-- A holder on a row: the name in its class colour, "(not in raid)" after it
function AssignmentsWindow:HolderText(name)
    local text = ns.NoteTemplate.ColouredName(name, self.people)
    if not self:InRaid(name) then
        text = text .. GREY .. " (" .. L["not in raid"] .. ")|r"
    end
    return text
end

-- A candidate in a menu: the name in its class colour, then its role (and "not in raid") in grey
function AssignmentsWindow:CandidateText(name)
    local person = self.people and self.people[name]
    local role = type(person) == "table" and person.role
    local details = {}
    if role then details[#details + 1] = ROLES[role] or role end
    if not self:InRaid(name) then details[#details + 1] = L["not in raid"] end
    local text = ns.NoteTemplate.ColouredName(name, self.people)
    if #details > 0 then
        text = text .. "  " .. GREY .. table.concat(details, " · ") .. "|r"
    end
    return text
end

local function holdersText(window, holders)
    if #holders == 0 then
        return GREY .. "(" .. L["nobody"] .. ")|r"
    end
    local names = {}
    for i, name in ipairs(holders) do names[i] = window:HolderText(name) end
    return table.concat(names, ", ")
end

function AssignmentsWindow:JobText(job)
    return holdersText(self, job.holders)
end

-- A row's label: the job's tokens, cyan when it is an override of the default
function AssignmentsWindow:KeyText(job)
    local text = table.concat(job.tokens, " · ")
    if not self.showDefault and Assignments.IsOverride(job, self.defaults) then
        return OVERRIDE .. text .. "|r"
    end
    return text
end

local function overridesText(count)
    return count == 1 and L["1 override"] or format(L["%d overrides"], count)
end

------------------------------------------------------------------------------------------------- menus ---

-- A job's menu: its candidates in alphabetical order. Several holders: check boxes, the menu stays open;
-- one holder: radio buttons and Nobody last, the menu closes. An AceGUI Frame is FULLSCREEN_DIALOG,
-- level 100, top level) in other addons, above Blizzard's menus: the menu goes to the TOOLTIP strata so it shows
-- over any window.
function AssignmentsWindow:OpenMenu(job, owner)
    local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(table.concat(job.tokens, " · "))
        local function holds(name) return Assignments.Holds(job, name) end
        for _, name in ipairs(job.candidates) do
            if job.multi then
                root:CreateCheckbox(self:CandidateText(name), holds, function()
                    Assignments.Toggle(job, name)
                    self:Update()
                    return MenuResponse and MenuResponse.Refresh
                end)
            else
                root:CreateRadio(self:CandidateText(name), holds, function()
                    Assignments.Set(job, name)
                    self:Update()
                    return MenuResponse and MenuResponse.Close
                end)
            end
        end
        if not job.multi then
            root:CreateRadio(L["Nobody"], function() return #job.holders == 0 end, function()
                Assignments.Set(job, nil)
                self:Update()
                return MenuResponse and MenuResponse.Close
            end)
        elseif #job.candidates == 0 then
            root:CreateTitle(L["Nobody can fill this."])
        end
        -- An override goes back to the default (greyed out when the default's players cannot fill it here)
        if not self.showDefault and Assignments.IsOverride(job, self.defaults) then
            root:CreateDivider()
            local default = self.defaults[job.key]
            local button = root:CreateButton(format(L["Use default: %s"], holdersText(self, default)), function()
                Assignments.UseDefault(job, self.defaults)
                self:Update()
                return MenuResponse and MenuResponse.Close
            end)
            if button.SetEnabled and not Assignments.CanUse(job, default) then button:SetEnabled(false) end
        end
    end)
    if menu then menu:SetFrameStrata("TOOLTIP") end
end

-- A menu entry with `right` at its right edge (the entries are as wide as the widest, so these line up), as the
-- Groups section's encounter menu shows a layout of its own. Without AttachFontString it follows the text.
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

-- The encounter text of the dropdown: "3. Lucifron", the active one marked
local function encounterText(plan, i, encounter)
    local text = format("%d. %s", i, encounter.label)
    if encounter.key == plan.active then text = text .. "  " .. GREY .. L["(active)"] .. "|r" end
    return text
end

-- How many overrides an encounter has: the shown one's as they are now, the others' as saved
function AssignmentsWindow:OverridesOf(encounter)
    if not Assignments.TakesPart(encounter) then return 0 end
    if not self.showDefault and self.jobs and encounter.key == self.key then
        return Assignments.Overrides(self.jobs, self.defaults)
    end
    return Assignments.Overrides(Assignments.Jobs(encounter), self.defaults)
end

-- The Encounter dropdown's menu: Default, a divider, the encounters with their overrides on the right in cyan.
-- With unsaved changes, choosing another asks first.
function AssignmentsWindow:OpenEncounterMenu(owner)
    local plan = currentPlan()
    if not plan then return end
    local function choose(showDefault, key)
        local function go()
            self.showDefault, self.key = showDefault, key or self.key
            self:Build()
        end
        if self:IsChanged() then
            self.host:ConfirmDiscard(L["Assignments"], go)
        else
            go()
        end
        return MenuResponse and MenuResponse.Close
    end
    local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(plan.event.title)
        root:CreateRadio(DEFAULT_TEXT, function() return self.showDefault end, function() return choose(true) end)
        root:CreateDivider()
        for i, encounter in ipairs(plan.encounters) do
            local radio = root:CreateRadio(encounterText(plan, i, encounter),
                function() return not self.showDefault and self.key == encounter.key end,
                function() return choose(false, encounter.key) end)
            local count = self:OverridesOf(encounter)
            if count > 0 then withRight(radio, OVERRIDE .. overridesText(count) .. "|r") end
        end
        if root.SetScrollMode then root:SetScrollMode(MENU_HEIGHT) end
    end)
    if menu then menu:SetFrameStrata("TOOLTIP") end
end

-- The people to preview the note as: the raid when in one, else the plan's people; { names (alphabetical),
-- classes (name → class token) }
local function viewers(people)
    local names, classes = {}, {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                names[#names + 1] = name
                classes[name] = class
            end
        end
    else
        for name, person in pairs(people or {}) do
            names[#names + 1] = name
            classes[name] = type(person) == "table" and person.class or nil
        end
    end
    return { names = Assignments.SortNames(names), classes = classes }
end

-- The game's class names (lower case) to class tokens, for {c:Krieger} in a German note
local classNames
local function gameClassNames()
    if classNames then return classNames end
    classNames = {}
    for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, name in pairs(list) do classNames[name:lower()] = token end
    end
    return classNames
end

-- The viewer ns.NoteView takes for the person the preview is shown as (nil: everyone): their class, their group
-- in this encounter's planned layout (not the raid's groups now) and the classes among the people
function AssignmentsWindow:Viewer()
    local name = self.viewer
    if not (name and self.encounter) then return nil end
    local present = {}
    for _, class in pairs(self.viewers.classes) do present[class] = true end
    local plan = currentPlan()
    local layout = plan and plan.layouts and (plan.layouts[self.encounter.layout] or plan.layouts.default)
    return {
        name = name, class = self.viewers.classes[name], classes = present, classNames = gameClassNames(),
        group = ns.NoteView.GroupIn(layout, name, ns.GroupPlan.Key),
    }
end

function AssignmentsWindow:ViewerText(name)
    if not name then return L["Everyone"] end
    return ns.NoteTemplate.ColouredName(name, { [name] = { class = self.viewers.classes[name] } })
end

-- The menu of people to preview as: Everyone (only the text outside the blocks for some), then the people in class colours
function AssignmentsWindow:OpenViewerMenu(owner)
    local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Preview as"])
        local function choose(name)
            self.viewer = name
            self:Update()
            return MenuResponse and MenuResponse.Close
        end
        root:CreateRadio(L["Everyone"] .. "  " .. GREY .. L["only what everyone sees"] .. "|r",
            function() return self.viewer == nil end, function() return choose(nil) end)
        for _, name in ipairs(self.viewers.names) do
            root:CreateRadio(self:ViewerText(name), function() return self.viewer == name end,
                function() return choose(name) end)
        end
        if root.SetScrollMode then root:SetScrollMode(MENU_HEIGHT) end
    end)
    if menu then menu:SetFrameStrata("TOOLTIP") end
end

-- The rows use AceGUI's Dropdown for its look (UIDropDownMenuTemplate, set up as the plan window's) with this menu
-- instead of its own list. AceGUI widgets are shared with other addons: the clicks and the text's alignment go back
-- before the widget is released.
function AssignmentsWindow:HookDropdown(dropdown, openMenu, justify)
    local saved = {
        button = dropdown.button:GetScript("OnClick"),
        cover = dropdown.button_cover:GetScript("OnClick"),
        justify = dropdown.text:GetJustifyH(),
    }
    local function open() openMenu(dropdown.frame) end
    dropdown.button:SetScript("OnClick", open)
    dropdown.button_cover:SetScript("OnClick", open)
    dropdown.text:SetJustifyH(justify or "LEFT")
    self.hooked[#self.hooked + 1] = { dropdown = dropdown, saved = saved }
end

function AssignmentsWindow:UnhookDropdowns()
    for _, hook in ipairs(self.hooked or {}) do
        local dropdown, saved = hook.dropdown, hook.saved
        dropdown.button:SetScript("OnClick", saved.button)
        dropdown.button_cover:SetScript("OnClick", saved.cover)
        dropdown.text:SetJustifyH(saved.justify)
    end
    self.hooked = {}
end

------------------------------------------------------------------------------------------------ the frame ---

local function addLabel(parent, text)
    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    label:SetFontObject(GameFontHighlight)
    label:SetText(text)
    parent:AddChild(label)
    return label
end

local function addButton(parent, text, width, onClick)
    local button = AceGUI:Create("Button")
    button:SetText(text)
    button:SetWidth(width)
    button:SetCallback("OnClick", onClick)
    parent:AddChild(button)
    return button
end

-- The preview: a UIPanelScrollFrameTemplate with the note in a font string, made once and lent to the window's
-- InlineGroup (AceGUI widgets are pooled: it goes back to nobody before the group is released)
local function createPreview()
    local scroll = CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    scroll.child, scroll.text = child, text
    function scroll:Fit()
        local width = self:GetWidth()
        self.child:SetWidth(width)
        self.text:SetWidth(width)
        self.child:SetHeight(math.max(self.text:GetStringHeight(), 1))
        self:UpdateScrollChildRect()
    end
    function scroll:SetText(note)
        self.text:SetText(note)
        self:Fit()
    end
    scroll:SetScript("OnSizeChanged", scroll.Fit)
    scroll:Hide()
    return scroll
end

function AssignmentsWindow:AttachPreview(content)
    self.previewScroll = self.previewScroll or createPreview()
    local scroll = self.previewScroll
    scroll:SetParent(content)
    scroll:SetFrameStrata(content:GetFrameStrata())
    scroll:SetFrameLevel(content:GetFrameLevel() + 1)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, 0)   -- room for the scroll bar
    scroll:SetVerticalScroll(0)
    scroll:Show()
    self.preview = scroll
end

function AssignmentsWindow:DetachPreview()
    local scroll = self.previewScroll
    if not scroll then return end
    scroll:Hide()
    scroll:ClearAllPoints()
    scroll:SetParent(UIParent)
    self.preview = nil
end

-- Fills the window for the encounter `self.key` of the current plan: the jobs, or why they cannot be changed
function AssignmentsWindow:Build(message)
    local host = self.host
    local frame = host.container
    self:UnhookDropdowns()
    self:DetachPreview()
    frame:ReleaseChildren()
    self.jobs, self.rows, self.labels, self.preview = nil, nil, nil, nil
    self.rowsBox, self.previewBox = nil, nil

    local plan = currentPlan()
    self.key = host:EncounterToEdit(self.key)
    local encounter = findEncounter(plan, self.key)
    if not encounter then
        addLabel(frame, L["The plan has no encounters."])
        host:SetStatus(message or "")
        host:UpdateTree()
        return
    end
    self.people, self.raid = plan.people, raidMembers()
    self.defaults = Assignments.Defaults(plan)
    self:AddEncounterRow(frame, plan, encounter)

    if self.showDefault then
        self:BuildDefault(plan, encounter, message)
        return
    end
    if not Assignments.HasTemplate(encounter) then
        addLabel(frame, L["This encounter's note has no assignment slots. Write the names in the note (Notes)."])
        host:SetStatus(message or "")
        host:UpdateTree()
        return
    end
    -- A note edited by hand (encounter.customNote) has no slots left: back to the plan's note first
    if encounter.customNote ~= nil then
        addLabel(frame,
            L["The note of this encounter was edited by hand. Reset it to the plan's note to change its assignments."])
        addButton(frame, L["Reset to the plan's note"], 200, function() self:ResetNote() end)
        host:SetStatus(message or "")
        host:UpdateTree()
        return
    end

    self.jobs = Assignments.GroupJobs(Assignments.Jobs(encounter))
    self.encounter = encounter
    self:BuildJobs(L["This encounter's note has no assignments."], message)
end

-- The encounter row: "Encounter" and a dropdown of Default and the plan's encounters (OpenEncounterMenu); the rest
-- of the row stays empty, the section starts below it
function AssignmentsWindow:AddEncounterRow(frame, plan, encounter)
    local label = AceGUI:Create("Label")
    label:SetFontObject(GameFontNormal)
    label:SetWidth(LABEL_WIDTH)
    label:SetText(L["Encounter"])
    frame:AddChild(label)
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetWidth(ENCOUNTER_WIDTH)
    self:HookDropdown(dropdown, function(owner) self:OpenEncounterMenu(owner) end, dropdown.text:GetJustifyH())
    local _, index = findEncounter(plan, encounter.key)
    dropdown:SetText(self.showDefault and DEFAULT_TEXT or encounterText(plan, index, encounter))
    frame:AddChild(dropdown)
    local rest = AceGUI:Create("Label")
    rest:SetFullWidth(true)
    frame:AddChild(rest)
end

-- Default: every job key of the plan's encounters with the default holders. The preview shows the encounter the
-- section showed last (else the first that takes part) as the new defaults would make it.
function AssignmentsWindow:BuildDefault(plan, encounter, message)
    self.jobs = Assignments.DefaultJobs(plan, self.defaults)
    self.encounter = nil
    if Assignments.TakesPart(encounter) then
        self.encounter = encounter
    else
        for _, other in ipairs(plan.encounters) do
            if not self.encounter and Assignments.TakesPart(other) then self.encounter = other end
        end
    end
    self:BuildJobs(L["None of the encounters' notes have assignments."], message)
end

-- The rows of `self.jobs` (or `empty` when there are none), the preview, Save and Undo changes
function AssignmentsWindow:BuildJobs(empty, message)
    local frame = self.host.container
    -- The jobs: label and dropdown, in a scroll frame
    local rowsBox = AceGUI:Create("SimpleGroup")
    rowsBox:SetFullWidth(true)
    rowsBox:SetHeight(MIN_ROWS_HEIGHT)
    rowsBox:SetLayout("Fill")
    frame:AddChild(rowsBox)
    local rows = AceGUI:Create("ScrollFrame")
    rows:SetLayout("Flow")
    rowsBox:AddChild(rows)
    self.rowsBox = rowsBox
    if #self.jobs == 0 then
        addLabel(rows, empty)
    end
    self.rows, self.labels = {}, {}
    for i, job in ipairs(self.jobs) do
        local label = AceGUI:Create("Label")
        label:SetFontObject(GameFontNormalSmall)
        label:SetWidth(LABEL_WIDTH)
        rows:AddChild(label)
        self.labels[i] = label
        local dropdown = AceGUI:Create("Dropdown")
        dropdown:SetWidth(DROPDOWN_WIDTH)
        self:HookDropdown(dropdown, function(owner) self:OpenMenu(job, owner) end)
        rows:AddChild(dropdown)
        self.rows[i] = dropdown
    end

    -- Whom the preview shows the note as: yourself when you are among the people, else everyone, until the
    -- window closes
    self.viewers = viewers(self.people)
    if not self.viewerChosen then
        self.viewer, self.viewerChosen = nil, true
        local me = UnitName("player")
        for _, name in ipairs(self.viewers.names) do
            if ns.GroupPlan.Key(name) == ns.GroupPlan.Key(me) then self.viewer = name end
        end
    elseif self.viewer then                 -- somebody who has left the raid: everyone
        local known = false
        for _, name in ipairs(self.viewers.names) do
            if name == self.viewer then known = true end
        end
        if not known then self.viewer = nil end
    end
    -- The preview's own section: a line like the encounter's heading, below the rows' scroll frame
    local divider = AceGUI:Create("Heading")
    divider:SetText("")
    divider:SetFullWidth(true)
    frame:AddChild(divider)

    local viewerLabel = AceGUI:Create("Label")
    viewerLabel:SetFontObject(GameFontNormalSmall)
    viewerLabel:SetWidth(LABEL_WIDTH)
    viewerLabel:SetText(L["Preview as"])
    frame:AddChild(viewerLabel)
    self.viewerDropdown = AceGUI:Create("Dropdown")
    self.viewerDropdown:SetWidth(DROPDOWN_WIDTH)
    self:HookDropdown(self.viewerDropdown, function(owner) self:OpenViewerMenu(owner) end)
    frame:AddChild(self.viewerDropdown)

    -- The rebuilt note, as Method Raid Tools shows it, in the window's own scroll frame
    local previewBox = AceGUI:Create("InlineGroup")
    -- Default: the note of the encounter it previews, named
    previewBox:SetTitle(self.showDefault and self.encounter and format(L["Note preview: %s"], self.encounter.label)
        or L["Note preview"])
    previewBox:SetFullWidth(true)
    previewBox:SetAutoAdjustHeight(false)
    previewBox:SetHeight(MIN_PREVIEW_HEIGHT)
    frame:AddChild(previewBox)
    self.previewBox = previewBox
    self:AttachPreview(previewBox.content)

    self.saveButton = addButton(frame, L["Save"], 140, function() self:Save() end)
    self.undoButton = addButton(frame, L["Undo changes"], 140, function() self:Build() end)

    self:Update(message)
    self:FitHeight()
end

-- Fills the section down to its bottom edge, Save and Undo changes last: after the layout, what the other rows use
-- is measured, and the rest goes to the jobs list (as much as its rows need) and the preview
function AssignmentsWindow:FitHeight()
    local content, button = self.host.content, self.saveButton.frame
    local top, bottom = content:GetTop(), button:GetBottom()
    if not (top and bottom) then return end     -- not laid out on screen yet: the minimums stay
    local rowsHeight, previewHeight = self.rowsBox.frame:GetHeight(), self.previewBox.frame:GetHeight()
    local flexible = rowsHeight + previewHeight + UTRM.GroupEditor.HEIGHT - (top - bottom)
    local needed = math.max(#self.jobs, 1) * ROW_HEIGHT
    rowsHeight = math.max(MIN_ROWS_HEIGHT, math.min(needed, flexible - MIN_PREVIEW_HEIGHT))
    previewHeight = math.max(MIN_PREVIEW_HEIGHT, flexible - rowsHeight)
    self.rowsBox:SetHeight(rowsHeight)
    self.previewBox:SetHeight(previewHeight)
    self.host.container:DoLayout()
end

-- The rows' texts, the preview and the status line after a change
function AssignmentsWindow:Update(message)
    if not (self.host and self.jobs) then return end
    for i, job in ipairs(self.jobs) do
        self.labels[i]:SetText(self:KeyText(job))
        self.rows[i]:SetText(self:JobText(job))
    end
    self.viewerDropdown:SetText(self:ViewerText(self.viewer))
    local note = ""
    if self.encounter then
        local jobs = self.jobs
        if self.showDefault then
            jobs = Assignments.FollowDefaults(Assignments.Jobs(self.encounter), self.defaults, self.jobs)
        end
        note = ns.NoteView.For(Assignments.Preview(self.encounter, jobs, self.people), self:Viewer())
    end
    self.preview:SetText(UTRM:GetModule("MRT"):FormatNote(note))
    local changed = self:ChangedCount()
    self.saveButton:SetDisabled(changed == 0)
    self.undoButton:SetDisabled(changed == 0)
    if message then
        self.host:SetStatus(message)
    elseif changed > 0 then
        self.host:SetStatus(format(L["%d changes not saved."], changed))
    else
        self.host:SetStatus("")
    end
    self.host.container:DoLayout()
    self.host:UpdateTree()
end

------------------------------------------------------------------------------------------------ actions ---

-- Sends the note again when the encounter is the active one, as choosing it does (UI/PlanWindow.lua)
local function postIfActive(key)
    local plan = currentPlan()
    if plan and plan.active == key then
        UTRM.PlanWindow:Commit()
    end
end

-- An edit of this encounter through PlanImport:Edit; the window does not rebuild on its own edit message
function AssignmentsWindow:EditEncounter(change)
    local key = self.key
    self.editing = true
    local ok, message = UTRM:GetModule("PlanImport"):Edit(function(plan)
        local encounter = findEncounter(plan, key)
        if not encounter then return false end
        return change(encounter, plan)
    end)
    self.editing = false
    if ok then postIfActive(key) end
    return ok, message
end

-- Default: the new holders go to every encounter that follows the old default (Modules/Assignments.lua)
function AssignmentsWindow:SaveDefault()
    local invalid = Assignments.Validate(self.jobs)
    if invalid then
        self.host:SetStatus("|cffff4040" .. format(L["%s cannot be saved like this: choose again."], invalid) .. "|r")
        return
    end
    local defaults, jobs, rebuilt, kept = self.defaults, self.jobs, {}, {}
    self.editing = true
    local ok, message = UTRM:GetModule("PlanImport"):Edit(function(plan)
        rebuilt, kept = Assignments.SaveDefaults(plan, defaults, jobs, plan.people)
    end)
    self.editing = false
    if not ok then
        self:Build("|cffff4040" .. (message or L["The encounter changed in the meantime: check it again."]) .. "|r")
        return
    end
    for _, key in ipairs(rebuilt) do postIfActive(key) end
    local text = format(L["Default assignments saved: %d encounters rebuilt."], #rebuilt)
    if #kept > 0 then
        text = text .. " " .. format(L["%d encounters keep their own players: the new ones cannot fill the job there."],
            #kept)
    end
    self:Build(UTRM.RaidPlanWindow:SavedMessage(text))
end

function AssignmentsWindow:Save()
    if self.showDefault then return self:SaveDefault() end
    local invalid = Assignments.Validate(self.jobs)
    if invalid then
        self.host:SetStatus("|cffff4040" .. format(L["%s cannot be saved like this: choose again."], invalid) .. "|r")
        return
    end
    local jobs = self.jobs
    local ok, message = self:EditEncounter(function(encounter, plan)
        if encounter.customNote ~= nil or not Assignments.HasTemplate(encounter) then return false end
        -- The defaults stay what they are now, also when this changes which holders are the most common
        if plan.assignmentDefaults == nil then Assignments.KeepDefaults(plan) end
        Assignments.Apply(encounter, jobs, plan.people)
    end)
    if not ok then
        self:Build("|cffff4040" .. (message or L["The encounter changed in the meantime: check it again."]) .. "|r")
        return
    end
    self:Build(UTRM.RaidPlanWindow:SavedMessage(L["Assignments saved."]))
end

-- Clears the hand-edited note (`customNote`), so the plan's note and its assignments are back
function AssignmentsWindow:ResetNote()
    local ok, message = self:EditEncounter(function(encounter)
        if encounter.customNote == nil then return false end
        encounter.customNote = nil
    end)
    self:Build(not ok and message and ("|cffff4040" .. message .. "|r") or nil)
end

-- How many jobs the draft changes: the Default's against the defaults, an encounter's against its slots
function AssignmentsWindow:ChangedCount()
    if not self.jobs then return 0 end
    if self.showDefault then return Assignments.ChangedDefaults(self.defaults, self.jobs) end
    return Assignments.Changed(self.encounter, self.jobs)
end

function AssignmentsWindow:IsChanged()
    return self:ChangedCount() > 0
end

-- Shows the section in the Raid Plan window (`host`, UI/RaidPlanWindow.lua) on the encounter it showed last
function AssignmentsWindow:Attach(host)
    self.host = host
    self.hooked = self.hooked or {}
    self:Build()
end

-- Before the window's section is released: AceGUI widgets go back as they were
function AssignmentsWindow:Detach()
    self:UnhookDropdowns()
    self:DetachPreview()
    self.host, self.jobs, self.rows, self.labels, self.viewerDropdown = nil, nil, nil, nil, nil
end

-- Unsaved changes are dropped (the Raid Plan window asked first)
function AssignmentsWindow:Discard()
    if self.host then self:Build() end
end

function AssignmentsWindow:OnEnable()
    -- Another plan, or another edit of this one (a sync, the note editor): the window shows it as it is now,
    -- unsaved changes are dropped
    for _, event in ipairs({ "UTRM_PLAN_IMPORTED", "UTRM_PLAN_EDITED", "UTRM_PLAN_CLEARED" }) do
        self:RegisterMessage(event, function()
            if self.host and not self.editing then
                self:Build(L["The raid plan changed: the assignments are shown as they are now."])
            end
        end)
    end
end
