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

-------------------------------------------------------------------------------------------- the defaults ---
-- Default assignments (issue #59): one set of holders per job key for the whole night, kept in the plan as
-- plan.assignmentDefaults (key → holders), so they sync with it. An encounter's job with other holders is an
-- override. A plan without them (an import) takes each job's most common holders across its encounters (ties: the
-- first encounter's). Protocol 2 has no defaults: the encounters' slots always keep their actual holders.

-- Whether the encounter takes part: its note is rebuilt from its template (not edited by hand)
function Assignments.TakesPart(encounter)
    return Assignments.HasTemplate(encounter) and encounter.customNote == nil
end

-- Each job key's default holders (copies): the stored ones, else the most common among the encounters
function Assignments.Defaults(plan)
    local stored = type(plan.assignmentDefaults) == "table" and plan.assignmentDefaults or {}
    local counts, order = {}, {}
    for _, encounter in ipairs(plan.encounters or {}) do
        if Assignments.TakesPart(encounter) then
            for _, job in ipairs(Assignments.Jobs(encounter)) do
                local seen = counts[job.key]
                if not seen then
                    seen = {}
                    counts[job.key] = seen
                    order[#order + 1] = job.key
                end
                local found = false
                for _, entry in ipairs(seen) do
                    if sameList(entry.holders, job.holders) then
                        entry.count = entry.count + 1
                        found = true
                    end
                end
                if not found then seen[#seen + 1] = { holders = job.holders, count = 1 } end
            end
        end
    end
    local defaults = {}
    for _, key in ipairs(order) do
        if type(stored[key]) == "table" then
            defaults[key] = copy(stored[key])
        else
            local best
            for _, entry in ipairs(counts[key]) do
                if not best or entry.count > best.count then best = entry end
            end
            defaults[key] = copy(best.holders)
        end
    end
    return defaults
end

-- The Default's jobs: every job key of the encounters that take part, with the tokens and candidates of all of
-- them and the default holders, grouped as an encounter's jobs are (GroupJobs)
function Assignments.DefaultJobs(plan, defaults)
    local jobs, byKey = {}, {}
    for _, encounter in ipairs(plan.encounters or {}) do
        if Assignments.TakesPart(encounter) then
            for _, job in ipairs(Assignments.Jobs(encounter)) do
                local merged = byKey[job.key]
                if not merged then
                    merged = {
                        key = job.key, kind = job.kind, multi = job.multi, tokens = {},
                        holders = copy(defaults[job.key]), candidates = {}, known = {},
                    }
                    byKey[job.key] = merged
                    jobs[#jobs + 1] = merged
                end
                merged.multi = merged.multi or job.multi
                for _, token in ipairs(job.tokens) do
                    if not merged.known["token:" .. token] then
                        merged.known["token:" .. token] = true
                        merged.tokens[#merged.tokens + 1] = token
                    end
                end
                for _, name in ipairs(job.candidates) do
                    if not merged.known[name] then
                        merged.known[name] = true
                        merged.candidates[#merged.candidates + 1] = name
                    end
                end
            end
        end
    end
    for _, job in ipairs(jobs) do
        job.known = nil
        table.sort(job.candidates, byName)
    end
    return Assignments.GroupJobs(jobs)
end

-- Whether an encounter's job has other holders than the default
function Assignments.IsOverride(job, defaults)
    local default = defaults[job.key]
    return default ~= nil and not sameList(default, job.holders)
end

-- How many of the jobs are overrides
function Assignments.Overrides(jobs, defaults)
    local count = 0
    for _, job in ipairs(jobs) do
        if Assignments.IsOverride(job, defaults) then count = count + 1 end
    end
    return count
end

-- Whether the default's holders can fill the job: one at most for a job of one, all of them candidates
function Assignments.CanUse(job, holders)
    if not job.multi and #holders > 1 then return false end
    for _, holder in ipairs(holders) do
        local candidate = false
        for _, name in ipairs(job.candidates) do
            if name == holder then candidate = true end
        end
        if not candidate then return false end
    end
    return true
end

-- Puts the job back to the default; false when the default cannot fill it (CanUse)
function Assignments.UseDefault(job, defaults)
    local default = defaults[job.key]
    if not default or not Assignments.CanUse(job, default) then return false end
    job.holders = copy(default)
    return true
end

-- How many of the Default's jobs have other holders than `defaults`
function Assignments.ChangedDefaults(defaults, jobs)
    local count = 0
    for _, job in ipairs(jobs) do
        if not sameList(defaults[job.key] or {}, job.holders) then count = count + 1 end
    end
    return count
end

-- An encounter's jobs after the Default's jobs are saved: a job that follows the old default (`defaults`) and
-- whose default changed gets the new holders, unless they cannot fill it here (CanUse): then it keeps its own, as
-- an override. Changes `jobs` in place; returns them, whether any changed and whether any kept their own.
function Assignments.FollowDefaults(jobs, defaults, defaultJobs)
    local new = {}
    for _, job in ipairs(defaultJobs) do new[job.key] = job.holders end
    local changed, kept = false, false
    for _, job in ipairs(jobs) do
        local old, holders = defaults[job.key], new[job.key]
        if old and holders and not sameList(old, holders) and sameList(old, job.holders) then
            if Assignments.CanUse(job, holders) then
                job.holders = copy(holders)
                changed = true
            else
                kept = true
            end
        end
    end
    return jobs, changed, kept
end

-- Stores the Default's jobs as the plan's defaults (plan.assignmentDefaults) and rebuilds the note of every
-- encounter they change (FollowDefaults). Returns the keys of the encounters rebuilt and of those that keep their
-- own holders for a job.
function Assignments.SaveDefaults(plan, defaults, defaultJobs, people)
    local rebuilt, kept = {}, {}
    for _, encounter in ipairs(plan.encounters or {}) do
        if Assignments.TakesPart(encounter) then
            local jobs, changed, keeps = Assignments.FollowDefaults(Assignments.Jobs(encounter), defaults, defaultJobs)
            if changed then
                Assignments.Apply(encounter, jobs, people)
                rebuilt[#rebuilt + 1] = encounter.key
            end
            if keeps then kept[#kept + 1] = encounter.key end
        end
    end
    local stored = {}
    for _, job in ipairs(defaultJobs) do stored[job.key] = copy(job.holders) end
    plan.assignmentDefaults = stored
    return rebuilt, kept
end

-- Keeps the defaults as they are now in the plan, so changing an encounter does not change which holders are the
-- most common (a plan without stored defaults): before an encounter's jobs are saved
function Assignments.KeepDefaults(plan)
    plan.assignmentDefaults = Assignments.Defaults(plan)
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
