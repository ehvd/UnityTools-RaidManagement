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

-- The encounter's jobs, in the order their first slot comes: { key, kind, multi, tokens, holders, candidates }.
-- The holders and candidates are copies of the first slot's (the slots of a job have the same).
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
