local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local Rules = ns.FallbackRules

-- After a boss kill, the raid leader's client makes the plan's fallback encounter active, as if chosen in the plan
-- window: its note goes to MRT, its groups are sorted (once nobody is in combat) and the sync tells the raid, whose
-- windows follow. What switches when: Modules/FallbackRules.lua. Choosing the fallback: the plan window's ⚙ menu.
local Fallback = UTRM:NewModule("Fallback", "AceEvent-3.0")

function Fallback:OnEncounterEnd(_, encounterId, encounterName, _, _, success)
    local plan = UTRM:GetModule("PlanImport"):GetPlan()
    local kill = { encounterId = encounterId, name = encounterName, success = success == 1 or success == true }
    local index, killed = Rules.Decide(plan, kill, IsInRaid() and UnitIsGroupLeader("player"))
    if not index then return end
    UTRM.PlanWindow:Activate(index, format(L["%s killed: switched to %s"], killed, plan.encounters[index].label))
end

function Fallback:OnEnable()
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
end
