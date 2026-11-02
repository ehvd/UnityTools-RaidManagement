local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Encounters section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #44): the plan's encounter list.
-- Rename, move up or down and remove the chosen encounter; add a boss of the boss table (Modules/Bosses.lua, issue
-- #43, when it is there) or a custom encounter with only a name. Every change is saved at once as an edit of the
-- plan (PlanImport:Edit), so it syncs to the raid; the list changes are in Modules/EncounterList.lua.
local EncountersSection = {}
UTRM.EncountersSection = EncountersSection

local REMOVE_POPUP = "UNITYTOOLSRAIDMANAGEMENT_REMOVE_ENCOUNTER"
local LABEL_WIDTH = 110
local FIELD_WIDTH = 260                 -- the encounter dropdown's width
local BUTTON_WIDTH = 120
local GREY = "|cff999999"
local CUSTOM = ""                       -- the Raid dropdown's value for a custom encounter

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

local function heading(container, text)
    local widget = AceGUI:Create("Heading")
    widget:SetText(text)
    widget:SetFullWidth(true)
    container:AddChild(widget)
end

-- The rest of the row stays empty: what follows starts below it
local function newRow(container)
    local rest = AceGUI:Create("Label")
    rest:SetFullWidth(true)
    container:AddChild(rest)
end

local function labelled(container, text, widget)
    local label = AceGUI:Create("Label")
    label:SetFontObject(GameFontNormal)
    label:SetWidth(LABEL_WIDTH)
    label:SetText(text)
    container:AddChild(label)
    container:AddChild(widget)
end

local function button(container, text, disabled, onClick)
    local widget = AceGUI:Create("Button")
    widget:SetText(text)
    widget:SetWidth(BUTTON_WIDTH)
    widget:SetDisabled(disabled)
    widget:SetCallback("OnClick", onClick)
    container:AddChild(widget)
    return widget
end

local function nameBox(text, onEnter, onChange)
    local box = AceGUI:Create("EditBox")
    box:SetWidth(FIELD_WIDTH)
    box:SetMaxLetters(60)
    box:SetText(text or "")
    box:SetCallback("OnEnterPressed", function(widget, _, value)
        widget:ClearFocus()
        onEnter(value)
    end)
    if onChange then box:SetCallback("OnTextChanged", function(_, _, value) onChange(value) end) end
    return box
end

-- Runs `change(plan)` (an EncounterList function's results) as an edit of the plan. Returns its results, or nil and
-- why (the message of PlanImport:Edit, or EncounterList's reason).
local function edit(change)
    local results
    local ok, message = UTRM:GetModule("PlanImport"):Edit(function(plan)
        results = { change(plan) }
        if results[1] == nil then return false end
    end)
    if not ok then return nil, message or (results and results[2]) end
    return unpack(results)
end

local PROBLEMS = {
    label = function() return L["Enter a name first."] end,
    encounter = function() return L["This encounter is no longer in the raid plan."] end,
}

function EncountersSection:Fail(why)
    local text = PROBLEMS[why] and PROBLEMS[why]() or (why ~= "unchanged" and why ~= "edge" and why) or nil
    if text then self.host:SetStatus("|cffff4040" .. text .. "|r") end
end

function EncountersSection:Saved(text)
    self.host:SetStatus(UTRM.RaidPlanWindow:SavedMessage(text))
end

------------------------------------------------------------------------------------------------ actions ---

function EncountersSection:Rename(label)
    local key = self.key
    local ok, why = edit(function(plan) return ns.EncounterList.Rename(plan, key, label) end)
    if not ok then return self:Fail(why) end
    self:Saved(format(L["Renamed to %s"], strtrim(label)))
end

function EncountersSection:Move(by)
    local key = self.key
    local index, why = edit(function(plan) return ns.EncounterList.Move(plan, key, by) end)
    if not index then return self:Fail(why) end
    self:Saved(format(L["Moved to place %d"], index))
end

-- Asks first, naming the encounter
StaticPopupDialogs[REMOVE_POPUP] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, key) EncountersSection:Remove(key) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function EncountersSection:ConfirmRemove()
    local plan = currentPlan()
    local index = plan and ns.EncounterList.IndexOf(plan, self.key)
    if not index then return end
    StaticPopupDialogs[REMOVE_POPUP].text = L["Remove the encounter %s from the raid plan?"]
    StaticPopup_Show(REMOVE_POPUP, plan.encounters[index].label, nil, self.key)
end

-- The plan window moves on when the active encounter goes: the next one is activated (its note and groups sent)
function EncountersSection:Remove(key)
    local plan = currentPlan()
    local before = plan and ns.EncounterList.IndexOf(plan, key)
    if before then
        -- What stays chosen here: the encounter that takes its place
        local following = plan.encounters[before + 1] or plan.encounters[before - 1]
        self.key = following and following.key
    end
    local wasActive = plan and plan.active == key
    local removed, active = edit(function(edited) return ns.EncounterList.Remove(edited, key) end)
    if not removed then return self:Fail(active) end
    if wasActive and active then UTRM.PlanWindow:Activate(active) end
    self:Saved(format(L["Removed %s"], removed.label))
end

function EncountersSection:Add()
    local boss
    if self.raid ~= CUSTOM and self.boss then
        for _, entry in ipairs(ns.Bosses.Of(self.raid)) do
            if entry.key == self.boss then
                boss = { slug = self.raid, key = entry.key, encounterId = entry.encounterId }
            end
        end
    end
    local name = self.name
    local index, why = edit(function(plan) return ns.EncounterList.Add(plan, name, boss) end)
    if not index then return self:Fail(why) end
    local encounter = currentPlan().encounters[index]
    self.key, self.name = encounter.key, boss and self.name or ""
    self:Attach(self.host)
    self:Saved(format(L["Added %s"], encounter.label))
end

-- The boss picker: choosing a raid picks its first boss, choosing a boss puts its name in the Name box
function EncountersSection:ChooseRaid(slug)
    self.raid, self.boss, self.name = slug, nil, ""
    if slug ~= CUSTOM then
        local first = ns.Bosses.Of(slug)[1]
        if first then self.boss, self.name = first.key, first.label end
    end
    self:Attach(self.host)
end

function EncountersSection:ChooseBoss(key)
    self.boss = key
    for _, entry in ipairs(ns.Bosses.Of(self.raid)) do
        if entry.key == key then self.name = entry.label end
    end
    self:Attach(self.host)
end

------------------------------------------------------------------------------------------------ section ---

function EncountersSection:AddList(container, plan)
    heading(container, L["Encounters"])
    local count = #plan.encounters
    if count == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetFontObject(GameFontHighlight)
        empty:SetText(L["The plan has no encounters."])
        container:AddChild(empty)
        return
    end
    local host = self.host
    host:AddEncounterDropdown(container, self.key, function(key)
        self.key = key
        self:Attach(host)
    end, function() return false end)

    local index = ns.EncounterList.IndexOf(plan, self.key)
    local encounter = plan.encounters[index]
    labelled(container, L["Name"], nameBox(encounter.label, function(value) self:Rename(value) end))
    newRow(container)

    local about = encounter.encounterId and format(L["Boss, encounter ID %d"], encounter.encounterId)
        or L["Custom encounter"]
    if plan.fallback == encounter.key then about = about .. ", " .. L["the note after a kill"] end
    local info = AceGUI:Create("Label")
    info:SetFullWidth(true)
    info:SetFontObject(GameFontHighlightSmall)
    info:SetText(GREY .. about .. "|r")
    container:AddChild(info)

    button(container, L["Move up"], index == 1, function() self:Move(-1) end)
    button(container, L["Move down"], index == count, function() self:Move(1) end)
    button(container, L["Remove"], false, function() self:ConfirmRemove() end)
end

function EncountersSection:AddNew(container, plan)
    heading(container, L["Add an encounter"])
    local Bosses = ns.Bosses
    if Bosses then
        local raids, raidOrder = { [CUSTOM] = L["Custom encounter"] }, { CUSTOM }
        for _, raid in ipairs(ns.EncounterList.Raids(Bosses, plan)) do
            raids[raid.slug] = raid.name
            raidOrder[#raidOrder + 1] = raid.slug
        end
        if not raids[self.raid] then self.raid = CUSTOM end
        local raid = AceGUI:Create("Dropdown")
        raid:SetWidth(FIELD_WIDTH)
        raid:SetList(raids, raidOrder)
        raid:SetValue(self.raid)
        raid:SetCallback("OnValueChanged", function(_, _, value) self:ChooseRaid(value) end)
        labelled(container, L["Raid"], raid)
        newRow(container)

        if self.raid ~= CUSTOM then
            local bosses, bossOrder = {}, {}
            for i, entry in ipairs(Bosses.Of(self.raid)) do
                bosses[entry.key] = entry.label
                    .. (ns.EncounterList.HasBoss(plan, entry.encounterId) and ("  " .. GREY .. L["(in the plan)"] .. "|r")
                        or "")
                bossOrder[i] = entry.key
            end
            local boss = AceGUI:Create("Dropdown")
            boss:SetWidth(FIELD_WIDTH)
            boss:SetList(bosses, bossOrder)
            boss:SetValue(self.boss)
            boss:SetCallback("OnValueChanged", function(_, _, value) self:ChooseBoss(value) end)
            labelled(container, L["Boss"], boss)
            newRow(container)
        end
    end

    local name = nameBox(self.name, function(value)
        self.name = value
        self:Add()
    end, function(value) self.name = value end)
    name:DisableButton(true)
    labelled(container, L["Name"], name)
    button(container, L["Add"], false, function() self:Add() end)
end

function EncountersSection:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()
    local plan = currentPlan()
    self.key = host:EncounterToEdit(self.key)
    self.raid = self.raid or CUSTOM
    self.name = self.name or ""
    self:AddList(container, plan)
    self:AddNew(container, plan)
end

function EncountersSection:Detach()
    self.host = nil
end

function EncountersSection:OnPlanChanged()
    if self.host then self:Attach(self.host) end
end
