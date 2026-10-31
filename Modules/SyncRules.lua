local _, ns = ...

-- The rules of the raid plan sync (Modules/Sync.lua): which copy of a plan wins, and whether a message is well
-- formed. Pure Lua, no WoW API, so tests/sync-rules can run it outside the game.
--
-- A copy of a plan is described by its meta:
--   id   the export it came from (the event id and the export time: two imports of one string share it) and its
--        revision, so an edited copy is another plan
--   c    when somebody chose this plan: their import, their edit, or a force sync they accepted (server time)
--   g    the export time (UnityWiki's generatedAt)
--   a    the active encounter's key, at when it was chosen (server time)
--   s    who holds this copy (the sender's name; our own name for our copy)
local SyncRules = {}
ns.SyncRules = SyncRules

SyncRules.VERSION = 2   -- goes up on every change of the messages; other versions are ignored (2: revisions)

local TYPES = { state = true, request = true, plan = true, force = true }

-- A plan's revision: nil for the plan as imported; every edit (PlanImport:Edit) makes a new one
--   n    a counter, one more than the revision it was made from
--   by   who edited (a character name)
--   at   when (server time)
function SyncRules.Revise(revision, by, at)
    return { n = (revision and revision.n or 0) + 1, by = by, at = at }
end

-- Whether a revision received with a plan is well formed (nil is the plan as imported)
function SyncRules.IsRevision(revision)
    if revision == nil then return true end
    return type(revision) == "table" and type(revision.n) == "number" and type(revision.by) == "string"
        and type(revision.at) == "number"
end

-- The export (event id @ export time), then the revision: "e1@100" as imported, "e1@100/2:Name:1700000000" edited
function SyncRules.Identity(plan)
    local id = tostring(plan.event and plan.event.id or "?") .. "@" .. tostring(plan.generatedAt or 0)
    local revision = plan.revision
    if revision then
        id = id .. "/" .. tostring(revision.n) .. ":" .. tostring(revision.by) .. ":" .. tostring(revision.at)
    end
    return id
end

-- The chosen time of an edit: now, and at least a millisecond newer than the plan's previous choice, so an edit
-- right after the import (or another edit) in the same server second still wins over the copy it was made from
function SyncRules.EditChosenAt(previous, now)
    return math.max(now, (previous or 0) + 0.001)
end

-- The meta of a stored plan (nil when there is none)
function SyncRules.Meta(plan, holder)
    if not plan then return nil end
    return {
        id = SyncRules.Identity(plan),
        c = plan.chosenAt or plan.importedAt or 0,
        g = plan.generatedAt or 0,
        a = plan.active,
        at = plan.activeAt or 0,
        s = holder,
    }
end

-- Whether `theirs` should replace `mine` (either may be nil). Copies of the same export and revision never replace
-- each other: they are the same plan. Otherwise the most recently chosen plan wins, then the newer export, then the
-- holder whose name sorts first, so every client picks the same one. An edit is a choice (EditChosenAt), so it wins
-- like a newer import.
function SyncRules.PlanWins(theirs, mine)
    if not theirs then return false end
    if not mine then return true end
    if theirs.id == mine.id then return false end
    if theirs.c ~= mine.c then return theirs.c > mine.c end
    if theirs.g ~= mine.g then return theirs.g > mine.g end
    return (theirs.s or "") < (mine.s or "")
end

-- Whether their active encounter should replace ours: same plan, a newer choice
function SyncRules.ActiveWins(theirs, mine)
    if not theirs or not mine or theirs.id ~= mine.id or not theirs.a then return false end
    return (theirs.at or 0) > (mine.at or 0)
end

local function optional(value, kind)
    return value == nil or type(value) == kind
end

-- A received message after deserializing: returns the message or nil and why it is ignored ("version" when it is
-- from another version of the sync, "invalid" otherwise)
function SyncRules.Validate(msg)
    if type(msg) ~= "table" or not TYPES[msg.t] then return nil, "invalid" end
    if msg.v ~= SyncRules.VERSION then return nil, "version" end
    if msg.t == "state" then
        if not optional(msg.id, "string") or not optional(msg.c, "number") or not optional(msg.g, "number")
            or not optional(msg.a, "string") or not optional(msg.at, "number") or not optional(msg.n, "string") then
            return nil, "invalid"
        end
    elseif msg.t == "request" then
        if type(msg.id) ~= "string" then return nil, "invalid" end
    elseif type(msg.p) ~= "string" then   -- plan, force: the encoded plan
        return nil, "invalid"
    end
    return msg
end

-- The meta a state message describes (nil when the sender has no plan)
function SyncRules.MetaOfState(msg, sender)
    if not msg.id then return nil end
    return { id = msg.id, c = msg.c or 0, g = msg.g or 0, a = msg.a, at = msg.at or 0, s = sender }
end
