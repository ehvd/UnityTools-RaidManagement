local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- Window for writing the raid note and sending it to Method Raid Tools (`/utrm note`). Opens with MRT's current note.
-- NoteEditor.Section is the Notes section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #25): an encounter's
-- note in the raid plan; Save stores the text as the encounter's hand edit, Reset to the plan's note removes it.
local NoteEditor = {}
UTRM.NoteEditor = NoteEditor

local FRAME_GLOBAL = "UnityToolsRaidManagementNoteFrame"
local specialFrameAdded = false

-- The Notes section's box fills the section (as tall as the groups editor, UI/RaidPlanWindow.lua) under the encounter
-- dropdown (26) and over the buttons (24). AceGUI's MultiLineEditBox is 14 px a line plus 19 without its button and
-- 10 for its label; the Flow layout puts 3 px between rows.
local LINE_HEIGHT = 14
local SECTION_FIXED = 26 + 3 + 10 + 19 + 3 + 24 + 4

local function sectionLines()
    return math.floor((UTRM.GroupEditor.HEIGHT - SECTION_FIXED) / LINE_HEIGHT)
end

local function planImport()
    return UTRM:GetModule("PlanImport")
end

local function button(parent, text, width, onClick)
    local widget = AceGUI:Create("Button")
    widget:SetText(text)
    widget:SetWidth(width)
    widget:SetCallback("OnClick", onClick)
    parent:AddChild(widget)
    return widget
end

local function noteBox(parent, lines)
    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(lines)
    parent:AddChild(editBox)
    return editBox
end

----------------------------------------------------------------------------------------- the MRT note ---

function NoteEditor:LoadFromMRT()
    if not self.editBox then return end
    self.editBox:SetText(UTRM:GetModule("MRT"):GetNote() or "")
end

function NoteEditor:Send()
    if not self.editBox then return end
    local _, message = UTRM:GetModule("MRT"):Post(self.editBox:GetText())
    self.frame:SetStatusText(message)
end

function NoteEditor:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetStatusTable(UTRM.db.profile.noteWindow)
    frame:SetTitle(L["Raid note"])
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        self.frame, self.editBox = nil, nil
        AceGUI:Release(widget)
    end)
    self.frame = frame

    self.editBox = noteBox(frame, 18)
    button(frame, L["Send"], 140, function() self:Send() end)
    button(frame, L["Reload from MRT"], 160, function()
        self:LoadFromMRT()
        frame:SetStatusText("")
    end)
    self:LoadFromMRT()
    self.editBox:SetFocus()

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end
end

-- The raid note editor (`/utrm note`)
function NoteEditor:Open()
    local _, reason = UTRM:GetModule("MRT"):GetNoteModule()
    if reason then
        UTRM:Print(reason)
        return
    end
    if not self.frame then
        self:Create()
    end
end

------------------------------------------------------------------------------- the Notes section ---

local Section = {}
NoteEditor.Section = Section

-- The encounter being edited, from the current plan (a sync may have replaced it since)
function Section:GetEncounter()
    local plan = planImport():GetPlan()
    if not plan or not self.key then return nil end
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key == self.key then return encounter end
    end
    return nil
end

function Section:IsChanged()
    local encounter = self.editBox and self:GetEncounter()
    return encounter ~= nil and self.editBox:GetText() ~= planImport():NoteOf(encounter)
end

-- Save and Reset follow the text: Save when it differs from the note sent, Reset when the note is a hand edit
function Section:UpdateButtons()
    if not self.editBox then return end
    local encounter, changed = self:GetEncounter(), self:IsChanged()
    self.save:SetDisabled(not changed)
    self.undo:SetDisabled(not changed)
    self.reset:SetDisabled(not (encounter and encounter.customNote))
    self.host:UpdateTree()
end

-- Stores the edit box's text (or nil: the plan's note again) for the encounter; the active one is also sent to MRT
function Section:SaveNote(text)
    local host = self.host
    local ok, message = planImport():EditNote(self.key, text)
    if not ok and message then
        host:SetStatus("|cffff4040" .. message .. "|r")
        return
    end
    local encounter = self:GetEncounter()
    if UTRM.PlanWindow:IsActive(encounter) then
        UTRM.PlanWindow:SendNote()
    end
    if not ok then
        message = L["The note is unchanged."]
    else
        message = host:SavedMessage(text == nil and L["The plan's note is back."] or L["Note saved in the raid plan."])
    end
    self:Build(message)
end

-- Fills the section for the encounter `self.key` (the window's choice when it is gone)
function Section:Build(message)
    local host = self.host
    local container = host.container
    container:ReleaseChildren()
    self.editBox = nil
    self.key = host:EncounterToEdit(self.key)
    local encounter = self:GetEncounter()
    if not encounter then
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(L["The plan has no encounters."])
        container:AddChild(label)
        host:SetStatus(message or "")
        host:UpdateTree()
        return
    end

    host:AddEncounterDropdown(container, self.key, function(key)
        self.key = key
        self:Build()
    end, function() return self:IsChanged() end)

    local editBox = noteBox(container, sectionLines())
    editBox:SetText(planImport():NoteOf(encounter))
    editBox:SetCallback("OnTextChanged", function() self:UpdateButtons() end)
    self.editBox = editBox

    self.save = button(container, L["Save"], 140, function() self:SaveNote(editBox:GetText()) end)
    self.undo = button(container, L["Undo changes"], 140, function() self:Build() end)
    self.reset = button(container, L["Reset to the plan's note"], 200, function() self:SaveNote(nil) end)
    host:SetStatus(message or (encounter.customNote and L["Edited by hand: assignments no longer rebuild this note."]
        or ""))
    self:UpdateButtons()
end

function Section:Attach(host)
    self.host = host
    self:Build()
end

function Section:Detach()
    self.host, self.editBox = nil, nil
end

function Section:Discard()
    if self.host then self:Build() end
end

-- Another plan or another edit of this one (a sync, the assignments): the note as it is now, unless it is being
-- changed here
function Section:OnPlanChanged()
    if self.host and not self:IsChanged() then self:Build() end
end
