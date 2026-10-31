local _, ns = ...

-- Changing a layout in the groups editor (UI/GroupEditor.lua, issue #26): moving and swapping players between the
-- 40 slots, and saving the result into the plan. Pure Lua, no WoW API, so tests/group-edit can run it outside the
-- game. Slots are 1..40 in MRT's raid-groups order (Modules/GroupPlan.lua); "" is an empty slot.
local GroupEdit = {}
ns.GroupEdit = GroupEdit

local SLOTS = 40

function GroupEdit.Copy(layout)
    local copy = {}
    for slot = 1, SLOTS do
        copy[slot] = layout[slot] or ""
    end
    return copy
end

function GroupEdit.Equal(a, b)
    for slot = 1, SLOTS do
        if (a[slot] or "") ~= (b[slot] or "") then return false end
    end
    return true
end

-- The slot that holds `name` (any spelling, GroupPlan.Key), or nil
function GroupEdit.Find(layout, name)
    local key = ns.GroupPlan.Key(name)
    for slot = 1, SLOTS do
        if layout[slot] ~= "" and ns.GroupPlan.Key(layout[slot]) == key then return slot end
    end
    return nil
end

-- Moves the player in slot `from` to slot `to`; whoever was in `to` takes `from` (an empty slot just moves)
function GroupEdit.Swap(layout, from, to)
    layout[from], layout[to] = layout[to], layout[from]
end

-- Puts `name` (a raid member from the list, or a player already in the layout) into `slot`. A player already in the
-- layout swaps with the slot; otherwise the slot's player leaves the layout.
function GroupEdit.Place(layout, slot, name)
    local from = GroupEdit.Find(layout, name)
    if from then
        GroupEdit.Swap(layout, from, slot)
    else
        layout[slot] = name
    end
end

-- Takes the player out of the layout: the slot is empty
function GroupEdit.Remove(layout, slot)
    layout[slot] = ""
end

-- A layout key not used in `layouts`: `base`, or "base (2)", "base (3)" ...
function GroupEdit.NewKey(layouts, base)
    if not layouts[base] then return base end
    local n = 2
    while layouts[string.format("%s (%d)", base, n)] do n = n + 1 end
    return string.format("%s (%d)", base, n)
end

-- Saves `layout` for the encounter with `encounterKey`: into the layout the encounter uses (every encounter on that
-- layout changes), or with `onlyThis` on an encounter that uses the night's groups ("default"), into a new layout
-- named after the encounter that only it uses (the planner names its layouts the same way).
-- Returns the layout key it saved into, or nil and "unchanged" / "encounter" (the encounter is no longer in the plan).
function GroupEdit.Save(plan, encounterKey, layout, onlyThis)
    local encounter
    for _, candidate in ipairs(plan.encounters) do
        if candidate.key == encounterKey then encounter = candidate end
    end
    if not encounter then return nil, "encounter" end
    local key = encounter.layout
    if GroupEdit.Equal(plan.layouts[key], layout) then return nil, "unchanged" end
    if onlyThis and key == "default" then
        key = GroupEdit.NewKey(plan.layouts, encounter.label)
        encounter.layout = key
    end
    plan.layouts[key] = GroupEdit.Copy(layout)
    return key
end
