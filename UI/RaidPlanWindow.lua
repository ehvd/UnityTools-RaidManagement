local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")

-- The Raid Plan window (issue #37): everything about the raid plan in one place. Blizzard's options list on the left
-- (AceGUI's TreeGroup, as in the Interface Options) picks a section: Groups, Assignments, Notes, Gargul, Config,
-- New plan, Import. The editing sections keep their own drafts with their own Save; leaving a section (or its
-- encounter) with unsaved changes asks first, and the list marks such a section with *. Choosing an encounter here
-- only picks what is edited: the active encounter changes in the plan window alone.
local RaidPlanWindow = UTRM:NewModule("RaidPlanWindow", "AceEvent-3.0")
UTRM.RaidPlanWindow = RaidPlanWindow

local FRAME_GLOBAL = "UnityToolsRaidManagementRaidPlanFrame"
local DISCARD_POPUP = "UNITYTOOLSRAIDMANAGEMENT_DISCARD_SECTION"
-- Layout (1 px = 1 UI pixel at 100% scale): AceGUI's Frame (content 17 px in, 27 px from the top, 40 px from the
-- bottom for the status bar), the list 170 wide, the section 10 px inside its border. The section is as big as the
-- groups editor, the largest one.
local TREE_WIDTH = 170
local LABEL_WIDTH = 110
local DROPDOWN_WIDTH = 260              -- the plan window's encounter box
local GREY = "|cff999999"

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

local function settings()
    return UTRM.db.profile.raidPlanWindow
end

----------------------------------------------------------------------------------------------- sections ---

-- The plan-wide Gargul loot priorities: whether Gargul has them, and importing them
local Gargul = {}

function Gargul:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()
    local plan = currentPlan()
    local module = UTRM:GetModule("Gargul")
    local _, unusable = module:GetAddon()
    local state = module:GetState(plan)

    local heading = AceGUI:Create("Heading")
    heading:SetText(L["Loot priorities"])
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local text
    if not plan.gargul then
        text = L["The raid plan has no Gargul loot priorities."]
    elseif unusable then
        text = unusable
    elseif state == "current" then
        text = "|cff40ff40" .. L["Gargul: loot priorities are up to date"] .. "|r"
    else
        text = "|cffffa040" .. L["Gargul: import the loot priorities"] .. "|r"
    end
    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    label:SetFontObject(GameFontHighlight)
    label:SetText(text)
    container:AddChild(label)

    local import = AceGUI:Create("Button")
    import:SetText(L["Import into Gargul"])
    import:SetWidth(180)
    import:SetDisabled(not (plan.gargul and not unusable))
    import:SetCallback("OnClick", function()
        local ok, message = module:ImportPlan(currentPlan())
        self:Attach(host)
        host:SetStatus(ok and message or ("|cffff4040" .. (message or "") .. "|r"))
    end)
    container:AddChild(import)
    host:SetStatus("")
end

function Gargul:Detach()
    self.host = nil
end

function Gargul:OnPlanChanged()
    if self.host then self:Attach(self.host) end
end

-- Settings that apply at once: the switch after a kill (a plan edit, it syncs), the plan window, the minimap button
-- and the sync
local Config = {}

local function heading(container, text)
    local widget = AceGUI:Create("Heading")
    widget:SetText(text)
    widget:SetFullWidth(true)
    container:AddChild(widget)
end

local function checkBox(container, text, value, onChange)
    local widget = AceGUI:Create("CheckBox")
    widget:SetLabel(text)
    widget:SetFullWidth(true)
    widget:SetValue(value)
    widget:SetCallback("OnValueChanged", function(_, _, checked) onChange(checked) end)
    container:AddChild(widget)
    return widget
end

local function labelled(container, text, widget)
    local label = AceGUI:Create("Label")
    label:SetFontObject(GameFontHighlight)
    label:SetWidth(LABEL_WIDTH)
    label:SetText(text)
    container:AddChild(label)
    container:AddChild(widget)
end

-- Where the sync stands for this player: whether their edits reach the raid
local function syncText()
    if not IsInRaid() then
        return L["Not in a raid: your edits stay on your client until you lead a raid or assist in one."]
    elseif UTRM:GetModule("Sync"):CanSync() then
        return L["You are raid leader or assistant: your edits sync to the raid."]
    end
    return "|cffffa040"
        .. L["You are not raid leader or assistant: your edits stay on your client, and the leader's plan may replace them."]
        .. "|r"
end

function Config:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()
    local plan = currentPlan()
    local window = UTRM.PlanWindow

    if plan and #plan.encounters > 0 then
        heading(container, L["After a kill"])
        local list, order = { [""] = NONE }, { "" }
        for i, encounter in ipairs(plan.encounters) do
            list[encounter.key] = format("%d. %s", i, encounter.label)
            order[#order + 1] = encounter.key
        end
        local fallback = AceGUI:Create("Dropdown")
        fallback:SetWidth(DROPDOWN_WIDTH)
        fallback:SetList(list, order)
        local current = ns.FallbackRules.Encounter(plan)
        fallback:SetValue(current and current.key or "")
        fallback:SetCallback("OnValueChanged", function(_, _, key)
            local chosen
            for _, encounter in ipairs(currentPlan().encounters) do
                if encounter.key == key then chosen = encounter end
            end
            window:SetFallback(chosen)
            host:SetStatus(RaidPlanWindow:SavedMessage(chosen and format(L["After a kill: switches to %s"], chosen.label)
                or L["After a kill: no switch"]))
        end)
        labelled(container, L["Switch the note to"], fallback)
    end

    heading(container, L["Mini window"])
    checkBox(container, L["Lock position"], window:IsLocked(), function(checked) window:SetLocked(checked) end)
    local scales, scaleOrder = {}, {}
    for i, value in ipairs(window.SCALES) do
        scales[value] = format("%d%%", value * 100)
        scaleOrder[i] = value
    end
    local scale = AceGUI:Create("Dropdown")
    scale:SetWidth(120)
    scale:SetList(scales, scaleOrder)
    scale:SetValue(window:GetScale())
    scale:SetCallback("OnValueChanged", function(_, _, value) window:SetScale(value) end)
    labelled(container, L["Scale"], scale)
    local minimap = UTRM:GetModule("Minimap")
    checkBox(container, L["Show the minimap button"], minimap:IsShown(), function(checked) minimap:SetShown(checked) end)

    heading(container, L["Sync"])
    local sync = AceGUI:Create("Label")
    sync:SetFullWidth(true)
    sync:SetFontObject(GameFontHighlight)
    sync:SetText(syncText())
    container:AddChild(sync)
    local force = AceGUI:Create("Button")
    force:SetText(L["Force sync"])
    force:SetWidth(150)
    force:SetDisabled(not (plan and UTRM:GetModule("Sync"):CanSync()))
    force:SetCallback("OnClick", function()
        local ok, message = UTRM:GetModule("Sync"):ForceSync()
        if message then host:SetStatus(ok and message or ("|cffff4040" .. message .. "|r")) end
    end)
    container:AddChild(force)
    host:SetStatus("")
end

function Config:Detach()
    self.host = nil
end

function Config:OnPlanChanged()
    if self.host then self:Attach(self.host) end
end

-- The sections in the list's order. Each one has Attach(host) and Detach(); the editing ones IsChanged() and
-- Discard(); OnPlanChanged() when it follows plan changes through the window.
local ORDER = { "groups", "assignments", "notes", "gargul", "config", "newplan", "import" }
local SECTIONS = {
    groups = { title = L["Groups"], needsPlan = true, get = function() return UTRM.GroupEditor end },
    assignments = { title = L["Assignments"], needsPlan = true, get = function() return UTRM.AssignmentsWindow end },
    notes = { title = L["Notes"], needsPlan = true, get = function() return UTRM.NoteEditor.Section end },
    gargul = { title = L["Gargul"], needsPlan = true, get = function() return Gargul end },
    config = { title = L["Config"], get = function() return Config end },
    newplan = { title = L["New plan"], get = function() return UTRM.NewPlanSection end },
    import = { title = L["Import"], get = function() return UTRM.ImportWindow end },
}

local function section(key)
    return SECTIONS[key] and SECTIONS[key].get()
end

local function isChanged(key)
    local current = section(key)
    return current ~= nil and current.IsChanged ~= nil and current:IsChanged()
end

------------------------------------------------------------------------------------------ for sections ---

function RaidPlanWindow:SetStatus(text)
    if self.frame then self.frame:SetStatusText(text or "") end
end

-- A save's message, or that it stays on this client (in a raid without lead or assist, Modules/Sync.lua)
function RaidPlanWindow:SavedMessage(text)
    if IsInRaid() and not UTRM:GetModule("Sync"):CanSync() then
        return "|cffffa040" .. L["Saved on your client only: you are not raid leader or assistant."] .. "|r"
    end
    return text
end

-- The encounter a section edits: `key` while it is in the plan, else the active encounter, else the first one
function RaidPlanWindow:EncounterToEdit(key)
    local plan = currentPlan()
    if not plan then return nil end
    local active, first
    for i, encounter in ipairs(plan.encounters) do
        if encounter.key == key then return key end
        if encounter.key == plan.active then active = encounter.key end
        if i == 1 then first = encounter.key end
    end
    return active or first
end

-- Asks before unsaved changes are lost, then runs `onDiscard`
StaticPopupDialogs[DISCARD_POPUP] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function() RaidPlanWindow:RunPending() end,
    OnCancel = function() RaidPlanWindow.pending = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function RaidPlanWindow:ConfirmDiscard(title, onDiscard)
    self.pending = onDiscard
    StaticPopupDialogs[DISCARD_POPUP].text = L["Discard your changes to %s?"]
    StaticPopup_Show(DISCARD_POPUP, title)
end

function RaidPlanWindow:RunPending()
    local pending = self.pending
    self.pending = nil
    if pending then pending() end
end

-- The encounter row of a section: "Encounter" and a dropdown of the plan's encounters, the active one marked.
-- Choosing one calls `onChoose(key)`; with unsaved changes (`hasChanges()`) it asks first.
function RaidPlanWindow:AddEncounterDropdown(container, key, onChoose, hasChanges)
    local plan = currentPlan()
    local list, order = {}, {}
    for i, encounter in ipairs(plan.encounters) do
        local text = format("%d. %s", i, encounter.label)
        if encounter.key == plan.active then text = text .. "  " .. GREY .. L["(active)"] .. "|r" end
        list[encounter.key], order[i] = text, encounter.key
    end
    local label = AceGUI:Create("Label")
    label:SetFontObject(GameFontNormal)
    label:SetWidth(LABEL_WIDTH)
    label:SetText(L["Encounter"])
    container:AddChild(label)

    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetWidth(DROPDOWN_WIDTH)
    dropdown:SetList(list, order)
    dropdown:SetValue(key)
    dropdown:SetCallback("OnValueChanged", function(_, _, value)
        if value == key then return end
        if hasChanges() then
            dropdown:SetValue(key)
            self:ConfirmDiscard(SECTIONS[self.section].title, function()
                section(self.section):Discard()
                onChoose(value)
            end)
        else
            onChoose(value)
        end
    end)
    container:AddChild(dropdown)

    -- The rest of the row stays empty: the section starts below it
    local rest = AceGUI:Create("Label")
    rest:SetFullWidth(true)
    container:AddChild(rest)
end

-- The list: the sections (those that need a plan greyed out without one), * on those with unsaved changes
function RaidPlanWindow:UpdateTree()
    if not self.tree then return end
    local plan = currentPlan()
    local tree, signature = {}, {}
    for i, key in ipairs(ORDER) do
        local info = SECTIONS[key]
        local changed = isChanged(key)
        tree[i] = {
            value = key,
            text = info.title .. (changed and " |cffffa040*|r" or ""),
            disabled = info.needsPlan and not plan,
        }
        signature[i] = tostring(changed) .. tostring(tree[i].disabled)
    end
    signature = table.concat(signature, ",")
    if signature ~= self.treeSignature then
        self.treeSignature = signature
        self.tree:SetTree(tree)
    end
end

------------------------------------------------------------------------------------------------ the frame ---

-- Shows section `key` (no questions asked)
function RaidPlanWindow:ShowSection(key)
    local old = section(self.section)
    if old then old:Detach() end
    self.tree:ReleaseChildren()
    self.section = key
    settings().section = key
    self.selecting = true
    self.tree:SelectByValue(key)
    self.selecting = false
    self:SetStatus("")
    section(key):Attach(self)
    self:UpdateTree()
end

-- Goes to section `key`, asking first when the one shown has unsaved changes
function RaidPlanWindow:Select(key)
    if key == self.section then return end
    if not isChanged(self.section) then
        self:ShowSection(key)
        return
    end
    self.selecting = true
    self.tree:SelectByValue(self.section)   -- the list keeps showing where we are until the answer
    self.selecting = false
    self:ConfirmDiscard(SECTIONS[self.section].title, function()
        section(self.section):Discard()
        self:ShowSection(key)
    end)
end

function RaidPlanWindow:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["Raid Plan"])
    frame:SetStatusTable(settings())
    frame:SetLayout("Fill")
    frame:EnableResize(false)
    local editor = UTRM.GroupEditor
    frame:SetWidth(17 + TREE_WIDTH + 10 + editor.WIDTH + 10 + 17)
    frame:SetHeight(27 + 10 + editor.HEIGHT + 10 + 40)
    -- Kept for the session (closing only hides it, the drafts stay); under Blizzard's popups, which ask about them
    frame.frame:SetFrameStrata("HIGH")
    self.frame = frame

    local tree = AceGUI:Create("TreeGroup")
    tree:SetTreeWidth(TREE_WIDTH, false)
    tree:SetLayout("Flow")
    tree:SetCallback("OnGroupSelected", function(_, _, key)
        if not self.selecting then self:Select(key) end
    end)
    frame:AddChild(tree)
    self.tree, self.container, self.content = tree, tree, tree.content

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    tinsert(UISpecialFrames, FRAME_GLOBAL)
end

-- Opens the window: on section `key` when given (asking about unsaved changes), else where it was. Without a plan
-- only Config, New plan and Import can show.
function RaidPlanWindow:Open(key)
    local plan = currentPlan()
    if not self.frame then self:Create() end
    self.frame:Show()
    self:UpdateTree()
    local wanted = key or self.section or settings().section or (plan and "groups" or "import")
    if not plan and SECTIONS[wanted].needsPlan then wanted = "import" end
    if not self.section then
        self:ShowSection(wanted)
    elseif wanted ~= self.section then
        self:Select(wanted)
    elseif not isChanged(self.section) then
        self:ShowSection(wanted)   -- shown again as the plan and the raid are now
    end
end

function RaidPlanWindow:OnEnable()
    for _, message in ipairs({ "UTRM_PLAN_IMPORTED", "UTRM_PLAN_EDITED", "UTRM_PLAN_CLEARED" }) do
        self:RegisterMessage(message, function()
            if not self.section then return end
            if not currentPlan() and SECTIONS[self.section].needsPlan then
                self:ShowSection("import")
            else
                local current = section(self.section)
                if current.OnPlanChanged then current:OnPlanChanged() end
            end
            self:UpdateTree()
        end)
    end
end
