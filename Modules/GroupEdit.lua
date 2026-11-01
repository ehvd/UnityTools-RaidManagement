local _, ns = ...

-- Changing a layout in the groups editor (UI/GroupEditor.lua, issue #26): moving and swapping players between the
-- 40 slots, the bench, saving into the plan, and giving an encounter its own groups (an override of the night's
-- groups) or taking them away. Pure Lua, no WoW API, so tests/group-edit can run it outside the
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

local function findEncounter(plan, key)
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key == key then return encounter end
    end
    return nil
end

-- The encounters on the layout `layoutKey`, in plan order (but `except`, an encounter key)
function GroupEdit.UsersOf(plan, layoutKey, except)
    local users = {}
    for _, encounter in ipairs(plan.encounters) do
        if encounter.layout == layoutKey and encounter.key ~= except then users[#users + 1] = encounter end
    end
    return users
end

-- Saves `layout` into the plan's layout `layoutKey` (every encounter on it changes). Returns `layoutKey`, or nil and
-- "unchanged" / "layout" (the layout is no longer in the plan).
function GroupEdit.Save(plan, layoutKey, layout)
    local saved = plan.layouts[layoutKey]
    if not saved then return nil, "layout" end
    if GroupEdit.Equal(saved, layout) then return nil, "unchanged" end
    plan.layouts[layoutKey] = GroupEdit.Copy(layout)
    return layoutKey
end

-- Gives the encounter `encounterKey`, which uses the night's groups ("default"), its own groups: a copy of the night's
-- groups in a new layout named after the encounter (the planner names its layouts the same way) that only it uses.
-- Returns the new layout key, or nil and "encounter" (no longer in the plan) / "override" (it has its own groups).
function GroupEdit.CreateOverride(plan, encounterKey)
    local encounter = findEncounter(plan, encounterKey)
    if not encounter then return nil, "encounter" end
    if encounter.layout ~= "default" then return nil, "override" end
    local key = GroupEdit.NewKey(plan.layouts, encounter.label)
    plan.layouts[key] = GroupEdit.Copy(plan.layouts.default)
    encounter.layout = key
    return key
end

-- Points the encounter `encounterKey` back to the night's groups; its layout is removed when no other encounter uses
-- it. Returns the layout key it used and whether that was removed, or nil and "encounter" / "default" (it already
-- uses the night's groups).
function GroupEdit.DeleteOverride(plan, encounterKey)
    local encounter = findEncounter(plan, encounterKey)
    if not encounter then return nil, "encounter" end
    local key = encounter.layout
    if key == "default" then return nil, "default" end
    encounter.layout = "default"
    local removed = #GroupEdit.UsersOf(plan, key) == 0
    if removed then plan.layouts[key] = nil end
    return key, removed
end

-- The bench: of `names` (the plan's people and planned players), the ones who are neither in `layout` nor in the raid
-- (`inRaid(name)`), once each (GroupPlan.Key), sorted
function GroupEdit.Bench(names, layout, inRaid)
    local bench, seen = {}, {}
    for _, name in ipairs(names) do
        local key = ns.GroupPlan.Key(name)
        if name ~= "" and not seen[key] and not GroupEdit.Find(layout, name) and not inRaid(name) then
            seen[key] = true
            bench[#bench + 1] = name
        end
    end
    table.sort(bench, function(a, b) return a:lower() < b:lower() end)
    return bench
end
