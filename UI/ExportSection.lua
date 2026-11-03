local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Export section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #46): the plan as one string in UnityWiki's
-- own format (PlanImport:Export), to import on another client or bring back to the raid planner. It is made when the
-- section opens and again when the plan changes, so the box always holds the plan as it is now.
local ExportSection = {}
UTRM.ExportSection = ExportSection

-- Fills the box with a new export, all selected for Ctrl+C: the game has no clipboard API. A night's string (up to
-- ~60,000 characters) goes in with one SetText, one layout of the text; a paste is slow because it lays the text out
-- again for every character (UI/ImportWindow.lua).
function ExportSection:Refresh()
    if not self.editBox then return end
    local PlanImport = UTRM:GetModule("PlanImport")
    local plan = PlanImport:GetPlan()
    if not plan then return end
    self.text = PlanImport:Export(plan)
    self.editBox:SetText(self.text)
    self.editBox:SetFocus()
    self.editBox:HighlightText()
    self.host:SetStatus(format(L["Exported %s: %d characters. Ctrl+C to copy."], plan.event.title, #self.text))
end

function ExportSection:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()

    -- Read only: what is typed into it is undone, and focusing it selects all of it again
    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["The raid plan as one string. Ctrl+C to copy:"])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(26)
    editBox:SetMaxLetters(0)
    editBox.editBox:SetMaxBytes(0)   -- no limit (a widget from AceGUI's pool may have had the paste box's)
    editBox:SetCallback("OnTextChanged", function(widget)
        widget:SetText(self.text or "")
        widget:HighlightText()
    end)
    editBox:SetCallback("OnEditFocusGained", function(widget) widget:HighlightText() end)
    container:AddChild(editBox)

    self.editBox = editBox
    self:Refresh()
end

function ExportSection:Detach()
    self.host, self.editBox, self.text = nil, nil, nil
end

function ExportSection:OnPlanChanged()
    self:Refresh()
end
