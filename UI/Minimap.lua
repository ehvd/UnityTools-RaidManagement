local ADDON_NAME = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- The minimap button (LibDataBroker launcher shown by LibDBIcon): left click shows or hides the raid plan window,
-- right click opens a menu with the plan actions of the window's ⚙ menu and the rest of the addon's tools.
local Minimap = UTRM:NewModule("Minimap")

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

local function settings()
    return UTRM.db.profile.minimap
end

local function showMenu(owner)
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Unity Tools - Raid Management"])
        UTRM.PlanWindow:AddPlanActions(root)
        root:CreateButton(L["Raid note editor..."], function() UTRM.NoteEditor:Open() end)
        root:CreateButton(L["Hide minimap button"], function()
            Minimap:SetShown(false)
            UTRM:Print(L["Minimap button hidden: /utrm minimap shows it again."])
        end)
    end)
end

local function showTooltip(tooltip)
    tooltip:AddLine(L["Unity Tools - Raid Management"] .. " " .. UTRM.version)
    local plan = UTRM:GetModule("PlanImport"):GetPlan()
    if plan then
        local active
        for _, encounter in ipairs(plan.encounters) do
            if encounter.key == plan.active then active = encounter.label end
        end
        tooltip:AddLine(plan.event.title .. (active and (": " .. active) or ""), 1, 1, 1)
    else
        tooltip:AddLine(L["No raid plan imported yet."], 0.75, 0.75, 0.75)
    end
    tooltip:AddLine(L["Left-click: show or hide the raid plan window"], 0.5, 0.5, 0.5)
    tooltip:AddLine(L["Right-click: options"], 0.5, 0.5, 0.5)
end

local launcher = LDB:NewDataObject(ADDON_NAME, {
    type = "launcher",
    text = L["Unity Tools - Raid Management"],
    icon = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon",
    OnClick = function(owner, button)
        if button == "RightButton" then
            showMenu(owner)
        else
            UTRM.PlanWindow:Toggle()
        end
    end,
    OnTooltipShow = showTooltip,
})

function Minimap:SetShown(shown)
    settings().hide = not shown
    if shown then
        DBIcon:Show(ADDON_NAME)
    else
        DBIcon:Hide(ADDON_NAME)
    end
end

function Minimap:Toggle()
    self:SetShown(settings().hide)
end

function Minimap:OnEnable()
    -- LibDBIcon keeps the position (minimapPos) and `hide` in this table, per profile
    DBIcon:Register(ADDON_NAME, launcher, settings())
end
