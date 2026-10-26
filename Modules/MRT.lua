local UTRM = UnityToolsRaidManagement
local L = UTRM.L

-- Method Raid Tools integration. MRT has no public API for setting the note, so this uses its internals
-- (Note.lua, checked against MRT 5335; see docs/CONSTRAINTS.md section 4). Every access to MRT lives in this file.
local MRT = UTRM:NewModule("MRT")

local isAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

-- Returns MRT's note module, or nil and the reason why it cannot be used.
function MRT:GetNoteModule()
    if not isAddOnLoaded("MRT") then
        return nil, L["Method Raid Tools is not loaded."]
    end
    local note = type(GMRT) == "table" and type(GMRT.A) == "table" and GMRT.A.Note
    if type(note) ~= "table" or type(note.frame) ~= "table" or type(note.frame.Save) ~= "function"
        or type(VMRT) ~= "table" or type(VMRT.Note) ~= "table" then
        return nil, L["This version of Method Raid Tools is not supported (its note has changed)."]
    end
    return note
end

function MRT:IsAvailable()
    return self:GetNoteModule() ~= nil
end

-- The current main note with its markup ({rt1}, colours, {spell:...}), or nil when MRT cannot be used.
function MRT:GetNote()
    if not self:GetNoteModule() then return nil end
    return VMRT.Note.Text1 or ""
end

-- Replaces MRT's main note and sends it to the group (to yourself when not in a group), the same way the
-- "Send" button of MRT does. Returns true, or false and an error message.
function MRT:SendNote(text)
    local note, reason = self:GetNoteModule()
    if not note then
        return false, reason
    end
    VMRT.Note.Text1 = text
    local ok, err = pcall(note.frame.Save, note.frame)
    if not ok then
        geterrorhandler()(err)
        return false, L["Method Raid Tools could not send the note."]
    end
    return true
end

-- Raid members who enabled "only from promoted players" in MRT ignore notes from everyone else.
function MRT:CanSendToRaid()
    return not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- SendNote for the UI and slash command: returns whether the note was sent and a message for the user.
function MRT:Post(text)
    local ok, err = self:SendNote(text)
    if not ok then
        return false, err
    end
    if not self:CanSendToRaid() then
        return true,
            L["Note sent, but you are not raid leader or assistant: players who only accept notes from promoted players ignore it."]
    end
    return true, L["Note sent to Method Raid Tools."]
end
