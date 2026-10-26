local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local Codec = ns.PlanCodec

-- Gargul integration: hands the imported plan's loot priorities (the /gl tmb string of /loot-policy) to Gargul and
-- tells whether Gargul still has them. Gargul opens itself up as _G.Gargul, but the import is its internals
-- (Classes/TMB.lua and Interface/TMB/Importer.lua, checked against Gargul 8.0.1; see docs/CONSTRAINTS.md section 5).
-- Every access to Gargul lives in this file.
local Gargul = UTRM:NewModule("Gargul")

local isAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

-- Returns Gargul's global, or nil and the reason why it cannot be used
function Gargul:GetAddon()
    if not isAddOnLoaded("Gargul") then
        return nil, L["Gargul is not loaded."]
    end
    local GL = _G.Gargul
    local importer = type(GL) == "table" and type(GL.Interface) == "table" and type(GL.Interface.TMB) == "table"
        and GL.Interface.TMB.Importer
    if type(GL) ~= "table" or type(GL.TMB) ~= "table" or type(GL.TMB.import) ~= "function"
        or type(importer) ~= "table" or type(importer.draw) ~= "function"
        or type(GL.DB) ~= "table" or type(GL.DB.get) ~= "function" then
        return nil, L["This version of Gargul is not supported (its import has changed)."]
    end
    return GL
end

function Gargul:IsAvailable()
    return self:GetAddon() ~= nil
end

-- The id Gargul gives every import (TMB.MetaData.hash, a random id plus the time), or nil when it has none
local function importId(GL)
    local ok, hash = pcall(GL.DB.get, GL.DB, "TMB.MetaData.hash")
    return ok and hash or nil
end

-- Imports `text` (a /gl tmb string) into Gargul the way its own Import button does. Gargul's importer window is
-- opened first: Gargul writes its errors there, and closes it after a successful import.
-- Returns true, or false and a message.
function Gargul:Import(text)
    local GL, reason = self:GetAddon()
    if not GL then
        return false, reason
    end
    local ok, result = pcall(function()
        GL.Interface.TMB.Importer:draw()
        return GL.TMB:import(text)
    end)
    if not ok then
        geterrorhandler()(result)
        return false, L["Gargul could not import the loot priorities."]
    end
    if result ~= true then
        return false, L["Gargul did not accept the loot priorities: see its import window."]
    end
    -- Gargul keeps no fingerprint of what was imported, only a new id per import: remember both
    UTRM.db.global.gargulImport = { id = importId(GL), checksum = Codec.Checksum(text) }
    UTRM:SendMessage("UTRM_GARGUL_IMPORTED")
    return true, L["Loot priorities imported into Gargul."]
end

-- Whether Gargul has the plan's loot priorities:
--   nil         nothing to compare (no plan, the plan has no Gargul string, or Gargul cannot be used)
--   "current"   Gargul's last import is ours and was this string
--   "outdated"  anything else: never imported from here, imported something else since, or the plan's string changed
function Gargul:GetState(plan)
    if not plan or not plan.gargul then return nil end
    local GL = self:GetAddon()
    if not GL then return nil end
    local saved = UTRM.db.global.gargulImport
    local id = importId(GL)
    if saved and id and saved.id == id and saved.checksum == Codec.Checksum(plan.gargul.string) then
        return "current"
    end
    return "outdated"
end

-- Imports the plan's string; returns true or false and a message (for the plan window's status line)
function Gargul:ImportPlan(plan)
    if not plan or not plan.gargul then
        return false, L["The raid plan has no Gargul loot priorities."]
    end
    return self:Import(plan.gargul.string)
end
