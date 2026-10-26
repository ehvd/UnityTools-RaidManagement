local ADDON_NAME = ...

-- The folder name has a hyphen, so the global table and the SavedVariable use the name without it
local UTRM = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
UnityToolsRaidManagement = UTRM

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
UTRM.L = L

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = getMetadata(ADDON_NAME, "Version")
-- "@project-version@" is only substituted by the packager / `make install`; a linked dev checkout keeps it
UTRM.version = (version and not version:find("@", 1, true)) and version or "dev"

-- profile: settings (shared by all characters unless a character picks another profile), global: account-wide data
local defaults = {
    profile = {
    },
    global = {
    },
}

function UTRM:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("UnityToolsRaidManagementDB", defaults, true)
    self:RegisterChatCommand("utrm", "OnSlashCommand")
end

function UTRM:OnEnable()
end

function UTRM:OnSlashCommand(input)
    local command = strlower(strtrim(input or ""))
    self:Print(format(L["Version %s"], self.version))
    if command ~= "version" then
        self:Print(L["Commands:"])
        self:Print("  /utrm version - " .. L["show the addon version"])
    end
end
