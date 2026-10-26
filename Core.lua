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
        noteWindow = { width = 560, height = 440 },   -- AceGUI status table of the note editor (position, size)
        importWindow = { width = 520, height = 400 }, -- the same for the raid plan import window
    },
    global = {
        -- plan = the raid plan imported from UnityWiki (Modules/PlanImport.lua), absent until the first import
    },
}

function UTRM:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("UnityToolsRaidManagementDB", defaults, true)
    self:RegisterChatCommand("utrm", "OnSlashCommand")
end

function UTRM:OnEnable()
end

function UTRM:PrintHelp()
    self:Print(format(L["Version %s"], self.version))
    self:Print(L["Commands:"])
    self:Print("  /utrm note - " .. L["open the raid note editor"])
    self:Print("  /utrm note <text> - " .. L["send <text> as the Method Raid Tools note (\\n starts a new line)"])
    self:Print("  /utrm import - " .. L["import a raid plan from the UnityWiki raid planner"])
    self:Print("  /utrm version - " .. L["show the addon version"])
end

function UTRM:OnSlashCommand(input)
    local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = strlower(command)
    if command == "note" then
        if rest == "" then
            self.NoteEditor:Open()
        else
            local _, message = self:GetModule("MRT"):Post((rest:gsub("\\n", "\n")))
            self:Print(message)
        end
    elseif command == "import" then
        self.ImportWindow:Open()
    elseif command == "version" then
        self:Print(format(L["Version %s"], self.version))
    else
        self:PrintHelp()
    end
end
