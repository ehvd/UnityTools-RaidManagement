local _, ns = ...

-- The fallback note (issue #29): after a boss kill the raid leader's client makes the plan's fallback encounter
-- active (a night note such as Trash). This decides whether a kill switches, and to what. Pure Lua, no WoW API, so
-- tests/fallback-rules can run it outside the game.
local FallbackRules = {}
ns.FallbackRules = FallbackRules

-- `kill` describes ENCOUNTER_END: { encounterId = n, name = "...", success = true/false }. `isLeader`: this client is
-- the raid leader's (only it switches, the others follow through the sync).
-- Returns the fallback's index in plan.encounters and the killed boss's name (the plan's label when the plan knows
-- the boss), or nil and why not: "leader", "wipe", "none" (no fallback), "boss" (not a boss of the plan), "active".
-- A plan with encounter IDs (export protocol 2) switches only for its own bosses; one without switches on any kill.
function FallbackRules.Decide(plan, kill, isLeader)
    if not isLeader then return nil, "leader" end
    if not kill.success then return nil, "wipe" end
    if not plan or not plan.fallback then return nil, "none" end
    local fallback, killed, hasIds
    for i, encounter in ipairs(plan.encounters) do
        if encounter.key == plan.fallback then fallback = i end
        if encounter.encounterId then
            hasIds = true
            if encounter.encounterId == kill.encounterId and not killed then killed = encounter end
        end
    end
    if not fallback then return nil, "none" end
    if hasIds and not killed then return nil, "boss" end
    if plan.active == plan.fallback then return nil, "active" end
    return fallback, killed and killed.label or kill.name
end

-- The fallback encounter of a plan, or nil (none chosen, or its encounter is no longer in the plan)
function FallbackRules.Encounter(plan)
    if not plan or not plan.fallback then return nil end
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key == plan.fallback then return encounter end
    end
    return nil
end
