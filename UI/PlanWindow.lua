local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- Small window for the raid leader during the raid: pick the active encounter of the imported raid plan (previous,
-- next, or the list behind the encounter's name), which sends its note to Method Raid Tools. Other modules follow
-- the active encounter through the UTRM_ENCOUNTER_ACTIVATED message (encounter, its layout's 40 names).
local PlanWindow = UTRM:NewModule("PlanWindow", "AceEvent-3.0")
UTRM.PlanWindow = PlanWindow

-- Composition from the Figma wireframe (1 px = 1 UI pixel at 100% scale): three rows, 2 px gaps, 2 px between the
-- border and the content. Every control is a Blizzard template at its own default size, and the rows are as tall as
-- the controls in them.
local BORDER = 4                        -- the tooltip backdrop's border (its insets)
local INSET = BORDER + 2
local GAP = 2
local PANEL_BUTTON = 22                 -- UIPanelButtonTemplate's usual height
local CLOSE_MARGIN = 5                  -- UIPanelCloseButton is 32×32 with ~5 px of empty art around the red square
local DROPDOWN = 26                     -- the height AceGUI gives UIDropDownMenuTemplate without a label
local ARROW_WIDTH = 18                  -- UIPanelScrollUp/DownButtonTemplate are 18×16
local TEXT_ROW = 16
local READY_ICON = 16                   -- the ready check icons, as raid frames show them

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ROW1 = INSET                      -- title, settings, close
local ROW2 = ROW1 + PANEL_BUTTON + GAP  -- ◀ [encounter ▼] ▶
local ROW3 = ROW2 + DROPDOWN + GAP      -- status line
local WIDTH, HEIGHT = 172 + 2 * INSET, ROW3 + TEXT_ROW + INSET   -- also the smallest size
local MAX_WIDTH = 600
local GRIP = 16                         -- the chat frame's size grabber

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

    -- The note, then the groups: the status line shows both in short, its tooltip the whole messages
    local ok, message = UTRM:GetModule("MRT"):Post(encounter.note)
    local short
    if not ok then
        short = "|cffff4040" .. L["Note not sent"] .. "|r"
    elseif encounter.note == "" then
        short, message = L["Note cleared"], L["This encounter has no note: the MRT note was cleared."]
    elseif UTRM:GetModule("MRT"):CanSendToRaid() then
        short = L["Note sent"]
    else
        short = "|cffffa040" .. L["Note sent, not as lead or assist"] .. "|r"
    end
    self.noteStatus, self.noteMessage = short, message
    self.groupStatus, self.groupDetails = nil, nil
    self:Refresh()
    UTRM:GetModule("RaidGroups"):Apply(plan.layouts[encounter.layout])
    self:SendMessage("UTRM_ENCOUNTER_ACTIVATED", encounter, plan.layouts[encounter.layout])
end

-- Hands the plan's loot priorities to Gargul; the result replaces the status line
function PlanWindow:ImportGargul()
    local ok, message = UTRM:GetModule("Gargul"):ImportPlan(currentPlan())
    self:Refresh(ok and message or ("|cffff4040" .. message .. "|r"))
    self.noteMessage = message   -- the whole text in the status tooltip
end

-- The raid groups' part of the status line (Modules/RaidGroups.lua), with tooltip lines naming the players
function PlanWindow:SetGroupStatus(text, details)
    self.groupStatus, self.groupDetails = text, details
    self:RenderStatus()
end

function PlanWindow:RenderStatus()
    if not frame then return end
    local parts = {}
    if self.noteStatus then parts[#parts + 1] = self.noteStatus end
    if self.groupStatus then parts[#parts + 1] = self.groupStatus end
    frame.status:SetText(table.concat(parts, "  ·  "))
end

-- The readiness icon's tooltip: every check with a ready check icon, and its details (Modules/Readiness.lua)
local function showReadinessTooltip(self)
    PlanWindow:UpdateReadiness()
    local readiness = PlanWindow.readiness
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Raid readiness"])
    if not readiness.inRaid then
        GameTooltip:AddLine(L["Checked in a raid only."], 0.75, 0.75, 0.75)
    end
    for _, check in ipairs(readiness.checks) do
        local icon = format("|T%s:14|t ", check.ok and READY or NOT_READY)
        if check.ok then
            GameTooltip:AddLine(icon .. check.text, 1, 1, 1, true)
        else
            GameTooltip:AddLine(icon .. check.text, 1, 0.35, 0.35, true)
        end
        for _, line in ipairs(check.details or {}) do
            GameTooltip:AddLine(line, 0.75, 0.75, 0.75, true)
        end
    end
    GameTooltip:Show()
end

local function showStatusTooltip(self)
    if not PlanWindow.noteMessage and not PlanWindow.groupStatus then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if PlanWindow.noteMessage then
        GameTooltip:AddLine(PlanWindow.noteMessage, 1, 1, 1, true)
    end
    if PlanWindow.groupStatus then
        GameTooltip:AddLine(PlanWindow.groupStatus, 1, 1, 1, true)
        for _, line in ipairs(PlanWindow.groupDetails or {}) do
            GameTooltip:AddLine(line, 0.75, 0.75, 0.75, true)
        end
    end
    GameTooltip:Show()
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
        -- Gargul: only when the plan carries loot priorities and Gargul can be used
        local gargulState = UTRM:GetModule("Gargul"):GetState(plan)
        if gargulState then
            local label = gargulState == "current" and L["Gargul: loot priorities are up to date"]
                or ("|cffffa040" .. L["Gargul: import the loot priorities"] .. "|r")
            root:CreateButton(label, function() PlanWindow:ImportGargul() end)
        end
        root:CreateCheckbox(L["Lock position"],
            function() return settings().locked end,
            function()
                settings().locked = not settings().locked
                frame.grip:SetShown(not settings().locked)
            end)
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

-- ◀ ▶: the buttons of Blizzard's scroll bars at their own size, turned a quarter (the up arrow points left, the
-- down arrow right)
local function scrollArrowButton(template)
    local button = CreateFrame("Button", nil, frame, template)
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
            button:GetDisabledTexture(), button:GetHighlightTexture() }) do
        texture:SetRotation(math.pi / 2)
    end
    return button
end

-- A red panel button (UIPanelButtonTemplate) at Blizzard's usual button height
local function panelButton(width, label)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, PANEL_BUTTON)
    if label then button:SetText(label) end
    return button
end

-- ⚙: a square panel button with Blizzard's options cogwheel
local function settingsButton()
    local button = panelButton(PANEL_BUTTON)
    local cog = button:CreateTexture(nil, "OVERLAY")
    cog:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog:SetSize(16, 16)
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
    text:SetJustifyH("LEFT")   -- the template right-aligns it

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

    local s = settings()
    frame:SetPoint(s.point or "TOP", UIParent, s.relativePoint or "TOP", s.x or 0, s.y or -120)
    frame:SetScale(s.scale or 1)

    -- Resizable in width only: the layout's size is the minimum, the height never changes
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(WIDTH, HEIGHT, MAX_WIDTH, HEIGHT)
    else
        frame:SetMinResize(WIDTH, HEIGHT)
        frame:SetMaxResize(MAX_WIDTH, HEIGHT)
    end
    frame:SetWidth(math.max(WIDTH, math.min(MAX_WIDTH, s.width or WIDTH)))

    -- The chat frame's size grabber in the bottom right corner, hidden while the window is locked
    frame.grip = CreateFrame("Button", nil, frame)
    frame.grip:SetSize(GRIP, GRIP)
    frame.grip:SetPoint("BOTTOMRIGHT", -BORDER + 1, BORDER - 1)
    frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.grip:SetShown(not s.locked)
    frame.grip:SetScript("OnMouseDown", function()
        if not settings().locked then frame:StartSizing("RIGHT") end
    end)
    frame.grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        settings().width = math.floor(frame:GetWidth() + 0.5)
        savePosition()
    end)

    -- Row 1: the event's title, settings and close. The close button's red square lines up with the content edge;
    -- its empty art around it may overlap the border, as in Blizzard's own windows.
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -INSET + CLOSE_MARGIN, -ROW1 + CLOSE_MARGIN)
    frame.close:SetScript("OnClick", function() PlanWindow:Hide() end)

    frame.settings = settingsButton()
    frame.settings:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", CLOSE_MARGIN - GAP, -CLOSE_MARGIN)
    frame.settings:SetScript("OnClick", function(self) openOptionsMenu(self) end)

    -- Readiness: one ready check icon left of the settings; the tooltip lists the checks
    frame.ready = CreateFrame("Button", nil, frame)
    frame.ready:SetSize(READY_ICON, READY_ICON)
    frame.ready:SetPoint("RIGHT", frame.settings, "LEFT", -GAP, 0)
    frame.ready.icon = frame.ready:CreateTexture(nil, "ARTWORK")
    frame.ready.icon:SetAllPoints()
    frame.ready:SetScript("OnEnter", showReadinessTooltip)
    frame.ready:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", INSET, -ROW1)
    frame.title:SetPoint("TOPRIGHT", frame.settings, "TOPLEFT", -GAP - READY_ICON - GAP, 0)
    frame.title:SetHeight(PANEL_BUTTON)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    -- Row 2: ◀ [encounter ▼] ▶ (or Import when there is no plan); the arrows are centred on the dropdown
    local rowMiddle = -(ROW2 + DROPDOWN / 2)
    frame.prev = scrollArrowButton("UIPanelScrollUpButtonTemplate")
    frame.prev:SetPoint("LEFT", frame, "TOPLEFT", INSET, rowMiddle)
    frame.prev:SetScript("OnClick", function() PlanWindow:Step(-1) end)

    frame.next = scrollArrowButton("UIPanelScrollDownButtonTemplate")
    frame.next:SetPoint("RIGHT", frame, "TOPRIGHT", -INSET, rowMiddle)
    frame.next:SetScript("OnClick", function() PlanWindow:Step(1) end)

    -- The encounter box fills most of the bar (and grows with the window), so it also moves the window
    frame.encounter = CreateFrame("Frame", nil, frame)
    frame.encounter:SetPoint("TOPLEFT", INSET + ARROW_WIDTH + GAP, -ROW2)
    frame.encounter:SetPoint("TOPRIGHT", -INSET - ARROW_WIDTH - GAP, -ROW2)
    frame.encounter:SetHeight(DROPDOWN)
    encounterDropdown(frame.encounter)
    for _, clickable in ipairs({ frame.encounter.cover, frame.encounter.button }) do
        clickable:SetScript("OnClick", function() openEncounterMenu(frame.encounter) end)
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
    frame.status:SetPoint("TOPRIGHT", -INSET - GRIP, -ROW3)   -- leave the size grabber free
    frame.status:SetHeight(TEXT_ROW)
    frame.status:SetTextColor(0.75, 0.75, 0.75)
    frame.status:SetWordWrap(false)
    -- Hover: the whole messages, and who is missing or not in the plan
    frame.statusHover = CreateFrame("Frame", nil, frame)
    frame.statusHover:SetAllPoints(frame.status)
    frame.statusHover:SetScript("OnEnter", showStatusTooltip)
    frame.statusHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function PlanWindow:Refresh(status)
    if not frame then return end
    local plan = currentPlan()
    if status then
        -- A new status replaces both parts ("" clears the line, after an import for example)
        self.noteStatus = status ~= "" and status or nil
        self.noteMessage, self.groupStatus, self.groupDetails = nil, nil, nil
    end
    self:RenderStatus()

    if not plan then
        frame.title:SetText(L["Raid plan"])
        frame.status:SetText(L["No raid plan imported yet."])
        frame.prev:Hide()
        frame.next:Hide()
        frame.encounter:Hide()
        frame.import:Show()
        self:UpdateReadiness()
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
    self:UpdateReadiness()
end

-- The readiness icon: waiting (grey) outside a raid, ready when every check passes, not ready otherwise
function PlanWindow:UpdateReadiness()
    self.readiness = UTRM:GetModule("Readiness"):Evaluate()
    if not frame then return end
    local readiness = self.readiness
    local icon = frame.ready.icon
    if not readiness.inRaid then
        icon:SetTexture(WAITING)
        icon:SetDesaturated(true)
        frame.ready:SetAlpha(0.5)
    else
        icon:SetTexture(readiness.problems == 0 and READY or NOT_READY)
        icon:SetDesaturated(false)
        frame.ready:SetAlpha(1)
    end
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
