local _, ns = ...

-- A raid plan made in game (issue #43), for a night without a UnityWiki plan. It has the shape of an imported export
-- (protocol 2, UnityWiki's docs/addon-export.md), so everything that works on an import works on it: per chosen
-- raid its Trash, then its bosses in kill order with their encounter IDs (Modules/Bosses.lua), every note empty and
-- without template or slots, the night's groups (`default`) as the raid is arranged now, and no Gargul string.
-- Pure Lua (Bosses is loaded first), so tests/new-plan.test.mjs can run it.
local NewPlan = {}
ns.NewPlan = NewPlan

local Bosses = ns.Bosses

NewPlan.PROTOCOL = 2
NewPlan.SLOTS = 40   -- names per layout: 8 groups of 5, MRT's raid groups order (PlanCodec.SLOTS)

local ID_PREFIX = "addon:"

-- Whether `plan` was made in game rather than exported from the wiki
function NewPlan.IsMadeInGame(plan)
    local id = plan and plan.event and plan.event.id
    return type(id) == "string" and id:sub(1, #ID_PREFIX) == ID_PREFIX
end

-- The title the form starts with: the raids' names and the date ("Molten Core + Onyxia's Lair 2026-11-02")
function NewPlan.DefaultTitle(raidNames, day)
    if #raidNames == 0 then return day end
    return table.concat(raidNames, " + ") .. " " .. day
end

-- The raid as it is now -> the 40 names of `default` and the people: each member in the first free slot of their
-- group. `roster` is { { name, group = 1..8, class = "WARRIOR" or nil }, ... } (GetRaidRosterInfo), {} outside a raid.
function NewPlan.Layout(roster)
    local names, people, used = {}, {}, {}
    for slot = 1, NewPlan.SLOTS do names[slot] = "" end
    for _, member in ipairs(roster) do
        local group = member.group
        if member.name and member.name ~= "" and not people[member.name] and group and group >= 1 and group <= 8 then
            used[group] = (used[group] or 0) + 1
            if used[group] <= 5 then
                names[(group - 1) * 5 + used[group]] = member.name
                people[member.name] = { class = member.class }
            end
        end
    end
    return names, people
end

-- The plan, as PlanImport:Read returns one, or nil and an error code ("title", "raids", "raid:<slug>").
-- options:
--   title      the event's title (required, not blank)
--   raids      the chosen raid slugs, in the order the night runs them (at least one)
--   roster     the raid as it is now (see Layout), {} or nil for empty groups
--   player     who made it ("Name" or "Name-Realm"), for the event ID
--   now        server time (unix seconds): the "export" time and the event ID's
--   translate  optional: English text -> what the plan shows (L), for "Trash" and "Trash (%s)" and the names
function NewPlan.Build(options)
    local translate = options.translate or function(text) return text end
    local title = options.title and options.title:match("^%s*(.-)%s*$") or ""
    if title == "" then return nil, "title" end
    local slugs = options.raids or {}
    if #slugs == 0 then return nil, "raids" end
    for _, slug in ipairs(slugs) do
        if not Bosses.RaidName(slug) then return nil, "raid:" .. tostring(slug) end
    end

    local raids, encounters = {}, {}
    for i, slug in ipairs(slugs) do
        local name = translate(Bosses.RaidName(slug))
        raids[i] = { slug = slug, name = name }
        -- One Trash per raid: named after the raid when the night has several
        encounters[#encounters + 1] = {
            key = slug .. ":trash",
            label = #slugs > 1 and string.format(translate("Trash (%s)"), name) or translate("Trash"),
            raid = slug,
            note = "",
            layout = "default",
        }
        for _, boss in ipairs(Bosses.Of(slug)) do
            encounters[#encounters + 1] = {
                key = slug .. ":" .. boss.key,
                label = translate(boss.label),
                raid = slug,
                encounterId = boss.encounterId,
                note = "",
                layout = "default",
            }
        end
    end

    local names, people = NewPlan.Layout(options.roster or {})
    return {
        protocol = NewPlan.PROTOCOL,
        generatedAt = options.now,
        event = {
            -- Never a wiki event's ID (those are Raid-Helper's numbers): two plans made apart are two plans
            id = ID_PREFIX .. tostring(options.player) .. ":" .. tostring(options.now),
            title = title,
            raids = raids,
        },
        layouts = { default = names },
        people = people,
        encounters = encounters,
    }
end
