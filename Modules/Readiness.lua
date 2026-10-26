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

local function isLeadOrAssist()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

------------------------------------------------------------------------------------------------- fixes ---
-- Each fix runs on a click in the readiness menu and returns true or false and a message for the status line
-- (nil message: the fix reports itself, like the group sorting).

-- Master Loot with the player as master looter; who loots can then be changed with Blizzard's own menus
local function setMasterLoot()
    if not UnitIsGroupLeader("player") then
        return false, L["Only the raid leader can change the loot method."]
    end
    if InCombatLockdown() then
        return false, L["The loot method cannot be changed in combat."]
    end
    local me = UnitName("player")
    if SetLootMethod then
        SetLootMethod("master", me)
    elseif C_PartyInfo and C_PartyInfo.SetLootMethod then
        C_PartyInfo.SetLootMethod(2, me)
    else
        return false, L["This client cannot change the loot method from an addon."]
    end
    return true, L["Master Loot set: you are the master looter."]
end

local function inviteUnit(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    else
        InviteUnit(name)
    end
end

-- Invites the planned players who are not in the raid, by the plan's names
local function inviteMissing(missing)
    if not isLeadOrAssist() then
        return false, L["Only the raid leader or an assistant can invite."]
    end
    for _, name in ipairs(missing) do
        inviteUnit(name)
    end
    return true, format(L["Invited %d players: %s"], #missing, table.concat(missing, ", "))
end

------------------------------------------------------------------------------------------------ checks ---
-- Each check gets the context (plan, the active encounter's layout and the roster compared with it) and returns nil
-- when it does not apply, or
--   { ok = true/false, text = "...", details = { "..." }, fix = { label = "...", run = function } or hint = "..." }
-- `fix` is offered in the readiness menu; a problem without a fix shows its `hint` there instead.
local CHECKS = {
    function()
        local method = lootMethod()
        if method == "master" then
            return { ok = true, text = L["Loot method: Master Loot"] }
        end
        return { ok = false, text = format(L["Loot method is %s, not Master Loot"], lootMethodName(method)),
            fix = { label = L["Set Master Loot (you loot)"], run = setMasterLoot } }
    end,

    function()
        local _, reason = UTRM:GetModule("MRT"):GetNoteModule()
        if reason then
            return { ok = false, text = reason, hint = L["Enable Method Raid Tools in the AddOns list and reload."] }
        end
        return { ok = true, text = L["Method Raid Tools is loaded"] }
    end,

    function(context)
        local state = UTRM:GetModule("Gargul"):GetState(context.plan)
        if not state then return nil end
        if state == "current" then
            return { ok = true, text = L["Gargul has the plan's loot priorities"] }
        end
        return { ok = false, text = L["Gargul does not have the plan's loot priorities"],
            fix = { label = L["Import the loot priorities into Gargul"],
                run = function() return UTRM:GetModule("Gargul"):ImportPlan(context.plan) end } }
    end,

    -- Who is in the raid, compared with the active encounter's groups (the night's before one is chosen)
    function(context)
        local result = context.compared
        if not result then return nil end
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
        local check = { ok = false, details = details,
            text = format(L["Raid differs from the plan: %d missing, %d not in the plan"], #result.missing, #result.extra) }
        if #result.missing > 0 then
            local missing = result.missing
            check.fix = { label = format(L["Invite %d missing players"], #missing), run = function() return inviteMissing(missing) end }
        else
            check.hint = L["Players not in the plan are not removed automatically."]
        end
        return check
    end,

    -- Whether the planned players present are in their planned groups
    function(context)
        local result = context.compared
        if not result then return nil end
        if result.misplaced == 0 then
            return { ok = true, text = L["Groups match the plan"] }
        end
        local layout = context.layout
        return { ok = false, text = format(L["%d players in the wrong group"], result.misplaced),
            fix = { label = L["Sort groups"], run = function() UTRM:GetModule("RaidGroups"):Apply(layout) end } }
    end,
}

-- { inRaid = false } outside a raid; otherwise { inRaid = true, checks = { ... }, problems = n }
function Readiness:Evaluate()
    if not IsInRaid() then
        return { inRaid = false, checks = {}, problems = 0 }
    end
    local plan = UTRM:GetModule("PlanImport"):GetPlan()
    local context = { plan = plan }
    if plan then
        local layoutKey = "default"
        for _, encounter in ipairs(plan.encounters) do
            if encounter.key == plan.active then layoutKey = encounter.layout end
        end
        context.layout = plan.layouts[layoutKey] or plan.layouts.default
        context.compared = GroupPlan.Compare(context.layout, currentRoster())
    end
    local checks, problems = {}, 0
    for _, check in ipairs(CHECKS) do
        local ok, result = pcall(check, context)
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
