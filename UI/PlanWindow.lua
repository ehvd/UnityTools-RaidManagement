local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- Small window for the raid leader during the raid: pick the active encounter of the imported raid plan (previous,
-- next, or the list behind the encounter's name), which sends its note to Method Raid Tools. Other modules follow
-- the active encounter through the UTRM_ENCOUNTER_ACTIVATED message (encounter, its layout's 40 names).
local PlanWindow = UTRM:NewModule("PlanWindow", "AceEvent-3.0")
UTRM.PlanWindow = PlanWindow

-- Layout from the Figma wireframe (1 px = 1 UI pixel at 100% scale): three rows inside a 4 px inset,
-- 16 px square buttons with 2 px gaps.
local WIDTH, HEIGHT = 180, 58
local INSET = 4
local BUTTON = 16
local GAP = 2
local ROW1, ROW2, ROW3 = 4, 22, 39     -- top of the title row, the encounter row and the status line

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local SQUARE = { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 }
local BUTTON_FILL = { 0.35, 0.04, 0.04 }          -- #5a0b0b
local BUTTON_EDGE = { 0.54, 0.43, 0.17 }          -- #8a6d2a
local SYMBOL = { 1, 0.82, 0 }                     -- #ffd100
local BOX_FILL = { 0.2, 0.2, 0.21 }               -- #323236
local BOX_EDGE = { 0.62, 0.62, 0.66 }             -- #9e9ea8

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

-- A flat square button (red fill, gold edge) like the others in the window; the symbol goes on top
local function squareButton(width)
    local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
    button:SetSize(width or BUTTON, BUTTON)
    button:SetBackdrop(SQUARE)
    button:SetBackdropColor(unpack(BUTTON_FILL))
    button:SetBackdropBorderColor(unpack(BUTTON_EDGE))
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(1, 1, 1, 0.15)
    return button
end

-- ◀ ▶ ▼: the gold arrow of Blizzard's dropdown menus, pointing right; flipped or turned for the others
local function arrowButton(direction)
    local button = squareButton()
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("CENTER")
    if direction == "left" then
        arrow:SetTexCoord(1, 0, 0, 1)
    elseif direction == "down" then
        arrow:SetRotation(-math.pi / 2)
    end
    button.symbol = arrow
    return button
end

-- ×: two gold lines
local function closeButton()
    local button = squareButton()
    for _, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local line = button:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(unpack(SYMBOL))
        line:SetSize(10, 2)
        line:SetPoint("CENTER")
        line:SetRotation(angle)
    end
    return button
end

-- Blizzard's options cogwheel, tinted gold
local function settingsButton()
    local button = squareButton()
    local cog = button:CreateTexture(nil, "ARTWORK")
    cog:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog:SetSize(12, 12)
    cog:SetPoint("CENTER")
    cog:SetVertexColor(unpack(SYMBOL))
    return button
end

local function setEnabled(button, enabled)
    button:SetEnabled(enabled)
    button:SetAlpha(enabled and 1 or 0.4)
    if button.symbol then button.symbol:SetDesaturated(not enabled) end
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
    frame:SetBackdropBorderColor(unpack(BOX_EDGE))
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

    -- Row 1: the event's title, settings and close
    frame.close = closeButton()
    frame.close:SetPoint("TOPRIGHT", -INSET, -ROW1)
    frame.close:SetScript("OnClick", function() PlanWindow:Hide() end)

    frame.settings = settingsButton()
    frame.settings:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -GAP, 0)
    frame.settings:SetScript("OnClick", function(self) openOptionsMenu(self) end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", INSET, -ROW1)
    frame.title:SetPoint("TOPRIGHT", frame.settings, "TOPLEFT", -GAP, 0)
    frame.title:SetHeight(BUTTON)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    -- Row 2: ◀ [encounter] ▼ ▶ (or Import when there is no plan)
    frame.prev = arrowButton("left")
    frame.prev:SetPoint("TOPLEFT", INSET, -ROW2)
    frame.prev:SetScript("OnClick", function() PlanWindow:Step(-1) end)

    frame.next = arrowButton("right")
    frame.next:SetPoint("TOPRIGHT", -INSET, -ROW2)
    frame.next:SetScript("OnClick", function() PlanWindow:Step(1) end)

    frame.dropdown = arrowButton("down")
    frame.dropdown:SetPoint("TOPRIGHT", frame.next, "TOPLEFT", -GAP, 0)
    frame.dropdown:SetScript("OnClick", function() openEncounterMenu(frame.encounter) end)

    -- The encounter box fills most of the bar, so it also moves the window and opens the options
    frame.encounter = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.encounter:SetPoint("TOPLEFT", frame.prev, "TOPRIGHT", GAP, 0)
    frame.encounter:SetPoint("BOTTOMRIGHT", frame.dropdown, "BOTTOMLEFT", -GAP, 0)
    frame.encounter:SetBackdrop(SQUARE)
    frame.encounter:SetBackdropColor(unpack(BOX_FILL))
    frame.encounter:SetBackdropBorderColor(unpack(BOX_EDGE))
    local boxHighlight = frame.encounter:CreateTexture(nil, "HIGHLIGHT")
    boxHighlight:SetPoint("TOPLEFT", 1, -1)
    boxHighlight:SetPoint("BOTTOMRIGHT", -1, 1)
    boxHighlight:SetColorTexture(1, 1, 1, 0.08)
    frame.encounter:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.encounter:RegisterForDrag("LeftButton")
    frame.encounter.text = frame.encounter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size = frame.encounter.text:GetFont()
    frame.encounter.text:SetFont(font, size, "OUTLINE")
    frame.encounter.text:SetPoint("TOPLEFT", 3, 0)
    frame.encounter.text:SetPoint("BOTTOMRIGHT", -3, 0)
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

    frame.import = squareButton(100)
    frame.import:SetPoint("TOP", 0, -ROW2)
    frame.import.text = frame.import:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.import.text:SetAllPoints()
    frame.import.text:SetText(L["Import"])
    frame.import:SetScript("OnClick", function() UTRM.ImportWindow:Open() end)

    -- Row 3: the result of the last action
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", INSET + 1, -ROW3)
    frame.status:SetPoint("TOPRIGHT", -INSET - 3, -ROW3)
    frame.status:SetHeight(BUTTON)
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
        frame.title:SetText(L["Raid plan"])
        frame.status:SetText(L["No raid plan imported yet."])
        frame.prev:Hide()
        frame.next:Hide()
        frame.dropdown:Hide()
        frame.encounter:Hide()
        frame.import:Show()
        return
    end

    frame.title:SetText(plan.event.title)
    frame.import:Hide()
    frame.prev:Show()
    frame.next:Show()
    frame.dropdown:Show()
    frame.encounter:Show()
    local index, count = self:GetActiveIndex(plan), #plan.encounters
    if index then
        frame.encounter.text:SetText(format("|cff999999%d/%d|r  %s", index, count, plan.encounters[index].label))
    else
        frame.encounter.text:SetText(count > 0 and L["Choose the encounter"] or L["The plan has no encounters."])
    end
    setEnabled(frame.prev, index ~= nil and index > 1)
    setEnabled(frame.next, count > 0 and (index or 0) < count)
    setEnabled(frame.dropdown, count > 0)
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
