local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local GroupPlan = ns.GroupPlan

-- Raid readiness: a list of small checks, each giving ok or a problem. The plan window shows the result as one icon
-- with a tooltip. Outside a raid nothing is checked (no false alarms). More checks can be added to CHECKS later
-- (master looter's name, loot threshold, consumables).
local Readiness = UTRM:NewModule("Readiness", "AceEvent-3.0")

-- Blizzard's own names for the loot methods (UnitPopup), so they read in the player's language
local LOOT_METHOD_NAMES = {
    freeforall = "LOOT_FREE_FOR_ALL",
    roundrobin = "LOOT_ROUND_ROBIN",
    master = "LOOT_MASTER_LOOTER",
    group = "LOOT_GROUP_LOOT",
    needbeforegreed = "LOOT_NEED_BEFORE_GREED",
}
-- C_PartyInfo.GetLootMethod returns a number where GetLootMethod does not exist
local LOOT_METHOD_IDS = { [0] = "freeforall", "roundrobin", "master", "group", "needbeforegreed", "personalloot" }

local function lootMethod()
    if GetLootMethod then
        return (GetLootMethod())
    end
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        return LOOT_METHOD_IDS[C_PartyInfo.GetLootMethod()]
    end
    return nil
end

local function lootMethodName(method)
    local global = LOOT_METHOD_NAMES[method]
    return global and _G[global] or tostring(method)
end

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

-- Each check returns nil when it does not apply, or { ok = true/false, text = "...", details = { "..." } }
local CHECKS = {
    function()
        local method = lootMethod()
        if method == "master" then
            return { ok = true, text = L["Loot method: Master Loot"] }
        end
        return { ok = false, text = format(L["Loot method is %s, not Master Loot"], lootMethodName(method)) }
    end,

    function()
        local _, reason = UTRM:GetModule("MRT"):GetNoteModule()
        if reason then
            return { ok = false, text = reason }
        end
        return { ok = true, text = L["Method Raid Tools is loaded"] }
    end,

    function(plan)
        local state = UTRM:GetModule("Gargul"):GetState(plan)
        if not state then return nil end
        if state == "current" then
            return { ok = true, text = L["Gargul has the plan's loot priorities"] }
        end
        return { ok = false, text = L["Gargul does not have the plan's loot priorities (import them from the options)"] }
    end,

    -- The active encounter's groups, or the night's before an encounter is chosen
    function(plan)
        if not plan then return nil end
        local layoutKey = "default"
        for _, encounter in ipairs(plan.encounters) do
            if encounter.key == plan.active then layoutKey = encounter.layout end
        end
        local result = GroupPlan.Compare(plan.layouts[layoutKey] or plan.layouts.default, currentRoster())
        if #result.missing == 0 and #result.extra == 0 then
            return { ok = true, text = L["Everyone planned is in the raid"] }
        end
        local details = {}
        if #result.missing > 0 then
            details[#details + 1] = L["Missing from the raid:"] .. " " .. table.concat(result.missing, ", ")
        end
        if #result.extra > 0 then
            details[#details + 1] = L["In the raid but not in the plan:"] .. " " .. table.concat(result.extra, ", ")
        end
        return { ok = false, text = format(L["Raid differs from the plan: %d missing, %d not in the plan"],
            #result.missing, #result.extra), details = details }
    end,
}

-- { inRaid = false } outside a raid; otherwise { inRaid = true, checks = { ... }, problems = n }
function Readiness:Evaluate()
    if not IsInRaid() then
        return { inRaid = false, checks = {}, problems = 0 }
    end
    local plan = UTRM:GetModule("PlanImport"):GetPlan()
    local checks, problems = {}, 0
    for _, check in ipairs(CHECKS) do
        local ok, result = pcall(check, plan)
        if not ok then
            geterrorhandler()(result)
        elseif result then
            checks[#checks + 1] = result
            if not result.ok then problems = problems + 1 end
        end
    end
    return { inRaid = true, checks = checks, problems = problems }
end

function Readiness:Changed()
    if UTRM.PlanWindow then
        UTRM.PlanWindow:UpdateReadiness()
    end
end

function Readiness:OnEnable()
    for _, event in ipairs({ "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        self:RegisterEvent(event, "Changed")
    end
    for _, message in ipairs({ "UTRM_PLAN_IMPORTED", "UTRM_ENCOUNTER_ACTIVATED", "UTRM_GARGUL_IMPORTED" }) do
        self:RegisterMessage(message, "Changed")
    end
end
