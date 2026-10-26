local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- Small window for the raid leader during the raid: pick the active encounter of the imported raid plan (previous,
-- next, or the list behind the encounter's name), which sends its note to Method Raid Tools. Other modules follow
-- the active encounter through the UTRM_ENCOUNTER_ACTIVATED message (encounter, its layout's 40 names).
local PlanWindow = UTRM:NewModule("PlanWindow", "AceEvent-3.0")
UTRM.PlanWindow = PlanWindow

-- Composition from the Figma wireframe (1 px = 1 UI pixel at 100% scale): three rows, 2 px gaps, 2 px between the
-- border and the content. The look is Blizzard's own art and templates. Every row and button has the height of the
-- native dropdown, so the rows line up: the buttons are ROW × ROW squares.
local BORDER = 4                        -- the tooltip backdrop's border (its insets)
local INSET = BORDER + 2
local ROW = 26                          -- the height AceGUI gives UIDropDownMenuTemplate without a label
local GAP = 2
local ROW1 = INSET                      -- title, settings, close
local ROW2 = ROW1 + ROW + GAP           -- ◀ [encounter ▼] ▶
local ROW3 = ROW2 + ROW + GAP           -- status line
local WIDTH, HEIGHT = 172 + 2 * INSET, ROW3 + ROW + INSET

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

-- A button drawn with one of Blizzard's button art sets (<path>Up / Down / Disabled). `crop` cuts the empty margin
-- around the art, so it fills the 16 px slot; 0 keeps the texture as Blizzard draws it.
local function artButton(path, highlight, crop)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ROW, ROW)
    button:SetNormalTexture(path .. "Up")
    button:SetPushedTexture(path .. "Down")
    button:SetDisabledTexture(path .. "Disabled")
    button:SetHighlightTexture(highlight, "ADD")
    if crop > 0 then
        for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
                button:GetDisabledTexture(), button:GetHighlightTexture() }) do
            texture:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        end
    end
    return button
end

-- ◀ ▶: the buttons of Blizzard's scroll bars, turned a quarter (the up arrow points left, the down arrow right)
local function scrollArrowButton(template)
    local button = CreateFrame("Button", nil, frame, template)
    button:SetSize(ROW, ROW)   -- 18×16 in the template; square here so it matches the other buttons of the row
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
            button:GetDisabledTexture(), button:GetHighlightTexture() }) do
        texture:SetRotation(math.pi / 2)
    end
    return button
end

-- ×: the art of UIPanelCloseButton, cropped to the red square (the crop Details uses for the same texture)
local function closeButton()
    return artButton("Interface\\Buttons\\UI-Panel-MinimizeButton-",
        "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", 0.14)
end

-- A red panel button (UIPanelButtonTemplate) with the small font
local function panelButton(width, label)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, ROW)
    button:SetNormalFontObject(GameFontNormalSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetDisabledFontObject(GameFontDisableSmall)
    if label then button:SetText(label) end
    return button
end

-- ⚙: a panel button with Blizzard's options cogwheel
local function settingsButton()
    local button = panelButton(ROW)
    local cog = button:CreateTexture(nil, "OVERLAY")
    cog:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog:SetSize(18, 18)
    cog:SetPoint("CENTER")
    return button
end

-- The encounter box: a Blizzard dropdown (UIDropDownMenuTemplate) set up the way AceGUI's Dropdown widget does it,
-- so it looks like the dropdowns of AceGUI windows (Guild Recruitment Buddy's for example). `holder` is the visible
-- box; the template's art has transparent margins, so the template frame reaches 15 px left and 17 px right of it.
-- Only the look and the ▼ button are used: the list itself is our MenuUtil menu.
local function encounterDropdown(holder)
    local dropdown = CreateFrame("Frame", "UnityToolsRaidManagementEncounterDropDown", holder, "UIDropDownMenuTemplate")
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", holder, "TOPLEFT", -15, 0)
    dropdown:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 17, 0)
    dropdown:SetScript("OnHide", nil)

    local name = dropdown:GetName()
    local left, middle, right = _G[name .. "Left"], _G[name .. "Middle"], _G[name .. "Right"]
    middle:ClearAllPoints()
    right:ClearAllPoints()
    middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
    middle:SetPoint("RIGHT", right, "LEFT", 0, 0)
    right:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, 17)

    local text = _G[name .. "Text"]
    text:ClearAllPoints()
    text:SetPoint("RIGHT", right, "RIGHT", -43, 2)
    text:SetPoint("LEFT", left, "LEFT", 25, 2)

    holder.text = text
    holder.button = _G[name .. "Button"]
    -- Blizzard's own menu must not open: clicks are handled by PlanWindow (OnClick is replaced there)
    holder.button:SetScript("OnMouseDown", nil)
    -- Clicking anywhere on the box works like its ▼, as in AceGUI
    holder.cover = CreateFrame("Button", nil, holder)
    holder.cover:SetAllPoints(holder)
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
    frame.title:SetHeight(ROW)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    -- Row 2: ◀ [encounter ▼] ▶ (or Import when there is no plan); the arrows are centred on the dropdown
    local rowMiddle = -(ROW2 + ROW / 2)
    frame.prev = scrollArrowButton("UIPanelScrollUpButtonTemplate")
    frame.prev:SetPoint("LEFT", frame, "TOPLEFT", INSET, rowMiddle)
    frame.prev:SetScript("OnClick", function() PlanWindow:Step(-1) end)

    frame.next = scrollArrowButton("UIPanelScrollDownButtonTemplate")
    frame.next:SetPoint("RIGHT", frame, "TOPRIGHT", -INSET, rowMiddle)
    frame.next:SetScript("OnClick", function() PlanWindow:Step(1) end)

    -- The encounter box fills most of the bar, so it also moves the window and opens the options
    frame.encounter = CreateFrame("Frame", nil, frame)
    frame.encounter:SetPoint("TOPLEFT", INSET + ROW + GAP, -ROW2)
    frame.encounter:SetPoint("TOPRIGHT", -INSET - ROW - GAP, -ROW2)
    frame.encounter:SetHeight(ROW)
    encounterDropdown(frame.encounter)
    local function onEncounterClick(self, button)
        if button == "RightButton" then
            openOptionsMenu(self)
        else
            openEncounterMenu(frame.encounter)
        end
    end
    for _, clickable in ipairs({ frame.encounter.cover, frame.encounter.button }) do
        clickable:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        clickable:SetScript("OnClick", onEncounterClick)
        clickable:SetScript("OnEnter", showEncounterTooltip)
        clickable:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame.encounter.cover:RegisterForDrag("LeftButton")
    frame.encounter.cover:SetScript("OnDragStart", startMoving)
    frame.encounter.cover:SetScript("OnDragStop", stopMoving)

    frame.import = panelButton(100, L["Import"])
    frame.import:SetPoint("CENTER", frame, "TOP", 0, rowMiddle)
    frame.import:SetScript("OnClick", function() UTRM.ImportWindow:Open() end)

    -- Row 3: the result of the last action
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", INSET, -ROW3)
    frame.status:SetPoint("TOPRIGHT", -INSET, -ROW3)
    frame.status:SetHeight(ROW)
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
        frame.encounter:Hide()
        frame.import:Show()
        return
    end

    frame.title:SetText(plan.event.title)
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
    frame.encounter.button:SetEnabled(count > 0)
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
