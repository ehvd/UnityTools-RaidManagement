local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- Window for writing the raid note and sending it to Method Raid Tools. Opens with MRT's current note.
local NoteEditor = {}
UTRM.NoteEditor = NoteEditor

local FRAME_GLOBAL = "UnityToolsRaidManagementNoteFrame"
local specialFrameAdded = false

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
    frame:SetTitle(L["Raid note"])
    frame:SetStatusTable(UTRM.db.profile.noteWindow)
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        self.frame, self.editBox = nil, nil
        AceGUI:Release(widget)
    end)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(18)
    frame:AddChild(editBox)

    local send = AceGUI:Create("Button")
    send:SetText(L["Send"])
    send:SetWidth(140)
    send:SetCallback("OnClick", function() self:Send() end)
    frame:AddChild(send)

    local reload = AceGUI:Create("Button")
    reload:SetText(L["Reload from MRT"])
    reload:SetWidth(160)
    reload:SetCallback("OnClick", function()
        self:LoadFromMRT()
        frame:SetStatusText("")
    end)
    frame:AddChild(reload)

    self.frame = frame
    self.editBox = editBox

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end

    self:LoadFromMRT()
    editBox:SetFocus()
end

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
