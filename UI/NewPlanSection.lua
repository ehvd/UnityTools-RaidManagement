local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The New plan section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #43): makes a raid plan in game from a
-- title and the night's raids (Modules/NewPlan.lua). It replaces the current plan like an import
-- (ImportWindow:Offer).
local NewPlanSection = {}
UTRM.NewPlanSection = NewPlanSection

local RAID_WIDTH = 190   -- three raid check boxes a row

-- A name of Modules/Bosses.lua in the client's language, English where there is no translation
local function translate(text)
    return rawget(L, text) or text
end

-- The form, kept while the window is closed until a plan is made: the chosen raid slugs (a set), and the typed
-- title (nil while the title follows the raids)
NewPlanSection.raids = {}
NewPlanSection.typedTitle = nil

function NewPlanSection:SetStatus(text)
    if self.host then self.host:SetStatus(text) end
end

-- The raids ticked in the form, in the game's order
function NewPlanSection:ChosenRaids()
    local slugs, names = {}, {}
    for _, raid in ipairs(ns.Bosses.Raids()) do
        if self.raids[raid.slug] then
            slugs[#slugs + 1] = raid.slug
            names[#names + 1] = translate(raid.name)
        end
    end
    return slugs, names
end

-- Create plan: the raid as it is now becomes the night's groups (empty outside a raid)
function NewPlanSection:CreatePlan()
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
    UTRM.ImportWindow:Offer(plan, L["Created %s."], function() self:Reset() end)
end

-- After a plan is made: the form empty again
function NewPlanSection:Reset()
    wipe(self.raids)
    self.typedTitle = nil
    local host = self.host
    if host then
        self:Detach()
        self:Attach(host)
    end
end

-- After a raid is ticked: the default title follows the raids until one is typed, and Create plan needs a raid
function NewPlanSection:Update()
    local slugs, names = self:ChosenRaids()
    if not self.typedTitle then
        self.title:SetText(ns.NewPlan.DefaultTitle(names, date("%Y-%m-%d")))
    end
    self.create:SetDisabled(#slugs == 0)
end

-- Fills the section in the Raid Plan window (`host`)
function NewPlanSection:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()

    local title = AceGUI:Create("EditBox")
    title:SetLabel(L["Title"])
    title:DisableButton(true)
    title:SetFullWidth(true)
    container:AddChild(title)

    for _, raid in ipairs(ns.Bosses.Raids()) do
        local box = AceGUI:Create("CheckBox")
        box:SetLabel(translate(raid.name))
        box:SetWidth(RAID_WIDTH)
        box:SetValue(self.raids[raid.slug] == true)
        box:SetCallback("OnValueChanged", function(_, _, checked)
            self.raids[raid.slug] = checked or nil
            self:Update()
        end)
        container:AddChild(box)
    end

    local create = AceGUI:Create("Button")
    create:SetText(L["Create plan"])
    create:SetWidth(140)
    create:SetCallback("OnClick", function() self:CreatePlan() end)
    container:AddChild(create)

    self.title, self.create = title, create
    host:SetStatus("")
    if self.typedTitle then title:SetText(self.typedTitle) end
    self:Update()
    -- Set after the text above, so only typing counts; an emptied title follows the raids again
    title:SetCallback("OnTextChanged", function(_, _, text) self.typedTitle = text ~= "" and text or nil end)
    container:DoLayout()
    title:SetFocus()
end

function NewPlanSection:Detach()
    self.host, self.title, self.create = nil, nil, nil
end

-- The plan window's New plan button
function NewPlanSection:Open()
    UTRM.RaidPlanWindow:Open("newplan")
end
