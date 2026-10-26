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
