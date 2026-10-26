local _, ns = ...
local L = LibStub("AceLocale-3.0"):NewLocale("UnityTools-RaidManagement", "enUS", true)
if not L then return end

-- The other languages (Locales/<code>.lua) fill this same table through ns.NewTranslation(code), which only
-- returns a writer when <code> is the language of the client. Setting UTRM_LOCALE_OVERRIDE (make install LOCALE=deDE)
-- selects a language on any client, which AceLocale's own GAME_LOCALE cannot do reliably when another addon
-- has already loaded AceLocale. Values left out of a translation fall back to English.
function ns.NewTranslation(code)
    local active = UTRM_LOCALE_OVERRIDE or GetLocale()
    if active == "enGB" then
        active = "enUS"
    elseif active == "esMX" then
        active = "esES"
    end
    if code ~= active then return nil end

    -- `L` above is AceLocale's write proxy for the default language, not the table the addon reads from, and it
    -- refuses to overwrite values. Translations are written straight into the real registry table.
    local registry = LibStub("AceLocale-3.0"):GetLocale("UnityTools-RaidManagement")
    return setmetatable({}, { __newindex = function(_, key, value) rawset(registry, key, value) end })
end

L["Version %s"] = true
L["Commands:"] = true
L["show the addon version"] = true
L["open the raid note editor"] = true
L["send <text> as the Method Raid Tools note (\\n starts a new line)"] = true

-- Method Raid Tools notes
L["Method Raid Tools is not loaded."] = true
L["This version of Method Raid Tools is not supported (its note has changed)."] = true
L["Method Raid Tools could not send the note."] = true
L["Note sent to Method Raid Tools."] = true
L["Note sent, but you are not raid leader or assistant: players who only accept notes from promoted players ignore it."] = true
L["Raid note"] = true
L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."] = true
L["Send"] = true
L["Reload from MRT"] = true
