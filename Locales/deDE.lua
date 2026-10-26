local _, ns = ...
local L = ns.NewTranslation("deDE")
if not L then return end

L["Version %s"] = "Version %s"
L["Commands:"] = "Befehle:"
L["show the addon version"] = "zeigt die Addon-Version"
L["open the raid note editor"] = "öffnet den Editor für die Raid-Notiz"
L["send <text> as the Method Raid Tools note (\\n starts a new line)"] = "sendet <text> als Method-Raid-Tools-Notiz (\\n beginnt eine neue Zeile)"

L["Method Raid Tools is not loaded."] = "Method Raid Tools ist nicht geladen."
L["This version of Method Raid Tools is not supported (its note has changed)."] = "Diese Version von Method Raid Tools wird nicht unterstützt (die Notiz hat sich geändert)."
L["Method Raid Tools could not send the note."] = "Method Raid Tools konnte die Notiz nicht senden."
L["Note sent to Method Raid Tools."] = "Notiz an Method Raid Tools gesendet."
L["Note sent, but you are not raid leader or assistant: players who only accept notes from promoted players ignore it."] = "Notiz gesendet, aber du bist weder Schlachtzugsleiter noch Assistent: Spieler, die nur Notizen von beförderten Spielern annehmen, ignorieren sie."
L["Raid note"] = "Raid-Notiz"
L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."] = "Notiztext. Method-Raid-Tools-Markup funktioniert: {rt1}, {spell:12345}, Farben."
L["Send"] = "Senden"
L["Reload from MRT"] = "Aus MRT neu laden"
