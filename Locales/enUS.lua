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

-- Raid plan import
L["import a raid plan from the UnityWiki raid planner"] = true
L["Import raid plan"] = true
L["Current plan"] = true
L["Paste the string from Export for addon in the UnityWiki raid planner:"] = true
L["Import"] = true
L["%d characters pasted. Press Import."] = true
L["Imported %s."] = true
L["Replace the imported raid plan \"%s\" with \"%s\"?"] = true
L["Paste the string from the raid planner's Export for addon first."] = true
L["This is not a complete raid plan export (%s). Copy it again with Copy for addon."] = true
L["This export uses protocol version %d, but this addon supports version %s. Update Unity Tools - Raid Management."] = true
L["The raid plan export is damaged (%s). Export it again from the raid planner."] = true
L["No raid plan imported yet."] = true
L["%d encounters, %d named group layouts"] = true
L["Gargul loot priorities included"] = true
L["No Gargul loot priorities"] = true
L["Exported %s, imported %s"] = true
L["Clear raid plan"] = true
L["Clear the raid plan \"%s\"?"] = true
L["Clear the raid plan \"%s\"? The raid leader or an assistant may sync their plan to you again."] = true
L["Raid plan %s cleared."] = true

-- Raid plan window
L["show or hide the raid plan window"] = true
L["Raid plan"] = true
L["Import raid plan..."] = true
L["Lock position"] = true
L["Scale"] = true
L["Choose the encounter"] = true
L["Click: choose the encounter"] = true
L["The plan has no encounters."] = true
L["The night's groups"] = true
L["Groups: %s"] = true
L["This encounter has no note: the MRT note was cleared."] = true
L["Sending..."] = true
L["Note sent"] = true
L["Note cleared"] = true
L["Note not sent"] = true
L["Note sent, not as lead or assist"] = true

-- Raid groups
L["This version of Method Raid Tools is not supported (its raid groups have changed)."] = true
L["Method Raid Tools could not sort the raid groups."] = true
L["Sorting groups..."] = true
L["Groups sorted"] = true
L["Groups already match"] = true
L["Groups: not in a raid"] = true
L["Groups: you need lead or assist"] = true
L["Groups: someone is in combat"] = true
L["Groups not finished: %d still in the wrong group"] = true
L["%d missing"] = true
L["%d not in the plan"] = true
L["Missing from the raid:"] = true
L["In the raid but not in the plan:"] = true

-- Gargul
L["Gargul is not loaded."] = true
L["This version of Gargul is not supported (its import has changed)."] = true
L["Gargul could not import the loot priorities."] = true
L["Gargul did not accept the loot priorities: see its import window."] = true
L["Loot priorities imported into Gargul."] = true
L["The raid plan has no Gargul loot priorities."] = true
L["Gargul: loot priorities are up to date"] = true
L["Gargul: import the loot priorities"] = true

-- Raid readiness
L["Raid readiness"] = true
L["Checked in a raid only."] = true
L["Loot method: Master Loot"] = true
L["Loot method is %s, not Master Loot"] = true
L["Method Raid Tools is loaded"] = true
L["Gargul has the plan's loot priorities"] = true
L["Everyone planned is in the raid"] = true
L["Raid differs from the plan: %d missing, %d not in the plan"] = true
L["Gargul does not have the plan's loot priorities"] = true
L["Groups match the plan"] = true
L["%d players in the wrong group"] = true
L["Click: fix"] = true
L["Everything is ready."] = true
L["Set Master Loot (you loot)"] = true
L["Import the loot priorities into Gargul"] = true
L["Invite %d missing players"] = true
L["Sort groups"] = true
L["Enable Method Raid Tools in the AddOns list and reload."] = true
L["Players not in the plan are not removed automatically."] = true
L["Only the raid leader can change the loot method."] = true
L["The loot method cannot be changed in combat."] = true
L["This client cannot change the loot method from an addon."] = true
L["Master Loot set: you are the master looter."] = true
L["Only the raid leader or an assistant can invite."] = true
L["Invited %d players: %s"] = true

-- Sync
L["Force sync"] = true
L["Synced from %s"] = true
L["Edited by %s at %s"] = true
L["%s chose %s"] = true
L["Raid plan %s synced from %s."] = true
L["Only the raid leader or an assistant can sync, in a raid."] = true
L["Force sync sent: the others are asked to accept your raid plan."] = true
L["%s wants to replace your raid plan with \"%s\" (Force sync). Accept?"] = true
L["Force sync from %s declined: your raid plan is kept."] = true
L["%s uses another version of the raid plan sync: update Unity Tools - Raid Management."] = true

-- Minimap button
L["Unity Tools - Raid Management"] = true
L["show or hide the minimap button"] = true
L["Left-click: show or hide the raid plan window"] = true
L["Right-click: options"] = true
L["Raid note editor..."] = true
L["Hide minimap button"] = true
L["Minimap button hidden: /utrm minimap shows it again."] = true
