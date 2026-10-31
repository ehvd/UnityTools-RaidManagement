local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- Window for writing the raid note and sending it to Method Raid Tools. Opens with MRT's current note.
-- The same window edits an encounter's note in the raid plan (issue #25, OpenEncounter): Save stores the text as the
-- encounter's hand edit, Reset to the plan's note removes it.
local NoteEditor = {}
UTRM.NoteEditor = NoteEditor

local FRAME_GLOBAL = "UnityToolsRaidManagementNoteFrame"
local specialFrameAdded = false

local function planImport()
    return UTRM:GetModule("PlanImport")
end

-- The encounter being edited, from the current plan (a sync may have replaced it since the editor opened)
function NoteEditor:GetEncounter()
    local plan = planImport():GetPlan()
    if not plan or not self.encounterKey then return nil end
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key == self.encounterKey then return encounter end
    end
    return nil
end

function NoteEditor:LoadFromMRT()
    if not self.editBox then return end
    self.editBox:SetText(UTRM:GetModule("MRT"):GetNote() or "")
end

function NoteEditor:Send()
    if not self.editBox then return end
    local _, message = UTRM:GetModule("MRT"):Post(self.editBox:GetText())
    self.frame:SetStatusText(message)
end

-- Stores the edit box's text (or nil: the plan's note again) for the encounter; the active one is also sent to MRT
function NoteEditor:SaveEncounterNote(text)
    local ok, message = planImport():EditNote(self.encounterKey, text)
    if not ok and message then
        self.frame:SetStatusText("|cffff4040" .. message .. "|r")
        return
    end
    local encounter = self:GetEncounter()
    if text == nil then
        self.editBox:SetText(planImport():NoteOf(encounter))
    end
    if UTRM.PlanWindow:IsActive(encounter) then
        UTRM.PlanWindow:SendNote()
    end
    if not ok then
        message = L["The note is unchanged."]
    elseif IsInRaid() and not UTRM:GetModule("Sync"):CanSync() then
        message = L["Saved on your client only: you are not raid leader or assistant."]
    else
        message = text == nil and L["The plan's note is back."] or L["Note saved in the raid plan."]
    end
    self.frame:SetStatusText(message)
    self:UpdateButtons()
end

function NoteEditor:UpdateButtons()
    local encounter = self:GetEncounter()
    if self.reset then
        self.reset:SetDisabled(not (encounter and encounter.customNote))
    end
end

local function button(frame, text, width, onClick)
    local widget = AceGUI:Create("Button")
    widget:SetText(text)
    widget:SetWidth(width)
    widget:SetCallback("OnClick", onClick)
    frame:AddChild(widget)
    return widget
end

-- The edit box and the buttons of the mode: MRT's note, or the encounter's note when `encounter` is given
function NoteEditor:Build(encounter)
    local frame = self.frame
    frame:ReleaseChildren()
    frame:SetStatusText("")
    self.reset = nil

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(18)
    frame:AddChild(editBox)
    self.editBox = editBox

    if encounter then
        self.encounterKey = encounter.key
        frame:SetTitle(format(L["Note: %s"], encounter.label))
        button(frame, SAVE, 140, function() self:SaveEncounterNote(editBox:GetText()) end)
        self.reset = button(frame, L["Reset to the plan's note"], 200, function() self:SaveEncounterNote(nil) end)
        editBox:SetText(planImport():NoteOf(encounter))
        self:UpdateButtons()
    else
        self.encounterKey = nil
        frame:SetTitle(L["Raid note"])
        button(frame, L["Send"], 140, function() self:Send() end)
        button(frame, L["Reload from MRT"], 160, function()
            self:LoadFromMRT()
            frame:SetStatusText("")
        end)
        self:LoadFromMRT()
    end
    editBox:SetFocus()
end

function NoteEditor:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetStatusTable(UTRM.db.profile.noteWindow)
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        self.frame, self.editBox, self.reset, self.encounterKey = nil, nil, nil, nil
        AceGUI:Release(widget)
    end)
    self.frame = frame

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end
end

-- The raid note editor (`/utrm note`). Already open on an encounter's note, it switches back to MRT's note.
function NoteEditor:Open()
    local _, reason = UTRM:GetModule("MRT"):GetNoteModule()
    if reason then
        UTRM:Print(reason)
        return
    end
    if not self.frame then
        self:Create()
        self:Build()
    elseif self.encounterKey then
        self:Build()
    end
end

-- Edit note... (the plan window): the encounter's note as it is sent, its hand edit when it has one
function NoteEditor:OpenEncounter(encounter)
    if not self.frame then
        self:Create()
    end
    self:Build(encounter)
end
