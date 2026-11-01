local _, ns = ...

-- Changing who fills an encounter's assignment slots (export protocol 2) and rebuilding its note, as the wiki's
-- contract allows ("Changing holders" in UnityWiki's docs/addon-export.md): slots with the same `key` are one job
-- and always get the same holders; `none` slots name nobody and `list` slots are everybody who matches, so neither
-- is offered. Pure Lua, no WoW API (tests/assignments.test.mjs).
local Assignments = {}
ns.Assignments = Assignments

local function copy(list)
    local out = {}
    for i, value in ipairs(list or {}) do out[i] = value end
    return out
end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Whether the encounter's note can be rebuilt: a protocol 2 encounter with its template and slots
function Assignments.HasTemplate(encounter)
    return type(encounter) == "table" and type(encounter.template) == "string" and type(encounter.slots) == "table"
end

local function offered(slot)
    return slot.kind ~= "none" and slot.kind ~= "list"
end

-- The accented letters of Latin-1 (UTF-8 "\195" and one byte) as their base letter, so names sort as people read
-- them: "Tracedeneïge" next to "Tracedeneige"
local FOLD = {}
for letter, codes in pairs({
    a = "\128\129\130\131\132\133\160\161\162\163\164\165", c = "\135\167", e = "\136\137\138\139\168\169\170\171",
    i = "\140\141\142\143\172\173\174\175", n = "\145\177", o = "\146\147\148\149\150\152\178\179\180\181\182\184",
    u = "\153\154\155\156\185\186\187\188", y = "\157\189\191",
}) do
    for i = 1, #codes do FOLD["\195" .. codes:sub(i, i)] = letter end
end

-- A name as it sorts: lower case, without accents
function Assignments.SortName(name)
    return (name:gsub("\195[\128-\191]", FOLD):lower())
end

local function byName(a, b)
    local sa, sb = Assignments.SortName(a), Assignments.SortName(b)
    if sa ~= sb then return sa < sb end
    return a < b
end

-- Sorts a list of names alphabetically (case and accents ignored) and returns it
function Assignments.SortNames(names)
    table.sort(names, byName)
    return names
end

-- The encounter's jobs, in the order their first slot comes: { key, kind, multi, tokens, holders, candidates }.
-- The holders are a copy of the first slot's (the slots of a job have the same), the candidates a copy in
-- alphabetical order.
function Assignments.Jobs(encounter)
    local jobs, byKey = {}, {}
    for _, slot in ipairs(encounter.slots or {}) do
        if offered(slot) then
            local job = byKey[slot.key]
            if not job then
                job = {
                    key = slot.key, kind = slot.kind, multi = slot.multi and true or false, tokens = {},
                    holders = copy(slot.holders), candidates = copy(slot.candidates),
                }
                table.sort(job.candidates, byName)
                byKey[slot.key] = job
                jobs[#jobs + 1] = job
            end
            local known = false
            for _, token in ipairs(job.tokens) do
                if token == slot.token then known = true end
            end
            if not known then job.tokens[#job.tokens + 1] = slot.token end
        end
    end
    return jobs
end

-- The jobs in the order the window shows them: grouped by their first token without its number (TANK1..TANK4 are
-- "TANK", a custom @Kicker is its own group), the groups in the order the note first names them, each group in the
-- note's order. TANK1, HEALER1, TANK2, HEALER2 → TANK1, TANK2, HEALER1, HEALER2.
function Assignments.GroupJobs(jobs)
    local groups, groupOf = {}, {}
    for _, job in ipairs(jobs) do
        local name = job.tokens[1]:gsub("%d+$", "")
        local group = groupOf[name]
        if not group then
            group = {}
            groupOf[name] = group
            groups[#groups + 1] = group
        end
        group[#group + 1] = job
    end
    local out = {}
    for _, group in ipairs(groups) do
        for _, job in ipairs(group) do out[#out + 1] = job end
    end
    return out
end

function Assignments.Holds(job, name)
    for _, holder in ipairs(job.holders) do
        if holder == name then return true end
    end
    return false
end

-- A job of one person: `name` fills it, nil empties it
function Assignments.Set(job, name)
    job.holders = name and { name } or {}
end

-- A job of several people: adds `name` after the others, or takes them out
function Assignments.Toggle(job, name)
    for i, holder in ipairs(job.holders) do
        if holder == name then
            table.remove(job.holders, i)
            return
        end
    end
    job.holders[#job.holders + 1] = name
end

-- How many jobs have other holders than the encounter's slots
function Assignments.Changed(encounter, jobs)
    local original, count = {}, 0
    for _, job in ipairs(Assignments.Jobs(encounter)) do
        original[job.key] = job.holders
    end
    for _, job in ipairs(jobs) do
        if not sameList(original[job.key] or {}, job.holders) then count = count + 1 end
    end
    return count
end

-- nil when the jobs can be saved, else the first token whose holders cannot: more than one in a job of one,
-- somebody twice, or somebody who is not a candidate (the wiki would not offer them)
function Assignments.Validate(jobs)
    for _, job in ipairs(jobs) do
        local seen = {}
        if not job.multi and #job.holders > 1 then return job.tokens[1] end
        for _, holder in ipairs(job.holders) do
            if seen[holder] then return job.tokens[1] end
            seen[holder] = true
            local candidate = false
            for _, name in ipairs(job.candidates) do
                if name == holder then candidate = true end
            end
            if not candidate then return job.tokens[1] end
        end
    end
    return nil
end

-- The encounter's slots with the jobs' holders: copies, the encounter is not changed
function Assignments.Slots(encounter, jobs)
    local byKey = {}
    for _, job in ipairs(jobs) do byKey[job.key] = job end
    local slots = {}
    for i, slot in ipairs(encounter.slots or {}) do
        local out = {}
        for field, value in pairs(slot) do out[field] = value end
        local job = offered(slot) and byKey[slot.key]
        out.holders = copy(job and job.holders or slot.holders)
        out.candidates = copy(slot.candidates)
        slots[i] = out
    end
    return slots
end

-- The note the jobs give
function Assignments.Preview(encounter, jobs, people)
    return ns.NoteTemplate.Render(encounter.template, Assignments.Slots(encounter, jobs), people)
end

-- Writes the jobs' holders into the encounter's slots and rebuilds its note; returns the note
function Assignments.Apply(encounter, jobs, people)
    encounter.slots = Assignments.Slots(encounter, jobs)
    encounter.note = ns.NoteTemplate.Render(encounter.template, encounter.slots, people)
    return encounter.note
end
