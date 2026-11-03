local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")
local Assignments = ns.Assignments

-- The Assignments section of the Raid Plan window (UI/RaidPlanWindow.lua): who fills an encounter's assignments
-- (export protocol 2). The encounter dropdown picks the encounter to change (it never changes the active one), then
-- one row per job with a dropdown of its candidates, a preview of the rebuilt note, Save. Saving is a plan edit
-- (PlanImport:Edit), so it syncs like one, and the note goes to Method Raid Tools when the encounter is the active one.
-- Layout from the Figma wireframe "Assignments", every control at its own size.
local AssignmentsWindow = UTRM:NewModule("AssignmentsWindow", "AceEvent-3.0")
UTRM.AssignmentsWindow = AssignmentsWindow

local ROWS_HEIGHT = 196                 -- seven rows of jobs (a 26 tall dropdown and the layout's gap), then scrolls
local LABEL_WIDTH = 110
local DROPDOWN_WIDTH = 400              -- wide enough that the next label starts a new row
local PREVIEW_HEIGHT = 150
local MENU_HEIGHT = 400                 -- a menu of a whole raid scrolls past this
local GREY = "|cff808080"

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

function AssignmentsWindow:JobText(job)
    if #job.holders == 0 then
        return GREY .. "(" .. L["nobody"] .. ")|r"
    end
    local names = {}
    for i, name in ipairs(job.holders) do names[i] = self:HolderText(name) end
    return table.concat(names, ", ")
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
    if not name then return nil end
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
function AssignmentsWindow:HookDropdown(dropdown, openMenu)
    local saved = {
        button = dropdown.button:GetScript("OnClick"),
        cover = dropdown.button_cover:GetScript("OnClick"),
        justify = dropdown.text:GetJustifyH(),
    }
    local function open() openMenu(dropdown.frame) end
    dropdown.button:SetScript("OnClick", open)
    dropdown.button_cover:SetScript("OnClick", open)
    dropdown.text:SetJustifyH("LEFT")
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
    self.jobs, self.rows, self.preview = nil, nil, nil

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

    host:AddEncounterDropdown(frame, self.key, function(key)
        self.key = key
        self:Build()
    end, function() return self:IsChanged() end)

    if not Assignments.HasTemplate(encounter) then
        addLabel(frame, ns.NewPlan.IsMadeInGame(plan)
            and L["This plan was made in game: its notes have no assignment slots. Write the names in the note (Notes)."]
            or L["This encounter's note has no assignment slots. Write the names in the note (Notes)."])
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

    -- The jobs: label and dropdown, in a scroll frame
    local rowsBox = AceGUI:Create("SimpleGroup")
    rowsBox:SetFullWidth(true)
    rowsBox:SetHeight(ROWS_HEIGHT)
    rowsBox:SetLayout("Fill")
    frame:AddChild(rowsBox)
    local rows = AceGUI:Create("ScrollFrame")
    rows:SetLayout("Flow")
    rowsBox:AddChild(rows)
    if #self.jobs == 0 then
        addLabel(rows, L["This encounter's note has no assignments."])
    end
    self.rows = {}
    for i, job in ipairs(self.jobs) do
        local label = AceGUI:Create("Label")
        label:SetFontObject(GameFontNormalSmall)
        label:SetWidth(LABEL_WIDTH)
        label:SetText(table.concat(job.tokens, " · "))
        rows:AddChild(label)
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
    previewBox:SetTitle(L["Note preview"])
    previewBox:SetFullWidth(true)
    previewBox:SetAutoAdjustHeight(false)
    previewBox:SetHeight(PREVIEW_HEIGHT)
    frame:AddChild(previewBox)
    self:AttachPreview(previewBox.content)

    self.saveButton = addButton(frame, L["Save"], 140, function() self:Save() end)
    self.undoButton = addButton(frame, L["Undo changes"], 140, function() self:Build() end)

    self:Update(message)
end

-- The rows' texts, the preview and the status line after a change
function AssignmentsWindow:Update(message)
    if not (self.host and self.jobs) then return end
    for i, job in ipairs(self.jobs) do
        self.rows[i]:SetText(self:JobText(job))
    end
    self.viewerDropdown:SetText(self:ViewerText(self.viewer))
    local note = ns.NoteView.For(Assignments.Preview(self.encounter, self.jobs, self.people), self:Viewer())
    self.preview:SetText(UTRM:GetModule("MRT"):FormatNote(note))
    local changed = Assignments.Changed(self.encounter, self.jobs)
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

function AssignmentsWindow:Save()
    local invalid = Assignments.Validate(self.jobs)
    if invalid then
        self.host:SetStatus("|cffff4040" .. format(L["%s cannot be saved like this: choose again."], invalid) .. "|r")
        return
    end
    local jobs = self.jobs
    local ok, message = self:EditEncounter(function(encounter, plan)
        if encounter.customNote ~= nil or not Assignments.HasTemplate(encounter) then return false end
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

function AssignmentsWindow:IsChanged()
    return self.jobs ~= nil and Assignments.Changed(self.encounter, self.jobs) > 0
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
    self.host, self.jobs, self.rows, self.viewerDropdown = nil, nil, nil, nil
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
