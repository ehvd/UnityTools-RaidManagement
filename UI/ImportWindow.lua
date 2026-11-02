local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Import section of the Raid Plan window (UI/RaidPlanWindow.lua): paste the raid plan export of the UnityWiki raid
-- planner, or make a new plan in game (issue #43: a title and raids, Modules/NewPlan.lua), see the current plan, clear
-- it
local ImportWindow = {}
UTRM.ImportWindow = ImportWindow

local RAID_WIDTH = 190   -- three raid check boxes a row

-- A name of Modules/Bosses.lua in the client's language, English where there is no translation
local function translate(text)
    return rawget(L, text) or text
end

-- The new plan's form, kept while the window is closed until a plan is made: the chosen raid slugs (a set) and
-- whether the title was typed (else it follows the raids)
ImportWindow.newRaids = {}
ImportWindow.titleTyped = false

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
                    ImportWindow:SetStatus(format(L["%d characters pasted. Press Import."], #ImportWindow.pasted))
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

-- Stores `plan` (imported or made here), asking first when it replaces one; `done` is the message, "%s" the title
function ImportWindow:Offer(plan, done)
    local current = UTRM:GetModule("PlanImport"):GetPlan()
    if current then
        StaticPopup_Show("UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN", current.event.title, plan.event.title,
            { plan = plan, done = done })
    else
        self:Store(plan, done)
    end
end

function ImportWindow:Store(plan, done)
    UTRM:GetModule("PlanImport"):Store(plan)
    self.pasted = nil
    wipe(self.newRaids)
    self.titleTyped = false
    local host = self.host
    if host then   -- the new plan's form empty again
        self:Detach()
        self:Attach(host)
    end
    self:Refresh(format(done, plan.event.title))
    UTRM.PlanWindow:Show()
end

-- The raids ticked in the form, in the game's order
function ImportWindow:ChosenRaids()
    local slugs, names = {}, {}
    for _, raid in ipairs(ns.Bosses.Raids()) do
        if self.newRaids[raid.slug] then
            slugs[#slugs + 1] = raid.slug
            names[#names + 1] = translate(raid.name)
        end
    end
    return slugs, names
end

-- Create plan: the raid as it is now becomes the night's groups (empty outside a raid)
function ImportWindow:CreatePlan()
    local roster = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            if name then
                roster[#roster + 1] = { name = name, group = subgroup, class = class }
            end
        end
    end
    local plan, problem = ns.NewPlan.Build({
        title = self.title:GetText(),
        raids = (self:ChosenRaids()),
        roster = roster,
        player = UnitName("player"),
        now = GetServerTime(),
        translate = translate,
    })
    if not plan then
        self:SetStatus("|cffff4040" .. (problem == "title" and L["Give the new plan a title."]
            or L["Choose at least one raid for the new plan."]) .. "|r")
        return
    end
    self:Offer(plan, L["Created %s."])
end

-- After a raid is ticked: the default title follows the raids until one is typed, and Create plan needs a raid
function ImportWindow:UpdateNewPlan()
    local slugs, names = self:ChosenRaids()
    if not self.titleTyped then
        self.title:SetText(ns.NewPlan.DefaultTitle(names, date("%Y-%m-%d")))
    end
    self.create:SetDisabled(#slugs == 0)
end

StaticPopupDialogs["UNITYTOOLSRAIDMANAGEMENT_REPLACE_PLAN"] = {
    text = L["Replace the imported raid plan \"%s\" with \"%s\"?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ImportWindow:Store(data.plan, data.done) end,
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
    editBox:SetNumLines(8)
    hookPaste(editBox)
    container:AddChild(editBox)

    local import = AceGUI:Create("Button")
    import:SetText(L["Import"])
    import:SetWidth(140)
    import:SetCallback("OnClick", function() self:Import() end)
    container:AddChild(import)

    -- New plan: a title and the night's raids
    local newHeading = AceGUI:Create("Heading")
    newHeading:SetText(L["New plan"])
    newHeading:SetFullWidth(true)
    container:AddChild(newHeading)

    local title = AceGUI:Create("EditBox")
    title:SetLabel(L["Title"])
    title:DisableButton(true)
    title:SetFullWidth(true)
    title:SetCallback("OnTextChanged", function(_, _, text) self.titleTyped = text ~= "" end)
    container:AddChild(title)

    for _, raid in ipairs(ns.Bosses.Raids()) do
        local box = AceGUI:Create("CheckBox")
        box:SetLabel(translate(raid.name))
        box:SetWidth(RAID_WIDTH)
        box:SetValue(self.newRaids[raid.slug] == true)
        box:SetCallback("OnValueChanged", function(_, _, checked)
            self.newRaids[raid.slug] = checked or nil
            self:UpdateNewPlan()
        end)
        container:AddChild(box)
    end

    local create = AceGUI:Create("Button")
    create:SetText(L["Create plan"])
    create:SetWidth(140)
    create:SetCallback("OnClick", function() self:CreatePlan() end)
    container:AddChild(create)

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

    self.editBox, self.summary, self.clear, self.title, self.create = editBox, summary, clear, title, create
    host:SetStatus("")
    if self.titleTyped then
        title:SetText(self.typedTitle or "")
    end
    self:UpdateNewPlan()
    self:Refresh()
    if self.focusTitle then
        self.focusTitle = nil
        title:SetFocus()
    else
        editBox:SetFocus()
    end
end

function ImportWindow:Detach()
    if self.editBox then unhookPaste(self.editBox) end
    if self.title then self.typedTitle = self.title:GetText() end
    self.host, self.editBox, self.summary, self.clear, self.pasted = nil, nil, nil, nil, nil
    self.title, self.create = nil, nil
end

function ImportWindow:OnPlanChanged()
    self:Refresh()
end

-- The plan window's Import button and `/utrm import`
function ImportWindow:Open()
    UTRM.RaidPlanWindow:Open("import")
end

-- The plan window's New plan button: the Import section with the new plan's title focused
function ImportWindow:OpenNewPlan()
    self.focusTitle = true
    UTRM.RaidPlanWindow:Open("import")
end
