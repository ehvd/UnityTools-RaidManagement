local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- Small window for the raid leader during the raid: pick the active encounter of the imported raid plan (previous,
-- next, or the list behind the encounter's name), which sends its note to Method Raid Tools. Other modules follow
-- the active encounter through the UTRM_ENCOUNTER_ACTIVATED message (encounter, its layout's 40 names).
local PlanWindow = UTRM:NewModule("PlanWindow", "AceEvent-3.0")
UTRM.PlanWindow = PlanWindow

local WIDTH, HEIGHT = 230, 42
local ROW = 18      -- height of the encounter row: the arrows are square
local PADDING = 5
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }
local TOOLTIP_NOTE_LINES = 12

local frame

local function settings()
    return UTRM.db.profile.planWindow
end

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

-- The active encounter's index in the plan, or nil. The plan keeps the key (`plan.active`), so a new import starts
-- with no encounter active.
function PlanWindow:GetActiveIndex(plan)
    if not plan or not plan.active then return nil end
    for i, encounter in ipairs(plan.encounters) do
        if encounter.key == plan.active then return i end
    end
    return nil
end

-- Makes an encounter active and sends its note. Selecting the active one again sends it again (somebody joined late).
function PlanWindow:Activate(index)
    local plan = currentPlan()
    local encounter = plan and plan.encounters[index]
    if not encounter then return end
    plan.active = encounter.key

    local ok, message = UTRM:GetModule("MRT"):Post(encounter.note)
    if ok and encounter.note == "" then
        message = L["This encounter has no note: the MRT note was cleared."]
    end
    self:SendMessage("UTRM_ENCOUNTER_ACTIVATED", encounter, plan.layouts[encounter.layout])
    self:Refresh(ok and message or ("|cffff4040" .. message .. "|r"))
end

function PlanWindow:Step(by)
    local plan = currentPlan()
    if not plan or #plan.encounters == 0 then return end
    local index = self:GetActiveIndex(plan)
    index = index and math.max(1, math.min(#plan.encounters, index + by)) or 1
    self:Activate(index)
end

------------------------------------------------------------------------------------------------- menus ---

local function openEncounterMenu(owner)
    local plan = currentPlan()
    if not plan then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(plan.event.title)
        local active = PlanWindow:GetActiveIndex(plan)
        for i, encounter in ipairs(plan.encounters) do
            root:CreateRadio(format("%d. %s", i, encounter.label),
                function() return i == active end,
                function()
                    PlanWindow:Activate(i)
                    return MenuResponse and MenuResponse.Close
                end)
        end
    end)
end

local function openOptionsMenu(owner)
    local plan = currentPlan()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(plan and plan.event.title or L["Raid plan"])
        root:CreateButton(L["Import raid plan..."], function() UTRM.ImportWindow:Open() end)
        root:CreateCheckbox(L["Lock position"],
            function() return settings().locked end,
            function() settings().locked = not settings().locked end)
        local scale = root:CreateButton(L["Scale"])
        for _, value in ipairs(SCALES) do
            scale:CreateRadio(format("%d%%", value * 100),
                function() return settings().scale == value end,
                function()
                    settings().scale = value
                    frame:SetScale(value)
                end)
        end
        root:CreateButton(CLOSE, function() PlanWindow:Hide() end)
    end)
end

------------------------------------------------------------------------------------------------ the frame ---

local function arrowButton(direction)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ROW, ROW)
    local path = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    button:SetNormalTexture(path .. "Up")
    button:SetPushedTexture(path .. "Down")
    button:SetDisabledTexture(path .. "Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return button
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    local s = settings()
    s.point, s.relativePoint, s.x, s.y = point, relativePoint, x, y
end

local function showEncounterTooltip(self)
    local plan = currentPlan()
    local encounter = plan and plan.encounters[PlanWindow:GetActiveIndex(plan) or 0]
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if plan then
        GameTooltip:AddLine(plan.event.title)
    end
    if encounter then
        GameTooltip:AddLine(encounter.label, 1, 1, 1)
        GameTooltip:AddLine(encounter.layout == "default" and L["The night's groups"]
            or format(L["Groups: %s"], encounter.layout), 0.6, 0.8, 1)
        local shown = 0
        for line in (encounter.note .. "\n"):gmatch("(.-)\n") do
            shown = shown + 1
            if shown > TOOLTIP_NOTE_LINES then
                GameTooltip:AddLine("...", 1, 1, 1)
                break
            end
            GameTooltip:AddLine(line, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(L["Click: choose the encounter"], 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L["Right-click: options"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function create()
    frame = CreateFrame("Frame", "UnityToolsRaidManagementPlanFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    local function startMoving()
        if not settings().locked then frame:StartMoving() end
    end
    local function stopMoving()
        frame:StopMovingOrSizing()
        savePosition()
    end
    frame:SetScript("OnDragStart", startMoving)
    frame:SetScript("OnDragStop", stopMoving)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then openOptionsMenu(self) end
    end)

    local s = settings()
    frame:SetPoint(s.point or "TOP", UIParent, s.relativePoint or "TOP", s.x or 0, s.y or -120)
    frame:SetScale(s.scale or 1)

    -- Row 1: ◀ encounter ▶ (or Import when there is no plan)
    frame.prev = arrowButton("Prev")
    frame.prev:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame.prev:SetScript("OnClick", function() PlanWindow:Step(-1) end)

    frame.next = arrowButton("Next")
    frame.next:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    frame.next:SetScript("OnClick", function() PlanWindow:Step(1) end)

    -- The encounter's name fills most of the bar, so it also moves the window and opens the options
    frame.encounter = CreateFrame("Button", nil, frame)
    frame.encounter:SetPoint("TOPLEFT", frame.prev, "TOPRIGHT", 2, 0)
    frame.encounter:SetPoint("BOTTOMRIGHT", frame.next, "BOTTOMLEFT", -2, 0)
    frame.encounter:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    frame.encounter:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.encounter:RegisterForDrag("LeftButton")
    frame.encounter.text = frame.encounter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.encounter.text:SetAllPoints()
    frame.encounter.text:SetWordWrap(false)
    frame.encounter:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            openOptionsMenu(self)
        else
            openEncounterMenu(self)
        end
    end)
    frame.encounter:SetScript("OnDragStart", startMoving)
    frame.encounter:SetScript("OnDragStop", stopMoving)
    frame.encounter:SetScript("OnEnter", showEncounterTooltip)
    frame.encounter:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.import:SetSize(100, ROW)
    frame.import:SetPoint("TOP", 0, -PADDING)
    frame.import:SetText(L["Import"])
    frame.import:SetScript("OnClick", function() UTRM.ImportWindow:Open() end)

    -- Row 2: the result of the last action
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", PADDING + 2, PADDING)
    frame.status:SetPoint("BOTTOMRIGHT", -PADDING - 2, PADDING)
    frame.status:SetTextColor(0.75, 0.75, 0.75)
    frame.status:SetWordWrap(false)
end

function PlanWindow:Refresh(status)
    if not frame then return end
    local plan = currentPlan()
    if status then
        frame.status:SetText(status)
    end

    if not plan then
        frame.status:SetText(L["No raid plan imported yet."])
        frame.prev:Hide()
        frame.next:Hide()
        frame.encounter:Hide()
        frame.import:Show()
        return
    end

    frame.import:Hide()
    frame.prev:Show()
    frame.next:Show()
    frame.encounter:Show()
    local index, count = self:GetActiveIndex(plan), #plan.encounters
    if index then
        frame.encounter.text:SetText(format("|cff999999%d/%d|r  %s", index, count, plan.encounters[index].label))
    else
        frame.encounter.text:SetText(count > 0 and L["Choose the encounter"] or L["The plan has no encounters."])
    end
    frame.prev:SetEnabled(index ~= nil and index > 1)
    frame.next:SetEnabled(count > 0 and (index or 0) < count)
end

function PlanWindow:Show()
    if not frame then create() end
    frame:Show()
    settings().shown = true
    self:Refresh()
end

function PlanWindow:Hide()
    if frame then frame:Hide() end
    settings().shown = false
end

function PlanWindow:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function PlanWindow:OnEnable()
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function()
        self:Refresh("")
    end)
    if settings().shown then
        self:Show()
    end
end
