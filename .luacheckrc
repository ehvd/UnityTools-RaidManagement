std = "lua51"
max_line_length = 140
codes = true
self = false

exclude_files = {
    "**/Libs/**",
    ".release/**",
    "tests/node_modules/**",
}

-- Globals written by the addon (SavedVariables, slash commands, binding / XML referenced names)
globals = {
    "UnityToolsRaidManagement",
    "UnityToolsRaidManagementDB",
    "UnityToolsRaidManagementNoteFrame",
    "UnityToolsRaidManagementImportFrame",
    "UnityToolsRaidManagementPlanFrame",
    "SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames",

    -- Method Raid Tools: the note text is written into its SavedVariable (Modules/MRT.lua)
    "VMRT",
}

-- Globals only read by the addon (WoW API, Ace3 and shared libraries). Add what luacheck reports as
-- "accessing undefined variable"; keep this list to things that really exist in the Classic Era client.
read_globals = {
    -- Lua / WoW extensions to the stdlib
    "strsplit", "strjoin", "strtrim", "strlower", "strupper", "strfind", "strmatch", "strsub",
    "strlen", "strrep", "gsub", "format", "tinsert", "tremove", "wipe", "tContains", "date", "time",
    "min", "max", "floor", "ceil", "mod", "abs", "random", "sort", "getn",

    -- Libraries
    "LibStub", "CreateFrame",

    -- Other addons
    "GMRT",

    -- Language override written by `make install LOCALE=xxXX` (GameLocale.lua, not in the repo)
    "UTRM_LOCALE_OVERRIDE",

    -- Frames / UI
    "UIParent", "GameTooltip", "PlaySound", "SOUNDKIT",
    "StaticPopup_Show", "YES", "NO", "CLOSE", "MenuUtil", "MenuResponse",

    -- Game API
    "C_AddOns", "GetAddOnMetadata", "IsAddOnLoaded",
    "UnitIsGroupLeader", "UnitIsGroupAssistant", "GetRaidRosterInfo", "UnitAffectingCombat",
    "GetLootMethod", "SetLootMethod", "InviteUnit", "C_PartyInfo",
    "Ambiguate", "ACCEPT", "DECLINE", "UnitInRaid",
    "C_Timer", "GetTime", "GetServerTime", "GetLocale", "geterrorhandler",
    "UnitName", "UnitGUID", "UnitExists", "UnitClass", "UnitLevel", "InCombatLockdown",
    "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetSpellInfo",
}

-- Translations keep one entry per line, however long
files["Locales/*.lua"] = { max_line_length = false }
