local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Encounters section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #44): the plan's encounter list, one
-- row per encounter in plan order (rename in place, move up or down, remove), and below it adding a boss of the boss
-- table (Modules/Bosses.lua, issue #43, when it is there) or a custom encounter with only a name. Every change is
-- saved at once as an edit of the plan (PlanImport:Edit), so it syncs to the raid; the list changes are in
-- Modules/EncounterList.lua.
local EncountersSection = {}
UTRM.EncountersSection = EncountersSection

local REMOVE_POPUP = "UNITYTOOLSRAIDMANAGEMENT_REMOVE_ENCOUNTER"
-- The list takes the section's height that the Add part below it leaves (the section is as tall as the groups
-- editor, UI/RaidPlanWindow.lua), at least a few rows; longer lists scroll
local MIN_LIST_HEIGHT = 150
local FLOW_GAP = 3                      -- AceGUI's Flow layout puts 3 px between rows
local LABEL_WIDTH = 110
local FIELD_WIDTH = 260                 -- the Add part's dropdowns and name box
local BUTTON_WIDTH = 120
-- A row (its own full-width group, so it never flows into the next): "15." right-aligned, a gap, the name, the hint,
-- three small buttons; 488 px, inside the list's scroll frame with its scroll bar shown
local PLACE_WIDTH, PLACE_GAP = 30, 6
local NAME_WIDTH = 220
local HINT_WIDTH = 160
local SMALL_BUTTON = 24
local GREY = "|cff999999"
local CUSTOM = ""                       -- the Raid dropdown's value for a custom encounter

-- A name of Modules/Bosses.lua in the client's language, English where there is no translation
local function translate(text)
    return rawget(L, text) or text
end

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

---------------------------------------------------------------------------------------- small buttons ---

-- A row's small buttons in Blizzard's own art: the scroll bar's up and down arrows, the close button's X. An AceGUI
-- widget of its own, so the rows' scroll frame lays them out with the rest.
local ICON_BUTTON = "UTRM-IconButton"
local ART = {
    up = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-",
    down = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-",
    remove = "Interface\\Buttons\\UI-Panel-MinimizeButton-",
}

do
    local methods = {
        OnAcquire = function(self)
            self:SetWidth(SMALL_BUTTON)
            self:SetHeight(SMALL_BUTTON)
            self:SetDisabled(false)
            self.tooltip = nil
        end,
        SetKind = function(self, kind)
            local art, frame = ART[kind], self.frame
            frame:SetNormalTexture(art .. "Up")
            frame:SetPushedTexture(art .. "Down")
            frame:SetDisabledTexture(art .. "Disabled")
            frame:SetHighlightTexture(art .. "Highlight", "ADD")
        end,
        SetDisabled = function(self, disabled)
            self.frame:SetEnabled(not disabled)
        end,
        SetTooltip = function(self, text)
            self.tooltip = text
        end,
    }

    local function constructor()
        local frame = CreateFrame("Button", nil, UIParent)
        frame:Hide()
        frame:SetScript("OnClick", function(button) button.obj:Fire("OnClick") end)
        frame:SetScript("OnEnter", function(button)
            if not button.obj.tooltip then return end
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button.obj.tooltip)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local widget = { frame = frame, type = ICON_BUTTON }
        for name, method in pairs(methods) do widget[name] = method end
        frame.obj = widget
        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(ICON_BUTTON, constructor, 1)
end

--------------------------------------------------------------------------------------------- helpers ---

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

local function label(container, text, width, font)
    local widget = AceGUI:Create("Label")
    widget:SetFontObject(font or GameFontNormal)
    widget:SetWidth(width)
    widget:SetText(text)
    container:AddChild(widget)
    return widget
end

local function labelled(container, text, widget)
    label(container, text, LABEL_WIDTH)
    container:AddChild(widget)
end

local function button(container, text, onClick)
    local widget = AceGUI:Create("Button")
    widget:SetText(text)
    widget:SetWidth(BUTTON_WIDTH)
    widget:SetCallback("OnClick", onClick)
    container:AddChild(widget)
    return widget
end

local function smallButton(container, kind, tooltip, disabled, onClick)
    local widget = AceGUI:Create(ICON_BUTTON)
    widget:SetKind(kind)
    widget:SetTooltip(tooltip)
    widget:SetDisabled(disabled)
    widget:SetCallback("OnClick", onClick)
    container:AddChild(widget)
end

-- A row's name: renamed on Enter or when the box loses focus; Escape puts the name back. The edit box is AceGUI's
-- (pooled), so its focus-lost and Escape scripts go back to AceGUI's when the row is released.
local function nameBox(text, onRename)
    local widget = AceGUI:Create("EditBox")
    widget:SetWidth(NAME_WIDTH)
    widget:SetMaxLetters(60)
    widget:DisableButton(true)
    widget:SetText(text)
    local box = widget.editbox
    local escape = box:GetScript("OnEscapePressed")
    widget:SetCallback("OnEnterPressed", function() AceGUI:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(frame)
        frame:SetText(text)
        escape(frame)
    end)
    box:SetScript("OnEditFocusLost", function(frame)
        if not EncountersSection.building then onRename(frame:GetText()) end
    end)
    widget:SetCallback("OnRelease", function()
        box:SetScript("OnEditFocusLost", nil)
        box:SetScript("OnEscapePressed", escape)
    end)
    return widget
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

function EncountersSection:Rename(key, name)
    local ok, why = edit(function(plan) return ns.EncounterList.Rename(plan, key, name) end)
    if not ok then
        -- An empty name: the row shows the name it keeps
        if why == "label" and self.host then self:Attach(self.host) end
        return self:Fail(why)
    end
    self:Saved(format(L["Renamed to %s"], strtrim(name)))
end

-- The moved row is highlighted when the list redraws (the plan edit redraws it)
function EncountersSection:Move(key, by)
    self.highlight = key
    local index, why = edit(function(plan) return ns.EncounterList.Move(plan, key, by) end)
    if not index then return self:Fail(why) end
    self:Saved(format(L["Moved %s to place %d"], currentPlan().encounters[index].label, index))
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

function EncountersSection:ConfirmRemove(key)
    local plan = currentPlan()
    local index = plan and ns.EncounterList.IndexOf(plan, key)
    if not index then return end
    StaticPopupDialogs[REMOVE_POPUP].text = L["Remove the encounter %s from the raid plan?"]
    StaticPopup_Show(REMOVE_POPUP, plan.encounters[index].label, nil, key)
end

-- The plan window moves on when the active encounter goes: the next one is activated (its note and groups sent)
function EncountersSection:Remove(key)
    local plan = currentPlan()
    local wasActive = plan and plan.active == key
    local removed, active = edit(function(edited) return ns.EncounterList.Remove(edited, key) end)
    if not removed then return self:Fail(active) end
    if wasActive and active then UTRM.PlanWindow:Activate(active) end
    self:Saved(format(L["Removed %s"], removed.label))
end

-- The new encounter is the list's last row, highlighted and scrolled into view
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
    self.highlight, self.name = encounter.key, boss and self.name or ""
    self.scroll.offset = math.huge
    self:Attach(self.host)
    self:Saved(format(L["Added %s"], encounter.label))
end

-- The boss picker: choosing a raid picks its first boss, choosing a boss puts its name in the Name box
function EncountersSection:ChooseRaid(slug)
    self.raid, self.boss, self.name = slug, nil, ""
    if slug ~= CUSTOM then
        local first = ns.Bosses.Of(slug)[1]
        if first then self.boss, self.name = first.key, translate(first.label) end
    end
    self:Attach(self.host)
end

function EncountersSection:ChooseBoss(key)
    self.boss = key
    for _, entry in ipairs(ns.Bosses.Of(self.raid)) do
        if entry.key == key then self.name = translate(entry.label) end
    end
    self:Attach(self.host)
end

------------------------------------------------------------------------------------------------ section ---

-- The rows: "n.", the name, a grey hint (boss and its encounter ID, or custom; active), up, down, remove. The scroll
-- position is kept across redraws. Returns the list's box (Attach sizes it).
function EncountersSection:AddList(container, plan)
    local box = AceGUI:Create("InlineGroup")
    box:SetTitle(L["Encounters"])
    box:SetFullWidth(true)
    box:SetAutoAdjustHeight(false)
    box:SetHeight(MIN_LIST_HEIGHT)
    box:SetLayout("Fill")
    container:AddChild(box)
    local rows = AceGUI:Create("ScrollFrame")
    rows:SetLayout("Flow")
    rows:SetStatusTable(self.scroll)
    box:AddChild(rows)

    local count = #plan.encounters
    if count == 0 then
        label(rows, L["The plan has no encounters."], 400, GameFontHighlight)
        return box
    end
    for i, encounter in ipairs(plan.encounters) do
        local key = encounter.key
        local place = format("%d.", i)
        if key == self.highlight then place = "|cff40ff40" .. place .. "|r" end
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        rows:AddChild(row)
        label(row, place, PLACE_WIDTH, key == self.highlight and GameFontNormal or GameFontHighlight):SetJustifyH("RIGHT")
        label(row, "", PLACE_GAP)
        row:AddChild(nameBox(encounter.label, function(name) self:Rename(key, name) end))
        local hint = encounter.encounterId and format(L["Boss, ID %d"], encounter.encounterId) or L["Custom"]
        if key == plan.active then hint = hint .. "  " .. L["(active)"] end
        label(row, "  " .. GREY .. hint .. "|r", HINT_WIDTH, GameFontHighlightSmall)
        smallButton(row, "up", L["Move up"], i == 1, function() self:Move(key, -1) end)
        smallButton(row, "down", L["Move down"], i == count, function() self:Move(key, 1) end)
        smallButton(row, "remove", L["Remove"], false, function() self:ConfirmRemove(key) end)
    end
    return box
end

function EncountersSection:AddNew(container, plan)
    heading(container, L["Add an encounter"])
    local Bosses = ns.Bosses
    if Bosses then
        local raids, raidOrder = { [CUSTOM] = L["Custom encounter"] }, { CUSTOM }
        for _, raid in ipairs(ns.EncounterList.Raids(Bosses, plan)) do
            raids[raid.slug] = translate(raid.name)
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
                bosses[entry.key] = translate(entry.label)
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

    local name = AceGUI:Create("EditBox")
    name:SetWidth(FIELD_WIDTH)
    name:SetMaxLetters(60)
    name:DisableButton(true)
    name:SetText(self.name)
    name:SetCallback("OnTextChanged", function(_, _, value) self.name = value end)
    name:SetCallback("OnEnterPressed", function(widget, _, value)
        widget:ClearFocus()
        self.name = value
        self:Add()
    end)
    labelled(container, L["Name"], name)
    button(container, L["Add"], function() self:Add() end)
end

function EncountersSection:Attach(host)
    self.host = host
    self.building = true            -- releasing the rows takes the focus from a name box: no rename then
    local container = host.container
    container:ReleaseChildren()
    local plan = currentPlan()
    self.scroll = self.scroll or {}
    self.raid = self.raid or CUSTOM
    self.name = self.name or ""
    local list = self:AddList(container, plan)
    local form = AceGUI:Create("SimpleGroup")
    form:SetFullWidth(true)
    form:SetLayout("Flow")
    container:AddChild(form)
    self:AddNew(form, plan)
    -- The Add part at the bottom of the section, the list in the rest
    local height = host.content:GetHeight()
    if not height or height <= 0 then height = UTRM.GroupEditor.HEIGHT end
    list:SetHeight(math.max(MIN_LIST_HEIGHT, floor(height - form.frame:GetHeight() - 2 * FLOW_GAP)))
    container:DoLayout()
    self.building = false
end

function EncountersSection:Detach()
    self.building = true
    self.host = nil
    self.highlight = nil
end

function EncountersSection:OnPlanChanged()
    if self.host then self:Attach(self.host) end
end
