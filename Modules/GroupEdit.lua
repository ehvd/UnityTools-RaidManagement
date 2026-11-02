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

------------------------------------------------------------------------------------------------- people ---
-- Adding players to the plan by hand and taking them out (issue #52). The plan's people are `name -> { class }`
-- (protocol 2; a protocol 1 plan gets them when a player is added).

-- The nine classes of Classic Era, in Blizzard's order (CLASS_SORT_ORDER without the later ones)
GroupEdit.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- A typed name as WoW spells it: trimmed, the first letter upper case and the rest lower case (ASCII only, like
-- GroupPlan.Key; a realm after "-" is kept as typed)
function GroupEdit.CleanName(text)
    local name = (text or ""):match("^%s*(.-)%s*$")
    local character, realm = name:match("^([^-]*)(.*)$")
    return character:sub(1, 1):upper() .. character:sub(2):lower() .. realm
end

-- nil when `name` (cleaned) can be added, else "empty" or "taken" (`taken(name)`: in the plan or the raid already)
function GroupEdit.CheckNewName(name, taken)
    if name == "" or name:sub(1, 1) == "-" then return "empty" end
    if taken(name) then return "taken" end
    return nil
end

-- The name the plan's people spell like `name` (GroupPlan.Key), or nil
function GroupEdit.PersonOf(plan, name)
    local key = ns.GroupPlan.Key(name)
    for person in pairs(plan.people or {}) do
        if ns.GroupPlan.Key(person) == key then return person end
    end
    return nil
end

-- Whether the plan names `name` (any spelling): among its people or in one of its layouts
function GroupEdit.InPlan(plan, name)
    if GroupEdit.PersonOf(plan, name) then return true end
    for _, layout in pairs(plan.layouts) do
        if GroupEdit.Find(layout, name) then return true end
    end
    return false
end

-- Adds `name` of `class` to the plan's people. Returns the name, or nil and "taken" (the plan names them already).
function GroupEdit.AddPerson(plan, name, class)
    if GroupEdit.InPlan(plan, name) then return nil, "taken" end
    plan.people = plan.people or {}
    plan.people[name] = { class = class }
    return name
end

-- Takes `name` (any spelling) out of the plan's people and every layout. Returns whether the plan changed.
function GroupEdit.RemovePerson(plan, name)
    local changed = false
    local person = GroupEdit.PersonOf(plan, name)
    if person then
        plan.people[person] = nil
        changed = true
    end
    for _, layout in pairs(plan.layouts) do
        local slot = GroupEdit.Find(layout, name)
        while slot do
            layout[slot] = ""
            changed = true
            slot = GroupEdit.Find(layout, name)
        end
    end
    return changed
end

-- Where else the plan uses `name`, besides the layout `layoutKey`: { groups = encounters whose groups (another
-- layout) have them, holds = encounters whose assignments (slots' holders) name them, night = true when the night's
-- groups have them but no encounter uses them }. The encounters are in plan order.
function GroupEdit.UsesOf(plan, name, layoutKey)
    local key = ns.GroupPlan.Key(name)
    local uses = { groups = {}, holds = {} }
    for _, encounter in ipairs(plan.encounters) do
        local layout = plan.layouts[encounter.layout]
        if encounter.layout ~= layoutKey and layout and GroupEdit.Find(layout, name) then
            uses.groups[#uses.groups + 1] = encounter
        end
        local holds = false
        for _, slot in ipairs(encounter.slots or {}) do
            for _, holder in ipairs(slot.holders or {}) do
                if ns.GroupPlan.Key(holder) == key then holds = true end
            end
        end
        if holds then uses.holds[#uses.holds + 1] = encounter end
    end
    uses.night = layoutKey ~= "default" and plan.layouts.default ~= nil
        and GroupEdit.Find(plan.layouts.default, name) ~= nil and #GroupEdit.UsersOf(plan, "default") == 0
    return uses
end

-- Saves the Groups section's draft: the players `removed` (names) leave the plan, the `added` ({ name, class }) join
-- its people, then `layout` goes into the layout `layoutKey`. Returns `layoutKey`, or nil and "unchanged" /
-- "layout" (the layout is no longer in the plan).
function GroupEdit.SaveDraft(plan, layoutKey, layout, added, removed)
    if not plan.layouts[layoutKey] then return nil, "layout" end
    local changed = false
    for _, name in ipairs(removed or {}) do
        if GroupEdit.RemovePerson(plan, name) then changed = true end
    end
    for _, person in ipairs(added or {}) do
        if GroupEdit.AddPerson(plan, person.name, person.class) then changed = true end
    end
    layout = GroupEdit.Copy(layout)
    for _, name in ipairs(removed or {}) do
        local slot = GroupEdit.Find(layout, name)
        if slot then layout[slot] = "" end
    end
    if GroupEdit.Save(plan, layoutKey, layout) then changed = true end
    if not changed then return nil, "unchanged" end
    return layoutKey
end
