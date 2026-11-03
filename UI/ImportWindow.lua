local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Import section of the Raid Plan window (UI/RaidPlanWindow.lua): paste the raid plan export of the UnityWiki raid
-- planner, see the current plan, clear it
local ImportWindow = {}
UTRM.ImportWindow = ImportWindow

-- A night's export is up to ~60,000 characters. Rendering that much text in a multi-line edit box freezes the
-- client, so (like the import of WeakAuras) the edit box keeps only the first bytes while OnChar, which still fires
-- for every pasted character, collects the whole paste; the paste ends on the next frame. The Gargul section uses it
-- too (a loot priority string is as long).
local SHOWN_BYTES = 2500
local MIN_PASTE = 50   -- fewer characters in one frame is typing, not a paste

-- Collects long pastes into the MultiLineEditBox `widget`: `onPaste(text)` gets the whole paste when one ends, or nil
-- when the characters were typing
function ImportWindow.HookPaste(widget, onPaste)
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
                local pasted = count >= MIN_PASTE and table.concat(buffer) or nil
                count = 0
                onPaste(pasted)
            end)
        end
        count = count + 1
        buffer[count] = c
    end)
end

-- AceGUI widgets are shared with other addons: leave the edit box as it was
function ImportWindow.UnhookPaste(widget)
    local editBox = widget.editBox
    editBox:SetScript("OnChar", nil)
    editBox:SetScript("OnUpdate", nil)
    editBox:SetMaxBytes(0)
end

function ImportWindow:SetStatus(text)
    if self.host then self.host:SetStatus(text) end
end

function ImportWindow:Refresh(status)
    if not self.host then return end
    local plan = UTRM:GetModule("PlanImport"):GetPlan()
    self.summary:SetText(UTRM:GetModule("PlanImport"):Summary(plan))
    self.clear:SetDisabled(not plan)
    if status then
        self:SetStatus(status)
    end
    self.host.container:DoLayout()
end

function ImportWindow:Import()
    local PlanImport = UTRM:GetModule("PlanImport")
    local plan, message = PlanImport:Read(self.pasted or self.editBox:GetText())
    if not plan then
        self:SetStatus("|cffff4040" .. message .. "|r")
        return
    end
    self:Offer(plan, L["Imported %s."])
end

-- Stores `plan` (imported here or made in the New plan section, UI/NewPlanSection.lua), asking first when it replaces
-- one. `done` is the status message ("%s" the title); `onStored()` runs once the plan is stored.
function ImportWindow:Offer(plan, done, onStored)
    local current = UTRM:GetModule("PlanImport"):GetPlan()
    if current then
        StaticPopup_Show("UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN", current.event.title, plan.event.title,
            { plan = plan, done = done, onStored = onStored })
    else
        self:Store(plan, done, onStored)
    end
end

function ImportWindow:Store(plan, done, onStored)
    UTRM:GetModule("PlanImport"):Store(plan)
    self.pasted = nil
    if self.editBox then
        self.editBox:SetText("")
    end
    if onStored then onStored() end
    UTRM.RaidPlanWindow:SetStatus(format(done, plan.event.title))
    UTRM.PlanWindow:Show()
end

StaticPopupDialogs["UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN"] = {
    text = L["Replace the imported raid plan \"%s\" with \"%s\"?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ImportWindow:Store(data.plan, data.done, data.onStored) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Fills the section in the Raid Plan window (`host`)
function ImportWindow:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(L["Paste the string from Export for addon in the UnityWiki raid planner:"])
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(12)
    ImportWindow.HookPaste(editBox, function(pasted)
        self.pasted = pasted
        if pasted then
            self:SetStatus(format(L["%d characters pasted. Press Import."], #pasted))
        end
    end)
    container:AddChild(editBox)

    local import = AceGUI:Create("Button")
    import:SetText(L["Import"])
    import:SetWidth(140)
    import:SetCallback("OnClick", function() self:Import() end)
    container:AddChild(import)

    local heading = AceGUI:Create("Heading")
    heading:SetText(L["Current plan"])
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local summary = AceGUI:Create("Label")
    summary:SetFullWidth(true)
    summary:SetFontObject(GameFontHighlight)
    container:AddChild(summary)

    local clear = AceGUI:Create("Button")
    clear:SetText(L["Clear raid plan"])
    clear:SetWidth(140)
    clear:SetCallback("OnClick", function() UTRM.PlanWindow:ConfirmClear() end)
    container:AddChild(clear)

    self.editBox, self.summary, self.clear = editBox, summary, clear
    host:SetStatus("")
    self:Refresh()
    editBox:SetFocus()
end

function ImportWindow:Detach()
    if self.editBox then ImportWindow.UnhookPaste(self.editBox) end
    self.host, self.editBox, self.summary, self.clear, self.pasted = nil, nil, nil, nil, nil
end

function ImportWindow:OnPlanChanged()
    self:Refresh()
end

-- The plan window's Import button and `/utrm import`
function ImportWindow:Open()
    UTRM.RaidPlanWindow:Open("import")
end
