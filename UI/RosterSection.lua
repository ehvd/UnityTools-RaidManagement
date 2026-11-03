local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")
local LibDeflate = LibStub("LibDeflate")

-- The Raid members section of the Raid Plan window (UI/RaidPlanWindow.lua, issue #47): the raid's members as one
-- string (Modules/Roster.lua) for the UnityWiki raid planner's Paste raid roster, which compares the plan with who is
-- really in the raid. Needs no plan. The string is made when the section opens and on Refresh.
local RosterSection = {}
UTRM.RosterSection = RosterSection

-- GetRaidRosterInfo(1..n) as rows for Roster.Payload
local function raidRows()
    local rows = {}
    for i = 1, GetNumGroupMembers() do
        local name, rank, subgroup, level, class, fileName, zone, online = GetRaidRosterInfo(i)
        rows[i] = {
            name = name, rank = rank, subgroup = subgroup, level = level, class = class, fileName = fileName,
            zone = zone, online = online,
        }
    end
    return rows
end

-- Fills the box with a new string, all selected for Ctrl+C: the game has no clipboard API
function RosterSection:Refresh()
    if not self.editBox then return end
    if not IsInRaid() then
        self.text = ""
        self.editBox:SetText("")
        self.editBox:SetDisabled(true)
        self.editBox:SetLabel("|cffffa040" .. L["Not in a raid: join one, then press Refresh."] .. "|r")
        self.host:SetStatus("")
        return
    end
    local Roster = ns.Roster
    local payload, skipped = Roster.Payload(raidRows(), UnitName("player"), GetNormalizedRealmName(), time())
    self.text = Roster.Encode(payload, LibDeflate)
    self.editBox:SetDisabled(false)
    self.editBox:SetLabel(L["The raid's members as one string. Ctrl+C to copy:"])
    self.editBox:SetText(self.text)
    self.editBox:SetFocus()
    self.editBox:HighlightText()
    local status = format(L["Exported %d raid members. Ctrl+C to copy."], #payload.members)
    if skipped > 0 then
        status = status .. " |cffffa040" .. format(L["%d not loaded yet: press Refresh."], skipped) .. "|r"
    end
    self.host:SetStatus(status)
end

function RosterSection:Attach(host)
    self.host = host
    local container = host.container
    container:ReleaseChildren()

    local about = AceGUI:Create("Label")
    about:SetFullWidth(true)
    about:SetFontObject(GameFontHighlight)
    about:SetText(
        L["Who is in the raid, for the UnityWiki raid planner: paste it into Paste raid roster there to match the plan's names."])
    container:AddChild(about)

    -- Read only: what is typed into it is undone, and focusing it selects all of it again
    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:DisableButton(true)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(12)
    editBox:SetMaxLetters(0)
    editBox.editBox:SetMaxBytes(0)   -- no limit (a widget from AceGUI's pool may have had the paste box's)
    editBox:SetCallback("OnTextChanged", function(widget)
        widget:SetText(self.text or "")
        widget:HighlightText()
    end)
    editBox:SetCallback("OnEditFocusGained", function(widget) widget:HighlightText() end)
    container:AddChild(editBox)

    local refresh = AceGUI:Create("Button")
    refresh:SetText(L["Refresh"])
    refresh:SetWidth(140)
    refresh:SetCallback("OnClick", function() self:Refresh() end)
    container:AddChild(refresh)

    self.editBox = editBox
    self:Refresh()
end

function RosterSection:Detach()
    self.host, self.editBox, self.text = nil, nil, nil
end

-- `/utrm roster`
function RosterSection:Open()
    UTRM.RaidPlanWindow:Open("roster")
end
