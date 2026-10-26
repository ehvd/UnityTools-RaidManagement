local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local GroupPlan = ns.GroupPlan

-- Sorts the raid into the active encounter's planned groups. The checks (raid, lead or assist, combat) are made here
-- so the plan window can say why nothing moved; the moving itself is Method Raid Tools' sorter (Modules/MRT.lua).
-- After asking MRT, the roster is watched until the groups match the plan or WATCH_SECONDS pass.
local RaidGroups = UTRM:NewModule("RaidGroups", "AceEvent-3.0", "AceTimer-3.0")

local WATCH_SECONDS = 15

-- The raid as GroupPlan wants it: { { name = "Name" or "Name-Realm", group = 1..8 }, ... }
local function currentRoster()
    local roster = {}
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            roster[#roster + 1] = { name = name, group = subgroup }
        end
    end
    return roster
end

local function anyoneInCombat()
    if InCombatLockdown() then return true end
    for i = 1, GetNumGroupMembers() do
        if UnitAffectingCombat("raid" .. i) then return true end
    end
    return false
end

-- "(2 missing, 1 not in the plan)" or ""
local function counts(result)
    local parts = {}
    if #result.missing > 0 then parts[#parts + 1] = format(L["%d missing"], #result.missing) end
    if #result.extra > 0 then parts[#parts + 1] = format(L["%d not in the plan"], #result.extra) end
    return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

-- Lines for the status tooltip: who is missing and who is not in the plan
local function details(result)
    local lines = {}
    if #result.missing > 0 then
        lines[#lines + 1] = L["Missing from the raid:"] .. " " .. table.concat(result.missing, ", ")
    end
    if #result.extra > 0 then
        lines[#lines + 1] = L["In the raid but not in the plan:"] .. " " .. table.concat(result.extra, ", ")
    end
    return lines
end

function RaidGroups:Report(text, result, failed)
    UTRM.PlanWindow:SetGroupStatus(failed and ("|cffff4040" .. text .. "|r") or text, result and details(result) or {})
end

function RaidGroups:StopWatching()
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    if self.watchTimer then
        self:CancelTimer(self.watchTimer)
        self.watchTimer = nil
    end
    self.watching = nil
end

-- Called on roster updates while MRT sorts: done once nobody planned is in the wrong group
function RaidGroups:CheckProgress()
    if not self.watching then return end
    local result = GroupPlan.Compare(self.watching, currentRoster())
    if result.misplaced == 0 then
        self:StopWatching()
        self:Report(L["Groups sorted"] .. counts(result), result)
    end
end

-- Sorts the raid into `layout` (the active encounter's 40 planned names)
function RaidGroups:Apply(layout)
    self:StopWatching()
    if not layout then return end
    if not IsInRaid() then
        self:Report(L["Groups: not in a raid"])
        return
    end
    local result = GroupPlan.Compare(layout, currentRoster())
    if result.misplaced == 0 then
        self:Report(L["Groups already match"] .. counts(result), result)
        return
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        self:Report(L["Groups: you need lead or assist"], result, true)
        return
    end
    if anyoneInCombat() then
        self:Report(L["Groups: someone is in combat"], result, true)
        return
    end

    local ok, message = UTRM:GetModule("MRT"):ApplyGroups(result.list)
    if not ok then
        self:Report(message, result, true)
        return
    end
    self.watching = layout
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "CheckProgress")
    self.watchTimer = self:ScheduleTimer(function()
        self.watchTimer = nil
        if not self.watching then return end
        local now = GroupPlan.Compare(self.watching, currentRoster())
        self:StopWatching()
        self:Report(format(L["Groups not finished: %d still in the wrong group"], now.misplaced) .. counts(now), now, true)
    end, WATCH_SECONDS)
    self:Report(L["Sorting groups..."] .. counts(result), result)
end
