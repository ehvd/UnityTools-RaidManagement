local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local Codec = ns.PlanCodec

-- The raid plan exported from the UnityWiki raid planner: reading the pasted string and keeping one plan
-- (account-wide, in db.global.plan). The format belongs to UnityWiki (docs/addon-export.md there).
local PlanImport = UTRM:NewModule("PlanImport")

local LibDeflate = LibStub("LibDeflate")

-- Text -> the plan, or nil and a message for the import window
function PlanImport:Read(text)
    local data, code = Codec.Decode(text, LibDeflate)
    if not data then
        if code == "empty" then
            return nil, L["Paste the string from the raid planner's Export for addon first."]
        end
        return nil, format(L["This is not a complete raid plan export (%s). Copy it again with Copy for addon."], code)
    end
    if not Codec.IsSupported(data.protocol) then
        local unsupported =
            L["This export uses protocol version %d, but this addon supports version %s. Update Unity Tools - Raid Management."]
        return nil, format(unsupported, data.protocol, table.concat(Codec.PROTOCOLS, ", "))
    end
    local problem = Codec.Check(data)
    if problem then
        return nil, format(L["The raid plan export is damaged (%s). Export it again from the raid planner."], problem)
    end

    -- Only what this addon reads goes into the SavedVariables
    return {
        protocol = data.protocol,
        generatedAt = data.generatedAt,
        url = data.url,
        event = {
            id = data.event.id,
            title = data.event.title,
            startsAt = data.event.startsAt,
            raids = data.event.raids,
        },
        layouts = data.layouts,
        encounters = data.encounters,
        gargul = data.gargul and { string = data.gargul.string, generatedAt = data.gargul.generatedAt },
    }
end

function PlanImport:GetPlan()
    return UTRM.db.global.plan
end

-- A plan imported on this client. Server time, so clients compare the same clock (Modules/SyncRules.lua):
-- importing is choosing this plan.
function PlanImport:Store(plan)
    plan.importedAt = GetServerTime()
    plan.chosenAt = plan.importedAt
    plan.syncedFrom = nil
    UTRM.db.global.plan = plan
    UTRM:SendMessage("UTRM_PLAN_IMPORTED", plan, "import")
end

-- A plan received from another client (Modules/Sync.lua): kept as it came, with its import, chosen and active times
function PlanImport:StoreSynced(plan)
    UTRM.db.global.plan = plan
    UTRM:SendMessage("UTRM_PLAN_IMPORTED", plan, "sync")
end

-- Every edit of the plan goes through here (note text, groups, assignments, the fallback note): `change(plan)`
-- changes the stored plan in place and returns false to leave it unchanged. The edited plan gets a new revision and
-- is chosen now (Modules/SyncRules.lua), so it is another plan that wins over the unedited copies like a newer
-- import: the sync sends it to the raid when this client is a source; a member's edit stays on their client.
-- Returns true, or false and a message.
function PlanImport:Edit(change)
    local plan = self:GetPlan()
    if not plan then
        return false, L["No raid plan imported yet."]
    end
    if change(plan) == false then
        return false
    end
    local now = GetServerTime()
    plan.revision = ns.SyncRules.Revise(plan.revision, UnitName("player"), now)
    plan.chosenAt = ns.SyncRules.EditChosenAt(plan.chosenAt or plan.importedAt, now)
    UTRM.db.global.plan = plan
    UTRM:SendMessage("UTRM_PLAN_EDITED", plan)
    return true
end

-- A few lines describing a plan for the import window
function PlanImport:Summary(plan)
    if not plan then
        return L["No raid plan imported yet."]
    end
    local named = -1
    for _ in pairs(plan.layouts) do named = named + 1 end
    local lines = {
        "|cffffd100" .. plan.event.title .. "|r"
            .. (plan.event.startsAt and ("  " .. date("%Y-%m-%d %H:%M", plan.event.startsAt)) or ""),
        format(L["%d encounters, %d named group layouts"], #plan.encounters, named),
        plan.gargul and L["Gargul loot priorities included"] or L["No Gargul loot priorities"],
        format(L["Exported %s, imported %s"], date("%Y-%m-%d %H:%M", plan.generatedAt or 0),
            date("%Y-%m-%d %H:%M", plan.importedAt or 0)),
    }
    if plan.syncedFrom then
        lines[#lines + 1] = format(L["Synced from %s"], plan.syncedFrom)
    end
    if plan.revision then
        lines[#lines + 1] = format(L["Edited by %s at %s"], Ambiguate(plan.revision.by, "none"),
            date("%H:%M", plan.revision.at))
    end
    return table.concat(lines, "\n")
end
