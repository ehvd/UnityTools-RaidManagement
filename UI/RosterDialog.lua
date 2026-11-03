local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L

local AceGUI = LibStub("AceGUI-3.0")
local LibDeflate = LibStub("LibDeflate")

-- Export raid (issue #47): the raid's members and groups as one string (Modules/Roster.lua, UnityWiki's roster
-- format, docs/addon-roster.md there) in a read-only box, all selected for Ctrl+C: the game has no clipboard API.
-- Opened from the Groups section of the Raid Plan window and `/utrm roster`; needs no plan. The string is made when
-- the dialog opens and on Refresh, so it does not change under a selection being copied.
local RosterDialog = {}
UTRM.RosterDialog = RosterDialog

local FRAME_GLOBAL = "UnityToolsRaidManagementRosterFrame"
local specialFrameAdded = false

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

-- Fills the box with a new string, all selected
function RosterDialog:Refresh()
    if not self.editBox then return end
    if not IsInRaid() then
        self.text = ""
        self.editBox:SetText("")
        self.editBox:SetDisabled(true)
        self.editBox:SetLabel("|cffffa040" .. L["Not in a raid"] .. "|r")
        self.frame:SetStatusText("")
        return
    end
    local Roster = ns.Roster
    local payload, skipped = Roster.Payload(raidRows(), UnitName("player"), GetNormalizedRealmName(), time())
    self.text = Roster.Encode(payload, LibDeflate)
    self.editBox:SetDisabled(false)
    self.editBox:SetLabel(L["The raid's members and groups as one string. Ctrl+C to copy:"])
    self.editBox:SetText(self.text)
    self.editBox:SetFocus()
    self.editBox:HighlightText()
    local status = format(L["Exported %d raid members. Ctrl+C to copy."], #payload.members)
    if skipped > 0 then
        status = status .. " |cffffa040" .. format(L["%d not loaded yet: press Refresh."], skipped) .. "|r"
    end
    self.frame:SetStatusText(status)
end

function RosterDialog:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["Export raid"])
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetWidth(520)
    frame:SetHeight(330)
    frame.frame:SetFrameStrata("DIALOG")   -- above the Raid Plan window it is opened from
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        self.frame, self.editBox, self.text = nil, nil, nil
        AceGUI:Release(widget)
    end)
    self.frame = frame

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
    frame:AddChild(editBox)
    self.editBox = editBox

    local refresh = AceGUI:Create("Button")
    refresh:SetText(L["Refresh"])
    refresh:SetWidth(140)
    refresh:SetCallback("OnClick", function() self:Refresh() end)
    frame:AddChild(refresh)

    -- Close with Escape
    _G[FRAME_GLOBAL] = frame.frame
    if not specialFrameAdded then
        tinsert(UISpecialFrames, FRAME_GLOBAL)
        specialFrameAdded = true
    end
end

-- The Groups section's Export raid and `/utrm roster`: opens the dialog, or makes the string again when it is open
function RosterDialog:Open()
    if not self.frame then self:Create() end
    self:Refresh()
end
