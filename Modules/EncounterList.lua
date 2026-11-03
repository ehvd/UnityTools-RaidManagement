local _, ns = ...

-- Changing the plan's encounter list in game (the Raid Plan window's Encounters section, issue #44): adding a boss or
-- a custom encounter, removing, renaming and reordering. Pure Lua, no WoW API, so tests/encounter-list can run it
-- outside the game. Each function changes the plan in place, inside PlanImport:Edit.
local EncounterList = {}
ns.EncounterList = EncounterList

local function indexOf(plan, key)
    for i, encounter in ipairs(plan.encounters) do
        if encounter.key == key then return i end
    end
    return nil
end
EncounterList.IndexOf = indexOf

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A key no encounter of the plan has. The planner's keys are "raid:boss" for its bosses and "x:n" for its own
-- entries: a boss gets "raid:boss" (or "raid:boss-2", "raid:boss-3" ...), a custom encounter the next "x:n".
function EncounterList.NewKey(plan, raid, boss)
    local used, highest = {}, 0
    for _, encounter in ipairs(plan.encounters) do
        used[encounter.key] = true
        local n = tonumber(encounter.key:match("^x:(%d+)$"))
        if n and n > highest then highest = n end
    end
    if not boss then
        local n = highest + 1
        while used["x:" .. n] do n = n + 1 end
        return "x:" .. n
    end
    local base = boss:find(":", 1, true) and boss or (raid .. ":" .. boss)
    if not used[base] then return base end
    local n = 2
    while used[base .. "-" .. n] do n = n + 1 end
    return base .. "-" .. n
end

-- Adds an encounter at the end: `label`, and for a boss of the boss table (Modules/Bosses.lua) `boss` =
-- { slug = raid, key = boss key, encounterId = n }. It starts with an empty note on the night's groups. Returns its
-- index, or nil and "label" (no name).
function EncounterList.Add(plan, label, boss)
    label = trim(label)
    if label == "" then return nil, "label" end
    local encounter = {
        key = EncounterList.NewKey(plan, boss and boss.slug, boss and boss.key),
        label = label,
        raid = boss and boss.slug or nil,
        encounterId = boss and boss.encounterId or nil,
        note = "",
        layout = "default",
    }
    plan.encounters[#plan.encounters + 1] = encounter
    return #plan.encounters
end

-- Removes the encounter `key`, and with it what pointed at it: the active encounter becomes the next one (the previous
-- one when it was the last, none when it was the only one), the note after a kill goes back to none, and its own
-- groups go when no other encounter uses them. Returns the removed encounter and the new active index when the active
-- one was removed (nil when none is left), or nil and "encounter" (no longer in the plan).
function EncounterList.Remove(plan, key)
    local index = indexOf(plan, key)
    if not index then return nil, "encounter" end
    local removed = table.remove(plan.encounters, index)
    if plan.fallback == key then plan.fallback = nil end
    if removed.layout ~= "default" and plan.layouts[removed.layout] then
        local used
        for _, encounter in ipairs(plan.encounters) do
            if encounter.layout == removed.layout then used = true end
        end
        if not used then plan.layouts[removed.layout] = nil end
    end
    local active
    if plan.active == key then
        active = math.min(index, #plan.encounters)
        if active == 0 then active = nil end
        plan.active = active and plan.encounters[active].key or nil
    end
    return removed, active
end

-- Gives the encounter `key` a new label; its key and encounter ID stay, so the sync and the note after a kill still
-- match. Returns true, or nil and "encounter" / "label" (no name) / "unchanged".
function EncounterList.Rename(plan, key, label)
    local index = indexOf(plan, key)
    if not index then return nil, "encounter" end
    label = trim(label)
    if label == "" then return nil, "label" end
    if plan.encounters[index].label == label then return nil, "unchanged" end
    plan.encounters[index].label = label
    return true
end

-- Moves the encounter `key` one place up (`by` -1) or down (1). Returns its new index, or nil and "encounter" /
-- "edge" (already first or last).
function EncounterList.Move(plan, key, by)
    local index = indexOf(plan, key)
    if not index then return nil, "encounter" end
    local to = index + by
    if to < 1 or to > #plan.encounters then return nil, "edge" end
    local encounters = plan.encounters
    encounters[index], encounters[to] = encounters[to], encounters[index]
    return to
end

-- The boss picker's raids: the boss table's (`Bosses.Raids()`), the plan's own raids first, in the plan's order
function EncounterList.Raids(Bosses, plan)
    local planned, order = {}, {}
    for _, raid in ipairs(plan.event and plan.event.raids or {}) do
        planned[raid.slug] = #order + 1
        order[#order + 1] = raid.slug
    end
    local first, rest = {}, {}
    for _, raid in ipairs(Bosses.Raids()) do
        if planned[raid.slug] then
            first[planned[raid.slug]] = raid
        else
            rest[#rest + 1] = raid
        end
    end
    local raids = {}
    for i = 1, #order do
        if first[i] then raids[#raids + 1] = first[i] end
    end
    for _, raid in ipairs(rest) do raids[#raids + 1] = raid end
    return raids
end

-- Whether the plan already has the boss with `encounterId`
function EncounterList.HasBoss(plan, encounterId)
    if not encounterId then return false end
    for _, encounter in ipairs(plan.encounters) do
        if encounter.encounterId == encounterId then return true end
    end
    return false
end
