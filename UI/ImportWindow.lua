local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- Window for pasting the raid plan export of the UnityWiki raid planner
local ImportWindow = {}
UTRM.ImportWindow = ImportWindow

local FRAME_GLOBAL = "UnityToolsRaidManagementImportFrame"
local specialFrameAdded = false

-- A night's export is up to ~60,000 characters. Rendering that much text in a multi-line edit box freezes the
-- client, so (like the import of WeakAuras) the edit box keeps only the first bytes while OnChar, which still fires
-- for every pasted character, collects the whole paste; the paste ends on the next frame.
local SHOWN_BYTES = 2500
local MIN_PASTE = 50   -- fewer characters in one frame is typing, not a paste

local function hookPaste(widget)
    local editBox = widget.editBox
    local buffer, count = {}, 0
    editBox:SetMaxBytes(SHOWN_BYTES)
    editBox:SetScript("OnChar", function(self, c)
        if count == 0 then
            -- A new paste over an earlier one: drop the old text, it may already fill the shown bytes
            if self:GetNumLetters() > MIN_PASTE then
                self:SetText("")
            end
            buffer = {}
            self:SetScript("OnUpdate", function(box)
                box:SetScript("OnUpdate", nil)
                if count >= MIN_PASTE then
                    ImportWindow.pasted = table.concat(buffer)
                    ImportWindow.frame:SetStatusText(format(L["%d characters pasted. Press Import."], #ImportWindow.pasted))
                else
                    ImportWindow.pasted = nil
                end
                count = 0
            end)
        end
        count = count + 1
        buffer[count] = c
    end)
end

-- AceGUI widgets are shared with other addons: leave the edit box as it was
local function unhookPaste(widget)
    local editBox = widget.editBox
    editBox:SetScript("OnChar", nil)
    editBox:SetScript("OnUpdate", nil)
    editBox:SetMaxBytes(0)
end

function ImportWindow:Refresh(status)
    if not self.frame then return end
    self.summary:SetText(UTRM:GetModule("PlanImport"):Summary(UTRM:GetModule("PlanImport"):GetPlan()))
    if status then
        self.frame:SetStatusText(status)
    end
    self.frame:DoLayout()
end

function ImportWindow:Import()
    local PlanImport = UTRM:GetModule("PlanImport")
    local plan, message = PlanImport:Read(self.pasted or self.editBox:GetText())
    if not plan then
        self.frame:SetStatusText("|cffff4040" .. message .. "|r")
        return
    end
    local current = PlanImport:GetPlan()
    if current then
        StaticPopup_Show("UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN", current.event.title, plan.event.title, plan)
    else
        self:Store(plan)
    end
end

function ImportWindow:Store(plan)
    UTRM:GetModule("PlanImport"):Store(plan)
    self.pasted = nil
    if self.editBox then
        self.editBox:SetText("")
    end
    self:Refresh(format(L["Imported %s."], plan.event.title))
    UTRM.PlanWindow:Show()
end

StaticPopupDialogs["UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN"] = {
    text = L["Replace the imported raid plan \"%s\" with \"%s\"?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, plan) ImportWindow:Store(plan) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ImportWindow:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["Import raid plan"])
    frame:SetStatusTable(UTRM.db.profile.importWindow)
    frame:SetLayout("List")
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        unhookPaste(self.editBox)
        _G[FRAME_GLOBAL] = nil
        self.frame, self.editBox, self.summary, self.pasted = nil, nil, nil, nil
        AceGUI:Release(widget)
    end)

    local heading = AceGUI:Create("Heading")
    heading:SetText(L["Current plan"])
    heading:SetFullWidth(true)
    frame:AddChild(heading)

    local summary = AceGUI:Create("Label")
    summary:SetFullWidth(true)
    frame:AddChild(summary)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["Paste the string from Export for addon in the UnityWiki raid planner:"])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(8)
    hookPaste(editBox)
    frame:AddChild(editBox)

    local import = AceGUI:Create("Button")
    import:SetText(L["Import"])
    import:SetWidth(140)
    import:SetCallback("OnClick", function() self:Import() end)
    frame:AddChild(import)

    self.frame, self.editBox, self.summary = frame, editBox, summary

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end

    self:Refresh()
    editBox:SetFocus()
end

function ImportWindow:Open()
    if not self.frame then
        self:Create()
    end
end
