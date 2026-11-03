local _, ns = ...

-- Changing a layout in the groups editor (UI/GroupEditor.lua, issue #26): moving and swapping players between the
-- 40 slots, the bench, the shared layouts (which encounter uses which, new and deleted layouts, issue #55) and saving
-- it all into the plan. Pure Lua, no WoW API, so tests/group-edit can run it outside the
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

------------------------------------------------------------------------------------------------ layouts ---
-- Shared layouts (issue #55). The Groups section edits a draft of all the plan's group layouts at once:
-- { layouts = layout key -> 40 names (copies), uses = encounter key -> layout key }. "default" (Default, the night's
-- groups) always exists; every other layout is named and may be used by any number of encounters.

function GroupEdit.NewDraft(plan)
    local draft = { layouts = {}, uses = {} }
    for key, layout in pairs(plan.layouts) do
        draft.layouts[key] = GroupEdit.Copy(layout)
    end
    for _, encounter in ipairs(plan.encounters) do
        draft.uses[encounter.key] = encounter.layout
    end
    return draft
end

function GroupEdit.CopyDraft(draft)
    local copy = { layouts = {}, uses = {} }
    for key, layout in pairs(draft.layouts) do
        copy.layouts[key] = GroupEdit.Copy(layout)
    end
    for key, layoutKey in pairs(draft.uses) do
        copy.uses[key] = layoutKey
    end
    return copy
end

local function sameKeys(a, b, same)
    for key, value in pairs(a) do
        if b[key] == nil or not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

function GroupEdit.SameDraft(a, b)
    return sameKeys(a.layouts, b.layouts, GroupEdit.Equal)
        and sameKeys(a.uses, b.uses, function(x, y) return x == y end)
end

-- The layout the encounter `encounterKey` uses in the draft ("default" when it names one that does not exist)
function GroupEdit.LayoutOf(draft, encounterKey)
    local key = draft.uses[encounterKey]
    return (key and draft.layouts[key]) and key or "default"
end

-- The named layouts (all but "default"), sorted by name
function GroupEdit.LayoutKeys(draft)
    local keys = {}
    for key in pairs(draft.layouts) do
        if key ~= "default" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end)
    return keys
end

-- The encounters of `plan` on the layout `layoutKey` in the draft, in plan order (but `except`, an encounter key)
function GroupEdit.UsersOf(plan, draft, layoutKey, except)
    local users = {}
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key ~= except and GroupEdit.LayoutOf(draft, encounter.key) == layoutKey then
            users[#users + 1] = encounter
        end
    end
    return users
end

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

-- nil when `name` (trimmed) can name a new layout, else "empty" or "taken" (a layout of that name in any case,
-- "Default" included)
function GroupEdit.CheckLayoutName(draft, name)
    name = trim(name)
    if name == "" then return "empty" end
    local lower = name:lower()
    if lower == "default" then return "taken" end
    for key in pairs(draft.layouts) do
        if key:lower() == lower then return "taken" end
    end
    return nil
end

-- A new layout `name` (trimmed) for the encounter `encounterKey`: a copy of the layout it uses now, and the encounter
-- on it. Returns the new layout key, or nil and "empty" / "taken" (CheckLayoutName) / "encounter" (not in the draft).
function GroupEdit.NewLayout(draft, encounterKey, name)
    if draft.uses[encounterKey] == nil then return nil, "encounter" end
    local why = GroupEdit.CheckLayoutName(draft, name)
    if why then return nil, why end
    name = trim(name)
    draft.layouts[name] = GroupEdit.Copy(draft.layouts[GroupEdit.LayoutOf(draft, encounterKey)])
    draft.uses[encounterKey] = name
    return name
end

-- Points the encounter `encounterKey` at the layout `layoutKey`. Returns `layoutKey`, or nil and "encounter" /
-- "layout" (not in the draft).
function GroupEdit.UseLayout(draft, encounterKey, layoutKey)
    if draft.uses[encounterKey] == nil then return nil, "encounter" end
    if not draft.layouts[layoutKey] then return nil, "layout" end
    draft.uses[encounterKey] = layoutKey
    return layoutKey
end

-- Deletes the named layout `layoutKey`; the encounters on it go back to "default". Returns how many moved, or nil and
-- "default" (it can't be deleted) / "layout" (not in the draft).
function GroupEdit.DeleteLayout(draft, layoutKey)
    if layoutKey == "default" then return nil, "default" end
    if not draft.layouts[layoutKey] then return nil, "layout" end
    draft.layouts[layoutKey] = nil
    local moved = 0
    for encounterKey, used in pairs(draft.uses) do
        if used == layoutKey then
            draft.uses[encounterKey] = "default"
            moved = moved + 1
        end
    end
    return moved
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

-- Where else the draft uses `name`, besides the layout `layoutKey`: { groups = encounters whose groups (another
-- layout) have them, holds = encounters whose assignments (slots' holders) name them, night = true when Default has
-- them but no encounter uses it }. The encounters are in plan order.
function GroupEdit.UsesOf(plan, draft, name, layoutKey)
    local key = ns.GroupPlan.Key(name)
    local uses = { groups = {}, holds = {} }
    for _, encounter in ipairs(plan.encounters) do
        local layoutOf = GroupEdit.LayoutOf(draft, encounter.key)
        if layoutOf ~= layoutKey and GroupEdit.Find(draft.layouts[layoutOf], name) then
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
    uses.night = layoutKey ~= "default" and draft.layouts.default ~= nil
        and GroupEdit.Find(draft.layouts.default, name) ~= nil and #GroupEdit.UsersOf(plan, draft, "default") == 0
    return uses
end

-- Saves the Groups section's draft: the players `removed` (names) leave the plan, the `added` ({ name, class }) join
-- its people, then the draft's layouts replace the plan's and each encounter of the plan uses its draft layout.
-- Returns true, or nil and "unchanged".
function GroupEdit.SaveDraft(plan, draft, added, removed)
    local changed = false
    for _, name in ipairs(removed or {}) do
        if GroupEdit.RemovePerson(plan, name) then changed = true end
    end
    for _, person in ipairs(added or {}) do
        if GroupEdit.AddPerson(plan, person.name, person.class) then changed = true end
    end
    local saved = { layouts = {}, uses = {} }
    for key, layout in pairs(draft.layouts) do
        layout = GroupEdit.Copy(layout)
        for _, name in ipairs(removed or {}) do
            local slot = GroupEdit.Find(layout, name)
            while slot do
                layout[slot] = ""
                slot = GroupEdit.Find(layout, name)
            end
        end
        saved.layouts[key] = layout
    end
    for _, encounter in ipairs(plan.encounters) do
        saved.uses[encounter.key] = GroupEdit.LayoutOf(draft, encounter.key)
    end
    if not GroupEdit.SameDraft(GroupEdit.NewDraft(plan), saved) then
        plan.layouts = saved.layouts
        for _, encounter in ipairs(plan.encounters) do
            encounter.layout = saved.uses[encounter.key]
        end
        changed = true
    end
    if not changed then return nil, "unchanged" end
    return true
end
