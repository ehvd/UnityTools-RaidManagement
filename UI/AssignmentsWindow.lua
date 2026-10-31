local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")
local Assignments = ns.Assignments

-- Window for changing who fills the active encounter's assignments (export protocol 2): one row per job with a
-- dropdown of its candidates, a preview of the rebuilt note, Save. Saving is a plan edit (PlanImport:Edit), so it
-- syncs like one, and the note goes to Method Raid Tools when the encounter is the active one. Layout from the
-- Figma wireframe "Assignments": an AceGUI Frame like the note editor's, every control at its own size.
local AssignmentsWindow = UTRM:NewModule("AssignmentsWindow", "AceEvent-3.0")
UTRM.AssignmentsWindow = AssignmentsWindow

local FRAME_GLOBAL = "UnityToolsRaidManagementAssignmentsFrame"
local WIDTH, HEIGHT = 440, 500
local SHORT_HEIGHT = 170                -- the window when there is nothing to change, only a message
local ROWS_HEIGHT = 196                 -- seven rows of jobs (a 26 tall dropdown and the layout's gap), then scrolls
local LABEL_WIDTH = 110
local DROPDOWN_WIDTH = 270              -- the rest of the scroll frame's width next to the label
local PREVIEW_HEIGHT = 150
local GREY = "|cff808080"

local status = { width = WIDTH, height = HEIGHT }   -- position and size for this session
local specialFrameAdded = false

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

-- A job's menu: its candidates as the export lists them. Several holders: check boxes, the menu stays open;
-- one holder: radio buttons and Nobody, the menu closes.
function AssignmentsWindow:OpenMenu(job, owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
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
end

-- The rows use AceGUI's Dropdown for its look (UIDropDownMenuTemplate, set up as the plan window's) with this menu
-- instead of its own list. AceGUI widgets are shared with other addons: the clicks and the text's alignment go back
-- before the widget is released.
function AssignmentsWindow:HookDropdown(dropdown, job)
    local saved = {
        button = dropdown.button:GetScript("OnClick"),
        cover = dropdown.button_cover:GetScript("OnClick"),
        justify = dropdown.text:GetJustifyH(),
    }
    local function open() self:OpenMenu(job, dropdown.frame) end
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

function AssignmentsWindow:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["Assignments"])
    frame:SetStatusTable(status)
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        self:UnhookDropdowns()
        _G[FRAME_GLOBAL] = nil
        self.frame, self.jobs, self.rows, self.preview = nil, nil, nil, nil
        AceGUI:Release(widget)
    end)
    self.frame = frame
    self.hooked = {}

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end
end

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

-- Fills the window for the encounter `self.key` of the current plan: the jobs, or why they cannot be changed
function AssignmentsWindow:Build(message)
    local frame = self.frame
    self:UnhookDropdowns()
    frame:ReleaseChildren()
    self.jobs, self.rows, self.preview = nil, nil, nil

    local plan = currentPlan()
    local encounter, index = findEncounter(plan, self.key)
    if not encounter then
        frame:Hide()
        return
    end
    self.people, self.raid = plan.people, raidMembers()

    local heading = AceGUI:Create("Heading")
    heading:SetText(format("%s  |cff999999%d/%d|r", encounter.label, index, #plan.encounters))
    heading:SetFullWidth(true)
    frame:AddChild(heading)

    if not Assignments.HasTemplate(encounter) then
        frame:SetHeight(SHORT_HEIGHT)
        addLabel(frame, L["Export the plan again from the wiki to change assignments."])
        frame:SetStatusText(message or "")
        return
    end
    -- A note edited by hand (encounter.customNote) has no slots left: back to the plan's note first
    if encounter.customNote ~= nil then
        frame:SetHeight(SHORT_HEIGHT)
        addLabel(frame,
            L["The note of this encounter was edited by hand. Reset it to the plan's note to change its assignments."])
        addButton(frame, L["Reset to the plan's note"], 200, function() self:ResetNote() end)
        frame:SetStatusText(message or "")
        return
    end

    frame:SetHeight(HEIGHT)
    self.jobs = Assignments.Jobs(encounter)
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
        self:HookDropdown(dropdown, job)
        rows:AddChild(dropdown)
        self.rows[i] = dropdown
    end

    -- The rebuilt note
    local previewBox = AceGUI:Create("InlineGroup")
    previewBox:SetTitle(L["Note preview"])
    previewBox:SetFullWidth(true)
    previewBox:SetHeight(PREVIEW_HEIGHT)
    previewBox:SetLayout("Fill")
    frame:AddChild(previewBox)
    local previewScroll = AceGUI:Create("ScrollFrame")
    previewScroll:SetLayout("List")
    previewBox:AddChild(previewScroll)
    self.preview = AceGUI:Create("Label")
    self.preview:SetFullWidth(true)
    self.preview:SetFontObject(GameFontHighlightSmall)
    previewScroll:AddChild(self.preview)

    addButton(frame, L["Save"], 140, function() self:Save() end)
    addButton(frame, CANCEL, 140, function() frame:Hide() end)

    self:Update(message)
end

-- The rows' texts, the preview and the status line after a change
function AssignmentsWindow:Update(message)
    if not (self.frame and self.jobs) then return end
    for i, job in ipairs(self.jobs) do
        self.rows[i]:SetText(self:JobText(job))
    end
    self.preview:SetText(Assignments.Preview(self.encounter, self.jobs, self.people))
    local changed = Assignments.Changed(self.encounter, self.jobs)
    if message then
        self.frame:SetStatusText(message)
    elseif changed > 0 then
        self.frame:SetStatusText(format(L["%d changes not saved."], changed))
    else
        self.frame:SetStatusText("")
    end
    self.frame:DoLayout()
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
        self.frame:SetStatusText("|cffff4040" .. format(L["%s cannot be saved like this: choose again."], invalid) .. "|r")
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
    self.frame:Hide()
end

-- Clears the hand-edited note (`customNote`), so the plan's note and its assignments are back
function AssignmentsWindow:ResetNote()
    local ok, message = self:EditEncounter(function(encounter)
        if encounter.customNote == nil then return false end
        encounter.customNote = nil
    end)
    self:Build(not ok and message and ("|cffff4040" .. message .. "|r") or nil)
end

-- Opens the window for the active encounter, or says why it cannot
function AssignmentsWindow:Open()
    local plan = currentPlan()
    local encounter = plan and plan.encounters[UTRM.PlanWindow:GetActiveIndex(plan) or 0]
    if not plan then
        UTRM.PlanWindow:ShowResult(false, L["No raid plan imported yet."])
        return
    end
    if not encounter then
        UTRM.PlanWindow:ShowResult(false, L["Choose the encounter first."])
        return
    end
    self.key = encounter.key
    if not self.frame then self:Create() end
    self:Build()
end

function AssignmentsWindow:OnEnable()
    -- Another plan, or another edit of this one (a sync, the note editor): the window shows it as it is now,
    -- unsaved changes are dropped
    for _, event in ipairs({ "UTRM_PLAN_IMPORTED", "UTRM_PLAN_EDITED", "UTRM_PLAN_CLEARED" }) do
        self:RegisterMessage(event, function()
            if self.frame and not self.editing then
                self:Build(L["The raid plan changed: the assignments are shown as they are now."])
            end
        end)
    end
end
