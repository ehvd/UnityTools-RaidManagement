local _, ns = ...

-- Compares a planned layout (40 names in MRT's raid-groups order: group 1 slots 1-5, group 2 slots 1-5 ...) with
-- the raid as it is. Pure Lua, no WoW API, so tests/group-plan can run it outside the game.
local GroupPlan = {}
ns.GroupPlan = GroupPlan

GroupPlan.SLOTS = 40
GroupPlan.GROUP_SIZE = 5

-- The key two spellings of a character share: no realm, lower case (ASCII only: WoW capitalises the first letter,
-- and the planner's names normally match the game's)
function GroupPlan.Key(name)
    return (name:match("^[^-]+") or name):lower()
end

local function groupOfSlot(slot)
    return math.floor((slot - 1) / GroupPlan.GROUP_SIZE) + 1
end

-- layout: 40 planned names ("" = empty slot). roster: { { name = "Name" or "Name-Realm", group = 1..8 }, ... }.
-- Returns:
--   list       40 names for MRT's ApplyGroups: the raid's own spelling of each planned name, "" where the planned
--              player is not in the raid (or the slot is empty)
--   missing    planned names not in the raid, in plan order
--   extra      raid members not in the plan, in roster order (MRT leaves them where they are or swaps them aside)
--   misplaced  planned raid members who are not in their planned group yet
function GroupPlan.Compare(layout, roster)
    local raidByKey = {}
    for _, member in ipairs(roster) do
        raidByKey[GroupPlan.Key(member.name)] = member
    end

    local result = { list = {}, missing = {}, extra = {}, misplaced = 0 }
    local planned = {}
    for slot = 1, GroupPlan.SLOTS do
        local name = layout[slot] or ""
        local key = name ~= "" and GroupPlan.Key(name)
        local member = key and not planned[key] and raidByKey[key]
        if key and not planned[key] then
            planned[key] = true
            if member then
                if member.group ~= groupOfSlot(slot) then
                    result.misplaced = result.misplaced + 1
                end
            else
                result.missing[#result.missing + 1] = name
            end
        end
        result.list[slot] = member and member.name or ""
    end

    for _, member in ipairs(roster) do
        if not planned[GroupPlan.Key(member.name)] then
            result.extra[#result.extra + 1] = member.name
        end
    end
    return result
end
